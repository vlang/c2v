// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
module main

import os
import strings
import json
import time
import toml

const version = '0.4.0'

// V keywords, that are not keywords in C:
const v_keywords = ['go', 'type', 'true', 'false', 'module', 'byte', 'in', 'none', 'map', 'string',
	'spawn', 'shared', 'select', 'as']

// libc fn definitions that have to be skipped (V already knows about them):
const builtin_fn_names = ['fopen', 'puts', 'fflush', 'printf', 'memset', 'atoi', 'memcpy', 'remove',
	'strlen', 'rename', 'stdout', 'stderr', 'stdin', 'ftell', 'fclose', 'fread', 'read', 'perror',
	'ftruncate', 'FILE', 'strcmp', 'toupper', 'strchr', 'strdup', 'strncasecmp', 'strcasecmp',
	'isspace', 'strncmp', 'malloc', 'close', 'open', 'lseek', 'fseek', 'fgets', 'rewind', 'write',
	'calloc', 'setenv', 'gets', 'abs', 'sqrt', 'erfl', 'fprintf', 'snprintf', 'exit', '__stderrp',
	'fwrite', 'scanf', 'sscanf', 'strrchr', 'strchr', 'div', 'free', 'memcmp', 'memmove', 'vsnprintf',
	'rintf', 'rint', 'bsearch', 'qsort', '__stdinp', '__stdoutp', '__stderrp']

const c_known_fn_names = ['getline']

const c_known_var_names = ['stdin', 'stdout', 'stderr', '__stdinp', '__stdoutp', '__stderrp']

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

fn find_clang_in_path() string {
	clangs := ['clang-17', 'clang-14', 'clang-13', 'clang-12', 'clang-11', 'clang-10', 'clang']
	for clang in clangs {
		os.find_abs_path_of_executable(clang) or { continue }
		return clang
	}
	panic('cannot find clang in PATH')
}

struct LabelStmt {
	name string
}

struct Struct {
mut:
	fields []string
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
	structs             map[string]Struct   // for correct `Foo{field:..., field2:...}` (implicit value init expr is 0, so un-initied fields are just skipped with 0s)
	fns                 []string // to avoid dups
	extern_fns          []string // extern C fns
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
	keep_ast                bool // do not delete ast.json after running
	already_declared_types  map[string]bool // to avoid duplicate type declarations
	last_declared_type_name string
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

pub fn replace_file_extension(file_path string, old_extension string, new_extension string) string {
	// NOTE: It can't be just `file_path.replace(old_extenstion, new_extension)`, because it will replace all occurencies of old_extenstion string.
	//		Path '/dir/dir/dir.c.c.c.c.c.c/kalle.c' will become '/dir/dir/dir.json.json.json.json.json.json/kalle.json'.
	return file_path.trim_string_right(old_extension) + new_extension
}

fn add_place_data_to_error(err IError) string {
	return '${@MOD}.${@FILE_LINE} - ${err}'
}

fn (mut c C2V) genln(s string) {
	if s.starts_with('type ') {
		if s in c.already_declared_types {
			return
		}

		c.already_declared_types[s] = true
	}

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
	vprintln('VVVV len=${c.labels.len}')
	vprintln(c.labels.str())
	// If there are goto statements, replace all placeholders with actual `goto label_name;`
	// Because JSON AST doesn't have label names for some reason, just IDs.
	if c.labels.len > 0 {
		for label_name, label_id in c.labels {
			vprintln('"${label_id}" => "${label_name}"')
			s = s.replace('_GOTO_PLACEHOLDER_' + label_id, label_name)
		}
	}
	c.out_file.write_string(s) or { panic('failed to write to the .v file: ${err}') }
	c.out_file.close()
	if s.contains('FILE') {
		c.has_cfile = true
	}
	if !c.is_wrapper && !c.outv.contains('st_lib.v') {
		os.system('v fmt -translated -w ${c.outv} > /dev/null')
	}
}

// recursive
fn set_kind_enum(mut n Node) {
	for mut child in n.inner {
		child.kind = convert_str_into_node_kind(child.kind_str)
		// unsafe {
		// child.parent_node = n
		//}
		if child.ref_declaration.kind_str != '' {
			child.ref_declaration.kind = convert_str_into_node_kind(child.ref_declaration.kind_str)
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
	vprintln('new tree(outv=${outv} c_file=${c_file})')
	c_file_contents := if c_file == '' {
		''
	} else {
		os.read_file(c_file) or { '' }
	}

	ast_txt := os.read_file(ast_path) or {
		vprintln('failed to read ast file "${ast_path}": ${err}')
		panic(err)
	}
	c2v.tree = json.decode(Node, ast_txt) or {
		vprintln('failed to decode ast file "${ast_path}": ${err}')
		panic(err)
	}

	c2v.outv = outv
	c2v.c_file_contents = c_file_contents
	c2v.cur_file = c_file

	if c2v.is_wrapper {
		// Generate v_wrapper.v in user's current directory
		c2v.wrapper_module_name = os.dir(outv).all_after_last('/')
		wrapper_path := c2v.outv
		c2v.out_file = os.create(wrapper_path) or { panic('cant create file "${wrapper_path}" ') }
	} else {
		c2v.out_file = os.create(c2v.outv) or {
			vprintln('cant create')
			panic(err)
		}
	}
	c2v.genln('@[translated]')
	// Predeclared identifiers
	if !c2v.is_wrapper {
		c2v.genln('module main\n')
	} else if c2v.is_wrapper {
		c2v.genln('module ${c2v.wrapper_module_name}\n')
	}

	// Convert Clang JSON AST nodes to C2V's nodes with extra info. Skip nodes from libc.
	set_kind_enum(mut c2v.tree)
	for i, mut node in c2v.tree.inner {
		vprintln('\nQQQQ ${i} ${node.name}')
		// Builtin types have completely empty "loc" objects:
		// `"loc": {}`
		// Mark them with `is_std`
		if node.is_builtin() {
			vprintln('${c2v.line_i} is_std name=${node.name}')
			node.is_builtin_type = true
			continue
		} else if line_is_source(node.location.file) {
			vprintln('${c2v.line_i} is_source')
		}
		// if node.name.contains('mobj_t') {
		//}
		vprintln('ADDED TOP NODE line_i=${c2v.line_i}')
	}
	if c2v.unhandled_nodes.len > 0 {
		vprintln('GOT SOME UNHANDLED NODES:')
		for s in c2v.unhandled_nodes {
			vprintln(s)
		}
		exit(1)
	}
}

fn line_is_builtin_header(val string) bool {
	return val.contains_any_substr(['usr/include', '/opt/', 'usr/lib', 'usr/local', '/Library/',
		'lib/clang'])
}

fn line_is_source(val string) bool {
	return val.ends_with('.c')
}

fn (mut c C2V) fn_call(mut node Node) {
	expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	// vprintln('FN CALL')
	c.expr(expr) // this is `fn_name(`
	// vprintln(expr.str())
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
		vprintln('!! ${c.cur_out_line}')
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

fn (mut c C2V) fn_decl(mut node Node, gen_types string) {
	vprintln('1FN DECL name="${node.name}" cur_file="${c.cur_file}"')
	c.inside_main = false
	if node.location.file.contains('usr/include') {
		vprintln('\nskipping fn:')
		vprintln('')
		return
	}

	if c.is_dir && c.cur_file.ends_with('/info.c') {
		// TODO tmp doom hack
		return
	}
	// No statements - it's a function declration, skip it
	no_stmts := if !node.has_child_of_kind(.compound_stmt) { true } else { false }

	vprintln('no_stmts: ${no_stmts}')
	for child in node.inner {
		vprintln('INNER: ${child.kind} ${child.kind_str}')
	}
	// Skip C++ tmpl args
	if node.has_child_of_kind(.template_argument) {
		cnt := node.count_children_of_kind(.template_argument)
		for i := 0; i < cnt; i++ {
			node.try_get_next_child_of_kind(.template_argument) or {
				println(add_place_data_to_error(err))
				continue
			}
		}
	}
	mut name := node.name
	if name in ['invalid', 'referenced'] {
		return
	}
	if !c.contains_word(name) {
		vprintln('RRRR ${name} not here, skipping')
		// This fn is not found in current .c file, means that it was only
		// in the include file, so it's declared and used in some other .c file,
		// no need to genenerate it here.
		// TODO perf right now this searches an entire .c file for each global.
		return
	}
	if node.ast_type.qualified.contains('...)') {
		// TODO handle this better (`...any` ?)
		c.genln('@[c2v_variadic]')
	}
	if name.contains('blkcpy') {
		vprintln('GOT FINISH')
	}
	if c.is_wrapper {
		if name in c.fns {
			return
		}
		if name.starts_with('_') {
			return
		}
		if node.class_modifier == 'static' {
			// Static functions are limited to their obejct files.
			// Cant include them into wrappers. Skip.
			vprintln('SKIPPING STATIC')
			return
		}
	}
	c.fns << name
	mut typ := node.ast_type.qualified.before('(').trim_space()
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
		vprintln('\nFN DECL name="${name}" typ="${typ}"')
	}

	// Build fn params
	params := c.fn_params(mut node)

	str_args := if name == 'main' { '' } else { params.join(', ') }
	if !no_stmts || c.is_wrapper {
		c_name := name + gen_types
		if c.is_wrapper {
			c.genln('fn C.${c_name}(${str_args}) ${typ}\n')
		}
		v_name := name.to_lower()
		if v_name != c_name && !c.is_wrapper {
			c.genln("[c:'${c_name}']")
		}
		if c.is_wrapper {
			// strip the "modulename__" from the start of the function
			stripped_name := v_name.replace(c.wrapper_module_name + '_', '')
			c.genln('pub fn ${stripped_name}(${str_args}) ${typ} {')
		} else {
			c.genln('fn ${v_name}(${str_args}) ${typ} {')
		}

		if !c.is_wrapper {
			// For wrapper generation just generate function definitions without bodies
			mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
				println(add_place_data_to_error(err))
				bad_node
			}

			c.statements(mut stmts)
		} else if c.is_wrapper {
			if typ != '' {
				c.gen('\treturn ')
			} else {
				c.gen('\t')
			}
			c.gen('C.${c_name}(')

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
			c.genln("[c:'${name}']")
		}
		name = lower
		if name in c_known_fn_names {
			c.genln('fn C.${name}(${str_args}) ${typ}')
			c.extern_fns << name
		} else {
			c.genln('fn ${name}(${str_args}) ${typ}')
		}
	}
	c.genln('')
	vprintln('END OF FN DECL ast line=${c.line_i}')
}

fn (c &C2V) fn_params(mut node Node) []string {
	mut str_args := []string{cap: 5}
	nr_params := node.count_children_of_kind(.parm_var_decl)
	for i := 0; i < nr_params; i++ {
		param := node.try_get_next_child_of_kind(.parm_var_decl) or {
			println(add_place_data_to_error(err))
			continue
		}
		arg_typ := convert_type(param.ast_type.qualified)

		mut param_name := param.name
		mut arg_typ_name := arg_typ.name

		if arg_typ.name.contains('...') {
			vprintln('vararg: ' + arg_typ.name)
		} else if arg_typ.name.ends_with('*restrict') {
			arg_typ_name = fix_restrict_name(arg_typ_name)
			arg_typ_name = convert_type(arg_typ_name.trim_right('restrict')).name
		}
		param_name = filter_name(param_name, false).to_lower().all_after_last('c.')
		if param_name == '' {
			param_name = 'arg${i}'
		}
		str_args << '${param_name} ${arg_typ_name}'
	}
	return str_args
}

// handles '__linep char **restrict' param stuff
fn fix_restrict_name(arg_typ_name string) string {
	mut typ_name := arg_typ_name

	if typ_name.replace(' ', '').contains('Char*') || typ_name.replace(' ', '').contains('Size_t') {
		typ_name = typ_name.to_lower()
	}

	return typ_name
}

// converts a C type to a V type
fn convert_type(typ_ string) Type {
	mut typ := typ_
	if true || typ.contains('type_t') {
		vprintln('\nconvert_type("${typ}")')
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

	// enum
	if typ.starts_with('enum ') {
		return Type{
			name: typ.substr('enum '.len, typ.len).capitalize()
			is_const: is_const
		}
	}

	// int[3]
	mut idx := ''
	if typ.contains('[') && typ.contains(']') {
		if true {
			pos := typ.index('[') or { panic('no [ in conver_type(${typ})') }
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
		'long double' {
			'f64'
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
		'uint16_t' {
			'u16'
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
		'ptrdiff_t', 'ssize_t', '__ssize_t' {
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
			typ = '${s}) ${ret_typ.name}'
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
	vprintln('"${typ_}" => "${typ}" base="${base}"')

	name := idx + typ
	return Type{
		name: name
		is_const: is_const
	}
}

fn (mut c C2V) enum_decl(mut node Node) {
	// Hack: typedef with the actual enum name is next, parse it and generate "enum NAME {" first
	mut enum_name := node.name //''
	if c.tree.inner.len > c.node_i + 1 {
		next_node := c.tree.inner[c.node_i + 1]
		if next_node.kind == .typedef_decl {
			enum_name = next_node.name
		}
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

		c.genln('enum ${enum_name} {')
	}
	mut vals := c.enum_vals[enum_name]
	for i, mut child in node.inner {
		name := filter_name(child.name.to_lower(), false)
		vals << name
		mut has_anon_generated := false
		// empty enum means it's just a list of #define'ed consts
		if enum_name == '' {
			if !name.starts_with('_') && name !in c.consts {
				c.consts << name
				c.gen('\t${name}')
				has_anon_generated = true
			}
		} else {
			c.gen('\t' + name)
		}
		// handle custom enum vals, e.g. `MF_SHOOTABLE = 4`
		if child.inner.len > 0 {
			mut const_expr := child.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			if const_expr.kind == .constant_expr {
				c.gen(' = ')
				c.skip_parens = true
				c.expr(const_expr.try_get_next_child() or {
					println(add_place_data_to_error(err))
					bad_node
				})
				c.skip_parens = false
			}
		} else if has_anon_generated {
			c.gen(' = ${i}')
		}
		c.genln('')
	}
	if enum_name != '' {
		vprintln('decl enum "${enum_name}" with ${vals.len} vals')
		c.enum_vals[enum_name] = vals
		c.genln('}\n')
	} else {
		c.genln(')\n')
	}
	if enum_name != '' {
		c.enums << enum_name
	}
}

fn (mut c C2V) statements(mut compound_stmt Node) {
	c.indent++
	// Each CompoundStmt's child is a statement
	for i, _ in compound_stmt.inner {
		c.statement(mut compound_stmt.inner[i])
	}
	c.indent--
	c.genln('}')
}

fn (mut c C2V) statements_no_rcbr(mut compound_stmt Node) {
	for i, _ in compound_stmt.inner {
		c.statement(mut compound_stmt.inner[i])
	}
}

fn (mut c C2V) statement(mut child Node) {
	if child.kindof(.decl_stmt) {
		c.var_decl(mut child)
		c.genln('')
	} else if child.kindof(.return_stmt) {
		c.return_st(mut child)
		c.genln('')
	} else if child.kindof(.if_stmt) {
		c.if_statement(mut child)
	} else if child.kindof(.while_stmt) {
		c.while_st(mut child)
	} else if child.kindof(.for_stmt) {
		c.for_st(mut child)
	} else if child.kindof(.do_stmt) {
		c.do_st(mut child)
	} else if child.kindof(.switch_stmt) {
		c.switch_st(mut child)
	}
	// Just  { }
	else if child.kindof(.compound_stmt) {
		c.genln('{')
		c.statements(mut child)
	} else if child.kindof(.gcc_asm_stmt) {
		c.genln('__asm__') // TODO
	} else if child.kindof(.goto_stmt) {
		c.goto_stmt(child)
	} else if child.kindof(.label_stmt) {
		label := child.name // child.get_val(-1)
		c.labels[child.name] = child.declaration_id
		c.genln('// RRRREG ${child.name} id=${child.declaration_id}')
		c.genln('${label}: ')
		c.statements_no_rcbr(mut child)
	}
	// C++
	else if child.kindof(.cxx_for_range_stmt) {
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
	c.genln('goto ${label} // id: ${node.label_id}')
}

fn (mut c C2V) return_st(mut node Node) {
	c.gen('return ')
	// returning expression?
	if node.inner.len > 0 && !c.inside_main {
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if expr.kindof(.implicit_cast_expr) {
			if expr.ast_type.qualified == 'bool' {
				// Handle `return 1` which is actually `return true`
				c.returning_bool = true
			}
		}
		c.expr(expr)
		c.returning_bool = false
	}
}

fn (mut c C2V) if_statement(mut node Node) {
	expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.gen('if ')
	c.gen_bool(expr)
	// Main if block
	mut child := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	if child.kindof(.null_stmt) {
		// The if branch body can be empty (`if (foo) ;`)
		c.genln(' {}')
	} else {
		c.st_block(mut child)
	}
	// Optional else block
	mut else_st := node.try_get_next_child() or {
		// dont print here not an error optional else
		// println(add_place_data_to_error(err))
		bad_node
	}
	if else_st.kindof(.compound_stmt) || else_st.kindof(.return_stmt) {
		c.genln('else {')
		c.st_block_no_start(mut else_st)
	}
	// else if
	else if else_st.kindof(.if_stmt) {
		c.gen('else ')
		c.if_statement(mut else_st)
	}
	// `else expr() ;` else statement in one line without {}
	else if !else_st.kindof(.bad) && !else_st.kindof(.null) {
		c.genln('else { // 3')
		if else_st.kind in [.return_stmt, .do_stmt] {
			c.statement(mut else_st)
		} else {
			c.expr(else_st)
		}
		c.genln('\n}')
	}
}

fn (mut c C2V) while_st(mut node Node) {
	c.gen('for ')
	expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.gen_bool(expr)
	c.genln(' {')
	mut stmts := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.st_block_no_start(mut stmts)
}

fn (mut c C2V) for_st(mut node Node) {
	c.inside_for = true
	c.gen('for ')
	// Can be "for (int i = ...)"
	if node.has_child_of_kind(.decl_stmt) {
		mut decl_stmt := node.try_get_next_child_of_kind(.decl_stmt) or {
			println(add_place_data_to_error(err))
			bad_node
		}

		c.var_decl(mut decl_stmt)
	}
	// Or "for (i = ....)"
	else {
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(expr)
	}
	c.gen(' ; ')
	mut expr2 := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	if expr2.kind_str == '' {
		// second cond can be Null
		expr2 = node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
	}
	c.expr(expr2)
	c.gen(' ; ')
	expr3 := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.expr(expr3)
	c.inside_for = false
	mut child := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.st_block(mut child)
}

fn (mut c C2V) do_st(mut node Node) {
	c.genln('for {')
	mut child := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.statements_no_rcbr(mut child)
	// TODO condition
	c.genln('// while()')
	c.gen('if ! (')
	expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.expr(expr)
	c.genln(' ) { break }')
	c.genln('}')
}

fn (mut c C2V) case_st(mut child Node, is_enum bool) bool {
	if child.kindof(.case_stmt) {
		if is_enum {
			// Force short `.val {` enum syntax, but only in `case .val:`
			// Later on it'll be set to false, so that full syntax is used (`Enum.val`)
			// Since enums are often used as ints, and V will need the full enum
			// value to convert it to ints correctly.
			c.inside_switch_enum = true
		}
		c.gen(' ')
		case_expr := child.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(case_expr)
		mut a := child.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if a.kindof(.null) {
			a = child.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
		}
		vprintln('A TYP=${a.ast_type}')
		if a.kindof(.compound_stmt) {
			c.genln('// case comp stmt')
			c.statements(mut a)
		} else if a.kindof(.case_stmt) {
			// case 1:
			// case 2:
			// case 3:
			// ===>
			// case 1, 2, 3:
			for a.kindof(.case_stmt) {
				e := a.try_get_next_child() or {
					println(add_place_data_to_error(err))
					bad_node
				}
				c.gen(', ')
				c.expr(e) // this is `1` in `case 1:`
				mut tmp := a.try_get_next_child() or {
					println(add_place_data_to_error(err))
					bad_node
				}
				if tmp.kindof(.null) {
					tmp = a.try_get_next_child() or {
						println(add_place_data_to_error(err))
						bad_node
					}
				}
				a = tmp
			}
			c.genln('{')
			vprintln('!!!!!!!!caseexpr=')
			c.inside_switch_enum = false
			if a.kindof(.default_stmt) {
				// This probably means something like
				/*
				case MD_LINE_BLANK:
                                case MD_LINE_SETEXTUNDERLINE: printf("hello");
                                case MD_LINE_TABLEUNDERLINE:
                                default:
                                    MD_UNREACHABLE();
				*/
				// c.gen('/*TODO fallthrough*/')
			} else {
				c.statement(mut a)
			}
		} else if a.kindof(.default_stmt) {
		}
		// case body
		else {
			c.inside_switch_enum = false
			c.genln('{ // case comp body kind=${a.kind} is_enum=${is_enum}')
			c.statement(mut a)
			if a.kindof(.return_stmt) {
			} else if a.kindof(.break_stmt) {
				return true
			}
			if is_enum {
				c.inside_switch_enum = true
			}
		}
	}
	return false
}

// Switch statements are a mess in C...
fn (mut c C2V) switch_st(mut switch_node Node) {
	c.gen('match ')
	c.inside_switch++
	mut expr := switch_node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	mut is_enum := false
	if expr.inner.len > 0 {
		// 0
		x := expr.inner[0]
		if x.ast_type.qualified == 'int' {
			// this is an int, not a C enum type
			c.inside_switch_enum = false
		} else {
			c.inside_switch_enum = true
			is_enum = true
		}
	}
	mut comp_stmt := switch_node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	// Detect if this switch statement runs on an enum (have to look at the first
	// value being compared). This means that the integer will have to be cast to this enum
	// in V.
	// switch (x) { case enum_val: ... }   ==>
	// match MyEnum(x) { .enum_val { ... } }
	// Don't cast if it's already an enum and not an int. Enum(enum) compiles, but still.
	mut second_par := false
	if comp_stmt.inner.len > 0 {
		mut child := comp_stmt.inner[0]
		if child.kindof(.case_stmt) {
			mut case_expr := child.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			if case_expr.kindof(.constant_expr) {
				x := case_expr.try_get_next_child() or {
					println(add_place_data_to_error(err))
					bad_node
				}
				vprintln('YEP')

				if x.ref_declaration.kind == .enum_constant_decl {
					is_enum = true
					c.inside_switch_enum = true
					c.gen(c.enum_val_to_enum_name(x.ref_declaration.name))

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
	mut default_node := bad_node
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
	mut has_case := false
	for i, mut child in comp_stmt.inner {
		if child.kindof(.case_stmt) {
			if i > 0 && has_case {
				c.genln('}')
			}
			c.case_st(mut child, is_enum)
			has_case = true
		} else if child.kindof(.default_stmt) {
			default_node = child.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			got_else = true
		} else {
			// handle weird children-siblings
			c.inside_switch_enum = false
			c.statement(mut child)
		}
	}
	if got_else {
		if default_node != bad_node {
			if default_node.kindof(.case_stmt) {
				c.case_st(mut default_node, is_enum)
				c.genln('}')
				c.genln('else {')
			} else {
				c.genln('}')
				c.genln('else {')
				c.statement(mut default_node)
			}
			c.genln('}')
		}
	} else {
		if has_case {
			c.genln('}')
		}
		c.genln('else{}')
	}
	c.genln('}')
	c.inside_switch--
	c.inside_switch_enum = false
}

fn (mut c C2V) st_block_no_start(mut node Node) {
	c.st_block2(mut node, false)
}

fn (mut c C2V) st_block(mut node Node) {
	c.st_block2(mut node, true)
}

// {} or just one statement if there is no {
fn (mut c C2V) st_block2(mut node Node, insert_start bool) {
	if insert_start {
		c.genln(' {')
	}
	if node.kindof(.compound_stmt) {
		c.statements(mut node)
	} else {
		// No {}, just one statement
		c.statement(mut node)
		c.genln('}')
	}
}

//
fn (mut c C2V) gen_bool(node &Node) {
	typ := c.expr(node)
	if typ == 'int' {
	}
}

fn (mut c C2V) var_decl(mut decl_stmt Node) {
	for _ in 0 .. decl_stmt.inner.len {
		mut var_decl := decl_stmt.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if var_decl.kindof(.record_decl) || var_decl.kindof(.enum_decl) {
			return
		}
		if var_decl.class_modifier == 'extern' {
			vprintln('local extern vars are not supported yet: ')
			vprintln(var_decl.str())
			vprintln(c.cur_file + ':' + c.line_i.str())
			exit(1)
			return
		}
		// cinit means we have an initialization together with var declaration:
		// `int a = 0;`
		cinit := var_decl.initialization_type == 'c'
		name := filter_name(var_decl.name, true).to_lower()
		typ_ := convert_type(var_decl.ast_type.qualified)
		if typ_.is_static {
			c.gen('static ')
		}
		if cinit {
			expr := var_decl.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			c.gen('${name} := ')
			c.expr(expr)
			if decl_stmt.inner.len > 1 {
				c.gen('\n')
			}
		} else {
			oldtyp := var_decl.ast_type.qualified
			mut typ := typ_.name
			vprintln('oldtyp="${oldtyp}" typ="${typ}"')
			// set default zero value (V requires initialization)
			mut def := ''
			if var_decl.ast_type.desugared_qualified.starts_with('struct ') {
				def = '${typ}{}' // `struct Foo foo;` => `foo := Foo{}` (empty struct init)
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
			} else if typ in ['ptrdiff_t', 'isize', 'ssize_t'] {
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
				def = '${typ}{}'
			} else {
				// We assume that everything else is a struct, because C AST doesn't
				// give us any info that typedef'ed structs are structs

				if oldtyp.contains_any_substr(['dirtype_t', 'angle_t']) { // TODO DOOM handle int aliases
					def = 'u32(0)'
				} else {
					def = '${typ}{}'
				}
			}
			// vector<int> => int => []int
			if typ.starts_with('vector<') {
				def = typ.substr('vector<'.len, typ.len - 1)
				def = '[]${def}'
			}
			c.gen('${name} := ${def}')
			if decl_stmt.inner.len > 1 {
				c.genln('')
			}
		}
	}
}

fn (mut c C2V) global_var_decl(mut var_decl Node) {
	// if the global has children, that means it's initialized, parse the expression
	mut is_inited := var_decl.inner.len > 0

	if var_decl.inner.len == 1 {
		if var_decl.inner[0].kindof(.visibility_attr) {
			is_inited = false
		}
	}

	vprintln('\nglobal name=${var_decl.name} typ=${var_decl.ast_type.qualified}')
	vprintln(var_decl.str())

	name := filter_name(var_decl.name, true)

	if var_decl.ast_type.qualified.starts_with('[]') {
		return
	}
	typ := convert_type(var_decl.ast_type.qualified)
	if var_decl.name in c.globals {
		existing := c.globals[var_decl.name]
		if !types_are_equal(existing.typ, typ.name) {
			c.verror('Duplicate global "${var_decl.name}" with different types:"${existing.typ}" and	"${typ.name}".
Since C projects do not use modules but header files, duplicate globals are allowed.
This will not compile in V, so you will have to modify one of the globals and come up with a
unique name')
		}
		if !existing.is_extern {
			c.genln('// skipping global dup "${var_decl.name}"')
			return
		}
	}
	// Skip extern globals that are initialized later in the file.
	// We'll have go thru all top level nodes, find a VarDecl with the same name
	// and make sure it's inited (has a child expressinon).
	is_extern := var_decl.class_modifier == 'extern'
	if is_extern && !is_inited {
		for x in c.tree.inner {
			if x.kindof(.var_decl) && x.name == var_decl.name && x.id != var_decl.id {
				if x.inner.len > 0 {
					c.genln('// skipped extern global ${x.name}')
					return
				}
			}
		}
	}
	// We assume that if the global's type is `[N]array`, and it's initialized,
	// then it's constant
	is_fixed_array := var_decl.ast_type.qualified.contains(']')
		&& var_decl.ast_type.qualified.contains(']')
	is_const := is_inited && (typ.is_const || is_fixed_array)
	if true || !typ.name.contains('[') {
	}
	if c.is_wrapper && typ.name.starts_with('_') {
		return
	}
	if c.is_wrapper {
		return
	}
	if !c.is_dir && is_extern && var_decl.redeclarations_count > 0 {
		// This is an extern global, and it's declared later in the file without `extern`.
		return
	}
	// Cut generated code from `c.out` to `c.globals_out`
	start := c.out.len
	if is_const {
		c.consts << name
		c.gen("[export:'${name}']\nconst (\n${name}  ")
	} else {
		if !c.contains_word(name) && !c.cur_file.contains('deh_') { // TODO deh_ hack remove
			vprintln('RRRR global ${name} not here, skipping')
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
			c.gen('@[weak] __global ( ${name} ')
		} else {
			mut typ_name := typ.name
			if typ_name.contains('anonymous enum') || typ_name.contains('unnamed enum') {
				// Skip anon enums, they are declared as consts in V
				return
			}

			if is_extern && is_fixed_array && var_decl.redeclarations_count == 0 {
				c.gen('@[c_extern] ')
			} else {
				c.gen('@[weak] ')
			}

			if typ_name.contains('unnamed at') {
				typ_name = c.last_declared_type_name
			}

			c.gen('__global ( ${name} ${typ_name} ')
		}
		c.global_struct_init = typ.name
	}
	if is_fixed_array && var_decl.ast_type.qualified.contains('[]')
		&& !var_decl.ast_type.qualified.contains('*') && !is_inited {
		// Do not allow uninitialized fixed arrays for now, since they are not supported by V
		eprintln('${c.cur_file}: uninitialized fixed array without the size "${name}" typ="${var_decl.ast_type.qualified}"')
		exit(1)
	}

	// if the global has children, that means it's initialized, parse the expression
	if is_inited {
		child := var_decl.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.gen(' = ')
		is_struct := child.kindof(.init_list_expr) && !is_fixed_array
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
	filtered_enum_val := filter_name(enum_val, false)
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
	if node.kindof(.null) || node.kindof(.visibility_attr) {
		return ''
	}
	if node.kindof(.integer_literal) {
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
	else if node.kindof(.character_literal) {
		val := if node.value_number == `\\` {
			'\\\\'
		} else if node.value_number == `\`` {
			'\\`'
		} else {
			rune(node.value_number).str()
		}
		if val == '\n' {
			c.gen('`\\n`')
		} else {
			c.gen('`' + val + '`')
		}
	}
	// 1e80
	else if node.kindof(.floating_literal) {
		c.gen(node.value)
	} else if node.kindof(.constant_expr) {
		n := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(&n)
	}
	// null
	else if node.kindof(.null_stmt) {
		c.gen('0')
	} else if node.kindof(.cold_attr) {
	}
	// = + - *
	else if node.kindof(.binary_operator) {
		op := node.opcode
		mut first_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(first_expr)
		c.gen(' ${op} ')
		mut second_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}

		if second_expr.kindof(.binary_operator) && second_expr.opcode == '=' {
			// handle `a = b = c` => `a = c; b = c;`
			second_child_expr := second_expr.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			} // `b`
			mut third_expr := second_expr.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			} // `c`
			c.expr(third_expr)
			c.genln('')
			c.expr(second_child_expr)
			c.gen(' = ')
			first_expr.current_child_id = 0
			c.expr(first_expr)
			c.gen('')
			second_expr.current_child_id = 0
		} else {
			c.expr(second_expr)
		}
		vprintln('done!')
		if op == '<' || op == '>' || op == '==' {
			return 'bool'
		}
	}
	// +=
	else if node.kindof(.compound_assign_operator) {
		op := node.opcode // get_val(-3)
		first_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(first_expr)
		c.gen(' ${op} ')
		second_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(second_expr)
	}
	// ++ --
	else if node.kindof(.unary_operator) {
		op := node.opcode
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if op in ['--', '++'] {
			c.expr(expr)
			c.gen(' ${op}')
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
	else if node.kindof(.paren_expr) {
		if !c.skip_parens {
			c.gen('(')
		}
		child := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(child)
		if !c.skip_parens {
			c.gen(')')
		}
	}
	// This junk means go again for its child
	else if node.kindof(.implicit_cast_expr) {
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(expr)
	}
	// var  name
	else if node.kindof(.decl_ref_expr) {
		c.name_expr(node)
	}
	// "string literal"
	else if node.kindof(.string_literal) {
		str := node.value
		// "a" => 'a'
		no_quotes := str.substr(1, str.len - 1)
		if no_quotes.contains("'") {
			// same quoting logic as in vfmt
			c.gen('c"${no_quotes}"')
		} else {
			c.gen("c'${no_quotes}'")
		}
	}
	// fn call
	else if node.kindof(.call_expr) {
		c.fn_call(mut node)
	}
	// `user.age`
	else if node.kindof(.member_expr) {
		mut field := node.name
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(expr)
		field = field.replace('->', '')
		if field.starts_with('.') {
			field = filter_name(field[1..], false)
		} else {
			field = filter_name(field, false)
		}
		c.gen('.${field}')
	}
	// sizeof
	else if node.kindof(.unary_expr_or_type_trait_expr) {
		c.gen('sizeof')
		// sizeof (expr) ?
		if node.inner.len > 0 {
			expr := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			if expr.kindof(.decl_ref_expr) {
				c.gen('(')
				defer {
					c.gen(')')
				}
			}
			c.expr(expr)
		}
		// sizeof (Type) ?
		else {
			typ := convert_type(node.ast_argument_type.qualified)
			c.gen('(${typ.name})')
		}
	}
	// a[0]
	else if node.kindof(.array_subscript_expr) {
		first_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(first_expr)
		c.gen(' [')

		second_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.inside_array_index = true
		c.expr(second_expr)
		c.inside_array_index = false
		c.gen('] ')
	}
	// int a[] = {1,2,3};
	else if node.kindof(.init_list_expr) {
		c.init_list_expr(mut node)
	}
	// (int*)a  => (int*)(a)
	// CStyleCastExpr 'const char **' <BitCast>
	else if node.kindof(.c_style_cast_expr) {
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		typ := convert_type(node.ast_type.qualified)
		mut cast := typ.name
		if cast.contains('*') {
			cast = '(${cast})'
		}
		c.gen('${cast}(')
		c.expr(expr)
		c.gen(')')
	}
	// ? :
	else if node.kindof(.conditional_operator) {
		c.gen('if ') // { } else { }')
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		case1 := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		case2 := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(expr)
		c.gen('{ ')
		c.expr(case1)
		c.gen(' } else {')
		c.expr(case2)
		c.gen('}')
	} else if node.kindof(.break_stmt) {
		if c.inside_switch == 0 {
			c.genln('break')
		}
	} else if node.kindof(.continue_stmt) {
		c.genln('continue')
	} else if node.kindof(.goto_stmt) {
		c.goto_stmt(node)
	} else if node.kindof(.opaque_value_expr) {
		// TODO
	} else if node.kindof(.paren_list_expr) {
	} else if node.kindof(.va_arg_expr) {
	} else if node.kindof(.compound_stmt) {
	} else if node.kindof(.offset_of_expr) {
	} else if node.kindof(.array_filler) {
	} else if node.kindof(.goto_stmt) {
	} else if node.kindof(.implicit_value_init_expr) {
	} else if c.cpp_expr(node) {
	} else if node.kindof(.deprecated_attr) {
	} else if node.kindof(.full_comment) {
	} else if node.kindof(.compound_literal_expr) {
		c.compound_literal_expr(mut node)
	} else if node.kindof(.bad) {
		vprintln('BAD node in expr()')
		vprintln(node.str())
	} else if node.kindof(.predefined_expr) {
		v_predefined := match node.name {
			'__func__' { '@FN' }
			'__line__' { '@LINE' }
			'__file__' { '@FILE' }
			else { '' }
		}
		if v_predefined != '' {
			c.gen(v_predefined)
		} else {
			eprintln('\n\nUnhandled PredefinedExpr: ${node.name}')
			eprintln(node.str())
		}
	} else {
		if node.is_builtin() {
			// TODO this check shouldn't be needed, all builtin nodes should be skipped
			// when handling top level nodes
			return node.value
		}
		eprintln('\n\nUnhandled expr() node {${node.kind}} (cur_file: "${c.cur_file}"):')

		eprintln(node.str())

		/*
		eprintln('parent:')
		mut i := 0
		mut cur_node := node
		for {
			eprint('parent ${i} :')
			i++
			cur_node = node.parent_node
			eprintln(cur_node.name)
			unsafe {
				if cur_node == nil || i > 300 {
					break
				}
			}
		}
		*/

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
	is_enum_val := node.ref_declaration.kind == .enum_constant_decl
	is_func_call := node.ref_declaration.kind == .function_decl

	mut name := node.ref_declaration.name

	if is_enum_val {
		enum_val := node.ref_declaration.name.to_lower()
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
	} else if is_func_call {
		if name in c.extern_fns {
			name = 'C.${name}'
		}
	}

	if name !in c.consts && name !in c.globals {
		// Functions and variables are all lowercase in V
		name = name.to_lower()
		if name.starts_with('c.') {
			name = 'C.' + name[2..] // TODO why is this needed?
		}
	}

	c.gen(filter_name(name, node.ref_declaration.kind == .var_decl))
	if is_enum_val && c.inside_array_index {
		c.gen(')')
	}
}

fn (mut c C2V) init_list_expr(mut node Node) {
	t := node.ast_type.qualified
	// c.gen(' /* list init $t */ ')
	// C list init can be an array (`numbers = {1,2,3}` => `numbers = [1,2,3]``)
	// or a struct init (`user = {"Bob", 20}` => `user = {'Bob', 20}`)
	is_arr := t.contains('[')
	mut struct_name := ''
	if !is_arr {
		// Struct init
		struct_name = parse_c_struct_name(t)
		c.genln('${struct_name} {')
	} else {
		c.gen('[')
	}
	if node.array_filler.len > 0 {
		for i, mut child in node.array_filler {
			// array_filler nodes were not handled by set_kind_enum
			child.initialize_node_and_children()

			if child.kindof(.implicit_value_init_expr) {
			} else {
				c.expr(child)
				if i < node.array_filler.len - 1 {
					c.gen(', ')
				}
			}
		}
	} else {
		mut struct_ := Struct{}
		if struct_name != '' {
			struct_ = c.structs[struct_name] or {
				c.gen('/*FAILED TO FIND STRUCT "${struct_name}"*/')
				Struct{}
			}
		}
		for i, mut child in node.inner {
			if child.kind == .bad {
				child.kind = convert_str_into_node_kind(child.kind_str) // array_filler nodes were not handled by set_kind_enum
			}

			// C allows not to set final fields (a = {1,2,,,,})
			// V requires all fields to be set
			if child.kindof(.implicit_value_init_expr) {
				continue
			}

			mut field_name := ''
			if i < struct_.fields.len {
				field_name = struct_.fields[i]
			}
			// c.gen('/*zer ${field_name} */0')
			if field_name != '' {
				c.gen(field_name + ': ')
			}

			c.expr(child)
			if i < node.inner.len - 1 {
				c.gen(', ')
			}
			if field_name != '' {
				c.gen('\n')
			}
		}
	}
	is_fixed := node.ast_type.qualified.contains('[') && node.ast_type.qualified.contains(']')
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

fn filter_name(name string, ignore_builtin bool) string {
	if name in v_keywords {
		return '${name}_'
	}
	if name in builtin_fn_names {
		if ignore_builtin && name !in c_known_var_names {
			return name
		}
		return 'C.' + name
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
		eprintln('')
		eprintln('args:')
		eprintln('  -keep_ast		keep ast files')
		eprintln('  -print_tree		print the entire tree')
		exit(1)
	}
	vprintln(os.args.str())
	is_wrapper := os.args[1] == 'wrapper'
	mut path := os.args.last()

	if os.is_abs_path(path) == false {
		path = os.abs_path(path)
	}

	if !os.exists(path) {
		eprintln('"${path}" does not exist')
		exit(1)
	}
	mut c2v := new_c2v(os.args)
	println('C to V translator ${version}')
	c2v.translation_start_ticks = time.ticks()
	if os.is_dir(path) {
		os.chdir(path)!
		println('"${path}" is a directory, processing all C files in it recursively...\n')
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
	cmd := '${clang} ${additional_clang_flags} -w -Xclang -ast-dump=json -fsyntax-only -fno-diagnostics-color -c ${os.quoted_path(path)}'
	vprintln('DA CMD')
	vprintln(cmd)
	out_ast := if c2v.is_dir {
		os.getwd() + '/' + (os.dir(os.dir(path)) + '/${c2v.project_output_dirname}/' +
			os.base(path).replace(ext, '.json'))
	} else {
		// file.c => file.json
		vprintln(path)
		replace_file_extension(path, ext, '.json')
	}
	out_ast_dir := os.dir(out_ast)
	if c2v.is_dir && !os.exists(out_ast_dir) {
		os.mkdir(out_ast_dir) or { panic(err) }
	}
	vprintln('running in path: ${os.abs_path('.')}')
	vprintln('EXT=${ext} out_ast=${out_ast}')
	vprintln('out_ast=${out_ast}')
	vprintln('${cmd} > "${out_ast}"')
	clang_result := os.system('${cmd} > "${out_ast}"')
	vprintln('${clang_result}')
	if clang_result != 0 {
		eprintln('\nThe file ${path} could not be parsed as a C source file.')
		exit(1)
	}
	lines = os.read_lines(out_ast) or { panic(err) }
	ast_path = out_ast
	vprintln('lines.len=${lines.len}')
	out_v := out_ast.replace('.json', '.v')
	short_output_path := out_v.replace(os.getwd() + '/', '')
	c_file := path
	c2v.add_file(ast_path, out_v, c_file)

	// preparation pass, fill in the Node redeclarations field:
	mut seen_ids := map[string]&Node{}
	for i, mut node in c2v.tree.inner {
		c2v.node_i = i
		seen_ids[node.id] = unsafe { node }
		if node.previous_declaration != '' {
			if mut pnode := seen_ids[node.previous_declaration] {
				pnode.redeclarations_count++
			}
		}
	}
	// Main parse loop
	for i, node in c2v.tree.inner {
		vprintln('\ndoing top node ${i} ${node.kind} name="${node.name}" is_std=${node.is_builtin_type}')
		c2v.node_i = i
		c2v.top_level(node)
	}
	if os.args.contains('-print_tree') {
		c2v.print_entire_tree()
	}
	// if !os.args.contains('-keep_ast') {
	if false && !c2v.keep_ast {
		os.rm(out_ast) or { panic(err) }
	}
	vprintln('DONE!2')
	c2v.save()
	c2v.translations++
	delta_ticks := time.ticks() - start_ticks
	println(' took ${delta_ticks:5} ms ; output .v file: ${short_output_path}')
}

fn (mut c2v C2V) print_entire_tree() {
	for _, node in c2v.tree.inner {
		print_node_recursive(node, 0)
	}
}

fn print_node_recursive(node &Node, ident int) {
	vprint('  '.repeat(ident))
	vprintln('${node.kind} n="${node.name}"')
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
	if node.is_builtin_type {
		vprintln('is std, ret (name="${node.name}")')
		return
	}
	if node.kindof(.typedef_decl) {
		c.typedef_decl(node)
	} else if node.kindof(.function_decl) {
		c.fn_decl(mut node, '')
	} else if node.kindof(.record_decl) {
		c.record_decl(node)
	} else if node.kindof(.var_decl) {
		c.global_var_decl(mut node)
	} else if node.kindof(.enum_decl) {
		c.enum_decl(mut node)
	} else if !c.cpp_top_level(node) {
		vprintln('\n\nUnhandled non C++ top level node typ=${node.ast_type}:')
		exit(1)
	}
}

// Struct init with a pointer? e.g.:
//      sg_setup(&(sg_desc){
//          .context = sapp_sgcontext(),
//          .logger.func = slog_func,
//      });
fn (mut c C2V) compound_literal_expr(mut node Node) {
	// c.gen(node.ast_type.qualified)
	// c.gen('/*CLE*/')
	mut x := node.inner[0]
	if x.kindof(.init_list_expr) {
		c.init_list_expr(mut node.inner[0])
	} else {
		c.gen('/*unknown typ*/')
	}
}

fn (node &Node) get_int_define() string {
	return 'HEADER'
}

// "'struct Foo':'struct Foo'"  => "Foo"
fn parse_c_struct_name(typ string) string {
	mut res := typ.all_before(':')
	res = res.replace('struct ', '')
	res = res.replace('union ', '')
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
		eprintln('\x1b[31merror: ${msg}\x1b[0m')
	} $else {
		eprintln('error: ${msg}')
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
	f.writeln('@[translated]\n') or { panic(err) }
	if c2v.has_cfile {
		f.writeln('@[typedef]\nstruct C.FILE {}') or { panic(err) }
	}
	for _, g in c2v.globals_out {
		f.writeln(g) or { panic(err) }
	}
}

@[if trace_verbose ?]
fn vprintln(s string) {
	println(s)
}

@[if trace_verbose ?]
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
