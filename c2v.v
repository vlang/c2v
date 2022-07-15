// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
module main

import os
import strings
import json
import time
import toml

const version = '0.3.1'

// V keywords, that are not keywords in C:
const v_keywords = ['go', 'type', 'true', 'false', 'module', 'byte', 'in', 'none', 'map', 'string']

// libc fn definitions that have to be skipped (V already knows about them):
const builtin_fn_names = ['fopen', 'puts', 'fflush', 'printf', 'memset', 'atoi', 'memcpy', 'remove',
	'strlen', 'rename', 'stdout', 'stderr', 'stdin', 'ftell', 'fclose', 'fread', 'read', 'perror',
	'ftruncate', 'FILE', 'strcmp', 'toupper', 'strchr', 'strdup', 'strncasecmp', 'strcasecmp',
	'isspace', 'strncmp', 'malloc', 'close', 'open', 'lseek', 'fgets', 'write', 'calloc', 'setenv',
	'gets', 'abs', 'sqrt', 'erfl', 'fprintf', 'snprintf', 'exit', '__stderrp', 'fwrite', 'scanf',
	'sscanf', 'strrchr', 'strchr', 'div', 'free', 'memcmp', 'memmove', 'vsnprintf', 'rintf', 'rint']

const builtin_type_names = ['ldiv_t', '__float2', '__double2', 'exception', 'double_t']

const builtin_global_names = ['sys_nerr', 'sys_errlist', 'suboptarg']

const tabs = ['', '\t', '\t\t', '\t\t\t', '\t\t\t\t', '\t\t\t\t\t', '\t\t\t\t\t\t', '\t\t\t\t\t\t\t',
	'\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t\t\t',
	'\t\t\t\t\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t\t\t\t\t']

const cur_dir = os.getwd()

const clang = find_clang_in_path()

struct Type {
mut:
	name      string
	is_const  bool
	is_static bool
}

struct AstJsonType {
	q           string [json: 'qualType']
	desugared_q string [json: 'desugaredQualType']
}

struct ReferencedDeclNode {
	id       string
	kind_str string      [json: 'kind'] // e.g. "IntegerLiteral"
	name     string
	typ      AstJsonType [json: 'type']
mut:
	kind NodeKind [skip]
}

[heap]
struct Node {
	id            string
	kind_str      string      [json: 'kind'] // e.g. "IntegerLiteral"
	name          string // e.g. "my_var_name"
	value         string // e.g. "777" for IntegerLiteral
	value_number  int         [json: 'value'] // For CharacterLiterals, since `value` is a number there, not at string
	mangled_name  string      [json: 'mangledName']
	loc           Loc
	typ           AstJsonType [json: 'type']
	arg_type      AstJsonType [json: 'argType']
	inner         []Node
	array_filler  []Node // for InitListExpr
	used          bool        [json: 'isUsed']
	storage_class string      [json: 'storageClass']
	tag_used      string      [json: 'tagUsed']
	init          string // "c" => "cinit"
	opcode        string // e.g. "+" in BinaryOperator
	range         Range
	decl_id       string      [json: 'declId'] // for goto labels
	// for goto statements
	label_id string [json: 'targetLabelDeclId']
mut:
	referenced_decl   ReferencedDeclNode [json: 'referencedDecl'] //&Node
	child_i           int                [skip]
	kind              NodeKind           [skip]
	is_std            bool               [skip]
	previous_decl     string             [json: 'previousDecl']
	nr_redeclarations int                [skip] // increased when some *other* Node had previous_decl == this Node.id
	is_postfix        bool               [json: 'isPostfix']
}

fn find_clang_in_path() string {
	clangs := ['clang-14', 'clang-13', 'clang-12', 'clang-11', 'clang-10', 'clang']
	for clang in clangs {
		os.find_abs_path_of_executable(clang) or { continue }
		return clang
	}
	panic('cannot find clang in PATH')
}

struct LabelStmt {
	name string
}

struct C2V {
mut:
	tree            Node
	is_dir          bool // when translating a directory (multiple C=>V files)
	c_file_contents string
	line_i          int
	node_i          int      // when parsing nodes
	unhandled_nodes []string // when coming across an unknown Clang AST node
	// out  stuff
	out                 strings.Builder   // os.File
	globals_out         map[string]string // `globals_out["myglobal"] == "extern int myglobal = 0;"` // strings.Builder
	out_file            os.File
	out_line_empty      bool
	types               []string // to avoid dups
	enums               []string // to avoid dups
	enum_vals           map[string][]string // enum_vals['Color'] = ['green', 'blue'], for converting C globals  to enum values
	fns                 []string // to avoid dups
	outv                string
	cur_file            string
	consts              []string
	globals             map[string]Global
	inside_switch       int // used to be a bool, a counter to handle switches inside switches
	inside_switch_enum  bool
	inside_for          bool // to handle `;;++i`
	inside_array_index  bool // for enums used as int array index: `if player.weaponowned[.wp_chaingun]`
	global_struct_init  string
	cur_out_line        string
	inside_main         bool
	indent              int
	empty_line          bool // for indents
	is_wrapper          bool
	wrapper_module_name string // name of the wrapper module
	nm_lines            []string
	is_verbose          bool
	skip_parens         bool // for skipping unnecessary params like in `enum Foo { bar = (1+2) }`
	labels              map[string]string // for goto stmts: `label_stmts[label_id] == 'labelname'`
	//
	project_folder string // the final folder passed on the CLI, or the folder of the last file, passed on the CLI. Will be used for searching for a c2v.toml file, containing project configuration overrides, when the C2V_CONFIG env variable is not set explicitly.
	conf           toml.Doc = empty_toml_doc() // conf will be set by parsing the TOML configuration file
	//
	project_output_dirname   string // by default, 'c2v_out.dir'; override with `[project] output_dirname = "another"`
	project_additional_flags string // what to pass to clang, so that it could parse all the input files; mainly -I directives to find additional headers; override with `[project] additional_flags = "-I/some/folder"`
	project_uses_sdl         bool   // if a project uses sdl, then the additional flags will include the result of `sdl2-config --cflags` too; override with `[project] uses_sdl = true`
	file_additional_flags    string // can be added per file, appended to project_additional_flags ; override with `['info.c'] additional_flags = -I/xyz`
	//
	project_globals_path string // where to store the _globals.v file, that will contain all the globals/consts for the project folder; calculated using project_output_dirname and project_folder
	//
	translations            int // how many translations were done so far
	translation_start_ticks i64 // initialised before the loop calling .translate_file()
	has_cfile               bool
	returning_bool          bool
}

fn empty_toml_doc() toml.Doc {
	return toml.parse_text('') or { panic(err) }
}

struct Global {
	name      string
	typ       string
	is_extern bool
}

struct NameType {
	name string
	typ  Type
}

fn filter_line(s string) string {
	return s.replace('false_', 'false').replace('true_', 'true')
}

fn (mut c C2V) genln(s string) {
	if c.indent > 0 && c.out_line_empty {
		c.out.write_string(tabs[c.indent])
	}
	if c.cur_out_line != '' {
		c.out.write_string(filter_line(c.cur_out_line))
		c.cur_out_line = ''
	}
	c.out.writeln(filter_line(s))
	c.out_line_empty = true
}

fn (mut c C2V) gen(s string) {
	if c.indent > 0 && c.out_line_empty {
		c.out.write_string(tabs[c.indent])
	}
	c.cur_out_line += s
	c.out_line_empty = false
}

fn (mut c C2V) save() {
	vprintln('\n\n')
	mut s := c.out.str()
	vprintln('VVVV len=$c.labels.len')
	vprintln(c.labels.str())
	// If there are goto statements, replace all placeholders with actual `goto label_name;`
	// Because JSON AST doesn't have label names for some reason, just IDs.
	if c.labels.len > 0 {
		for label_name, label_id in c.labels {
			vprintln('"$label_id" => "$label_name"')
			s = s.replace('_GOTO_PLACEHOLDER_' + label_id, label_name)
		}
	}
	c.out_file.write_string(s) or { panic('failed to write to the .v file: $err') }
	c.out_file.close()
	if s.contains('FILE') {
		c.has_cfile = true
	}
	if !c.is_wrapper && !c.outv.contains('st_lib.v') {
		os.system('v fmt -translated -w $c.outv > /dev/null')
	}
}

struct IncludedFrom {
	file string
}

struct Loc {
	offset        int
	file          string
	line          int
	col           int
	tok_len       int
	included_from IncludedFrom [json: 'includedFrom']
	spelling_loc  IncludedFrom [json: 'spellingLoc']
	range         Range
}

struct Range {
	begin Begin
}

struct Begin {
	spelling_loc IncludedFrom [json: 'spellingLoc']
}

// recursive
fn set_kind_enum(mut n Node) {
	for mut child in n.inner {
		child.kind = node_kind_from_str(child.kind_str)
		if child.referenced_decl.kind_str != '' {
			child.referenced_decl.kind = node_kind_from_str(child.referenced_decl.kind_str)
		}
		if child.inner.len > 0 {
			set_kind_enum(mut child)
		}
	}
}

fn new_c2v(args []string) &C2V {
	mut c2v := &C2V{
		is_wrapper: args.len > 1 && args[1] == 'wrapper'
	}
	c2v.handle_configuration(args)
	return c2v
}

fn (mut c2v C2V) add_file(ast_path string, outv string, c_file string) {
	vprintln('new tree(outv=$outv c_file=$c_file)')
	c_file_contents := if c_file == '' {
		''
	} else {
		os.read_file(c_file) or { '' }
	}

	ast_txt := os.read_file(ast_path) or {
		vprintln('failed to read ast file "$ast_path": $err')
		panic(err)
	}
	c2v.tree = json.decode(Node, ast_txt) or {
		vprintln('failed to decode ast file "$ast_path": $err')
		panic(err)
	}

	c2v.outv = outv
	c2v.c_file_contents = c_file_contents
	c2v.cur_file = c_file

	if c2v.is_wrapper {
		// Generate v_wrapper.v in user's current directory
		c2v.wrapper_module_name = os.dir(outv).after('/')
		wrapper_path := c2v.outv
		c2v.out_file = os.create(wrapper_path) or { panic('cant create file "$wrapper_path" ') }
	} else {
		c2v.out_file = os.create(c2v.outv) or {
			vprintln('cant create')
			panic(err)
		}
	}
	c2v.genln('[translated]')
	// Predeclared identifiers
	if !c2v.is_wrapper {
		c2v.genln('module main\n')
	} else if c2v.is_wrapper {
		c2v.genln('module $c2v.wrapper_module_name\n')
	}

	// Convert Clang JSON AST nodes to C2V's nodes with extra info. Skip nodes from libc.
	set_kind_enum(mut c2v.tree)
	for i, mut node in c2v.tree.inner {
		vprintln('\nQQQQ $i $node.name')
		// Builtin types have completely empty "loc" objects:
		// `"loc": {}`
		// Mark them with `is_std`
		if (node.loc.file == '' && node.loc.line == 0 && node.loc.offset == 0
			&& node.loc.spelling_loc.file == '' && node.range.begin.spelling_loc.file == '')
			|| line_is_builtin_header(node.loc.file)
			|| line_is_builtin_header(node.loc.included_from.file)
			|| line_is_builtin_header(node.loc.spelling_loc.file)
			|| node.name in builtin_fn_names {
			vprintln('$c2v.line_i is_std name=$node.name')
			node.is_std = true
			continue
		} else if line_is_source(node.loc.file) {
			vprintln('$c2v.line_i is_source')
		}
		if node.name.contains('mobj_t') {
		}
		vprintln('ADDED TOP NODE line_i=$c2v.line_i')
	}
	if c2v.unhandled_nodes.len > 0 {
		vprintln('GOT SOME UNHANDLED NODES:')
		for s in c2v.unhandled_nodes {
			vprintln(s)
		}
		exit(1)
	}
}

fn (mut c C2V) fn_call(node &Node) {
	expr := node.get2()
	c.expr(expr) // this is `fn_name(`
	// Clean up macos builtin fn names
	// $if macos
	is_memcpy := c.cur_out_line.contains('__builtin___memcpy_chk')
	is_memmove := c.cur_out_line.contains('__builtin___memmove_chk')
	is_memset := c.cur_out_line.contains('__builtin___memset_chk')
	if is_memcpy {
		c.cur_out_line = c.cur_out_line.replace('__builtin___memcpy_chk', 'C.memcpy')
	}
	if is_memmove {
		c.cur_out_line = c.cur_out_line.replace('__builtin___memmove_chk', 'C.memmove')
	}
	if is_memset {
		c.cur_out_line = c.cur_out_line.replace('__builtin___memset_chk', 'C.memset')
	}
	if c.cur_out_line.contains('memset') {
		vprintln('!! $c.cur_out_line')
		c.cur_out_line = c.cur_out_line.replace('memset(', 'C.memset(')
	}
	// Drop last argument if we have memcpy_chk
	is_m := is_memcpy || is_memmove || is_memset
	len := if is_m { 3 } else { node.inner.len - 1 }
	c.gen('(')
	for i, arg in node.inner {
		if is_m && i > len {
			break
		}
		if i > 0 {
			c.expr(arg)
			if i < len {
				c.gen(', ')
			}
		}
	}
	c.gen(')')
}

fn (mut c C2V) fn_decl(node &Node, gen_types string) {
	vprintln('1FN DECL name="$node.name" cur_file="$c.cur_file"')
	c.inside_main = false
	if node.loc.file.contains('usr/include') {
		vprintln('\nskipping fn:')
		vprintln('')
		return
	}
	if c.is_dir && c.cur_file.ends_with('/info.c') {
		// TODO tmp doom hack
		return
	}
	// No statements - it's a function declration, skip it
	no_stmts := if !node.has(.compound_stmt) { true } else { false }

	vprintln('no_stmts: $no_stmts')
	for child in node.inner {
		vprintln('INNER: $child.kind $child.kind_str')
	}
	// Skip C++ tmpl args
	if node.has(.template_argument) {
		cnt := node.nr_children(.template_argument)
		for i := 0; i < cnt; i++ {
			node.get(.template_argument)
		}
	}
	mut name := node.name
	if name in ['invalid', 'referenced'] {
		return
	}
	if !c.contains_word(name) {
		vprintln('RRRR $name not here, skipping')
		// This fn is not found in current .c file, means that it was only
		// in the include file, so it's declared and used in some other .c file,
		// no need to genenerate it here.
		// TODO perf right now this searches an entire .c file for each global.
		return
	}
	if node.typ.q.contains('...)') {
		// TODO handle this better (`...any` ?)
		c.genln('[c2v_variadic]')
	}
	if name.contains('blkcpy') {
		vprintln('GOT FINISH')
	}
	if c.is_wrapper {
		// We don't need fn headers in wrappers, and we also don't need dups
		if no_stmts {
			return
		}
		if name in c.fns {
			return
		}
		if name.starts_with('_') {
			return
		}
		if node.storage_class == 'static' {
			// Static functions are limited to their obejct files.
			// Cant include them into wrappers. Skip.
			vprintln('SKIPPING STATIC')
			return
		}
	}
	c.fns << name
	mut typ := node.typ.q.before('(').trim_space()
	if typ == 'void' {
		typ = ''
	} else {
		typ = convert_type(typ).name
	}
	if typ.contains('...') {
		c.gen('F')
	}
	if name == 'main' {
		c.inside_main = true
		typ = ''
	}
	if true || name.contains('Vile') {
		vprintln('\nFN DECL name="$name" typ="$typ"')
	}

	// Build fn args
	params := c.fn_params(node)

	str_args := if name == 'main' { '' } else { params.join(', ') }
	if !no_stmts {
		mut stmts := node.get(.compound_stmt)
		name += gen_types
		if c.is_wrapper {
			c.genln('fn C.${name}($str_args) $typ\n')
			c.gen('pub ')
		}
		lower := name.to_lower()
		if lower != name {
			c.genln("[c:'$name']")
		}
		name = lower
		if c.is_wrapper {
			// strip the "modulename__" from the start of the function
			stripped_name := name.replace(c.wrapper_module_name + '_', '')
			c.genln('fn ${stripped_name}($str_args) $typ {')
		} else {
			c.genln('fn ${name}($str_args) $typ {')
		}

		if !c.is_wrapper {
			// For wrapper generation just generate function definitions without bodies
			c.statements(stmts)
		} else if c.is_wrapper {
			if typ != '' {
				c.gen('\treturn ')
			} else {
				c.gen('\t')
			}
			c.gen('C.${name}(')

			mut i := 0
			for param in params {
				x := param.trim_space().split(' ')[0]
				if x == '' {
					continue
				}
				c.gen(x)
				if i < params.len - 1 {
					c.gen(', ')
				}
				i++
			}
			c.genln(')\n}')
		}
	} else {
		lower := name.to_lower()
		if lower != name {
			// This fixes unknown symbols errors when building separate .c => .v files into .o files
			// example:
			//
			// [c: 'P_TryMove']
			// fn p_trymove(thing &Mobj_t, x int, y int) bool
			//
			// Now every time `p_trymove` is called, `P_TryMove` will be generated instead.
			c.genln("[c:'$name']")
		}
		name = lower
		c.genln('fn ${name}($str_args) $typ')
	}
	c.genln('')
	vprintln('END OF FN DECL ast line=$c.line_i')
}

fn (c &C2V) fn_params(node &Node) []string {
	mut str_args := []string{cap: 5}
	nr_params := node.nr_children(.parm_var_decl)
	for i := 0; i < nr_params; i++ {
		param := node.get(.parm_var_decl)
		arg_typ := convert_type(param.typ.q)
		if arg_typ.name.contains('...') {
			vprintln('vararg: ' + arg_typ.name)
		}
		param_name := filter_name(param.name).to_lower()
		str_args << '$param_name $arg_typ.name'
	}
	return str_args
}

// converts a C type to a V type
fn convert_type(typ_ string) Type {
	mut typ := typ_
	if true || typ.contains('type_t') {
		vprintln('\nconvert_type("$typ")')
	}

	if typ.contains('int64') && !typ.contains(' ') {
		return Type{
			name: 'i64'
		}
	}
	if typ.contains('__va_list_tag *') {
		return Type{
			name: 'va_list'
		}
	}
	// TODO DOOM hack
	typ = typ.replace('fixed_t', 'int')

	is_const := typ.contains('const ')
	if is_const {
	}
	typ = typ.replace('const ', '')
	typ = typ.replace('volatile ', '')
	typ = typ.replace('std::', '')
	if typ == 'char **' {
		return Type{
			name: '&&u8'
		}
	}
	if typ == 'void *' {
		return Type{
			name: 'voidptr'
		}
	} else if typ == 'void **' {
		return Type{
			name: '&voidptr'
		}
	} else if typ.starts_with('void *[') {
		return Type{
			name: '[' + typ.substr('void *['.len, typ.len - 1) + ']voidptr'
		}
	}
	// int[3]
	mut idx := ''
	if typ.contains('[') && typ.contains(']') {
		if true {
			pos := typ.index('[') or { panic('no [ in conver_type($typ)') }
			idx = typ[pos..]
			typ = typ[..pos]
		} else {
			idx = typ.after('[')
			idx = '[' + idx
			typ = typ.before('[')
		}
	}
	// leveldb::DB
	if typ.contains('::') {
		typ = typ.after('::')
	}
	// boolean:boolean
	else if typ.contains(':') {
		typ = typ.all_before(':')
	}
	typ = typ.replace(' void *', 'voidptr')

	// char*** => ***char
	mut base := typ.trim_space().replace_each(['struct ', '']) //, 'signed ', ''])
	if base.starts_with('signed ') {
		// "signed char" == "char", so just ignore "signed "
		base = base['signed '.len..]
	}
	if base.ends_with('*') {
		base = base.before(' *')
	}

	base = match base {
		'long long' {
			'i64'
		}
		'long' {
			'int'
		}
		'unsigned int' {
			'u32'
		}
		'unsigned long long' {
			'i64'
		}
		'unsigned long' {
			'u32'
		}
		'unsigned char' {
			'u8'
		}
		'*unsigned char' {
			'&u8'
		}
		'unsigned short' {
			'u16'
		}
		'uint32_t' {
			'u32'
		}
		'int32_t' {
			'int'
		}
		'uint64_t' {
			'u64'
		}
		'int64_t' {
			'i64'
		}
		'int16_t' {
			'i16'
		}
		'uint8_t' {
			'u8'
		}
		'__int64_t' {
			'i64'
		}
		'__int32_t' {
			'int'
		}
		'__uint32_t' {
			'u32'
		}
		'__uint64_t' {
			'u64'
		}
		'short' {
			'i16'
		}
		'char' {
			'i8'
		}
		'float' {
			'f32'
		}
		'double' {
			'f64'
		}
		'byte' {
			'u8'
		}
		//  just to avoid capitalizing these:
		'int' {
			'int'
		}
		'voidptr' {
			'voidptr'
		}
		'intptr_t' {
			'C.intptr_t'
		}
		'void' {
			'void'
		}
		'u32' {
			'u32'
		}
		'size_t' {
			'usize'
		}
		'ptrdiff_t' {
			'isize'
		}
		'boolean', '_Bool', 'Bool', 'bool (int)', 'bool' {
			'bool'
		}
		'FILE' {
			'C.FILE'
		}
		else {
			trim_underscores(base.capitalize())
		}
	}
	mut amps := ''

	if typ.ends_with('*') {
		star_pos := typ.index('*') or { -1 }

		nr_stars := typ[star_pos..].len
		amps = strings.repeat(`&`, nr_stars)
		typ = amps + base
	}
	// fn type
	// int (*)(void *, int, char **, char **)
	// fn (voidptr, int, *byteptr, *byteptr) int
	else if typ.contains('(*)') {
		ret_typ := convert_type(typ.all_before('('))
		mut s := 'fn ('
		// move fn to the right place
		typ = typ.replace('(*)', ' ')
		// handle each arg
		sargs := typ.find_between('(', ')')
		args := sargs.split(',')
		for i, arg in args {
			t := convert_type(arg)
			s += t.name
			if i < args.len - 1 {
				s += ', '
			}
		}
		// Function doesn't return anything
		if ret_typ.name == 'void' {
			typ = s + ')'
		} else {
			typ = '$s) $ret_typ.name'
		}
		// C allows having fn(void) instead of fn()
		typ = typ.replace('(void)', '()')
	} else {
		typ = base
	}
	// User & => &User
	if typ.ends_with(' &') {
		typ = typ[..typ.len - 2]
		base = typ
		typ = '&' + typ
	}
	typ = typ.trim_space()
	if typ.contains('&& ') {
		typ = typ.replace(' ', '')
	}
	if typ.contains(' ') {
	}
	vprintln('"$typ_" => "$typ" base="$base"')

	name := idx + typ
	return Type{
		name: name
		is_const: is_const
	}
}

// |-RecordDecl 0x7fd7c302c560 <a.c:3:1, line:5:1> line:3:8 struct User definition
fn (mut c C2V) record_decl(node &Node) {
	vprintln('record_decl("$node.name")')
	// Skip empty structs (extern or forward decls)
	if node.iss(.record_decl) && node.inner.len == 0 {
		return
	}
	mut name := node.name
	// Dont generate struct header if it was already generated by typedef
	// Confusing, but typedefs in C AST are really messy.
	// ...
	// If the struct has no name, then it's `typedef struct { ... } name`
	// AST: 1) RecordDecl struct definition 2) TypedefDecl struct name

	if c.tree.inner.len > c.node_i + 1 {
		next_node := c.tree.inner[c.node_i + 1]

		if next_node.kind == .typedef_decl {
			if c.is_verbose {
				c.genln('// typedef struct')
			}

			name = next_node.name

			if name.contains('apthing_t') {
				vprintln(node.str())
			}
		}
	}

	if name in builtin_type_names {
		return
	}
	if c.is_verbose {
		c.genln('// struct decl name="$name"')
	}
	if name in c.types {
		return
	}
	if name !in ['struct', 'union'] {
		c.types << name
		name = capitalize_type(name)
		if node.tag_used.contains('union') {
			c.genln('union $name { ')
		} else {
			c.genln('struct $name { ')
		}
	}
	for field in node.inner {
		// There may be comments, skip them
		if field.kind != .field_decl {
			continue
		}
		field_type := convert_type(field.typ.q)
		field_name := filter_name(field.name)
		if field_type.name.contains('anonymous at') {
			continue
		}
		/*
		if field_type.name.contains('union') {
			continue // TODO
		}
		*/
		if field_type.name.ends_with('_s') { // TODO doom _t _s hack, remove
			n := field_type.name[..field_type.name.len - 2] + '_t'
			c.genln('\t$field_name $n')
		} else {
			c.genln('\t$field_name $field_type.name')
		}
	}
	c.genln('}')
}

// Typedef node goes after struct enum, but we need to parse it first, so that "type name { " is
// generated first
fn (mut c C2V) typedef_decl(node &Node) {
	mut typ := node.typ.q
	// just a single line typedef: (alias)
	// typedef sha1_context_t sha1_context_s ;
	// typedef after enum decl, just generate "enum NAME {" header
	mut alias_name := node.name // get_val(-2)
	vprintln('TYPEDEF "$node.name" $node.is_std $typ')
	if alias_name.contains('et_context_t') {
		// TODO remove this
		return
	}
	if node.name in builtin_type_names {
		return
	}
	if !typ.contains(alias_name) {
		if typ.contains('(*)') {
			tt := convert_type(typ)
			typ = tt.name
		}
		// Struct types have junk before spaces
		else {
			alias_name = alias_name.all_after(' ')
			tt := convert_type(typ)
			typ = tt.name
		}
		if alias_name.starts_with('__') {
			// Skip internal stuff like __builtin_ms_va_list
			return
		}
		if alias_name in c.types || alias_name in c.enums {
			// This means that this is a struct/enum typedef that has already been defined.
			return
		}
		if typ in c.enums {
			return
		}
		c.types << alias_name
		mut cgen_alias := typ
		if cgen_alias.starts_with('_') {
			cgen_alias = trim_underscores(typ)
		}
		if typ !in ['int', 'i8', 'i16', 'u8', 'i64', 'u32', 'f64'] && !typ.starts_with('fn (') {
			// TODO handle this better
			cgen_alias = cgen_alias.capitalize()
		}
		c.genln('type $alias_name.capitalize() = $cgen_alias') // typedef alias (SINGLE LINE)')
		return
	}
	if typ.contains('enum ') {
		// enums were alredy handled in enum_decl
		return
	} else if typ.contains('struct ') {
		// structs were already handled in struct_decl
		return
	} else if typ.contains('union ') {
		// unions were alredy handled in struct_decl
		return
	}
}

// this calls typedef_decl() above
fn (mut c C2V) parse_next_typedef() bool {
	// Hack: typedef with the actual enum name is next, parse it and generate "enum NAME {" first
	/*
	XTODO
	next_line := c.lines[c.line_i + 1]
	if next_line.contains('TypedefDecl') {
		c.line_i++
		c.parse_next_node()
		return true
	}
	*/
	return false
}

fn (mut c C2V) enum_decl(node &Node) {
	// Hack: typedef with the actual enum name is next, parse it and generate "enum NAME {" first
	mut enum_name := node.name //''
	next_node := c.tree.inner[c.node_i + 1]
	if next_node.kind == .typedef_decl {
		enum_name = next_node.name
	}

	if enum_name == 'boolean' {
		return
	}
	if enum_name == '' {
		// empty enum means it's just a list of #define'ed consts
		c.genln('\nconst ( // empty enum')
	} else {
		enum_name = enum_name.capitalize().replace('Enum ', '')
		if enum_name in c.enums {
			return
		}

		c.genln('enum $enum_name {')
	}
	mut vals := c.enum_vals[enum_name]
	for i, child in node.inner {
		name := filter_name(child.name.to_lower())
		vals << name
		// empty enum means it's just a list of #define'ed consts
		if enum_name == '' {
			if !name.starts_with('_') && name !in c.consts {
				c.consts << name
				c.genln('\t$name = $i')
			}
		} else {
			c.gen('\t' + name)
			// handle custom enum vals, e.g. `MF_SHOOTABLE = 4`
			if child.inner.len > 0 {
				const_expr := child.get2()
				if const_expr.kind == .constant_expr {
					c.gen(' = ')
					c.skip_parens = true
					c.expr(const_expr.get2())
					c.skip_parens = false
				}
			} else {
				c.genln('')
			}
		}
	}
	if enum_name != '' {
		vprintln('decl enum "$enum_name" with $vals.len vals')
		c.enum_vals[enum_name] = vals
		c.genln('}\n')
	} else {
		c.genln(')\n')
	}
	if enum_name != '' {
		c.enums << enum_name
	}
}

fn (mut c C2V) statements(compound_stmt &Node) {
	c.indent++
	// Each CompoundStmt's child is a statement
	for i, _ in compound_stmt.inner {
		c.statement(compound_stmt.inner[i])
	}
	c.indent--
	c.genln('}')
}

fn (mut c C2V) statements_no_rcbr(compound_stmt &Node) {
	for i, _ in compound_stmt.inner {
		c.statement(compound_stmt.inner[i])
	}
}

fn (mut c C2V) statement(child &Node) {
	if child.iss(.decl_stmt) {
		c.var_decl(child)
		c.genln('')
	} else if child.iss(.return_stmt) {
		c.return_st(child)
		c.genln('')
	} else if child.iss(.if_stmt) {
		c.if_statement(child)
	} else if child.iss(.while_stmt) {
		c.while_st(child)
	} else if child.iss(.for_stmt) {
		c.for_st(child)
	} else if child.iss(.do_stmt) {
		c.do_st(child)
	} else if child.iss(.switch_stmt) {
		c.switch_st(child)
	}
	// Just  { }
	else if child.iss(.compound_stmt) {
		c.genln('{')
		c.statements(child)
	} else if child.iss(.gcc_asm_stmt) {
		c.genln('__asm__') // TODO
	} else if child.iss(.goto_stmt) {
		c.goto_stmt(child)
	} else if child.iss(.label_stmt) {
		label := child.name // child.get_val(-1)
		c.labels[child.name] = child.decl_id
		c.genln('/*RRRREG $child.name id=$child.decl_id */')
		c.genln('$label: ')
		c.statements_no_rcbr(child)
	}
	// C++
	else if child.iss(.cxx_for_range_stmt) {
		c.for_range(child)
	} else {
		c.expr(child)
		c.genln('')
	}
}

fn (mut c C2V) goto_stmt(node &Node) {
	mut label := c.labels[node.label_id]
	if label == '' {
		label = '_GOTO_PLACEHOLDER_' + node.label_id
	}
	c.genln('goto $label /* id: $node.label_id */')
}

fn (mut c C2V) return_st(node &Node) {
	c.gen('return ')
	// returning expression?
	if node.inner.len > 0 && !c.inside_main {
		expr := node.get2()
		if expr.iss(.implicit_cast_expr) {
			if expr.typ.q == 'bool' {
				// Handle `return 1` which is actually `return true`
				c.returning_bool = true
			}
		}
		c.expr(expr)
		c.returning_bool = false
	}
}

fn (mut c C2V) if_statement(node &Node) {
	expr := node.get2()
	c.gen('if ')
	c.gen_bool(expr)
	// Main if block
	mut child := node.get2()
	if child.iss(.null_stmt) {
		// The if branch body can be empty (`if (foo) ;`)
		c.genln(' {/* empty if */}')
	} else {
		c.st_block(child)
	}
	// Optional else block
	mut else_st := node.get2()
	if else_st.iss(.compound_stmt) {
		c.genln('else {')
		c.st_block_no_start(else_st)
	}
	// else if
	else if else_st.iss(.if_stmt) {
		c.gen('else ')
		c.if_statement(else_st)
	}
	// `else expr() ;` else statement in one line without {}
	else if !else_st.iss(.bad) && !else_st.iss(.null) {
		c.genln('else { // 3')
		c.expr(else_st)
		c.genln('\n}')
	}
}

fn (mut c C2V) while_st(node &Node) {
	c.gen('for ')
	expr := node.get2()
	c.gen_bool(expr)
	c.genln(' {')
	mut stmts := node.get2()
	c.st_block_no_start(stmts)
}

fn (mut c C2V) for_st(node &Node) {
	c.inside_for = true
	c.gen('for ')
	// Can be "for (int i = ...)"
	if node.has(.decl_stmt) {
		mut decl_stmt := node.get(.decl_stmt)
		c.var_decl(decl_stmt)
	}
	// Or "for (i = ....)"
	else {
		expr := node.get2()
		c.expr(expr)
	}
	c.gen(' ; ')
	mut expr2 := node.get2()
	if expr2.kind_str == '' {
		// second cond can be Null
		expr2 = node.get2()
	}
	c.expr(expr2)
	c.gen(' ; ')
	expr3 := node.get2()
	c.expr(expr3)
	c.inside_for = false
	mut child := node.get2()
	c.st_block(child)
}

fn (mut c C2V) do_st(node &Node) {
	c.genln('for {')
	mut child := node.get2()
	c.statements_no_rcbr(child)
	// TODO condition
	c.genln('// while()')
	c.gen('if ! (')
	expr := node.get2()
	c.expr(expr)
	c.genln(' ) { break }')
	c.genln('}')
}

// Switch statements are a mess in C...
fn (mut c C2V) switch_st(switch_node &Node) {
	c.gen('match ')
	c.inside_switch++
	mut expr := switch_node.get2()
	mut is_enum := false
	if expr.inner.len > 0 {
		// 0
		x := expr.inner[0]
		if x.typ.q == 'int' {
			// this is an int, not a C enum type
			c.inside_switch_enum = false
		} else {
			c.inside_switch_enum = true
			is_enum = true
		}
	}
	comp_stmt := switch_node.get2()
	// Detect if this switch statement runs on an enum (have to look at the first
	// value being compared). This means that the integer will have to be cast to this enum
	// in V.
	// switch (x) { case enum_val: ... }   ==>
	// match MyEnum(x) { .enum_val { ... } }
	// Don't cast if it's already an enum and not an int. Enum(enum) compiles, but still.
	mut second_par := false
	if comp_stmt.inner.len > 0 {
		mut child := comp_stmt.inner[0]
		if child.iss(.case_stmt) {
			mut case_expr := child.get2()
			if case_expr.iss(.constant_expr) {
				x := case_expr.get2()
				vprintln('YEP')

				if x.referenced_decl.kind == .enum_constant_decl {
					is_enum = true
					c.inside_switch_enum = true
					c.gen(c.enum_val_to_enum_name(x.referenced_decl.name))

					c.gen('(')
					second_par = true
				}
			}
		}
	}
	// Now the opposite. Detect if the switch runs on a C int which is an enum in V.
	// switch (x) { case enum_val: ... }   ==>
	// match (x) { int(.enum_val) { ... } }

	//
	c.expr(expr)
	if is_enum {
	}
	if second_par {
		c.gen(')')
	}
	// c.inside_switch_enum = false
	c.genln(' {')
	mut got_else := false
	// Switch AST node is weird. First child is a CaseStmt that contains a single child
	// statement (the first in the block). All other statements in the block are siblings
	// of this CaseStmt:
	// switch (x) {
	//   case 1:
	//     line1(); // child of CaseStmt
	//     line2(); // CallExpr (sibling of CaseStmt)
	//     line3(); // CallExpr (sibling of CaseStmt)
	// }
	mut end_added := false
	for i, child in comp_stmt.inner {
		if child.iss(.case_stmt) {
			if is_enum {
				// Force short `.val {` enum syntax, but only in `case .val:`
				// Later on it'll be set to false, so that full syntax is used (`Enum.val`)
				// Since enums are often used as ints, and V will need the full enum
				// value to convert it to ints correctly.
				c.inside_switch_enum = true
			}
			c.gen(' ')
			case_expr := child.get2()
			if i > 0 {
				c.genln('}')
			}
			c.expr(case_expr)
			mut a := child.get2()
			if a.iss(.null) {
				a = child.get2()
			}
			vprintln('A TYP=$a.typ')
			if a.iss(.compound_stmt) {
				c.genln('// case comp stmt')
				c.statements(a)
			} else if a.iss(.case_stmt) {
				// case 1:
				// case 2:
				// case 3:
				// ===>
				// case 1, 2, 3:
				for a.iss(.case_stmt) {
					e := a.get2()
					c.gen(', ')
					c.expr(e) // this is `1` in `case 1:`
					mut tmp := a.get2()
					if tmp.iss(.null) {
						tmp = a.get2()
					}
					a = tmp
				}
				c.genln('{')
				vprintln('!!!!!!!!caseexpr=')
				c.inside_switch_enum = false
				c.statement(a)
				end_added = true
			} else if a.iss(.default_stmt) {
			}
			// case body
			else {
				c.inside_switch_enum = false
				c.genln('// case comp body kind=$a.kind is_enum=$is_enum ')
				c.genln('{')
				c.statement(a)
				if a.iss(.return_stmt) {
				}
				if is_enum {
					c.inside_switch_enum = true
				}
			}
		} else if child.iss(.break_stmt) {
			if !end_added {
			}
		} else if child.iss(.default_stmt) {
			c.genln('}')

			got_else = true
			c.genln(' else { ')
			mut a := child.get2()

			c.statement(a)
		} else {
			// handle weird children-siblings
			c.inside_switch_enum = false
			c.statement(child)
		}
	}
	if got_else {
		c.genln('}')
	} else {
		c.genln('}else{}')
	}
	c.genln('}')
	c.inside_switch--
	c.inside_switch_enum = false
}

fn (mut c C2V) st_block_no_start(node &Node) {
	c.st_block2(node, false)
}

fn (mut c C2V) st_block(node &Node) {
	c.st_block2(node, true)
}

// {} or just one statement if there is no {
fn (mut c C2V) st_block2(node &Node, insert_start bool) {
	if insert_start {
		c.genln(' {')
	}
	if node.iss(.compound_stmt) {
		c.statements(node)
	} else {
		// No {}, just one statement
		c.statement(node)
		c.genln('}')
	}
}

//
fn (mut c C2V) gen_bool(node &Node) {
	typ := c.expr(node)
	if typ == 'int' {
	}
}

fn (mut c C2V) var_decl(decl_stmt &Node) {
	for _ in 0 .. decl_stmt.inner.len {
		mut var_decl := decl_stmt.get2()
		if var_decl.iss(.record_decl) || var_decl.iss(.enum_decl) {
			return
		}
		if var_decl.storage_class == 'extern' {
			vprintln('local extern vars are not supported yet: ')
			vprintln(var_decl.str())
			vprintln(c.cur_file + ':' + c.line_i.str())
			exit(1)
			return
		}
		// cinit means we have an initialization together with var declaration:
		// `int a = 0;`
		cinit := var_decl.init == 'c'
		name := filter_name(var_decl.name).to_lower()
		typ_ := convert_type(var_decl.typ.q)
		if typ_.is_static {
			c.gen('static ')
		}
		if cinit {
			expr := var_decl.get2()
			c.gen('$name := ')
			c.expr(expr)
		} else {
			oldtyp := var_decl.typ.q
			mut typ := typ_.name
			vprintln('oldtyp="$oldtyp" typ="$typ"')
			// set default zero value (V requires initialization)
			mut def := ''
			if var_decl.typ.desugared_q.starts_with('struct ') {
				def = '$typ{}' // `struct Foo foo;` => `foo := Foo{}` (empty struct init)
			} else if typ == 'u8' {
				def = 'u8(0)'
			} else if typ == 'u16' {
				def = 'u16(0)'
			} else if typ == 'u32' {
				def = 'u32(0)'
			} else if typ == 'u64' {
				def = 'u64(0)'
			} else if typ in ['size_t', 'usize'] {
				def = 'usize(0)'
			} else if typ == 'i8' {
				def = 'i8(0)'
			} else if typ == 'i16' {
				def = 'i16(0)'
			} else if typ == 'int' {
				def = '0'
			} else if typ == 'i64' {
				def = 'i64(0)'
			} else if typ in ['ptrdiff_t', 'isize'] {
				def = 'isize(0)'
			} else if typ == 'bool' {
				def = 'false'
			} else if typ == 'f32' {
				def = 'f32(0.0)'
			} else if typ == 'f64' {
				def = '0.0'
			} else if typ == 'boolean' {
				def = 'false'
			} else if oldtyp.ends_with('*') {
				// *sqlite3_mutex ==>
				// &sqlite3_mutex{!}
				// println2('!!! $oldtyp $typ')
				// def = '&${typ.right(1)}{!}'
				tt := if typ.starts_with('&') { typ[1..] } else { typ }
				def = '&${tt}(0)'
			} else if typ.starts_with('[') {
				// Empty array init
				def = '$typ{}'
			} else {
				// We assume that everything else is a struct, because C AST doesn't
				// give us any info that typedef'ed structs are structs

				if oldtyp.contains_any_substr(['dirtype_t', 'angle_t']) { // TODO DOOM handle int aliases
					def = 'u32(0)'
				} else {
					def = '$typ{}'
				}
			}
			// vector<int> => int => []int
			if typ.starts_with('vector<') {
				def = typ.substr('vector<'.len, typ.len - 1)
				def = '[]$def'
			}
			c.gen('$name := $def')
			if decl_stmt.inner.len > 1 {
				c.genln('')
			}
		}
	}
}

fn (mut c C2V) global_var_decl(mut var_decl Node) {
	// if the global has children, that means it's initialized, parse the expression
	is_inited := var_decl.inner.len > 0

	vprintln('\nglobal name=$var_decl.name typ=$var_decl.typ.q')
	vprintln(var_decl.str())

	name := filter_name(var_decl.name)

	if var_decl.typ.q.starts_with('[]') {
		return
	}
	typ := convert_type(var_decl.typ.q)
	if var_decl.name in c.globals {
		existing := c.globals[var_decl.name]
		if !types_are_equal(existing.typ, typ.name) {
			c.verror('Duplicate global "$var_decl.name" with different types:"$existing.typ" and	"$typ.name".
Since C projects do not use modules but header files, duplicate globals are allowed.
This will not compile in V, so you will have to modify one of the globals and come up with a
unique name')
		}
		if !existing.is_extern {
			c.genln('// skipping global dup "$var_decl.name"')
			return
		}
	}
	// Skip extern globals that are initialized later in the file.
	// We'll have go thru all top level nodes, find a VarDecl with the same name
	// and make sure it's inited (has a child expressinon).
	is_extern := var_decl.storage_class == 'extern'
	if is_extern && !is_inited {
		for x in c.tree.inner {
			if x.iss(.var_decl) && x.name == var_decl.name && x.id != var_decl.id {
				if x.inner.len > 0 {
					c.genln('// skipped extern global $x.name')
					return
				}
			}
		}
	}
	// We assume that if the global's type is `[N]array`, and it's initialized,
	// then it's constant
	is_fixed_array := var_decl.typ.q.contains(']') && var_decl.typ.q.contains(']')
	is_const := is_inited && (typ.is_const || is_fixed_array)
	if true || !typ.name.contains('[') {
	}
	if c.is_wrapper && typ.name.starts_with('_') {
		return
	}
	if c.is_wrapper {
		return
	}
	if !c.is_dir && is_extern && var_decl.nr_redeclarations > 0 {
		// This is an extern global, and it's declared later in the file without `extern`.
		return
	}
	// Cut generated code from `c.out` to `c.globals_out`
	start := c.out.len
	if is_const {
		c.consts << name
		c.gen("[export:'$name']\nconst (\n$name  ")
	} else {
		if !c.contains_word(name) && !c.cur_file.contains('deh_') { // TODO deh_ hack remove
			vprintln('RRRR global $name not here, skipping')
			// This global is not found in current .c file, means that it was only
			// in the include file, so it's declared and used in some other .c file,
			// no need to genenerate it here.
			// TODO perf right now this searches an entire .c file for each global.
			return
		}
		if name in builtin_global_names {
			return
		}

		if is_inited {
			c.gen('/*!*/[weak] __global ( $name ')
		} else {
			if typ.name.contains('anonymous enum') || typ.name.contains('unnamed enum') {
				// Skip anon enums, they are declared as consts in V
				return
			}

			if is_extern && is_fixed_array && var_decl.nr_redeclarations == 0 {
				c.gen('[c_extern]')
			} else {
				c.gen('[weak]')
			}
			c.gen('__global ( $name $typ.name ')
		}
		c.global_struct_init = typ.name
	}
	if is_fixed_array && var_decl.typ.q.contains('[]') && !var_decl.typ.q.contains('*')
		&& !is_inited {
		// Do not allow uninitialized fixed arrays for now, since they are not supported by V
		eprintln('$c.cur_file: uninitialized fixed array without the size "$name" typ="$var_decl.typ.q"')
		exit(1)
	}

	// if the global has children, that means it's initialized, parse the expression
	if is_inited {
		child := var_decl.get2()
		c.gen(' = ')
		is_struct := child.iss(.init_list_expr) && !is_fixed_array
		needs_cast := !is_const && !is_struct // Don't generate `foo=Foo(Foo{` if it's a struct init
		if needs_cast {
			c.gen(typ.name + ' (') ///* typ=$typ   KIND= $child.kind isf=$is_fixed_array*/(')
		}
		c.expr(child)
		if needs_cast {
			c.gen(')')
		}
		c.genln('')
	} else {
		c.genln('\n')
	}
	if true {
		c.genln(')\n')
	}
	if c.is_dir {
		s := c.out.cut_to(start)
		c.globals_out[name] = s
	}
	c.global_struct_init = ''
	c.globals[name] = Global{
		name: name
		is_extern: is_extern
		typ: typ.name
	}
}

// `"red"` => `"Color"`
fn (c &C2V) enum_val_to_enum_name(enum_val string) string {
	filtered_enum_val := filter_name(enum_val)
	for enum_name, vals in c.enum_vals {
		if filtered_enum_val in vals {
			return enum_name
		}
	}
	return ''
}

// expr is a spcial one. we dont know what type node has.
// can be multiple.
fn (mut c C2V) expr(_node &Node) string {
	mut node := unsafe { _node }
	// Just gen a number
	if node.iss(.null) {
		return ''
	}
	if node.iss(.integer_literal) {
		if c.returning_bool {
			if node.value == '1' {
				c.gen('true')
			} else {
				c.gen('false')
			}
		} else {
			c.gen(node.value)
		}
	}
	// 'a'
	else if node.iss(.character_literal) {
		c.gen('`' + rune(node.value_number).str() + '`')
	}
	// 1e80
	else if node.iss(.floating_literal) {
		c.gen(node.value)
	} else if node.iss(.constant_expr) {
		n := node.get2()
		c.expr(&n)
	}
	// null
	else if node.iss(.null_stmt) {
		c.gen('0 /* null */')
	} else if node.iss(.cold_attr) {
	}
	// = + - *
	else if node.iss(.binary_operator) {
		op := node.opcode
		mut first_expr := node.get2()
		c.expr(first_expr)
		c.gen(' $op ')
		mut second_expr := node.get2()

		if second_expr.iss(.binary_operator) && second_expr.opcode == '=' {
			// handle `a = b = c` => `a = c; b = c;`
			second_child_expr := second_expr.get2() // `b`
			mut third_expr := second_expr.get2() // `c`
			c.expr(third_expr)
			c.genln('')
			c.expr(second_child_expr)
			c.gen(' = ')
			first_expr.child_i = 0
			c.expr(first_expr)
			c.gen('')
			second_expr.child_i = 0
		} else {
			c.expr(second_expr)
		}
		vprintln('done!')
		if op == '<' || op == '>' || op == '==' {
			return 'bool'
		}
	}
	// +=
	else if node.iss(.compound_assign_operator) {
		op := node.opcode // get_val(-3)
		first_expr := node.get2()
		c.expr(first_expr)
		c.gen(' $op ')
		second_expr := node.get2()
		c.expr(second_expr)
	}
	// ++ --
	else if node.iss(.unary_operator) {
		op := node.opcode
		expr := node.get2()
		if op in ['--', '++'] {
			c.expr(expr)
			c.gen(' $op')
			if !c.inside_for && !node.is_postfix {
				// prefix ++
				// but do not generate `++i` in for loops, it breaks in V for some reason
				c.gen('$')
			}
		} else if op == '-' || op == '&' || op == '*' || op == '!' || op == '~' {
			c.gen(op)
			c.expr(expr)
		}
	}
	// ()
	else if node.iss(.paren_expr) {
		if !c.skip_parens {
			c.gen('(')
		}
		child := node.get2()
		c.expr(child)
		if !c.skip_parens {
			c.gen(')')
		}
	}
	// This junk means go again for its child
	else if node.iss(.implicit_cast_expr) {
		expr := node.get2()
		c.expr(expr)
	}
	// var  name
	else if node.iss(.decl_ref_expr) {
		c.name_expr(node)
	}
	// "string literal"
	else if node.iss(.string_literal) {
		str := node.value
		// "a" => 'a'
		no_quotes := str.substr(1, str.len - 1)
		if no_quotes.contains("'") {
			// same quoting logic as in vfmt
			c.gen('c"$no_quotes"')
		} else {
			c.gen("c'$no_quotes'")
		}
	}
	// fn call
	else if node.iss(.call_expr) {
		c.fn_call(node)
	}
	// `user.age`
	else if node.iss(.member_expr) {
		mut field := node.name
		expr := node.get2()
		c.expr(expr)
		field = field.replace('->', '')
		if field.starts_with('.') {
			field = filter_name(field[1..])
		} else {
			field = filter_name(field)
		}
		c.gen('.$field')
	}
	// sizeof
	else if node.iss(.unary_expr_or_type_trait_expr) {
		c.gen('sizeof')
		// sizeof (expr) ?
		if node.inner.len > 0 {
			expr := node.get2()
			c.expr(expr)
		}
		// sizeof (Type) ?
		else {
			typ := convert_type(node.arg_type.q)
			c.gen('($typ.name)')
		}
	}
	// a[0]
	else if node.iss(.array_subscript_expr) {
		first_expr := node.get2()
		c.expr(first_expr)
		c.gen(' [')

		second_expr := node.get2()
		c.inside_array_index = true
		c.expr(second_expr)
		c.inside_array_index = false
		c.gen('] ')
	}
	// int a[] = {1,2,3};
	else if node.iss(.init_list_expr) {
		c.init_list_expr(mut node)
	}
	// (int*)a  => (int*)(a)
	// CStyleCastExpr 'const char **' <BitCast>
	else if node.iss(.c_style_cast_expr) {
		expr := node.get2()
		typ := convert_type(node.typ.q)
		mut cast := typ.name
		if cast.contains('*') {
			cast = '($cast)'
		}
		c.gen('${cast}(')
		c.expr(expr)
		c.gen(')')
	}
	// ? :
	else if node.iss(.conditional_operator) {
		c.gen('if ') // { } else { }')
		expr := node.get2()
		case1 := node.get2()
		case2 := node.get2()
		c.expr(expr)
		c.gen('{ ')
		c.expr(case1)
		c.gen(' } else {')
		c.expr(case2)
		c.gen('}')
	} else if node.iss(.break_stmt) {
		if c.inside_switch == 0 {
			c.genln('break')
		}
	} else if node.iss(.continue_stmt) {
		c.genln('continue')
	} else if node.iss(.goto_stmt) {
		c.goto_stmt(node)
	} else if node.iss(.opaque_value_expr) {
		// TODO
	} else if node.iss(.paren_list_expr) {
	} else if node.iss(.va_arg_expr) {
	} else if node.iss(.compound_stmt) {
	} else if node.iss(.offset_of_expr) {
	} else if node.iss(.array_filler) {
		c.gen('/*AFFF*/')
	} else if node.iss(.goto_stmt) {
	} else if node.iss(.implicit_value_init_expr) {
	} else if c.cpp_expr(node) {
	} else if node.iss(.bad) {
		vprintln('BAD node in expr()')
		vprintln(node.str())
	} else {
		eprintln('\n\nUnhandled expr() node {$node.kind} (ast line nr node.ast_line_nr "$c.cur_file"):')

		eprintln(node.str())

		print_backtrace()
		exit(1)
	}
	return node.value // get_val(0)
}

fn (mut c C2V) name_expr(node &Node) {
	// `GREEN` => `Color.GREEN`
	// Find the enum that has this value
	// vals:
	// ["int", "EnumConstant", "MT_SPAWNFIRE", "int"]
	is_enum_val := node.referenced_decl.kind == .enum_constant_decl

	if is_enum_val {
		enum_val := node.referenced_decl.name.to_lower()
		mut need_full_enum := true // need `Color.green` instead of just `.green`

		if c.inside_switch != 0 && c.inside_switch_enum {
			// generate just `match ... { .val { } }`, not `match ... { Enum.val { } }`
			need_full_enum = false
		}
		if c.inside_array_index {
			need_full_enum = true
		}
		enum_name := c.enum_val_to_enum_name(enum_val)
		if c.inside_array_index {
			// `foo[ENUM_VAL]` => `foo(int(ENUM_NAME.ENUM_VAL))`
			c.gen('int(')
		}
		if need_full_enum {
			c.gen(enum_name)
		}
		if enum_val !in ['true', 'false'] && enum_name != '' {
			// Don't add a `.` before "const" enum vals so that e.g. `tmbbox[BOXLEFT]`
			// won't get translated to `tmbbox[.boxleft]`
			// (empty enum name means its enum vals are consts)

			c.gen('.')
		}
	}

	mut name := node.referenced_decl.name

	if name !in c.consts && name !in c.globals {
		// Functions and variables are all lowercase in V
		name = name.to_lower()
		if name.starts_with('c.') {
			name = 'C.' + name[2..] // TODO why is this needed?
		}
	}

	c.gen(filter_name(name))
	if is_enum_val && c.inside_array_index {
		c.gen(')')
	}
}

fn (mut c C2V) init_list_expr(mut node Node) {
	t := node.typ.q
	// c.gen(' /* list init $t */ ')
	// C list init can be an array (`numbers = {1,2,3}` => `numbers = [1,2,3]``)
	// or a struct init (`user = {"Bob", 20}` => `user = {'Bob', 20}`)
	is_arr := t.contains('[')
	if !is_arr {
		c.genln(parse_c_struct_name(t) + ' {')
	} else {
		c.gen('[')
	}
	if node.array_filler.len > 0 {
		for i, mut child in node.array_filler {
			// array_filler nodes were not handled by set_kind_enum
			child.set_node_kind_recursively()

			if child.iss(.implicit_value_init_expr) {
			} else {
				c.expr(child)
				if i < node.array_filler.len - 1 {
					c.gen(', ')
				}
			}
		}
	} else {
		for i, mut child in node.inner {
			if child.kind == .bad {
				child.kind = node_kind_from_str(child.kind_str) // array_filler nodes were not handled by set_kind_enum
			}

			// C allows not to set final fields (a = {1,2,,,,})
			// V requires all fields to be set
			if child.iss(.implicit_value_init_expr) {
				c.gen('0/*IMPLICIT*/')
			} else {
				c.expr(child)
				if i < node.inner.len - 1 {
					c.gen(', ')
				}
			}
		}
	}
	is_fixed := node.typ.q.contains('[') && node.typ.q.contains(']')
	if !is_arr {
		c.genln('}')
	} else {
		if is_fixed {
			c.genln(']!')
		} else {
			c.genln(']')
		}
	}
}

fn filter_name(name string) string {
	if name in v_keywords {
		return '${name}_'
	}
	if name in builtin_fn_names {
		return 'C.' + name
	}
	if name == 'argv' {
		return 'os.argv'
	}
	if name == 'FILE' {
		return 'C.FILE'
	}
	return name
}

fn main() {
	if os.args.len < 2 {
		eprintln('Usage:')
		eprintln('  c2v file.c')
		eprintln('  c2v wrapper file.h')
		eprintln('  c2v folder/')
		exit(1)
	}
	vprintln(os.args.str())
	is_wrapper := os.args[1] == 'wrapper'
	mut path := os.args.last()
	if !os.exists(path) {
		eprintln('"$path" does not exist')
		exit(1)
	}
	mut c2v := new_c2v(os.args)
	println('C to V translator $version')
	c2v.translation_start_ticks = time.ticks()
	if os.is_dir(path) {
		os.chdir(path)?
		println('"$path" is a directory, processing all C files in it recursively...\n')
		files := os.walk_ext('.', '.c')

		if is_wrapper {
		} else {
			if files.len > 0 {
				for file in files {
					c2v.translate_file(file)
				}
				c2v.save_globals()
			}
		}
	} else {
		c2v.translate_file(path)
	}
	delta_ticks := time.ticks() - c2v.translation_start_ticks
	println('Translated ${c2v.translations:3} files in ${delta_ticks:5} ms.')
}

fn (mut c2v C2V) translate_file(path string) {
	start_ticks := time.ticks()
	print('  translating ${path:-15s} ... ')
	flush_stdout()
	c2v.set_config_overrides_for_file(path)
	mut lines := []string{}
	mut ast_path := path
	ext := os.file_ext(path)
	if path.contains('/src/') {
		// Hack to fix 'doomtype.h' file not found
		// TODO come up with a better solution
		work_path := path.before('/src/') + '/src'
		vprintln(work_path)
		os.chdir(work_path) or {}
	}
	additional_clang_flags := c2v.get_additional_flags(path)
	cmd := '$clang $additional_clang_flags -w -Xclang -ast-dump=json -fsyntax-only -fno-diagnostics-color -c ${os.quoted_path(path)}'
	vprintln('DA CMD')
	vprintln(cmd)
	out_ast := if c2v.is_dir {
		os.getwd() + '/' + (os.dir(os.dir(path)) + '/$c2v.project_output_dirname/' +
			os.base(path.replace(ext, '.json')))
	} else {
		// file.c => file.json
		path.replace(ext, '.json')
	}
	out_ast_dir := os.dir(out_ast)
	if c2v.is_dir && !os.exists(out_ast_dir) {
		os.mkdir(out_ast_dir) or { panic(err) }
	}
	vprintln('EXT=$ext out_ast=$out_ast')
	vprintln('out_ast=$out_ast')
	clang_result := os.system('$cmd > $out_ast')
	if clang_result != 0 {
		eprintln('\nThe file $path could not be parsed as a C source file.')
		exit(1)
	}
	lines = os.read_lines(out_ast) or { panic(err) }
	ast_path = out_ast
	vprintln('lines.len=$lines.len')
	out_v := out_ast.replace('.json', '.v')
	short_output_path := out_v.replace(os.getwd() + '/', '')
	c_file := path
	c2v.add_file(ast_path, out_v, c_file)

	// preparation pass, fill in the Node redeclarations field:
	mut seen_ids := map[string]&Node{}
	for i, mut node in c2v.tree.inner {
		c2v.node_i = i
		seen_ids[node.id] = unsafe { node }
		if node.previous_decl != '' {
			if mut pnode := seen_ids[node.previous_decl] {
				pnode.nr_redeclarations++
			}
		}
	}
	// Main parse loop
	for i, node in c2v.tree.inner {
		vprintln('\ndoing top node $i $node.kind name="$node.name" is_std=$node.is_std')
		c2v.node_i = i
		c2v.top_level(node)
	}
	if os.args.contains('-print_tree') {
		c2v.print_entire_tree()
	}
	if !os.args.contains('-keep_ast') {
		os.rm(out_ast) or { panic(err) }
	}
	vprintln('DONE!2')
	c2v.save()
	c2v.translations++
	delta_ticks := time.ticks() - start_ticks
	println(' took ${delta_ticks:5} ms ; output .v file: $short_output_path')
}

fn (mut c2v C2V) print_entire_tree() {
	for _, node in c2v.tree.inner {
		print_node_recursive(node, 0)
	}
}

fn print_node_recursive(node &Node, ident int) {
	vprint('  '.repeat(ident))
	vprintln('$node.kind n="$node.name"')
	for child in node.inner {
		print_node_recursive(child, ident + 1)
	}
	if node.array_filler.len > 0 {
		for child in node.array_filler {
			print_node_recursive(child, ident + 1)
		}
	}
}

fn (mut c C2V) top_level(_node &Node) {
	mut node := unsafe { _node }
	if node.is_std {
		vprintln('is std, ret (name="$node.name")')
		return
	}
	if node.iss(.typedef_decl) {
		c.typedef_decl(node)
	} else if node.iss(.function_decl) {
		c.fn_decl(node, '')
	} else if node.iss(.record_decl) {
		c.record_decl(node)
	} else if node.iss(.var_decl) {
		c.global_var_decl(mut node)
	} else if node.iss(.enum_decl) {
		c.enum_decl(node)
	} else if !c.cpp_top_level(node) {
		vprintln('\n\nUnhandled non C++ top level node typ=$node.typ:')
		exit(1)
	}
}

fn (node &Node) get_int_define() string {
	return 'HEADER'
}

// "'struct Foo':'struct Foo'"  => "Foo"
fn parse_c_struct_name(typ string) string {
	mut res := typ.all_before(':')
	res = res.replace('struct ', '')
	res = res.capitalize() // lowercase structs are stored as is, but need to be capitalized during gen
	return res
}

fn trim_underscores(s string) string {
	mut i := 0
	for i < s.len {
		if s[i] != `_` {
			break
		}
		i++
	}
	return s[i..]
}

fn capitalize_type(s string) string {
	mut name := s
	if name.starts_with('_') {
		// Trim "_" from the start of the struct name
		// TODO this can result in conflicts
		name = trim_underscores(name)
	}
	if !name.starts_with('fn ') {
		name = name.capitalize()
	}
	return name
}

fn (c &C2V) verror(msg string) {
	$if linux {
		eprintln('\x1b[31merror: $msg\x1b[0m')
	} $else {
		eprintln('error: $msg')
	}
	exit(1)
}

fn (c &C2V) contains_word(word string) bool {
	return c.c_file_contents.contains(word)
}

fn (mut c2v C2V) save_globals() {
	globals_path := c2v.get_globals_path()
	mut f := os.create(globals_path) or { panic(err) }
	defer {
		f.close()
	}
	f.writeln('[translated]\n') or { panic(err) }
	if c2v.has_cfile {
		f.writeln('[typedef]\nstruct C.FILE {}') or { panic(err) }
	}
	for _, g in c2v.globals_out {
		f.writeln(g) or { panic(err) }
	}
}

[if trace_verbose ?]
fn vprintln(s string) {
	println(s)
}

[if trace_verbose ?]
fn vprint(s string) {
	print(s)
}

fn types_are_equal(a string, b string) bool {
	if a == b {
		return true
	}
	if a.starts_with('[') && b.starts_with('[') {
		return a.after(']') == b.after(']')
	}
	return false
}
