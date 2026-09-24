// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
module main

import os
import strings
import json2
import time
import toml
import datatypes

// Clang's C++ AST can contain deeply nested overloaded expressions. The
// translator's expression dispatcher is intentionally broad and therefore has
// a large native stack frame for strict project translations.
#flag darwin -Wl,-stack_size,0x2000000

const version = '0.4.1'

// V keywords, that are not keywords in C:
const v_keywords = ['__global', '__offsetof', 'as', 'asm', 'assert', 'atomic', 'bool', 'byte', 'chan',
	'defer', 'dump', 'false', 'fn', 'go', 'implements', 'import', 'in', 'interface', 'is', 'isize',
	'isreftype', 'lock', 'map', 'match', 'module', 'mut', 'nil', 'none', 'or', 'pub', 'rlock', 'rune',
	'select', 'shared', 'spawn', 'string', 'struct', 'thread', 'true', 'type', 'typeof', 'unsafe',
	'usize', 'voidptr']

// V's reserved words. C names spelled like them are written as `@name` in V.
const v_reserved_words = ['__global', '__offsetof', 'as', 'asm', 'assert', 'atomic', 'break', 'const',
	'continue', 'defer', 'dump', 'else', 'enum', 'false', 'fn', 'for', 'go', 'goto', 'if',
	'implements', 'import', 'in', 'interface', 'is', 'isreftype', 'lock', 'match', 'module', 'mut',
	'nil', 'none', 'or', 'pub', 'return', 'rlock', 'select', 'shared', 'sizeof', 'spawn', 'static',
	'struct', 'true', 'type', 'typeof', 'union', 'unsafe', 'volatile']

// libc fn definitions that have to be skipped (V already knows about them):
const builtin_fn_names = ['fopen', 'puts', 'fflush', 'getline', 'printf', 'memset', 'atoi', 'memcpy',
	'remove', 'strlen', 'rename', 'stdout', 'stderr', 'stdin', 'ftell', 'fclose', 'fread', 'read',
	'perror', 'ftruncate', 'FILE', 'strcmp', 'toupper', 'strchr', 'strdup', 'strncasecmp',
	'strcasecmp', 'isspace', 'strncmp', 'malloc', 'close', 'open', 'lseek', 'fseek', 'fgets', 'rewind',
	'write', 'calloc', 'setenv', 'gets', 'abs', 'sqrt', 'erfl', 'fprintf', 'snprintf', 'exit',
	'__stderrp', 'fwrite', 'scanf', 'sscanf', 'strrchr', 'strchr', 'div', 'free', 'memcmp', 'memmove',
	'vsnprintf', 'rintf', 'rint', 'bsearch', 'qsort', '__stdinp', '__stdoutp', '__stderrp', 'getenv',
	'strtoul', 'strtol', 'strtod', 'strtof', '__error', 'errno', 'atol', 'atof', 'atoll', 'fputs',
	'fputc', 'putchar', 'getchar', 'putc', 'getc', 'feof', 'ferror', 'clearerr', 'fileno', 'isalnum',
	'isalpha', 'isdigit', 'islower', 'isupper', 'isxdigit', 'iscntrl', 'isgraph', 'isprint', 'ispunct',
	'tolower', 'strcat', 'strncat', 'strpbrk', 'strspn', 'strcspn', 'strstr', 'strerror', 'sprintf',
	'vsprintf', 'vfprintf', 'vprintf', 'strcpy', '__assert_rtn', '__builtin_expect',
	'__builtin_va_start', '__builtin_va_end', 'setvbuf', 'stat', 'tmpfile', 'rand', 'strncpy',
	'getuid', 'ioctl', 'realpath', 'sigaction', 'sysconf']

const c_known_fn_names = ['__ctype_b_loc', 'acos', 'acosf', 'asin', 'asinf', 'atan', 'atan2', 'atan2f',
	'atanf', 'ceil', 'ceilf', 'cos', 'cosf', 'exp', 'expf', 'fabs', 'fabsf', 'floor', 'floorf',
	'log', 'logf', 'pow', 'powf', 'sin', 'sinf', 'sqrt', 'sqrtf', 'tan', 'tanf', '__error', 'isalpha',
	'localtime_r', 'realloc', 'strftime', 'time', 'vfprintf', 'vprintf', 'vsnprintf', 'vsprintf',
	'strstr']

const c_known_var_names = ['stdin', 'stdout', 'stderr', '__stdinp', '__stdoutp', '__stderrp']

const c_known_const_names = ['_ISspace']

const c_known_mutable_fixed_array_global_names = ['forwardmove', 'sidemove']

const builtin_type_names = ['ldiv_t', '__float2', '__double2', 'exception', 'double_t']

const builtin_global_names = ['sys_nerr', 'sys_errlist', 'suboptarg']

// V built-in type names that cannot be used as struct/enum names (case-insensitive after capitalize):
const v_builtin_type_names = ['Option', 'Result', 'Error']
const v_primitive_type_names = ['bool', 'i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
	'usize', 'f32', 'f64', 'byte', 'rune', 'char', 'string', 'voidptr', 'none']

// V reserved function names that conflict with V builtins or cause module prefix issues:
// - 'error' is V's built-in error function
// - functions starting with 'builtin_' get interpreted as 'builtin__' module prefix
const v_reserved_fn_names = ['error', 'print', 'println', 'eprintln', 'panic', 'assert', 'init',
	'cleanup']

const tabs = ['', '\t', '\t\t', '\t\t\t', '\t\t\t\t', '\t\t\t\t\t', '\t\t\t\t\t\t', '\t\t\t\t\t\t\t',
	'\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t\t\t',
	'\t\t\t\t\t\t\t\t\t\t\t\t', '\t\t\t\t\t\t\t\t\t\t\t\t\t']

// const cur_dir = os.getwd()

const clang_exe = find_clang_in_path()

const builtin_header_folders = get_builtin_header_folders(clang_exe)

// The target's data model: `long` is 64-bit on LP64 systems (macOS, 64-bit
// Linux) and 32-bit on LLP64 (Windows).
const c_long_size = get_c_long_size(clang_exe)

fn get_c_long_size(clang_path string) int {
	null_device := if os.user_os() == 'windows' { 'nul' } else { '/dev/null' }
	res := os.execute('${os.quoted_path(clang_path)} -dM -E -x c ${null_device}')
	for line in res.output.split_into_lines() {
		if line.starts_with('#define __SIZEOF_LONG__ ') {
			return line.all_after_last(' ').int()
		}
	}
	return 4
}

fn get_builtin_header_folders(clang_path string) []string {
	mut folders := map[string]bool{}
	folders['/opt/homebrew'] = true
	folders['/Library/'] = true
	folders['/usr/include'] = true
	folders['/usr/lib'] = true
	folders['/usr/local'] = true
	folders['/lib/clang'] = true
	if os.user_os() == 'macos' {
		res := os.execute('xcrun --show-sdk-path')
		if res.exit_code == 0 {
			folders[res.output.trim_space()] = true
		}
	}
	psd := os.execute('${os.quoted_path(clang_path)} -print-search-dirs')
	if psd.exit_code == 0 {
		programs_line := psd.output.split_into_lines().filter(it.starts_with('programs: ='))[0] or {
			''
		}
		program_paths := programs_line.all_after(': =').split(os.path_delimiter)
		based_program_paths :=
			program_paths.map(it.all_before_last('/usr/bin')).map(it.all_before_last('/bin'))
		for p in based_program_paths {
			folders[p] = true
		}
	}

	null_device := if os.user_os() == 'windows' { 'nul' } else { '/dev/null' }
	clang_evx := os.execute('${os.quoted_path(clang_path)} -E -v -### -x c ${null_device}')
	if clang_evx.exit_code == 0 {
		params := clang_evx.output.split('" "')
		for idx, p in params {
			if p == '-internal-externc-isystem' || p == '-internal-isystem' {
				// special case for windows
				// clang dumps all paths in json with doubled '\'
				if os.user_os() == 'windows' {
					dequoted := params[idx + 1].replace('\\\\', '\\')
					folders[dequoted] = true
				} else {
					folders[params[idx + 1]] = true
				}
			}
		}
	}
	folders.delete('')
	res := folders.keys().map(os.real_path(it))
	vprintln('> builtin_header_folders: ${res}')
	return res
}

fn line_is_builtin_header(val string) bool {
	for folder in builtin_header_folders {
		if folder.starts_with('/') {
			if val.starts_with(folder) {
				vprintln('>>> line_is_builtin_header val starts_with folder: ${folder} | val: ${val}')
				return true
			}
			continue
		}
		if val.contains(folder) {
			vprintln('>>> line_is_builtin_header val contains folder: ${folder} | val: ${val}')
			return true
		}
	}
	vprintln('>>> line_is_builtin_header val is NOT builtin header | val: ${val}')
	return false
}

struct ExternalCFnSignature {
	params      []string
	return_type string
}

struct Type {
mut:
	name      string
	is_const  bool
	is_static bool
}

fn find_clang_in_path() string {
	clangs := ['clang-18', 'clang-19', 'clang-18', 'clang-17', 'clang-14', 'clang-13', 'clang-12',
		'clang-11', 'clang-10', 'clang']
	for clang in clangs {
		clang_path := os.find_abs_path_of_executable(clang) or { continue }
		vprintln('Found clang ${clang_path}')
		return clang
	}
	panic('cannot find clang in PATH')
}

struct LabelStmt {
	name string
}

struct Struct {
mut:
	fields      []string
	field_types []string
}

struct C2V {
mut:
	tree   Node
	is_dir bool // when translating a directory (multiple C=>V files)
	line_i int
	node_i int // when parsing nodes
	// out  stuff
	out                         strings.Builder // os.File
	globals_out                 map[string]string // `globals_out["myglobal"] == "extern int myglobal = 0;"` // strings.Builder
	out_file                    os.File
	out_line_empty              bool
	types                       map[string]string // to avoid dups
	type_aliases                map[string]string // V type name -> underlying type (for resolving alias chains)
	file_declared_aliases       map[string]bool // aliases emitted in the current output file
	file_type_alias_names       map[string]string // colliding project alias -> translation-unit-local V alias
	enums                       map[string]string // to avoid dups
	enum_vals                   map[string][]string // enum_vals['Color'] = ['green', 'blue'], for converting C globals  to enum values
	enum_int_vals               map[string]i64 // maps enum constant names to their integer values
	structs                     map[string]Struct // for correct `Foo{field:..., field2:...}` (implicit value init expr is 0, so un-initied fields are just skipped with 0s)
	fns                         map[string]string // to avoid dups
	extern_fns                  map[string]string // extern C fns
	external_c_fn_declarations  map[string]string // C-linkage header function -> typed V ABI declaration
	external_c_fn_signatures    map[string]ExternalCFnSignature // the V types of external_c_fn_declarations
	outv                        string
	cur_file                    string
	consts                      map[string]string
	globals                     map[string]Global
	defined_globals             map[string]bool
	defined_global_order        []string
	inside_switch               int // used to be a bool, a counter to handle switches inside switches
	inside_switch_enum          bool
	inside_for                  bool // to handle `;;++i`
	inside_comma_expr           bool // to handle prefix ++/-- in comma expressions
	inside_for_post             bool // to keep comma operators inline in `for` post expressions
	inside_for_init             bool // while emitting the init section of a C-style `for` loop
	for_clause_root_id          string // AST id of the active C-style `for` init/post clause root
	inside_cpp_reference_lvalue bool // preserve &T returned by an overloaded operator in lvalue/reference contexts
	inside_array_index          bool // for enums used as int array index: `if player.weaponowned[.wp_chaingun]`
	inside_sizeof               bool // to skip unsafe blocks for pointer dereferences in sizeof
	inside_unsafe               bool // to prevent nested unsafe blocks
	pre_cond_stmts              []string // statements to output before conditions (for assignment-in-expr patterns)
	collecting_pre_cond         bool
	global_struct_init          string
	inside_global_init          bool
	cur_out_line                string
	inside_main                 bool
	indent                      int
	empty_line                  bool // for indents
	is_wrapper                  bool
	is_cpp                      bool // translating a C++ (.cpp) file
	single_fn_def               bool // v translate fndef [fn_name]
	fn_def_name                 string // for translating just one fn definition (used by V on #include "header.h")
	wrapper_module_name         string // name of the wrapper module
	nm_lines                    []string
	is_verbose                  bool
	skip_parens                 bool // for skipping unnecessary params like in `enum Foo { bar = (1+2) }`
	labels                      map[string]string // for goto stmts: `label_stmts[label_id] == 'labelname'`
	//
	project_folder   string // the folder where c2v.toml was discovered (or the CLI target folder by default)
	target_root      string // the final folder passed on the CLI, or the folder of the final file passed on the CLI
	source_scan_root string // directory root used for recursive source discovery in dir mode
	invocation_cwd   string // working directory where c2v was invoked
	conf             toml.Doc = empty_toml_doc() // conf will be set by parsing the TOML configuration file
	//
	project_output_dirname   string // by default, 'c2v_out.dir'; override with `[project] output_dirname = "another"`
	project_additional_flags string // what to pass to clang, so that it could parse all the input files; mainly -I directives to find additional headers; override with `[project] additional_flags = "-I/some/folder"`
	project_uses_sdl         bool // if a project uses sdl, then the additional flags will include the result of `sdl2-config --cflags` too; override with `[project] uses_sdl = true`
	project_single_module    bool // flatten directory output so every translated unit is compiled in one V module
	project_generate_stubs   bool // generate cross-directory fallback types/methods and an empty main
	project_require_no_stubs bool // reject recovered ASTs and generated placeholder bodies
	project_require_main     bool // require a translated executable entrypoint in directory output
	project_source_manifest  string // optional newline-delimited source list, relative to project_folder
	project_native_manifest  string // optional newline-delimited C sources compiled unchanged into the V target
	project_pkg_config       []string // pkg-config packages of external C libraries used by the project
	project_link_flags       string // extra C linker flags for external libraries (`[project] link_flags`)
	file_additional_flags    string // can be added per file, appended to project_additional_flags ; override with `['info.c'] additional_flags = -I/xyz`
	skeleton_mode            bool // generate stub function bodies instead of full statements
	//
	project_output_root  string // absolute output root for translated files and globals
	project_globals_path string // where to store the leading 0_globals.v file containing project globals/consts
	source_text          string // current source file contents, used for conservative recovery fallbacks
	//
	translations                     int // how many translations were done so far
	translation_start_ticks          i64 // initialised before the loop calling .translate_file()
	has_cfile                        bool
	project_has_cpp                  bool
	returning_bool                   bool
	cur_fn_ret_type                  string // current function's return type
	current_fn_uses_va_arg           bool // the active variadic function consumes arguments with va_arg
	cur_class                        string // current C++ class/struct being processed
	keep_ast                         bool // do not delete ast.json after running
	last_declared_type_name          string
	expression_temp_id               int
	declared_local_vars              datatypes.Set[string] // track declared local vars in current function
	declared_local_var_types         map[string]string // V local name -> V type name in current function/scope
	local_decl_v_names               map[string]string // clang declaration id -> collision-free V local name
	for_init_vars                    datatypes.Set[string] // track variables declared in for-init (separate scope)
	current_fn_v_name                string
	synthesizing_cpp_derived_method  bool // inherited concrete implementation is being cloned onto a derived V receiver
	synthesizing_cpp_default_method  bool // qualified base implementation is being cloned under c2v_default_ on a derived receiver
	static_local_vars                map[string]string
	address_taken_locals             map[string]bool
	copied_pointer_params            map[string]bool // parameter ids whose address the body takes
	param_local_copies               []string // statements opening the body that copy such parameters
	copied_params_fn_id              string // the function copied_pointer_params belongs to
	conditional_mutable_locals       map[string]bool // locals assigned inside value-producing ternaries need V `mut`
	declared_methods                 map[string]int // track declared methods per class to handle overloads
	cpp_function_decl_names          map[string]string // clang function declaration id -> exact overloaded V function name
	cpp_function_signature_v_names   map[string]string // stable free C++ function signature -> overloaded V function name
	cpp_method_decl_names            map[string]string // clang method declaration id -> exact overloaded V method name
	cpp_constructor_signature_names  map[string]string // concrete class/ctor type -> emitted init method
	cpp_constructor_signature_params map[string][]string // concrete class/ctor type -> emitted V params
	cpp_nonconst_method_decls        map[string]bool // clang method declaration ids whose receiver may be mutated
	cpp_primitive_reference_decls    map[string]bool // C++ primitive reference parameter declaration ids
	cpp_value_reference_params       map[string]bool // `const T &` parameters of primitive T, passed by value
	enum_value_aliases               map[string]string // enum constant => the earlier constant of its enum with the same value
	cpp_nrvo_vars                    map[string]bool // locals C++ constructs in the return slot (named return value optimization)
	inside_return_stmt               bool
	cur_receiver_is_ref              bool // the current method's `this` is a V pointer (`this &T`)
	static_global_arrays             map[string]bool // V globals holding a constant-initialized fixed array
	namespace_var_ids                map[string]bool // namespace-scope variable declarations of the current translation unit
	global_constructor_calls         map[string]string // global C name => the call constructing it (run by the generated `fn init()`)
	global_constructor_order         []string
	deref_reference_call_values      bool // read the values of reference-returning calls (C variadic arguments)
	continue_labels                  []string // innermost loop last: the label `continue` jumps to, or '' for V's `continue`
	used_continue_labels             map[string]bool
	continue_label_count             int
	cpp_method_signature_v_names     map[string]string // stable class/signature -> overloaded V method name across project ASTs
	cpp_mut_method_names             map[string]bool // emitted V method names that require a mutable receiver
	cpp_abstract_types               map[string]bool // pure-virtual C++ bases lowered to V interfaces
	cpp_pure_method_bases            map[string]bool // pure interface methods keyed as "Type.method"
	cpp_method_body_bases            map[string]bool // C++ methods with an available body, keyed as "Type.method"
	cpp_opaque_record_files          map[string]string // opaque V record name -> earlier output file containing its empty declaration
	class_method_bases               map[string]bool // known method bases from C++ class declarations: "Class.method"
	cpp_class_bases                  map[string][]string // concrete C++ base classes by translated receiver name
	project_function_surfaces        map[string]string // cross-file callable surfaces: "fn_name" -> "fn fn_name(args ...voidptr) Ret"
	project_method_surfaces          map[string]string // cross-file callable surfaces: "Type.method" -> "fn (this Type) method(args ...voidptr) Ret"
	project_dir_method_defs          map[string]bool // "output_dir|Type.method" definitions found in project sources
	project_emitted_method_defs      map[string]bool // typed header/interface methods emitted into an output directory
	cpp_field_v_names                map[string]string // "Type.c_field" -> collision-free V field name
	cpp_template_values              map[string]string // active concrete values for C++ non-type template parameters
	cpp_template_type_aliases        map[string]string // active nested-type aliases for a concrete C++ template specialization
	local_type_declarations          []string // function-local record declarations hoisted to V module scope
	cpp_static_member_v_names        map[string]string // unambiguous C++ static member name -> translated project global
	cpp_ambiguous_static_members     map[string]bool // static member names owned by more than one class
	cpp_static_member_decl_names     map[string]string // clang static-member declaration id -> exact translated global
	file_static_global_decl_v_names  map[string]string // clang file-static declaration id -> translation-unit-qualified global
	current_static_init_owner        string // class whose static member initializer is being emitted
	cpp_static_method_symbols        map[string]bool // mangled methods declared static inside C++ class records
	can_output_comment               map[int]bool // to avoid duplicate output comment
	seen_comments                    map[string]bool // to avoid repeated comments across AST segments
	cnt                              int // global unique id counter
	files                            []string // all files' names used in current file, include header files' names
	used_fn                          datatypes.Set[string] // used fn in current .c file
	used_global                      datatypes.Set[string] // used global in current .c file
	seen_ids                         map[string]&Node
	callback_seen_ids                map[string]&Node // recursive declaration index used only for member callbacks
	generated_declarations           map[string]bool // prevent duplicate generations
	emitted_cpp_members              map[string]bool // cross-file dedup for emitted C++ member definitions
	emitted_top_level_fns            map[string]bool // cross-file dedup for top-level C/C++ function emissions
	emitted_top_level_name_counts    map[string]int // overload suffixes for top-level function names in dir mode
	external_types                   map[string]bool // external C types that need declarations
	system                           SystemSurface // declarations read from system headers
	function_type_aliases            map[string]bool // aliases of C function types (not function pointers)
	cpp_template_param_names         map[string]bool // names of template type parameters in the project
	cpp_receiver_cast_id             string // explicit cast node that is the current method call receiver
	cpp_record_nested_type_aliases   map[string]map[string]string // specialization => nested typedef V name => its concrete V name
	known_types                      map[string]bool // all type names that will be defined in this translation unit (pre-scanned)
	project_known_types              map[string]bool // all type names discovered across the whole dir translation
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
	mut line := s
	return line.replace('false_', 'false').replace('true_', 'true')
}

fn is_all_upper_identifier(name string) bool {
	if name == '' {
		return false
	}
	mut has_letter := false
	for ch in name {
		if ch >= `A` && ch <= `Z` {
			has_letter = true
			continue
		}
		if ch >= `0` && ch <= `9` {
			continue
		}
		if ch == `_` {
			continue
		}
		return false
	}
	return has_letter
}

fn c_identifier_to_v_name(name string) string {
	if is_all_upper_identifier(name) {
		return name.to_lower().trim_left('_')
	}
	return name.camel_to_snake().trim_left('_')
}

fn c_known_symbol_v_name(name string) string {
	if name in c_known_fn_names || name in c_known_const_names {
		return 'C.${name}'
	}
	return ''
}

fn c_float_math_overload_v_name(name string, qualified_type string) string {
	if name.ends_with('f') || '${name}f' !in c_known_fn_names || !qualified_type.contains('(') {
		return ''
	}
	return_type := qualified_type.all_before('(').trim_space()
	if convert_type(return_type).name == 'f32' {
		return 'C.${name}f'
	}
	return ''
}

fn c_stdio_stream_v_name(name string) string {
	return match name {
		'stdin', '__stdinp' { 'stdin' }
		'stdout', '__stdoutp' { 'stdout' }
		'stderr', '__stderrp' { 'stderr' }
		else { '' }
	}
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

// Place text on the same line as the preceding aggregate closing delimiter.
// Strips trailing whitespace after '}', ']', or ']!' and appends ' <text>'.
// If add_newline is true, adds a newline after text.
fn (mut c C2V) put_on_same_line_as_close_brace(text string, add_newline bool) {
	mut s := c.out.str()
	// Trim trailing whitespace/newlines to find the closing delimiter.
	trimmed := s.trim_right(' \t\n\r')
	c.out = strings.new_builder(s.len + text.len)
	if trimmed.ends_with('}') || trimmed.ends_with(']') || trimmed.ends_with(']!') {
		c.out.write_string(trimmed)
		c.out.write_string(' ')
	} else {
		// Restore the original content
		c.out.write_string(s)
	}
	if add_newline {
		c.out.writeln(text)
		c.out_line_empty = true
	} else {
		c.out.write_string(text)
		c.out_line_empty = false
	}
}

fn (mut c C2V) gen_comment(node Node) {
	comment_id := node.unique_id
	if node.comment.len != 0 && c.can_output_comment[comment_id] == true {
		vprint('${node.comment}')
		vprintln('offset=[${node.location.offset},${node.range.begin.offset},${node.range.end.offset}] ${node.kind} n="${node.name}"\n')
		// If we're in the middle of a line (expression), skip comment to avoid breaking syntax
		if c.cur_out_line.trim_space().len > 0 {
			// Don't place comment in middle of expression
			c.can_output_comment[comment_id] = false
			return
		}
		c.cur_out_line += node.comment
		c.out.write_string(c.cur_out_line)
		c.cur_out_line = ''
		c.out_line_empty = true
		c.can_output_comment[comment_id] = false // we can't output a comment mutiple times
	}
}

// add_var_func_name add the_string into a map. Keep value unique
// key is in c_name form, but value in v_name form
// v variable/function name: can't start with `_`, snake case
fn (mut c C2V) add_var_func_name(mut the_map map[string]string, c_string string) string {
	if v := the_map[c_string] {
		return v
	}
	mut v_string := c_identifier_to_v_name(c_string)
	// Check for conflict with V reserved function names
	if v_string in v_reserved_fn_names {
		vprintln('${@FN}reserved conflict: ${c_string} => ${v_string}')
		v_string = 'c_' + v_string
	}
	// Check for 'builtin_' prefix which V interprets as 'builtin__' module prefix
	if v_string.starts_with('builtin_') {
		vprintln('${@FN}builtin prefix conflict: ${c_string} => ${v_string}')
		v_string = 'c_' + v_string
	}
	if v_string in the_map.values() {
		vprintln('${@FN}dup: ${c_string} => ${v_string}')
		v_string += '_vdup' + c.cnt.str() // renaming the variable's name, avoid duplicate
		c.cnt++
	}
	the_map[c_string] = v_string
	return v_string
}

fn global_name_uses_v_name(global_name string, v_name string) bool {
	if c_identifier_to_v_name(global_name) == v_name {
		return true
	}
	lower_first_alias := filter_name(global_name.uncapitalize(), true)
	if lower_first_alias == v_name {
		return true
	}
	snake_alias := filter_name(c_identifier_to_v_name(global_name), true)
	if snake_alias == v_name {
		return true
	}
	return false
}

fn (c &C2V) global_uses_v_name(v_name string) bool {
	for global_name, _ in c.globals {
		if global_name_uses_v_name(global_name, v_name) {
			return true
		}
	}
	for node in c.tree.inner {
		if !node.kindof(.var_decl) {
			continue
		}
		mut global_name := node.name
		class_name := extract_class_from_mangled(node.mangled_name)
		if class_name != '' {
			global_name = class_name + '_' + global_name
		}
		if global_name_uses_v_name(global_name, v_name) {
			return true
		}
	}
	return false
}

fn is_ascii_space_byte(ch u8) bool {
	return ch == ` ` || ch == `\t` || ch == `\r` || ch == `\n`
}

fn collapse_ascii_whitespace(s string) string {
	mut out := strings.new_builder(s.len)
	mut in_space := false
	for i := 0; i < s.len; i++ {
		ch := s[i]
		if is_ascii_space_byte(ch) {
			if !in_space {
				out.write_u8(` `)
				in_space = true
			}
			continue
		}
		out.write_u8(ch)
		in_space = false
	}
	return out.str().trim_space()
}

fn normalize_cpp_name_fragment(name string) string {
	mut t := collapse_ascii_whitespace(name)
	if t == '' {
		return ''
	}
	if !t.contains('<') && t.contains(' ') {
		parts := t.split(' ').filter(it != '')
		if parts.len > 0 {
			t = parts[parts.len - 1]
		}
	}
	for t.starts_with('&') || t.starts_with('*') {
		t = t[1..].trim_space()
	}
	for t.ends_with('&') || t.ends_with('*') {
		t = t[..t.len - 1].trim_space()
	}
	return t
}

fn (mut c C2V) add_fn_name(c_name string) string {
	mut v_name := c.add_var_func_name(mut c.fns, c_name)
	if c.global_uses_v_name(v_name) {
		base := v_name + '_fn'
		mut candidate := base
		mut i := 2
		for {
			mut taken := c.global_uses_v_name(candidate)
			if !taken {
				for existing in c.fns.values() {
					if existing == candidate {
						taken = true
						break
					}
				}
			}
			if !taken {
				break
			}
			candidate = '${base}${i}'
			i++
		}
		c.fns[c_name] = candidate
		v_name = candidate
	}
	return v_name
}

// add_struct_name add the_string into a map. Keep value unique
// key is in c_name form, but value in v_name form
// v struct name : can't start with `_`, capitalize
fn (mut c C2V) add_struct_name(mut the_map map[string]string, c_string string) string {
	c_key := normalize_cpp_name_fragment(c_string)
	if c_key == '' {
		return ''
	}
	if v := the_map[c_key] {
		return v
	}
	// Some C++ AST paths already carry the canonical V spelling after the source
	// record was registered. Reuse that value instead of manufacturing an
	// unreachable duplicate receiver.
	if c_key[0].is_capital() && c_key in the_map.values() {
		the_map[c_key] = c_key
		return c_key
	}
	mut v_string := c_key.trim_left('_').capitalize()
	// Check for conflict with V built-in type names (e.g., Option, Result)
	if v_string in v_builtin_type_names {
		vprintln('${@FN}builtin conflict: ${c_key} => ${v_string}')
		v_string += '_'
	}
	if v_string in the_map.values() {
		vprintln('${@FN}dup: ${c_key} => ${v_string}')
		v_string += '_vdup' + c.cnt.str() // renaming the struct's name, avoid duplicate
		c.cnt++
	}
	the_map[c_key] = v_string
	return v_string
}

// prefix_external_type checks if a type is external (not defined in this translation unit)
// and prefixes it with 'C.' if so. This handles types from header files.
fn (mut c C2V) prefix_external_type(type_name string) string {
	// Handle function types: fn (&Foo, Bar) Baz
	if type_name.starts_with('fn (') {
		// Extract parts: args and return type
		close_paren := type_name.last_index(')') or { return type_name }
		args_part := type_name['fn ('.len..close_paren]
		ret_part := type_name[close_paren + 1..].trim_space()

		// Process each argument type
		args := args_part.split(',')
		mut new_args := []string{}
		for arg in args {
			new_args << c.prefix_external_type(arg.trim_space())
		}

		// Process return type if present
		mut result := 'fn (' + new_args.join(', ') + ')'
		if ret_part.len > 0 {
			result += ' ' + c.prefix_external_type(ret_part)
		}
		return result
	}

	// Skip built-in V types
	builtin_v_types := ['int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'f32', 'f64',
		'bool', 'string', 'rune', 'voidptr', 'usize', 'isize', 'void']
	// Extract base type name (remove & and [] prefixes)
	mut base := type_name
	for base.starts_with('&') || base.starts_with('[') {
		if base.starts_with('&') {
			base = base[1..]
		} else if base.starts_with('[') {
			// Skip past array notation like [3] or []
			idx := base.index(']') or { break }
			base = base[idx + 1..]
		}
	}
	// If it's empty, starts with lowercase, or is a builtin type, return unchanged
	if base.len == 0 || !base[0].is_capital() || base in builtin_v_types {
		return type_name
	}
	// If it starts with 'C.' already, return unchanged
	if base.starts_with('C.') {
		return type_name
	}
	// Records declared by system headers use C interop spelling, even when the
	// AST pre-scan has registered the same tag as a project-local type.
	if c_name := c.system.record_v_names[base] {
		if base !in c.project_known_types {
			return type_name.replace(base, 'C.' + c_name)
		}
	}
	// Check if this type is defined in the current translation unit
	// Look for the lowercase version in types map values (V type names are capitalized)
	for _, v_name in c.types {
		if v_name == base {
			return type_name // Type is defined, no prefix needed
		}
	}
	for _, v_name in c.enums {
		if v_name == base {
			return type_name // Type is defined as enum, no prefix needed
		}
	}
	// Check if this type will be defined later in this translation unit
	if base in c.known_types {
		return type_name
	}
	// Type is external.
	// Track this external type for declaration generation.
	// Only add valid V identifiers (no spaces, special chars, single-letter capitals, reserved words)
	if base.len > 1 && !base.contains(' ') && !base.contains('(') && !base.contains(')')
		&& !base.contains('*') && !base.contains('&') && !base.contains('<') && !base.contains('>')
		&& !base.contains(',') {
		c.external_types[base] = true
	}
	// In C++ mode we do not rely on C. aliases for unknown symbols.
	// Emit local fallback stubs instead so generated wrappers remain self-contained.
	if c.is_cpp {
		return type_name
	}
	// Replace the base type with C.base in C mode.
	return type_name.replace(base, 'C.' + base)
}

fn (c &C2V) is_known_enum_v_type(type_name string) bool {
	for _, v_name in c.enums {
		if v_name == type_name {
			return true
		}
	}
	return false
}

fn (c &C2V) external_decl_abi_type(type_name string) string {
	mut base := type_name.trim_space()
	mut prefix := ''
	for base.starts_with('&') {
		prefix += '&'
		base = base[1..]
	}
	if c.is_known_enum_v_type(base) {
		return prefix + 'int'
	}
	return type_name
}

fn (mut c C2V) save() {
	vprintln('\n\n')
	if !c.is_dir {
		// Directory translation writes global constructors to 0_globals.v.
		c.out.write_string(c.global_constructors_source(map[string]string{}))
	}
	mut s := c.out.str()
	vprintln('VVVV len=${c.labels.len}')
	vprintln(c.labels.str())
	// If there are goto statements, replace all placeholders with actual `goto label_name;`
	// Because JSON AST doesn't have label names for some reason, just IDs.
	if c.labels.len > 0 {
		for label_id, label_name in c.labels {
			vprintln('"${label_id}" => "${label_name}"')
			s = s.replace('_GOTO_PLACEHOLDER_' + label_id, label_name)
		}
	}
	if c.skeleton_mode {
		s = sanitize_skeleton_output(s)
	}
	// Generate declarations for external C types
	// Generate common C function declarations if they're used
	mut c_fn_decls := strings.new_builder(100)
	needs_ctype_b_loc_decl := s.contains('C.__ctype_b_loc') && !s.contains('fn C.__ctype_b_loc(')
	needs_c_fns := s.contains('C.getenv') || s.contains('C.strtoul') || s.contains('C.strtol')
		|| s.contains('C.strcpy') || s.contains('C.strcat') || s.contains('C.__error')
		|| s.contains('C.tmpfile') || s.contains('C.fgets') || s.contains('C.strncpy')
		|| s.contains('C.qsort') || s.contains('C.__builtin_expect')
		|| s.contains('C.__assert_rtn') || s.contains('C.fabs') || s.contains('C.fabsf')
		|| s.contains('C.strlen') || s.contains('C.strstr') || needs_ctype_b_loc_decl
	if needs_c_fns {
		c_fn_decls.write_string('\n// Common C function declarations\n')
		if s.contains('C.getenv') {
			c_fn_decls.write_string('fn C.getenv(&char) &char\n')
		}
		if s.contains('C.strtoul') {
			c_fn_decls.write_string('fn C.strtoul(&i8, &&i8, int) u64\n')
		}
		if s.contains('C.strtol') {
			c_fn_decls.write_string('fn C.strtol(&i8, &&i8, int) int\n')
		}
		if s.contains('C.strcpy') {
			c_fn_decls.write_string('fn C.strcpy(&i8, &i8) &i8\n')
		}
		if s.contains('C.strcat') {
			c_fn_decls.write_string('fn C.strcat(&i8, &i8) &i8\n')
		}
		if s.contains('C.tmpfile') {
			c_fn_decls.write_string('fn C.tmpfile() &C.FILE\n')
		}
		if s.contains('C.fgets') {
			c_fn_decls.write_string('fn C.fgets(&i8, int, &C.FILE) &i8\n')
		}
		if s.contains('C.strncpy') {
			c_fn_decls.write_string('fn C.strncpy(&i8, &i8, usize) &i8\n')
		}
		if s.contains('C.__error') {
			c_fn_decls.write_string('fn C.__error() &int\n')
		}
		if s.contains('C.qsort') {
			c_fn_decls.write_string('fn C.qsort(voidptr, usize, usize, fn (voidptr, voidptr) int)\n')
		}
		if s.contains('C.__builtin_expect') {
			c_fn_decls.write_string('fn C.__builtin_expect(int, int) int\n')
		}
		if s.contains('C.__assert_rtn') {
			c_fn_decls.write_string('fn C.__assert_rtn(&i8, &i8, int, &i8)\n')
		}
		if s.contains('C.fabs(') {
			c_fn_decls.write_string('fn C.fabs(f64) f64\n')
		}
		if s.contains('C.fabsf(') {
			c_fn_decls.write_string('fn C.fabsf(f32) f32\n')
		}
		if s.contains('C.strlen(') {
			c_fn_decls.write_string('fn C.strlen(&i8) usize\n')
		}
		if s.contains('C.strstr(') {
			c_fn_decls.write_string('fn C.strstr(&i8, &i8) &i8\n')
		}
		if needs_ctype_b_loc_decl {
			c_fn_decls.write_string('fn C.__ctype_b_loc() &&u16\n')
		}
		c_fn_decls.write_string('\n')
	}
	mut preamble_insert := if s.contains('c2v_main_argv_storage') { 'import os\n' } else { '' }
	preamble_insert += c_fn_decls.str()
	if c.is_cpp && !c.is_dir && c.external_c_fn_declarations.len > 0 {
		mut external_fn_names := c.external_c_fn_declarations.keys()
		external_fn_names.sort()
		preamble_insert += '// C-linkage functions supplied by external libraries\n'
		for name in external_fn_names {
			if name !in c.system.declaring_headers {
				preamble_insert += '@[c_extern]\n'
			}
			preamble_insert += c.external_c_fn_declaration(name) + '\n'
		}
		preamble_insert += '\n'
	}
	if c.is_cpp && !c.is_dir {
		preamble_insert += c.external_surface_declarations(s, c.project_additional_flags)
	}
	if !c.is_dir && s.contains('c2v_builtin_trap()') {
		preamble_insert += "fn c2v_builtin_trap() { panic('C __builtin_trap') }\n\n"
	}
	if !c.is_dir && (s.contains('c2v_builtin_bswap16(') || s.contains('c2v_builtin_bswap32(')) {
		mut bswap_helpers := strings.new_builder(320)
		write_c2v_bswap_helpers(mut bswap_helpers)
		preamble_insert += bswap_helpers.str()
	}
	va_list_decl_key := 'cpp_va_list_decl:${os.dir(c.outv)}'
	if s.contains('C.va_list') && va_list_decl_key !in c.generated_declarations {
		c.generated_declarations[va_list_decl_key] = true
		preamble_insert += '@[typedef]\nstruct C.va_list {}\n\n'
	}
	if !c.is_dir && (s.contains('c2v_pointer_postfix(') || s.contains('c2v_pointer_prefix(')) {
		mut pointer_helpers := strings.new_builder(320)
		write_c2v_pointer_update_helpers(mut pointer_helpers)
		preamble_insert += pointer_helpers.str()
	}
	if c.local_type_declarations.len > 0 {
		preamble_insert += c.local_type_declarations.join('') + '\n'
	}
	if c.external_types.len > 0 {
		mut ext_names := c.external_types.keys()
		ext_names.sort()
		mut external_decls := strings.new_builder(200)
		if c.is_cpp {
			// In directory mode, emit shared declarations once in 0_globals.v via save_globals().
			if !c.is_dir {
				mut undeclared_ext_types := []string{}
				for ext_type in ext_names {
					if ext_type in c.known_types || ext_type in c.type_aliases
						|| ext_type in c.file_declared_aliases {
						continue
					}
					undeclared_ext_types << ext_type
				}
				if undeclared_ext_types.len > 0 {
					external_decls.write_string('\n// External type declarations (from headers)\n')
				}
				for ext_type in undeclared_ext_types {
					external_decls.write_string('struct ' + ext_type + ' {}\n')
				}
			}
		} else {
			external_decls.write_string('\n// External C type declarations (from headers)\n')
			for ext_type in ext_names {
				external_decls.write_string('struct C.' + ext_type + ' {}\n')
			}
		}
		mut external_s := external_decls.str()
		if external_s != '' {
			external_s += '\n'
			preamble_insert += external_s
		}
	}
	if preamble_insert.len > 0 {
		// Insert after @[translated] and module lines.
		insert_pos := s.index('\n\n') or { 0 }
		if insert_pos > 0 {
			s = s[..insert_pos + 1] + preamble_insert + s[insert_pos + 1..]
		} else {
			s = preamble_insert + s
		}
	}
	if c.skeleton_mode {
		s = sanitize_skeleton_output(s)
	} else {
		s = sanitize_translated_output(s, c.skeleton_mode, c.cpp_mut_method_names.keys())
	}
	c.out_file.write_string(s) or { panic('failed to write to the .v file: ${err}') }
	c.out_file.close()
	if s.contains('FILE') {
		c.has_cfile = true
	}
	if !c.is_wrapper && !c.outv.contains('st_lib.v') && !c.skeleton_mode {
		mut fmt_result := -1
		max_attempts := if c.project_require_no_stubs { 5 } else { 1 }
		for attempt in 0 .. max_attempts {
			fmt_result = os.system('v fmt -translated -w ${c.outv} > /dev/null')
			if fmt_result == 0 {
				break
			}
			if attempt + 1 < max_attempts {
				// Long translations launch many short-lived parser and formatter
				// processes. Allow a transient process-table failure to settle before
				// deciding that otherwise valid generated source is malformed.
				time.sleep((attempt + 1) * 100 * time.millisecond)
			}
		}
		if fmt_result != 0 && c.project_require_no_stubs {
			c.verror('v fmt rejected strict translation output ${c.outv}')
		}
	}
}

fn leading_whitespace(line string) string {
	mut i := 0
	for i < line.len {
		if line[i] == ` ` || line[i] == `\t` {
			i++
			continue
		}
		break
	}
	return line[..i]
}

fn is_identifier_char_for_ctor_fix(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
		|| (ch >= `0` && ch <= `9`) || ch == `_` || ch == `[` || ch == `]`
}

fn replace_type_empty_ctor_field_access(line string) string {
	mut out := line
	mut start_search := 0
	for start_search < out.len {
		rel := out[start_search..].index('().') or { break }
		idx := start_search + rel
		mut tok_start := idx
		for tok_start > 0 && is_identifier_char_for_ctor_fix(out[tok_start - 1]) {
			tok_start--
		}
		// Only a bare type name is a constructor; `C.Name()` and `obj.Name()` are calls.
		if tok_start < idx && (tok_start == 0 || out[tok_start - 1] != `.`) {
			token := out[tok_start..idx]
			if token.len > 0 && token[0] >= `A` && token[0] <= `Z` {
				out = out[..idx] + '{}.' + out[idx + 3..]
				start_search = idx + 3
				continue
			}
		}
		start_search = idx + 3
	}
	return out
}

fn is_simple_identifier_char(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
		|| (ch >= `0` && ch <= `9`) || ch == `_`
}

fn is_simple_identifier(name string) bool {
	if name.len == 0 {
		return false
	}
	first := name[0]
	if !((first >= `a` && first <= `z`) || (first >= `A` && first <= `Z`) || first == `_`) {
		return false
	}
	for i in 1 .. name.len {
		if !is_simple_identifier_char(name[i]) {
			return false
		}
	}
	return true
}

fn replace_bare_identifier(line string, from string, to string) string {
	if from == '' || !line.contains(from) {
		return line
	}
	mut out := strings.new_builder(line.len + to.len)
	mut i := 0
	mut in_single_quote := false
	mut in_double_quote := false
	mut in_backtick := false
	for i < line.len {
		ch := line[i]
		if in_single_quote {
			out.write_u8(ch)
			if ch == `\\` && i + 1 < line.len {
				i++
				out.write_u8(line[i])
				i++
				continue
			}
			if ch == `'` {
				in_single_quote = false
			}
			i++
			continue
		}
		if in_double_quote {
			out.write_u8(ch)
			if ch == `\\` && i + 1 < line.len {
				i++
				out.write_u8(line[i])
				i++
				continue
			}
			if ch == `"` {
				in_double_quote = false
			}
			i++
			continue
		}
		if in_backtick {
			out.write_u8(ch)
			if ch == `\\` && i + 1 < line.len {
				i++
				out.write_u8(line[i])
				i++
				continue
			}
			if ch == `\`` {
				in_backtick = false
			}
			i++
			continue
		}
		if ch == `/` && i + 1 < line.len && line[i + 1] == `/` {
			out.write_string(line[i..])
			break
		}
		match ch {
			`'` {
				in_single_quote = true
			}
			`"` {
				in_double_quote = true
			}
			`\`` {
				in_backtick = true
			}
			else {}
		}

		if i + from.len <= line.len && line[i..i + from.len] == from {
			prev := if i > 0 { line[i - 1] } else { ` ` }
			next := if i + from.len < line.len { line[i + from.len] } else { ` ` }
			if !is_simple_identifier_char(prev) && !is_simple_identifier_char(next) && prev != `.` {
				out.write_string(to)
				i += from.len
				continue
			}
		}
		out.write_u8(ch)
		i++
	}
	return out.str()
}

fn find_simple_assignment_operator_index(line string) int {
	mut paren_depth := 0
	mut bracket_depth := 0
	mut brace_depth := 0
	for i := 0; i < line.len; i++ {
		ch := line[i]
		match ch {
			`(` {
				paren_depth++
			}
			`)` {
				if paren_depth > 0 {
					paren_depth--
				}
			}
			`[` {
				bracket_depth++
			}
			`]` {
				if bracket_depth > 0 {
					bracket_depth--
				}
			}
			`{` {
				brace_depth++
			}
			`}` {
				if brace_depth > 0 {
					brace_depth--
				}
			}
			`=` {
				if paren_depth != 0 || bracket_depth != 0 || brace_depth != 0 {
					continue
				}
				prev := if i > 0 { line[i - 1] } else { ` ` }
				next := if i + 1 < line.len { line[i + 1] } else { ` ` }
				if next == `=` {
					continue
				}
				if prev == `=` || prev == `!` || prev == `<` || prev == `>` || prev == `+`
					|| prev == `-` || prev == `*` || prev == `/` || prev == `%` || prev == `&`
					|| prev == `|` || prev == `^` || prev == `:` {
					continue
				}
				return i
			}
			else {}
		}
	}
	return -1
}

fn unwrap_inline_unsafe_statement(line string) (string, bool) {
	trimmed := line.trim_space()
	prefix := 'unsafe {'
	if !trimmed.starts_with(prefix) || !trimmed.ends_with('}') {
		return line, false
	}
	inner := trimmed[prefix.len..trimmed.len - 1].trim_space()
	if inner == '' || !rendered_parentheses_are_balanced(inner) {
		return line, false
	}
	return leading_whitespace(line) + inner, true
}

fn find_compound_assignment_operator(line string) (int, string) {
	compound_ops := ['<<=', '>>=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=']
	mut paren_depth := 0
	mut bracket_depth := 0
	mut brace_depth := 0
	for i := 0; i < line.len; i++ {
		ch := line[i]
		match ch {
			`(` {
				paren_depth++
			}
			`)` {
				if paren_depth > 0 {
					paren_depth--
				}
			}
			`[` {
				bracket_depth++
			}
			`]` {
				if bracket_depth > 0 {
					bracket_depth--
				}
			}
			`{` {
				brace_depth++
			}
			`}` {
				if brace_depth > 0 {
					brace_depth--
				}
			}
			else {}
		}

		if paren_depth != 0 || bracket_depth != 0 || brace_depth != 0 {
			continue
		}
		for op in compound_ops {
			if i + op.len <= line.len && line[i..i + op.len] == op {
				return i, op
			}
		}
	}
	return -1, ''
}

fn collapse_nested_parenthesized_unsafe_addr(line string) string {
	if line.count('unsafe {') < 2 || !line.contains('(unsafe { &') {
		return line
	}
	mut out := line
	mut search_from := 0
	marker := '(unsafe { &'
	for search_from < out.len {
		rel := out[search_from..].index(marker) or { break }
		start := search_from + rel
		if start > 0 && is_recovery_ident_char(out[start - 1]) {
			search_from = start + 1
			continue
		}
		expr_start := start + marker.len
		mut nested_parens := 0
		mut close_idx := -1
		for i := expr_start; i < out.len; i++ {
			ch := out[i]
			if ch == `(` {
				nested_parens++
			} else if ch == `)` {
				if nested_parens > 0 {
					nested_parens--
				}
			}
			if nested_parens == 0 && i + 2 < out.len && out[i] == ` ` && out[i + 1] == `}`
				&& out[i + 2] == `)` {
				close_idx = i
				break
			}
		}
		if close_idx < 0 {
			break
		}
		inner := out[expr_start..close_idx]
		out = out[..start] + '(&' + inner + ')' + out[close_idx + 3..]
		search_from = start + inner.len + 3
	}
	return out
}

fn collapse_nested_unsafe_rhs_deref(line string) string {
	if line.count('unsafe {') < 2 || !line.contains('= unsafe { *') {
		return line
	}
	mut out := line
	mut search_from := 0
	marker := '= unsafe { *'
	for search_from < out.len {
		rel := out[search_from..].index(marker) or { break }
		start := search_from + rel
		expr_start := start + marker.len
		close_rel := out[expr_start..].index(' }') or { break }
		close_idx := expr_start + close_rel
		out = out[..start] + '= *' + out[expr_start..close_idx] + out[close_idx + 2..]
		search_from = start + 3
	}
	return out
}

fn collapse_nested_unsafe_deref_blocks(line string) string {
	if line.count('unsafe { *') < 2 {
		return line
	}
	mut out := line
	marker := 'unsafe { *'
	first_idx := out.index(marker) or { return out }
	mut search_from := first_idx + marker.len
	for search_from < out.len {
		rel := out[search_from..].index(marker) or { break }
		start := search_from + rel
		expr_start := start + marker.len
		close_rel := out[expr_start..].index(' }') or { break }
		close_idx := expr_start + close_rel
		out = out[..start] + '*' + out[expr_start..close_idx] + out[close_idx + 2..]
		search_from = start + 1
	}
	return out
}

fn collapse_nested_unsafe_blocks(line string) string {
	marker := 'unsafe {'
	if line.count(marker) < 2 {
		return line
	}
	mut out := line
	for {
		mut collapsed := false
		mut outer_search_from := 0
		for outer_search_from < out.len {
			outer_rel := out[outer_search_from..].index(marker) or { break }
			outer_start := outer_search_from + outer_rel
			outer_close := find_matching_unsafe_block_close(out, outer_start)
			if outer_close < 0 {
				break
			}
			inner_search_from := outer_start + marker.len
			inner_rel := out[inner_search_from..outer_close].index(marker) or {
				outer_search_from = outer_close + 1
				continue
			}
			inner_start := inner_search_from + inner_rel
			inner_close := find_matching_unsafe_block_close(out, inner_start)
			if inner_close < 0 || inner_close > outer_close {
				outer_search_from = outer_close + 1
				continue
			}
			inner := out[inner_start + marker.len..inner_close].trim_space()
			out = out[..inner_start] + inner + out[inner_close + 1..]
			collapsed = true
			break
		}
		if !collapsed {
			break
		}
	}
	return out
}

fn find_matching_unsafe_block_close(text string, marker_start int) int {
	mut depth := 1
	for i := marker_start + 'unsafe {'.len; i < text.len; i++ {
		if text[i] == `{` {
			depth++
		} else if text[i] == `}` {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

fn break_long_logical_condition(line string) string {
	trimmed := line.trim_space()
	if line.len < 240 || !trimmed.starts_with('if ') {
		return line
	}
	indent := leading_whitespace(line)
	continuation := '\n' + indent + '\t'
	return line.replace(' && ', continuation + '&& ').replace(' || ', continuation + '|| ')
}

fn split_long_if_condition(line string) ([]string, []string, bool) {
	trimmed := line.trim_space()
	// vfmt's infix wrapper currently panics on some nested conditions above roughly
	// 200 columns. Materialize their top-level terms before formatting.
	if line.len < 200 || !trimmed.starts_with('if ') || !trimmed.ends_with('{') {
		return []string{}, []string{}, false
	}
	condition := trimmed[3..trimmed.len - 1].trim_space()
	mut terms := []string{}
	mut operators := []string{}
	mut depth := 0
	mut quote := u8(0)
	mut escaped := false
	mut term_start := 0
	mut i := 0
	for i < condition.len {
		ch := condition[i]
		if quote != 0 {
			if escaped {
				escaped = false
			} else if ch == `\\` {
				escaped = true
			} else if ch == quote {
				quote = 0
			}
			i++
			continue
		}
		if ch == `'` || ch == `"` {
			quote = ch
			i++
			continue
		}
		if ch in [`(`, `[`, `{`] {
			depth++
		} else if ch in [`)`, `]`, `}`] {
			depth--
		}
		if depth == 0 {
			mut op := ''
			if condition[i..].starts_with(' && ') {
				op = '&&'
			} else if condition[i..].starts_with(' || ') {
				op = '||'
			}
			if op != '' {
				term := condition[term_start..i].trim_space()
				if term == '' {
					return []string{}, []string{}, false
				}
				terms << term
				operators << op
				i += 4
				term_start = i
				continue
			}
		}
		i++
	}
	last_term := condition[term_start..].trim_space()
	if terms.len == 0 || last_term == '' {
		return []string{}, []string{}, false
	}
	terms << last_term
	return terms, operators, terms.len == operators.len + 1
}

fn split_simple_return_assignment(line string) (string, string, bool) {
	trimmed := line.trim_space()
	if !trimmed.starts_with('return ') {
		return '', '', false
	}
	tail := trimmed['return '.len..]
	assign_idx := find_simple_assignment_operator_index(tail)
	if assign_idx <= 0 {
		return '', '', false
	}
	lhs := tail[..assign_idx].trim_space()
	rhs := tail[assign_idx + 1..].trim_space()
	if rhs == '' || !is_simple_identifier(lhs) {
		return '', '', false
	}
	return lhs, rhs, true
}

fn should_sanitize_nonassignable_lhs(lhs string) bool {
	_, _, found := split_nonassignable_lhs_receiver(lhs)
	return found
}

fn last_suffixed_method_call(expr string, method_prefix string) (int, int, bool) {
	mut search_from := 0
	mut last_method_idx := -1
	mut last_open_idx := -1
	for search_from < expr.len {
		rel_idx := expr[search_from..].index(method_prefix) or { break }
		method_idx := search_from + rel_idx
		mut open_idx := method_idx + method_prefix.len
		for open_idx < expr.len && expr[open_idx] >= `0` && expr[open_idx] <= `9` {
			open_idx++
		}
		if open_idx < expr.len && expr[open_idx] == `(` {
			last_method_idx = method_idx
			last_open_idx = open_idx
		}
		search_from = method_idx + method_prefix.len
	}
	return last_method_idx, last_open_idx, last_method_idx >= 0
}

fn matching_open_paren_before(expr string, close_idx int) int {
	if close_idx < 0 || close_idx >= expr.len || expr[close_idx] != `)` {
		return -1
	}
	mut depth := 0
	for i := close_idx; i >= 0; i-- {
		if expr[i] == `)` {
			depth++
		} else if expr[i] == `(` {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

fn split_assignable_call_lhs_receiver(lhs string) (string, string, bool) {
	for close_idx := lhs.len - 1; close_idx >= 0; close_idx-- {
		if lhs[close_idx] != `)` {
			continue
		}
		open_idx := matching_open_paren_before(lhs, close_idx)
		if open_idx <= 0 || !is_simple_identifier_char(lhs[open_idx - 1]) {
			continue
		}
		receiver := lhs[..close_idx + 1].trim_space()
		tail := lhs[close_idx + 1..].trim_space()
		if tail == '' || tail.starts_with('.') || tail.starts_with('[') {
			return receiver, tail, true
		}
	}
	return '', '', false
}

fn split_unsafe_deref_lhs_receiver(lhs string) (string, string, bool) {
	trimmed := lhs.trim_space()
	if trimmed.starts_with('*') && !trimmed.starts_with('*(') && trimmed.ends_with(')') {
		receiver := trimmed[1..].trim_space()
		if receiver.contains('(') && rendered_parentheses_are_balanced(receiver) {
			// A dereferenced pointer-returning call is already the lvalue. Preserve
			// the pointer returned by the call when materializing it; copying the
			// pointed-to scalar and dereferencing that temporary later produces
			// invalid C such as `*int_value = ...`.
			return receiver, '', true
		}
	}
	if trimmed.starts_with('*&') && trimmed.contains('(') && trimmed.ends_with(')')
		&& rendered_parentheses_are_balanced(trimmed[1..]) {
		// Materialize the pointer in casted lvalues such as `*&int(&bytes[i])`,
		// rather than copying the value that it points at.
		return trimmed[1..], '', true
	}
	if trimmed.starts_with('*(') {
		close_idx := find_matching_paren_index(trimmed, 1)
		if close_idx == trimmed.len - 1 {
			receiver := strip_balanced_outer_parentheses(trimmed[2..close_idx])
			if receiver != '' && rendered_parentheses_are_balanced(receiver) {
				return receiver, '', true
			}
		}
	}
	mut prefix := ''
	mut close_marker := ''
	if trimmed.starts_with('unsafe { *') {
		prefix = 'unsafe { *'
		close_marker = ' }'
	} else if trimmed.starts_with('(unsafe { *') {
		prefix = '(unsafe { *'
		close_marker = ' })'
	} else {
		return '', '', false
	}
	close_idx := trimmed.last_index(close_marker) or { return '', '', false }
	if close_idx <= prefix.len {
		return '', '', false
	}
	receiver := strip_balanced_outer_parentheses(trimmed[prefix.len..close_idx])
	tail := trimmed[close_idx + close_marker.len..].trim_space()
	if receiver == '' || (tail != '' && !tail.starts_with('.') && !tail.starts_with('[')) {
		return '', '', false
	}
	return receiver, tail, true
}

fn sanitized_lhs_initializer(expr string, was_unsafe bool) string {
	trimmed := expr.trim_space()
	// Address-of taken out of an unsafe block stays unsafe, and so does pointer
	// arithmetic addressing the assigned element.
	if (was_unsafe && (trimmed.starts_with('&') || trimmed.contains('(&')))
		|| trimmed.contains(' + ') || trimmed.contains(' - ') {
		return 'unsafe { ${expr} }'
	}
	return expr
}

fn split_nonassignable_lhs_receiver(lhs string) (string, string, bool) {
	unsafe_receiver, unsafe_tail, has_unsafe_receiver := split_unsafe_deref_lhs_receiver(lhs)
	if has_unsafe_receiver {
		return unsafe_receiver, unsafe_tail, true
	}
	mut marker_idx := -1
	mut open_idx := -1
	// C++ `operator[]` returns an lvalue reference; other reference-returning
	// calls are handled by the generic call-receiver split below.
	candidate_idx, candidate_open, found := last_suffixed_method_call(lhs, '.op_index')
	if found {
		marker_idx = candidate_idx
		open_idx = candidate_open
	}
	if marker_idx < 0 || open_idx < 0 {
		return split_assignable_call_lhs_receiver(lhs)
	}
	mut depth := 0
	mut close_idx := -1
	for i := open_idx; i < lhs.len; i++ {
		if lhs[i] == `(` {
			depth++
		} else if lhs[i] == `)` {
			depth--
			if depth == 0 {
				close_idx = i
				break
			}
		}
	}
	if close_idx < 0 {
		return '', '', false
	}
	receiver := lhs[..close_idx + 1].trim_space()
	tail := lhs[close_idx + 1..].trim_space()
	if tail != '' && !tail.starts_with('.') && !tail.starts_with('[') {
		return '', '', false
	}
	return receiver, tail, true
}

fn should_sanitize_mut_receiver_expr(receiver string) bool {
	trimmed := strip_balanced_outer_parentheses(receiver)
	if trimmed == '' || !rendered_parentheses_are_balanced(trimmed) {
		return false
	}
	return should_sanitize_nonassignable_lhs(trimmed) || trimmed.contains('(')
		|| trimmed.contains(' as ') || trimmed.starts_with('unsafe {')
		|| trimmed.starts_with('(unsafe {')
}

fn v_receiver_tail_contains_method_call(tail string) bool {
	mut i := 0
	for i < tail.len {
		if tail[i] != `.` {
			i++
			continue
		}
		i++
		for i < tail.len && (tail[i].is_alnum() || tail[i] == `_`) {
			i++
		}
		if i < tail.len && tail[i] == `(` {
			return true
		}
	}
	return false
}

fn v_receiver_tail_ends_in_method_call(tail string) bool {
	return tail.trim_space().ends_with(')') && v_receiver_tail_contains_method_call(tail)
}

fn strip_balanced_outer_parentheses(expr string) string {
	mut trimmed := expr.trim_space()
	for trimmed.len >= 2 && trimmed[0] == `(` && trimmed[trimmed.len - 1] == `)` {
		mut depth := 0
		mut closes_at_end := false
		for i, ch in trimmed {
			if ch == `(` {
				depth++
			} else if ch == `)` {
				depth--
				if depth == 0 {
					closes_at_end = i == trimmed.len - 1
					break
				}
			}
		}
		if !closes_at_end {
			break
		}
		trimmed = trimmed[1..trimmed.len - 1].trim_space()
	}
	return trimmed
}

fn rendered_parentheses_are_balanced(expr string) bool {
	mut depth := 0
	for ch in expr {
		if ch == `(` {
			depth++
		} else if ch == `)` {
			depth--
			if depth < 0 {
				return false
			}
		}
	}
	return depth == 0
}

fn mut_receiver_rhs_start(prefix string) string {
	trimmed := prefix.trim_space()
	if trimmed.starts_with('return ') {
		return trimmed['return '.len..].trim_space()
	}
	if decl_idx := prefix.last_index(':=') {
		return prefix[decl_idx + 2..].trim_space()
	}
	compound_idx, compound_op := find_compound_assignment_operator(prefix)
	if compound_idx >= 0 {
		return prefix[compound_idx + compound_op.len..].trim_space()
	}
	assign_idx := find_simple_assignment_operator_index(prefix)
	if assign_idx >= 0 {
		return prefix[assign_idx + 1..].trim_space()
	}
	return prefix.trim_space()
}

fn split_mut_receiver_call_expr(trimmed string, method_names []string) (string, string, bool) {
	if trimmed.starts_with('//') || trimmed.starts_with('if ') || trimmed.starts_with('for ')
		|| !trimmed.ends_with(')') {
		return '', '', false
	}
	mut best_marker_idx := -1
	mut best_receiver := ''
	mut best_tail := ''
	for method_name in method_names {
		marker := '.' + method_name + '('
		marker_idx := trimmed.last_index(marker) or { continue }
		receiver := trailing_mut_receiver_expr(mut_receiver_rhs_start(trimmed[..marker_idx]))
		if marker_idx > best_marker_idx && should_sanitize_mut_receiver_expr(receiver) {
			best_marker_idx = marker_idx
			best_receiver = receiver
			best_tail = trimmed[marker_idx..]
		}
	}
	return best_receiver, best_tail, best_marker_idx >= 0
}

fn split_mut_receiver_if_call_expr(trimmed string, method_names []string) (string, string, bool) {
	if !trimmed.starts_with('if ') || !trimmed.ends_with('{') {
		return '', '', false
	}
	condition := trimmed['if '.len..trimmed.len - 1].trim_space()
	mut best_marker_idx := -1
	mut best_receiver := ''
	mut best_tail := ''
	for method_name in method_names {
		marker := '.' + method_name + '('
		marker_idx := condition.last_index(marker) or { continue }
		receiver := trailing_mut_receiver_expr(condition[..marker_idx])
		if marker_idx > best_marker_idx && should_sanitize_mut_receiver_expr(receiver) {
			best_marker_idx = marker_idx
			best_receiver = receiver
			best_tail = condition[marker_idx..]
		}
	}
	return best_receiver, best_tail, best_marker_idx >= 0
}

// Extract the final receiver from a compound condition. For example, the
// receiver before `.parse()` in `!ready || !item.values[0].parse()` is
// `item.values[0]`, not the complete boolean expression to its left.
fn trailing_mut_receiver_expr(prefix string) string {
	mut end := prefix.len
	for end > 0 && prefix[end - 1].is_space() {
		end--
	}
	if end == 0 {
		return ''
	}
	mut paren_depth := 0
	mut bracket_depth := 0
	mut brace_depth := 0
	mut start := end
	for start > 0 {
		ch := prefix[start - 1]
		match ch {
			`)` {
				paren_depth++
			}
			`(` {
				if paren_depth == 0 {
					break
				}
				paren_depth--
			}
			`]` {
				bracket_depth++
			}
			`[` {
				if bracket_depth == 0 {
					break
				}
				bracket_depth--
			}
			`}` {
				brace_depth++
			}
			`{` {
				if brace_depth == 0 {
					break
				}
				brace_depth--
			}
			else {}
		}
		if paren_depth == 0 && bracket_depth == 0 && brace_depth == 0 {
			if ch in [`!`, `&`, `|`, `=`, `<`, `>`, `,`, `?`, `:`, `+`, `-`, `*`, `/`, `%`, `^`] {
				break
			}
		}
		start--
	}
	return prefix[start..end].trim_space()
}

fn replace_unary_marker_suffixes(src string) string {
	lines := src.split_into_lines()
	mut out := strings.new_builder(src.len)
	for i, line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('//') {
			out.write_string(line)
		} else {
			out.write_string(line.replace('++\$', '++').replace('--\$', '--'))
		}
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
	}
	return out.str()
}

fn replace_fixed_array_result_suffixes(src string) string {
	lines := src.split_into_lines()
	mut out := strings.new_builder(src.len)
	mut inside_global_init := false
	for i, line in lines {
		if line.contains('__global') && line.contains('=') {
			inside_global_init = true
		}
		trimmed := line.trim_space()
		field_name := trimmed.all_before(': [')
		is_fixed_array_struct_field := (line.contains('{') && line.contains(': [')
			&& line.contains(']!')) || (trimmed.ends_with(']!') && field_name != trimmed
			&& field_name.len > 0 && field_name.bytes().all(is_simple_identifier_char(it)))
		if inside_global_init || line.contains('__global') || is_fixed_array_struct_field {
			out.write_string(line)
		} else {
			out.write_string(line.replace(']!', ']').replace(']!,', '],').replace(']!}', ']}'))
		}
		if inside_global_init && line.trim_space().ends_with(']!') {
			inside_global_init = false
		}
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
	}
	return out.str()
}

// V emits a fixed-array module global (`[...]!`) as static C data, which C
// rejects unless every element is a compile-time constant. Other initializers
// keep their values in a normal V array, initialized at run time; C/C++
// array-to-pointer casts lower references to `&name[0]`, so callers retain
// pointer semantics.
fn replace_strict_global_array_result_suffixes(src string, static_names map[string]bool) string {
	mut out := strings.new_builder(src.len)
	mut inside_global_init := false
	mut array_depth := 0
	lines := src.split_into_lines()
	for i, line in lines {
		mut closes_outer_array := false
		global_name := line.all_after('__global').trim_space().all_before(' ').all_before('=')
		if !inside_global_init && line.contains('__global') && line.contains('=')
			&& global_name !in static_names {
			rhs := line.all_after('=').trim_space()
			if rhs.starts_with('[') {
				array_depth = rhs.count('[') - rhs.count(']')
				inside_global_init = array_depth > 0
				closes_outer_array = array_depth == 0 && line.trim_space().ends_with(']!')
			}
		} else if inside_global_init {
			array_depth += line.count('[') - line.count(']')
			closes_outer_array = array_depth == 0 && line.trim_space().ends_with(']!')
			if array_depth == 0 {
				inside_global_init = false
			}
		}
		if closes_outer_array {
			suffix_i := line.last_index(']!') or { -1 }
			if suffix_i >= 0 {
				out.write_string(line[..suffix_i] + ']' + line[suffix_i + 2..])
			} else {
				out.write_string(line)
			}
		} else {
			out.write_string(line)
		}
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
	}
	return out.str()
}

fn find_matching_paren_index(text string, open_idx int) int {
	if open_idx < 0 || open_idx >= text.len || text[open_idx] != `(` {
		return -1
	}
	mut depth := 0
	for i := open_idx; i < text.len; i++ {
		if text[i] == `(` {
			depth++
		} else if text[i] == `)` {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

// join_parenthesized_continuation returns the line at `start` joined with the
// following lines needed to balance its parentheses, and how many lines it added.
fn join_parenthesized_continuation(lines []string, start int) (string, int) {
	mut depth := 0
	for i := start; i < lines.len && i < start + 256; i++ {
		depth += lines[i].count('(') - lines[i].count(')')
		if depth <= 0 {
			return lines[start..i + 1].join('\n'), i - start
		}
	}
	return lines[start], 0
}

fn materialize_cpp_reference_args(line string) ([]string, string) {
	marker := '__c2v_ref_arg_'
	mut declarations := []string{}
	mut out := line
	mut search_from := 0
	for search_from < out.len {
		rel_start := out[search_from..].index(marker) or { break }
		start := search_from + rel_start
		mut id_end := start + marker.len
		for id_end < out.len && out[id_end] >= `0` && out[id_end] <= `9` {
			id_end++
		}
		if id_end == start + marker.len || id_end >= out.len || out[id_end] != `(` {
			search_from = id_end
			continue
		}
		close_idx := find_matching_paren_index(out, id_end)
		if close_idx < 0 {
			break
		}
		expr := out[id_end + 1..close_idx].trim_space()
		if expr == '' {
			break
		}
		nested_declarations, materialized_expr := materialize_cpp_reference_args(expr)
		declarations << nested_declarations
		tmp_name := '__c2v_arg_' + out[start + marker.len..id_end]
		declarations << '${tmp_name} := ${materialized_expr}'
		replacement := '&${tmp_name}'
		out = out[..start] + replacement + out[close_idx + 1..]
		search_from = start + replacement.len
	}
	return declarations, out
}

fn collect_nonempty_v_type_names(src string) map[string]bool {
	lines := src.split_into_lines()
	mut names := map[string]bool{}
	for i := 0; i < lines.len; i++ {
		trimmed := lines[i].trim_space()
		if trimmed == '' || trimmed.starts_with('//') {
			continue
		}
		if trimmed.starts_with('interface ') || trimmed.starts_with('enum ')
			|| (trimmed.starts_with('type ') && trimmed.contains('=')) {
			name := extract_declared_type_name(trimmed)
			if name != '' {
				names[name] = true
			}
			continue
		}
		if !trimmed.starts_with('struct ') {
			continue
		}
		name := trimmed.all_after('struct ').all_before('{').trim_space()
		if name == '' || trimmed.ends_with('{}') {
			continue
		}
		mut depth := lines[i].count('{') - lines[i].count('}')
		mut has_layout := depth <= 0
		mut j := i + 1
		for j < lines.len && depth > 0 {
			body_line := lines[j].trim_space()
			depth += lines[j].count('{') - lines[j].count('}')
			if body_line != '' && !body_line.starts_with('//') && body_line != '}' {
				has_layout = true
			}
			j++
		}
		if has_layout {
			names[name] = true
		}
	}
	return names
}

fn remove_project_duplicate_empty_struct_stubs(src string, real_decls map[string]bool, mut seen_empty map[string]bool) string {
	lines := src.split_into_lines()
	mut out := strings.new_builder(src.len)
	mut i := 0
	for i < lines.len {
		line := lines[i]
		trimmed := line.trim_space()
		if trimmed.starts_with('struct ') {
			name := trimmed.all_after('struct ').all_before('{').trim_space()
			mut empty_end := -1
			if trimmed.ends_with('{}') {
				empty_end = i
			} else if trimmed.ends_with('{') {
				mut j := i + 1
				mut only_empty_body := true
				for j < lines.len {
					body_line := lines[j].trim_space()
					if body_line == '}' {
						empty_end = j
						break
					}
					if body_line != '' && !body_line.starts_with('//') {
						only_empty_body = false
						break
					}
					j++
				}
				if !only_empty_body {
					empty_end = -1
				}
			}
			if empty_end >= i && (name in real_decls || name in seen_empty) {
				i = empty_end + 1
				if i < lines.len {
					out.write_u8(`\n`)
				}
				continue
			}
			if empty_end >= i && name != '' {
				seen_empty[name] = true
			}
		}
		out.write_string(line)
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
		i++
	}
	return out.str()
}

fn remove_duplicate_external_empty_struct_stubs(src string) string {
	lines := src.split_into_lines()
	mut real_decls := map[string]bool{}
	// Interfaces, enums and aliases are always real declarations. For structs,
	// distinguish an opaque forward-declaration stub from an actual layout,
	// including the multiline `struct Name {\n}` form emitted by C++ recovery.
	for i := 0; i < lines.len; i++ {
		trimmed := lines[i].trim_space()
		if trimmed.starts_with('interface ') || trimmed.starts_with('enum ')
			|| trimmed.starts_with('type ') {
			name := extract_declared_type_name(trimmed)
			if name != '' {
				real_decls[name] = true
			}
			continue
		}
		if !trimmed.starts_with('struct ') {
			continue
		}
		name := trimmed.all_after('struct ').all_before('{').trim_space()
		if name == '' || trimmed.ends_with('{}') {
			continue
		}
		mut depth := lines[i].count('{') - lines[i].count('}')
		mut has_layout := false
		mut j := i + 1
		for j < lines.len && depth > 0 {
			body_line := lines[j].trim_space()
			depth += lines[j].count('{') - lines[j].count('}')
			if body_line != '' && !body_line.starts_with('//') && body_line != '}' {
				has_layout = true
			}
			j++
		}
		if has_layout {
			real_decls[name] = true
		}
	}
	mut out := strings.new_builder(src.len)
	mut i := 0
	for i < lines.len {
		line := lines[i]
		trimmed := line.trim_space()
		if trimmed.starts_with('struct ') {
			name := trimmed.all_after('struct ').all_before('{').trim_space()
			mut empty_end := -1
			if trimmed.ends_with('{}') {
				empty_end = i
			} else if trimmed.ends_with('{') {
				mut j := i + 1
				mut only_empty_body := true
				for j < lines.len {
					body_line := lines[j].trim_space()
					if body_line == '}' {
						empty_end = j
						break
					}
					if body_line != '' && !body_line.starts_with('//') {
						only_empty_body = false
						break
					}
					j++
				}
				if !only_empty_body {
					empty_end = -1
				}
			}
			if empty_end >= i && (name in real_decls) {
				i = empty_end + 1
				if i < lines.len {
					out.write_u8(`\n`)
				}
				continue
			}
		}
		out.write_string(line)
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
		i++
	}
	return out.str()
}

fn collect_enum_v_type_names(src string) map[string]bool {
	mut names := map[string]bool{}
	for raw_line in src.split_into_lines() {
		trimmed := raw_line.trim_space()
		if trimmed.starts_with('enum ') {
			name := trimmed.all_after('enum ').all_before('{').trim_space()
			if name != '' {
				names[name] = true
			}
		}
	}
	return names
}

fn sanitize_skeleton_enum_default_returns(src string) string {
	enum_names := collect_enum_v_type_names(src)
	mut out := strings.new_builder(src.len)
	lines := src.split_into_lines()
	for i, line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('return ') && trimmed.ends_with('{}') {
			type_name := trimmed.all_after('return ').all_before('{').trim_space()
			if type_name in enum_names {
				out.write_string(leading_whitespace(line) + 'return ' + type_name + '(0)')
				if i < lines.len - 1 {
					out.write_u8(`\n`)
				}
				continue
			}
		}
		out.write_string(line)
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
	}
	return out.str()
}

fn is_top_level_fn_prototype_line(trimmed string) bool {
	if !(trimmed.starts_with('fn ') || trimmed.starts_with('fn C.')) {
		return false
	}
	return !trimmed.contains('{')
}

fn top_level_fn_decl_name(trimmed string) string {
	if !trimmed.starts_with('fn ') || trimmed.starts_with('fn (') {
		return ''
	}
	mut rest := trimmed['fn '.len..].trim_space()
	if rest == '' {
		return ''
	}
	if rest.starts_with('C.') {
		rest = rest[2..]
	}
	name := rest.all_before('(').trim_space()
	if name == '' || name.contains(' ') {
		return ''
	}
	return name
}

fn remove_duplicate_top_level_fn_prototypes(src string) string {
	mut seen := map[string]bool{}
	mut pending_attrs := []string{}
	mut out := strings.new_builder(src.len)
	lines := src.split_into_lines()
	for i, line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('@[') {
			pending_attrs << line
			if i == lines.len - 1 {
				for attr in pending_attrs {
					out.writeln(attr)
				}
			}
			continue
		}
		if is_top_level_fn_prototype_line(trimmed) {
			key := trimmed
			if key in seen {
				pending_attrs = []
				if i < lines.len - 1 {
					out.write_u8(`\n`)
				}
				continue
			}
			seen[key] = true
		}
		for attr in pending_attrs {
			out.writeln(attr)
		}
		pending_attrs = []
		out.write_string(line)
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
	}
	return out.str()
}

fn remove_duplicate_top_level_fns_by_name(src string) string {
	mut seen := map[string]bool{}
	mut pending_attrs := []string{}
	mut out := strings.new_builder(src.len)
	mut skip_depth := 0
	lines := src.split_into_lines()
	for i, line in lines {
		if skip_depth > 0 {
			skip_depth += line.count('{')
			skip_depth -= line.count('}')
			if skip_depth <= 0 && i < lines.len - 1 {
				out.write_u8(`\n`)
			}
			continue
		}
		trimmed := line.trim_space()
		if trimmed.starts_with('@[') {
			pending_attrs << line
			if i == lines.len - 1 {
				for attr in pending_attrs {
					out.writeln(attr)
				}
			}
			continue
		}
		fn_name := top_level_fn_decl_name(trimmed)
		if fn_name != '' {
			if fn_name in seen {
				pending_attrs = []
				depth := line.count('{') - line.count('}')
				if depth > 0 {
					skip_depth = depth
				}
				if i < lines.len - 1 && skip_depth == 0 {
					out.write_u8(`\n`)
				}
				continue
			}
			seen[fn_name] = true
		}
		for attr in pending_attrs {
			out.writeln(attr)
		}
		pending_attrs = []
		out.write_string(line)
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
	}
	return out.str()
}

fn rewrite_skeleton_interface_default_returns(src string, interface_names map[string]bool) string {
	if interface_names.len == 0 {
		return src
	}
	mut out := strings.new_builder(src.len)
	lines := src.split_into_lines()
	for i, line in lines {
		trimmed := line.trim_space()
		if trimmed.starts_with('return ') && trimmed.ends_with('{}') {
			type_name := trimmed.all_after('return ').all_before('{').trim_space()
			if type_name in interface_names {
				out.write_string(leading_whitespace(line) + 'return unsafe { ' + type_name + '(voidptr(0)) }')
			} else {
				out.write_string(line)
			}
		} else {
			out.write_string(line)
		}
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
	}
	return out.str()
}

fn rewrite_unknown_file_suffixed_type_refs(src string, declared_types map[string]bool, file_suffix string) string {
	if file_suffix == '' {
		return src
	}
	marker := '_' + file_suffix
	mut replacements := map[string]string{}
	mut token_start := -1
	for i := 0; i <= src.len; i++ {
		is_ident := i < src.len && is_identifier_char(src[i])
		if is_ident && token_start < 0 {
			token_start = i
		} else if !is_ident && token_start >= 0 {
			token := src[token_start..i]
			if token.ends_with(marker) && token !in declared_types {
				base := token[..token.len - marker.len]
				if base in declared_types {
					replacements[token] = base
				}
			}
			token_start = -1
		}
	}
	if replacements.len == 0 {
		return src
	}
	mut rewritten_lines := []string{}
	for line in src.split('\n') {
		mut rewritten := line
		for from, to in replacements {
			rewritten = replace_bare_identifier(rewritten, from, to)
		}
		rewritten_lines << rewritten
	}
	return rewritten_lines.join('\n')
}

const c2v_external_decls_file_name = '0_external.c.v'

fn is_c2v_globals_file(path string) bool {
	return os.file_name(path) in ['0_globals.v', '_globals.v', c2v_external_decls_file_name]
}

fn (c2v &C2V) sanitize_single_module_outputs() {
	if !c2v.is_dir || !c2v.project_single_module || c2v.project_output_root == ''
		|| !os.exists(c2v.project_output_root) {
		return
	}
	mut files := os.walk_ext(c2v.project_output_root, '.v')
	files.sort()
	// First remove declarations that only made an individual skeleton file
	// self-contained.  Building the project-wide type map before this pass makes
	// stale dependency and recovered forward declarations look real, which in
	// turn prevents file-qualified references from being folded onto the one
	// concrete declaration in the flattened module.
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		src := os.read_file(file) or { continue }
		mut sanitized := src
		if c2v.skeleton_mode {
			sanitized = remove_duplicate_external_empty_struct_stubs(sanitized)
		}
		if sanitized != src {
			os.write_file(file, sanitized) or {}
		}
	}
	// Included C++ headers can produce an opaque `struct Name {}` in one
	// translation unit and the real struct or interface in another. Flattened V
	// modules cannot register both. Keep a single opaque declaration only when
	// the project has no concrete declaration for that name.
	mut real_decls := map[string]bool{}
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		src := os.read_file(file) or { continue }
		for name, _ in collect_nonempty_v_type_names(src) {
			real_decls[name] = true
		}
	}
	mut seen_empty := map[string]bool{}
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		src := os.read_file(file) or { continue }
		sanitized := remove_project_duplicate_empty_struct_stubs(src, real_decls, mut seen_empty)
		if sanitized != src {
			os.write_file(file, sanitized) or {}
		}
	}
	mut interface_names := map[string]bool{}
	mut declared_types := map[string]bool{}
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		for line in os.read_lines(file) or { continue } {
			trimmed := line.trim_space()
			name := extract_declared_type_name(trimmed)
			if name != '' {
				declared_types[name] = true
			}
			if trimmed.starts_with('interface ') && name != '' {
				interface_names[name] = true
			}
		}
	}
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		src := os.read_file(file) or { continue }
		mut sanitized := src
		if c2v.skeleton_mode {
			sanitized = rewrite_skeleton_interface_default_returns(sanitized, interface_names)
		}
		mut file_suffix := os.file_name(file)
		if file_suffix.ends_with('.v') {
			file_suffix = file_suffix[..file_suffix.len - 2]
		}
		if file_suffix.contains('__') {
			file_suffix = file_suffix.all_after_last('__')
		}
		sanitized = rewrite_unknown_file_suffixed_type_refs(sanitized, declared_types, file_suffix)
		if sanitized != src {
			os.write_file(file, sanitized) or {}
		}
	}
}

fn sanitize_translated_output(src string, skeleton_mode bool, translated_mut_method_names []string) string {
	mut s := src
	mutable_method_names := translated_mut_method_names.clone()
	// Recovery-AST fallback: malformed inferred empty array literals occasionally appear as `[]!`.
	// Replace them with scalar zero placeholders to keep generated V parsable.
	s = s.replace(':= []!', ':= 0')
	s = s.replace(' = []!', ' = 0')
	s = s.replace('= []!', '= 0')
	// Invalid V return type spelling from translated C signatures.
	s = s.replace(') void {', ') {')
	s = s.replace(') void\n', ')\n')
	// Postfix increments/decrements with the C2V marker suffix.
	s = replace_unary_marker_suffixes(s)
	// Fixed-array conversion (`]!`) creates Result values in places where V cannot store them.
	s = replace_fixed_array_result_suffixes(s)

	mut out := strings.new_builder(s.len)
	mut sanitized_lhs_assign_id := 0
	mut sanitized_condition_id := 0
	source_lines := s.split_into_lines()
	mut source_line_idx := 0
	for source_line_idx < source_lines.len {
		mut raw_line := source_lines[source_line_idx]
		source_line_idx++
		if raw_line.contains('__c2v_ref_arg_') {
			// Record literals span several lines. Materialize a temporary reference
			// argument together with the lines that close its parentheses.
			joined, consumed := join_parenthesized_continuation(source_lines, source_line_idx - 1)
			raw_line = joined
			source_line_idx += consumed
		}
		mut line := raw_line
		line = replace_type_empty_ctor_field_access(line)
		line = collapse_nested_parenthesized_unsafe_addr(line)
		line = collapse_nested_unsafe_rhs_deref(line)
		line = collapse_nested_unsafe_blocks(line)
		reference_arg_declarations, materialized_reference_line :=
			materialize_cpp_reference_args(line)
		if reference_arg_declarations.len > 0 {
			indent := leading_whitespace(line)
			for declaration in reference_arg_declarations {
				out.writeln(indent + declaration)
			}
			line = materialized_reference_line
		}
		if line.contains(':= // skipped: unresolved call') {
			line = line.replace(':= // skipped: unresolved call', ':= 0 // skipped: unresolved call')
		}
		if line.contains('= // skipped: unresolved call') {
			line = line.replace('= // skipped: unresolved call', '= 0 // skipped: unresolved call')
		}
		trimmed := line.trim_space()
		condition_terms, condition_operators, has_split_condition := split_long_if_condition(line)
		if has_split_condition {
			indent := leading_whitespace(line)
			mut condition_names := []string{}
			for term in condition_terms {
				name := '__c2v_condition_${sanitized_condition_id}'
				sanitized_condition_id++
				condition_names << name
				mut rewritten_term := term
				for {
					receiver_expr, call_tail, found :=
						split_mut_receiver_call_expr(rewritten_term, mutable_method_names)
					if !found {
						break
					}
					tmp_name := '__c2v_mut_recv_${sanitized_lhs_assign_id}'
					normalized_receiver := strip_balanced_outer_parentheses(receiver_expr)
					base_receiver, receiver_tail, has_base_receiver :=
						split_nonassignable_lhs_receiver(normalized_receiver)
					materialize_full_receiver := has_base_receiver
						&& v_receiver_tail_contains_method_call(receiver_tail)
					materialized_receiver := if has_base_receiver && !materialize_full_receiver {
						base_receiver
					} else {
						normalized_receiver
					}
					replacement_receiver := tmp_name + if has_base_receiver
						&& !materialize_full_receiver {
						receiver_tail
					} else {
						''
					}
					out.writeln(indent + 'mut ' + tmp_name + ' := ' + materialized_receiver)
					rewritten_term = rewritten_term.replace(receiver_expr + call_tail, replacement_receiver + call_tail)
					sanitized_lhs_assign_id++
				}
				out.writeln(indent + name + ' := ' + rewritten_term)
			}
			mut rebuilt_condition := condition_names[0]
			for i, op in condition_operators {
				rebuilt_condition += ' ' + op + ' ' + condition_names[i + 1]
			}
			out.writeln(indent + 'if ' + rebuilt_condition + ' {')
			continue
		}
		ret_lhs, ret_rhs, has_ret_assign := split_simple_return_assignment(line)
		if has_ret_assign {
			indent := leading_whitespace(line)
			out.writeln(indent + ret_lhs + ' = ' + ret_rhs)
			out.writeln(indent + 'return ' + ret_lhs)
			continue
		}
		assignment_line, assignment_was_unsafe := unwrap_inline_unsafe_statement(line)
		assignment_trimmed := assignment_line.trim_space()
		if !assignment_trimmed.starts_with('//')
			&& (assignment_trimmed.ends_with('++') || assignment_trimmed.ends_with('--')) {
			op := assignment_trimmed[assignment_trimmed.len - 2..]
			lhs_expr := assignment_trimmed[..assignment_trimmed.len - 2].trim_space()
			if should_sanitize_nonassignable_lhs(lhs_expr) {
				indent := leading_whitespace(line)
				tmp_name := '__c2v_lhs_tmp_${sanitized_lhs_assign_id}'
				receiver, tail, has_receiver := split_nonassignable_lhs_receiver(lhs_expr)
				if has_receiver {
					final_call_lvalue := v_receiver_tail_ends_in_method_call(tail)
					initializer := if final_call_lvalue {
						lhs_expr
					} else {
						receiver
					}
					out.writeln(indent + 'mut ' + tmp_name + ' := ' + sanitized_lhs_initializer(initializer, assignment_was_unsafe))
					if tail == '' || final_call_lvalue {
						out.writeln(indent + 'unsafe { *' + tmp_name + op + ' }')
					} else {
						out.writeln(indent + tmp_name + tail + op)
					}
				} else {
					out.writeln(indent + 'mut ' + tmp_name + ' := ' + lhs_expr)
					out.writeln(indent + tmp_name + op)
				}
				sanitized_lhs_assign_id++
				continue
			}
		}
		compound_assign_idx, compound_assign_op :=
			find_compound_assignment_operator(assignment_line)
		if compound_assign_idx >= 0 && !assignment_trimmed.starts_with('for ')
			&& !assignment_trimmed.starts_with('//') {
			lhs_expr := assignment_line[..compound_assign_idx].trim_space()
			if should_sanitize_nonassignable_lhs(lhs_expr) {
				rhs_expr :=
					assignment_line[compound_assign_idx + compound_assign_op.len..].trim_space()
				indent := leading_whitespace(line)
				tmp_name := '__c2v_lhs_tmp_${sanitized_lhs_assign_id}'
				receiver, tail, has_receiver := split_nonassignable_lhs_receiver(lhs_expr)
				if has_receiver {
					final_call_lvalue := v_receiver_tail_ends_in_method_call(tail)
					initializer := if final_call_lvalue {
						lhs_expr
					} else {
						receiver
					}
					out.writeln(indent + 'mut ' + tmp_name + ' := ' + sanitized_lhs_initializer(initializer, assignment_was_unsafe))
					access := tmp_name + if final_call_lvalue { '' } else { tail }
					if tail == '' || final_call_lvalue {
						out.writeln(collapse_nested_unsafe_blocks(collapse_nested_unsafe_deref_blocks(indent + 'unsafe { *' + access + ' ' + compound_assign_op + ' ' + (if rhs_expr == '' {
							'0'
						} else {
							rhs_expr
						}) + ' }')))
					} else {
						out.writeln(indent + access + ' ' + compound_assign_op + ' ' + (if rhs_expr == '' {
							'0'
						} else {
							rhs_expr
						}))
					}
				} else {
					out.writeln(indent + 'mut ' + tmp_name + ' := ' + lhs_expr)
					out.writeln(indent + tmp_name + ' ' + compound_assign_op + ' ' + (if rhs_expr == '' {
						'0'
					} else {
						rhs_expr
					}))
				}
				sanitized_lhs_assign_id++
				continue
			}
		}
		assign_idx := find_simple_assignment_operator_index(assignment_line)
		if assign_idx >= 0 && !assignment_trimmed.starts_with('//')
			&& !assignment_trimmed.starts_with('for ') {
			lhs_expr := assignment_line[..assign_idx].trim_space()
			if should_sanitize_nonassignable_lhs(lhs_expr) {
				rhs_expr := assignment_line[assign_idx + 1..].trim_space()
				indent := leading_whitespace(line)
				tmp_name := '__c2v_lhs_tmp_${sanitized_lhs_assign_id}'
				receiver, tail, has_receiver := split_nonassignable_lhs_receiver(lhs_expr)
				if has_receiver {
					final_call_lvalue := v_receiver_tail_ends_in_method_call(tail)
					initializer := if final_call_lvalue {
						lhs_expr
					} else {
						receiver
					}
					out.writeln(indent + 'mut ' + tmp_name + ' := ' + sanitized_lhs_initializer(initializer, assignment_was_unsafe))
					access := tmp_name + if final_call_lvalue { '' } else { tail }
					if tail == '' || final_call_lvalue {
						out.writeln(collapse_nested_unsafe_blocks(collapse_nested_unsafe_deref_blocks(indent + 'unsafe { *' + access + ' = ' + (if rhs_expr == '' {
							'0'
						} else {
							rhs_expr
						}) + ' }')))
					} else {
						out.writeln(indent + access + ' = ' + (if rhs_expr == '' {
							'0'
						} else {
							rhs_expr
						}))
					}
				} else {
					out.writeln(indent + 'mut ' + tmp_name + ' := ' + lhs_expr)
					out.writeln(indent + tmp_name + ' = ' + (if rhs_expr == '' {
						'0'
					} else {
						rhs_expr
					}))
				}
				sanitized_lhs_assign_id++
				continue
			}
		}
		mut mutable_call_line := trimmed
		mut materialized_mut_receiver := false
		for {
			receiver_expr, call_tail, has_mut_receiver_call :=
				split_mut_receiver_call_expr(mutable_call_line, mutable_method_names)
			if !has_mut_receiver_call {
				break
			}
			indent := leading_whitespace(line)
			tmp_name := '__c2v_mut_recv_${sanitized_lhs_assign_id}'
			normalized_receiver := strip_balanced_outer_parentheses(receiver_expr)
			base_receiver, receiver_tail, has_base_receiver :=
				split_nonassignable_lhs_receiver(normalized_receiver)
			materialize_full_receiver := has_base_receiver
				&& v_receiver_tail_contains_method_call(receiver_tail)
			materialized_receiver := if has_base_receiver && !materialize_full_receiver {
				base_receiver
			} else {
				normalized_receiver
			}
			replacement_receiver := tmp_name + if has_base_receiver && !materialize_full_receiver {
				receiver_tail
			} else {
				''
			}
			out.writeln(indent + 'mut ' + tmp_name + ' := ' + materialized_receiver)
			mutable_call_line = mutable_call_line.replace(receiver_expr + call_tail, replacement_receiver + call_tail)
			sanitized_lhs_assign_id++
			materialized_mut_receiver = true
		}
		if materialized_mut_receiver {
			out.writeln(leading_whitespace(line) + mutable_call_line)
			continue
		}
		if_receiver_expr, if_call_tail, has_mut_receiver_if_call := split_mut_receiver_if_call_expr(trimmed, mutable_method_names)
		if has_mut_receiver_if_call {
			indent := leading_whitespace(line)
			tmp_name := '__c2v_mut_recv_${sanitized_lhs_assign_id}'
			normalized_receiver := strip_balanced_outer_parentheses(if_receiver_expr)
			base_receiver, receiver_tail, has_base_receiver :=
				split_nonassignable_lhs_receiver(normalized_receiver)
			materialize_full_receiver := has_base_receiver
				&& v_receiver_tail_contains_method_call(receiver_tail)
			materialized_receiver := if has_base_receiver && !materialize_full_receiver {
				base_receiver
			} else {
				normalized_receiver
			}
			replacement_receiver := tmp_name + if has_base_receiver && !materialize_full_receiver {
				receiver_tail
			} else {
				''
			}
			out.writeln(indent + 'mut ' + tmp_name + ' := ' + materialized_receiver)
			out.writeln(indent + trimmed.replace(if_receiver_expr + if_call_tail, replacement_receiver + if_call_tail))
			sanitized_lhs_assign_id++
			continue
		}
		if trimmed.starts_with('__asm__') {
			out.writeln('// ' + trimmed)
			continue
		}
		if trimmed.starts_with('if  ') {
			out.writeln(leading_whitespace(line) + 'if false {')
			continue
		}
		if trimmed.starts_with('} else if  ') {
			out.writeln(leading_whitespace(line) + '} else if false {')
			continue
		}
		if trimmed.ends_with(':=') {
			out.writeln(line.trim_right(' \t') + ' 0')
			continue
		}
		if trimmed.ends_with('=') && !trimmed.ends_with('==') && !trimmed.ends_with('!=')
			&& !trimmed.ends_with('<=') && !trimmed.ends_with('>=') {
			out.writeln(line.trim_right(' \t') + ' 0')
			continue
		}
		if trimmed.contains(':=') && (trimmed.ends_with('+') || trimmed.ends_with('-')
			|| trimmed.ends_with('*') || trimmed.ends_with('/')
			|| trimmed.ends_with('%') || trimmed.ends_with('&')
			|| trimmed.ends_with('|')) {
			out.writeln(line.trim_right(' \t+-*/%&|'))
			continue
		}
		if trimmed.starts_with('= ') {
			out.writeln('// ' + trimmed)
			continue
		}
		out.writeln(break_long_logical_condition(line))
	}
	mut sanitized := out.str()
	if skeleton_mode {
		sanitized = remove_duplicate_external_empty_struct_stubs(sanitized)
		sanitized = sanitize_skeleton_enum_default_returns(sanitized)
		sanitized = remove_duplicate_top_level_fn_prototypes(sanitized)
		sanitized = remove_duplicate_top_level_fns_by_name(sanitized)
	}
	return sanitized
}

fn sanitize_skeleton_output(src string) string {
	return sanitize_translated_output(src, true, []string{})
}

// recursive
fn set_kind_enum(mut n Node) {
	n.kind = convert_str_into_node_kind(n.kind_str)
	if n.ref_declaration.kind_str != '' {
		n.ref_declaration.kind = convert_str_into_node_kind(n.ref_declaration.kind_str)
	}
	if n.any_init.kind_str != '' {
		n.any_init.kind = convert_str_into_node_kind(n.any_init.kind_str)
	}
	if n.template_argument_decl.kind_str != '' {
		n.template_argument_decl.kind = convert_str_into_node_kind(n.template_argument_decl.kind_str)
	}
	for mut child in n.inner {
		// unsafe {
		// child.parent_node = n
		// }
		set_kind_enum(mut child)
	}
	for mut child in n.array_filler {
		set_kind_enum(mut child)
	}
}

fn new_c2v(args []string) &C2V {
	mut c2v := &C2V{
		is_wrapper: args.len > 1 && args[1] == 'wrapper'
		single_fn_def: args.len > 1 && args[1] == 'fndef'
		invocation_cwd: os.getwd()
	}
	if c2v.single_fn_def {
		if args.len <= 2 {
			eprintln('usage: c2v fndef [fn_name] ')
			exit(1)
		}
		c2v.fn_def_name = args[2]
		println('new_c2v: translating one function ${c2v.fn_def_name}')
		c2v.is_wrapper = true
	}
	c2v.handle_configuration(args)
	return c2v
}

fn (mut c2v C2V) add_file(ast_path string, outv string, c_file string) ! {
	vprintln('new tree(outv=${outv} c_file=${c_file})')

	ast_txt := os.read_file(ast_path) or {
		vprintln('failed to read ast file "${ast_path}": ${err}')
		return err
	}
	mut all_nodes := json2.decode[Node](ast_txt) or {
		vprintln('failed to decode ast file "${ast_path}": ${err}')
		return err
	}
	// Drop the large clang AST JSON as soon as it is decoded to reduce peak
	// disk usage during big directory translations.
	if !c2v.keep_ast {
		os.rm(ast_path) or {}
	}
	c2v.cnt = 0
	c2v.set_unique_id(mut all_nodes)

	// do not reset the cnt, because we will add comment nodes soon
	// c2v.cnt = 0

	c2v.tree.inner.clear()
	c2v.seen_comments.clear()
	c2v.source_text = os.read_file(c_file) or { '' }
	mut main_file_for_grouping := os.real_path(c_file)
	if main_file_for_grouping == '' {
		main_file_for_grouping = c_file
	}
	mut header_node := Node{}
	mut curr_file := ''
	mut keep_file := false
	for mut node in all_nodes.inner {
		mut node_file := if c2v.is_cpp { resolve_node_file_path(node) } else { node.location.file }
		if c2v.is_cpp && node_file == '' && (is_cpp_body_decl_node_by_kind_str(node)
			|| is_cpp_body_container_node_by_kind_str(node)) {
			node_file = main_file_for_grouping
			node.location.file = node_file
		}
		if node_file != '' {
			if is_synthetic_source_path(node_file) {
				curr_file = node_file
			} else {
				curr_file = os.real_path(node_file)
				if curr_file == '' {
					curr_file = node_file
				}
			}
			vprintln('==> node_id = ${node.id} curr_file=${curr_file}')
			keep_file = !line_is_builtin_header(curr_file)
		}
		if node_file != '' && keep_file {
			if header_node.inner.len > 0 && header_node.location.file != '' {
				vprintln('=====>processing header file ${header_node.location.file} node number=${header_node.inner.len}')
				c2v.parse_comment(mut header_node, header_node.location.file)
				c2v.tree.inner << header_node.inner
			}
			header_node = Node{
				location: NodeLocation{
					file: curr_file
					// source_file : SourceFile {
					//	path : c_file
					// }
				}
				range: Range{
					end: End{
						offset: if source_path_exists(curr_file) {
							int(os.file_size(curr_file)) + 10
						} else {
							node.range.end.offset + 10
						}
					}
				}
			}
			header_node.inner << node
			vprintln('processing header file ${curr_file}')
		} else if node_file == '' && keep_file {
			header_node.inner << node
		}
	}

	if header_node.inner.len > 0 {
		c2v.parse_comment(mut header_node, header_node.location.file)
		c2v.tree.inner << header_node.inner
	}

	c2v.cnt = 0
	mut main_c_file := os.real_path(c_file)
	if main_c_file == '' {
		main_c_file = c_file
	}
	c2v.files.clear()
	c2v.files << main_c_file
	c2v.cur_file = main_c_file
	if c2v.is_cpp {
		c2v.collect_system_surface(&all_nodes)
		c2v.prune_nested_system_decls(mut c2v.tree.inner)
	}
	c2v.set_file_index(mut c2v.tree)
	c2v.namespace_var_ids = map[string]bool{}
	collect_namespace_var_ids(c2v.tree.inner, mut c2v.namespace_var_ids)
	c2v.used_fn.clear()
	c2v.cur_file = main_c_file
	c2v.get_used_fn(c2v.tree)
	if c2v.is_dir && c2v.is_cpp && c2v.project_require_no_stubs {
		c2v.collect_cpp_class_hierarchy_from_node(&all_nodes)
		c2v.collect_cpp_abstract_types_from_node(&all_nodes)
	}
	if c2v.is_cpp && (!c2v.is_dir || c2v.project_require_no_stubs) {
		c2v.collect_used_external_c_function_decls(&all_nodes)
	}
	// println(c2v.used_fn)
	c2v.used_global.clear()
	c2v.get_used_global(c2v.tree)
	if c2v.is_dir && c2v.is_cpp && c2v.project_require_no_stubs {
		c2v.collect_used_external_c_global_decls(&all_nodes)
	}
	c2v.file_declared_aliases.clear()
	c2v.file_type_alias_names.clear()
	c2v.local_type_declarations.clear()
	c2v.cpp_static_member_decl_names.clear()
	c2v.cpp_function_decl_names.clear()
	c2v.cpp_method_decl_names.clear()
	c2v.cpp_nonconst_method_decls.clear()
	c2v.cpp_primitive_reference_decls.clear()
	c2v.cpp_value_reference_params.clear()
	c2v.cpp_nrvo_vars.clear()
	c2v.file_static_global_decl_v_names.clear()
	if !c2v.is_dir {
		c2v.declared_methods.clear()
		c2v.cpp_function_signature_v_names.clear()
		c2v.cpp_method_signature_v_names.clear()
		c2v.cpp_mut_method_names.clear()
	}
	if !c2v.is_dir {
		c2v.class_method_bases.clear()
		c2v.cpp_class_bases.clear()
		c2v.cpp_method_body_bases.clear()
	}
	if !c2v.is_dir {
		c2v.emitted_cpp_members.clear()
		c2v.emitted_top_level_fns.clear()
		c2v.emitted_top_level_name_counts.clear()
	}

	c2v.outv = outv
	c2v.cur_file = main_c_file

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
	if !c2v.single_fn_def {
		c2v.genln('@[translated]')
		// Predeclared identifiers
		if !c2v.is_wrapper {
			c2v.genln('module main\n')
		} else if c2v.is_wrapper {
			c2v.genln('module ${c2v.wrapper_module_name}\n')
		}
	}

	// Convert Clang JSON AST nodes to C2V's nodes with extra info.
	set_kind_enum(mut c2v.tree)
}

fn (mut c2v C2V) release_translation_ast() {
	// `seen_ids` contains pointers into `tree`, so release it first. A directory
	// translation only needs the compact project symbol maps after `save()`.
	c2v.seen_ids = {}
	c2v.callback_seen_ids = {}
	c2v.tree = Node{}
	gc_collect()
}

fn unwrap_function_pointer_callee(node Node) (Node, bool) {
	mut current := node
	mut changed := false
	for current.inner.len > 0 {
		if current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr) {
			current = current.inner[0]
			changed = true
			continue
		}
		if current.kindof(.unary_operator) && current.opcode == '*' {
			current = current.inner[0]
			changed = true
			continue
		}
		break
	}
	return current, changed
}

// Compiler builtins reached through system macros have fixed C semantics.
fn (mut c C2V) gen_compiler_builtin_call(callee Node, call Node) bool {
	decl_ref := cpp_function_decl_ref_source(&callee) or { return false }
	name := if decl_ref.ref_declaration.name != '' {
		decl_ref.ref_declaration.name
	} else {
		decl_ref.name
	}
	args := if call.inner.len > 1 { call.inner[1..] } else { []Node{} }
	match name {
		'__builtin_constant_p' {
			// "Is this known at compile time?" -- 0 is always a correct answer.
			c.gen('0')
			return true
		}
		'__builtin_bzero' {
			if args.len != 2 {
				return false
			}
			c.gen('C.memset(')
			c.expr(args[0])
			c.gen(', 0, ')
			c.expr(args[1])
			c.gen(')')
			return true
		}
		else {
			return false
		}
	}
}

fn (mut c C2V) fn_call(mut node Node) {
	mut expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	if c.is_cpp && expr.kindof(.member_expr) && expr.name.contains('operator') {
		mut raw_method := expr.name.replace('->', '.').trim_space()
		if raw_method.starts_with('.') {
			raw_method = raw_method[1..]
		}
		op_token := raw_method.replace('operator', '').trim_space()
		receiver := expr.try_get_next_child() or { bad_node }
		if is_cpp_operator_literal_operand(receiver) {
			mut args := []Node{}
			for i, arg in node.inner {
				if i == 0 {
					continue
				}
				args << arg
			}
			if op_token == '[]' && args.len == 1 {
				c.expr(receiver)
				c.gen('[')
				c.expr(args[0])
				c.gen(']')
				return
			}
			if args.len == 1
				&& op_token in ['=', '+=', '-=', '*=', '/=', '%=', '==', '!=', '<', '>', '<=', '>=',
					'+', '-', '*', '/', '%', '&', '|', '^', '&&', '||', '<<', '>>', '<<=', '>>=',
					','] {
				c.expr(receiver)
				c.gen(' ${op_token} ')
				c.expr(args[0])
				return
			}
			if args.len == 0 && op_token in ['-', '+', '!', '~', '*', '&'] {
				c.gen(op_token)
				c.expr(receiver)
				return
			}
		}
	}
	// vprintln('FN CALL')
	if c.gen_compiler_builtin_call(expr, node) {
		return
	}
	callee_start := c.cur_out_line.len
	mut emitted_recovery_callee := false
	// Recover calls whose callee could not be resolved semantically.
	if expr.kindof(.recovery_expr) {
		c.recovery_expr(expr)
		emitted_recovery_callee = true
	}
	// V calls function pointers directly. Clang can wrap a callback member in
	// several layers, e.g. `ImplicitCast(Paren(*ImplicitCast(Paren(member))))`.
	// Normalize the complete callee instead of leaving an invalid `()member`.
	unwrapped, callee_was_wrapped := unwrap_function_pointer_callee(expr)
	mut emitted_callee := false
	if callee_was_wrapped && (unwrapped.kindof(.decl_ref_expr) || unwrapped.kindof(.member_expr)
		|| unwrapped.kindof(.array_subscript_expr)) {
		c.expr(unwrapped)
		emitted_callee = true
	}
	if !emitted_callee && !emitted_recovery_callee {
		c.expr(expr) // this is `fn_name(`
	}
	// vprintln(expr.str())
	// Clean up macos builtin fn names
	// $if macos
	is_memcpy := c.cur_out_line.contains('__builtin___memcpy_chk')
		|| c.cur_out_line.contains('builtin___memcpy_chk')
	is_memmove := c.cur_out_line.contains('__builtin___memmove_chk')
		|| c.cur_out_line.contains('builtin___memmove_chk')
	is_memset := c.cur_out_line.contains('__builtin___memset_chk')
		|| c.cur_out_line.contains('builtin___memset_chk')
	if is_memcpy {
		c.cur_out_line = c.cur_out_line.replace('__builtin___memcpy_chk', 'C.memcpy')
		c.cur_out_line = c.cur_out_line.replace('c_builtin___memcpy_chk', 'C.memcpy')
		c.cur_out_line = c.cur_out_line.replace('builtin___memcpy_chk', 'C.memcpy')
	}
	if is_memmove {
		c.cur_out_line = c.cur_out_line.replace('__builtin___memmove_chk', 'C.memmove')
		c.cur_out_line = c.cur_out_line.replace('c_builtin___memmove_chk', 'C.memmove')
		c.cur_out_line = c.cur_out_line.replace('builtin___memmove_chk', 'C.memmove')
	}
	if is_memset {
		c.cur_out_line = c.cur_out_line.replace('__builtin___memset_chk', 'C.memset')
		c.cur_out_line = c.cur_out_line.replace('c_builtin___memset_chk', 'C.memset')
		c.cur_out_line = c.cur_out_line.replace('builtin___memset_chk', 'C.memset')
	}
	if c.cur_out_line.contains('builtin_memcpy') {
		c.cur_out_line = c.cur_out_line.replace('builtin_memcpy', 'C.memcpy')
	}
	if c.cur_out_line.contains('__builtin_alloca') {
		c.cur_out_line = c.cur_out_line.replace('__builtin_alloca', 'builtin_alloca')
	}
	if c.cur_out_line.contains('__builtin_va_start') {
		c.cur_out_line = c.cur_out_line.replace('__builtin_va_start', 'builtin_va_start')
	}
	if c.cur_out_line.contains('__builtin_va_end') {
		c.cur_out_line = c.cur_out_line.replace('__builtin_va_end', 'builtin_va_end')
	}
	emitted_builtin_name := c.cur_out_line[callee_start..].trim_space()
	if emitted_builtin_name in ['__builtin_bswap16', 'builtin_bswap16', 'c_builtin_bswap16',
		'_OSSwapInt16', 'os_swap_int16'] {
		c.cur_out_line = c.cur_out_line[..callee_start] + 'c2v_builtin_bswap16'
	} else if emitted_builtin_name in ['__builtin_bswap32', 'builtin_bswap32', 'c_builtin_bswap32',
		'_OSSwapInt32', 'os_swap_int32'] {
		c.cur_out_line = c.cur_out_line[..callee_start] + 'c2v_builtin_bswap32'
	}
	emitted_builtin_name_after_bswap := c.cur_out_line[callee_start..].trim_space()
	if emitted_builtin_name_after_bswap in ['__builtin_trap', 'builtin_trap', 'c_builtin_trap'] {
		c.cur_out_line = c.cur_out_line[..callee_start] + 'c2v_builtin_trap'
	}
	if c.cur_out_line.contains('memset') {
		vprintln('!! ${c.cur_out_line}')
		c.cur_out_line = c.cur_out_line.replace('memset(', 'C.memset(')
	}
	// Recovered C++ macro calls, notably assertion expansions, can
	// leave Clang with a CallExpr whose callee lowers to nothing. Without this
	// guard c2v emits a bare `()`, which is invalid V.
	if c.cur_out_line[callee_start..].trim_space() == '' {
		c.cur_out_line = c.cur_out_line[..callee_start]
		return
	}
	// Drop last argument if we have memcpy_chk
	is_m := is_memcpy || is_memmove || is_memset
	len := if is_m { 3 } else { node.inner.len - 1 }
	emitted_callee_text := c.cur_out_line[callee_start..].trim_space()
	if c.declared_local_vars.exists('c2v_variadic_args')
		&& emitted_callee_text in ['builtin_va_start', 'builtin_va_end'] {
		if node.inner.len > 1 {
			index_name := c.render_expr_to_string(node.inner[1])
			if index_name != '' && c.declared_local_var_types[index_name] == 'int' {
				c.cur_out_line = c.cur_out_line[..callee_start]
				if emitted_callee_text == 'builtin_va_start' {
					c.gen('${index_name} = 0')
				} else {
					// Preserve a valid no-op statement for va_end; the V variadic slice
					// owns no native traversal state that needs releasing.
					c.gen('${index_name} = ${index_name}')
				}
				return
			}
		}
	}
	if !c.is_dir && emitted_callee_text in ['builtin_va_start', 'builtin_va_end', 'builtin_va_copy'] {
		helper_key := 'cpp_native_variadic_helpers:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn builtin_va_start(arg0 &C.va_list, arg1 voidptr) {}\nfn builtin_va_end(arg0 &C.va_list) {}\nfn builtin_va_copy(arg0 &C.va_list, arg1 &C.va_list) {}\n\n'
		}
	}
	if c.is_cpp && c.project_require_no_stubs
		&& emitted_callee_text in ['C.vsnprintf', 'C.vsprintf', 'C.vfprintf', 'C.vprintf'] {
		// A `va_list` of translated code carries no C arguments; format the
		// translated variadic arguments instead.
		c.cur_out_line = c.cur_out_line[..callee_start] + 'c2v_' + emitted_callee_text[2..]
	}
	is_c_foreign_call := emitted_callee_text.starts_with('C.')
	callee_type := fn_call_callee_type(expr)
	callee_params := function_type_params(callee_type)
	is_variadic := callee_params.any(it == '...')
	cast_variadic_args_to_voidptr := c.is_cpp && !is_c_foreign_call
	fixed_param_count := callee_params.filter(it != '...').len
	c.gen('(')
	for i, arg in node.inner {
		if is_m && i > len {
			break
		}
		if i > 0 {
			is_variadic_arg := cast_variadic_args_to_voidptr && is_variadic && i > fixed_param_count
			param_type := if i - 1 < callee_params.len { callee_params[i - 1] } else { '' }
			is_va_list_arg := emitted_callee_text in ['builtin_va_start', 'builtin_va_end',
				'builtin_va_copy'] && (i == 1 || (emitted_callee_text == 'builtin_va_copy' && i == 2))
			if is_va_list_arg {
				va_list_source := c.unwrap_expr_for_deref_check(arg)
				rendered_va_list := c.render_expr_to_string(va_list_source)
				if rendered_va_list.starts_with('&') {
					c.gen(rendered_va_list)
				} else {
					c.gen('&${rendered_va_list}')
				}
			} else {
				c.gen_call_arg(arg, param_type, is_variadic_arg)
			}
			if i < len {
				// Check if there are more args ahead.
				mut has_more := false
				for j := i + 1; j < node.inner.len; j++ {
					_ = j
					has_more = true
					break
				}
				if has_more {
					c.gen(', ')
				}
			}
		}
	}
	if cast_variadic_args_to_voidptr && is_variadic && node.inner.len - 1 == fixed_param_count {
		// V's C backend currently emits an invalid raw second argument for an
		// empty V variadic call. A trailing null word is harmless to C/C++
		// printf-style APIs whose format has no conversions and keeps the
		// generated variadic slice well formed.
		if fixed_param_count > 0 {
			c.gen(', ')
		}
		c.gen('voidptr(0)')
	}
	c.gen(')')
}

fn fn_call_callee_type(expr Node) string {
	mut current := expr
	for current.kindof(.implicit_cast_expr) && current.cast_kind == 'FunctionToPointerDecay'
		&& current.inner.len > 0 {
		current = current.inner[0]
	}
	if current.ast_type.desugared_qualified != '' {
		return current.ast_type.desugared_qualified
	}
	return current.ast_type.qualified
}

fn (c &C2V) cpp_member_call_callee_type(member_expr Node) string {
	callee_type := fn_call_callee_type(member_expr)
	if callee_type != '' && callee_type != '<bound member function type>' {
		return callee_type
	}
	if member_expr.referenced_member_decl != '' {
		if declaration := c.callback_seen_ids[member_expr.referenced_member_decl] {
			return fn_call_callee_type(*declaration)
		}
	}
	return callee_type
}

fn cpp_operator_call_returns_reference(node Node) bool {
	if !node.kindof(.cxx_operator_call_expr) || node.inner.len == 0 {
		return false
	}
	// A call expression is an lvalue only when the overloaded operator returns
	// an lvalue reference. This is also the reliable signal for instantiated
	// template operators whose callee type is left as a bound-member placeholder.
	if node.value_category == 'lvalue' {
		return true
	}
	callee_type := fn_call_callee_type(node.inner[0])
	open_paren := callee_type.index_u8(`(`)
	if open_paren < 0 {
		return false
	}
	return callee_type[..open_paren].trim_space().ends_with('&')
}

fn (c &C2V) cpp_operator_call_returns_primitive_reference(node Node) bool {
	if !cpp_operator_call_returns_reference(node) || node.inner.len == 0 {
		return false
	}
	callee_type := fn_call_callee_type(node.inner[0])
	open_paren := callee_type.index_u8(`(`)
	if open_paren < 0 {
		return false
	}
	return_type := c.convert_type(callee_type[..open_paren].trim_space()).name.trim_space()
	return return_type.starts_with('&')
		&& normalize_v_ptr_type(return_type) in v_primitive_type_names
}

fn (c &C2V) cpp_primitive_reference_operator_source(node &Node) ?Node {
	mut current := *node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.constant_expr) || current.kindof(.expr_with_cleanups)
			|| current.kindof(.materialize_temporary_expr)
			|| current.kindof(.cxx_bind_temporary_expr)) {
		current = current.inner[0]
	}
	if c.cpp_operator_call_returns_primitive_reference(current) {
		return current
	}
	return none
}

fn function_type_params(fn_type string) []string {
	mut s := fn_type.trim_space()
	if s == '' {
		return []
	}
	if pointer_marker := s.index('(*)') {
		first_open := s.index_u8(`(`)
		if first_open == pointer_marker {
			// Strip only a top-level function-pointer declarator. A normal
			// function may itself accept a callback, for example
			// `T *(const char *, void (*)(T *))`; jumping to every embedded
			// `(*)` shifts its parameter list to the callback's arguments.
			s = s[pointer_marker + 3..]
		}
	}
	open := s.index_u8(`(`)
	if open < 0 {
		return []
	}
	mut depth := 0
	mut close := -1
	for i := open; i < s.len; i++ {
		if s[i] == `(` {
			depth++
		} else if s[i] == `)` {
			depth--
			if depth == 0 {
				close = i
				break
			}
		}
	}
	if close <= open {
		return []
	}
	params_section := s[open + 1..close].trim_space()
	if params_section == '' || params_section == 'void' {
		return []
	}
	mut params := []string{}
	mut start := 0
	depth = 0
	mut angle_depth := 0
	mut bracket_depth := 0
	for i := 0; i < params_section.len; i++ {
		if params_section[i] == `(` {
			depth++
		} else if params_section[i] == `)` {
			depth--
		} else if params_section[i] == `<` {
			angle_depth++
		} else if params_section[i] == `>` && angle_depth > 0 {
			angle_depth--
		} else if params_section[i] == `[` {
			bracket_depth++
		} else if params_section[i] == `]` && bracket_depth > 0 {
			bracket_depth--
		} else if params_section[i] == `,` && depth == 0 && angle_depth == 0
			&& bracket_depth == 0 {
			params << params_section[start..i].trim_space()
			start = i + 1
		}
	}
	params << params_section[start..].trim_space()
	return params.filter(it != '')
}

// function_pointer_cast_helper_name returns a helper that reinterprets a raw
// pointer as a function value of type `fn_type`, declaring it on first use.
fn (mut c C2V) function_pointer_cast_helper_name(fn_type string) string {
	// Preserve pointer layers in the identifier. Plain punctuation stripping
	// would collide `fn (T)` with `fn (&T)`.
	type_token := function_pointer_cast_type_token(fn_type)
	helper_name := 'c2v_function_pointer_cast_${type_token}'
	storage_name := 'C2vFunctionPointerCast_${type_token}'
	function_type_name := '${storage_name}Fn'
	helper_key := 'cpp_function_pointer_cast_helper:${os.dir(c.outv)}:${fn_type}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << 'type ${function_type_name} = ${fn_type}\n\nunion ${storage_name} {\nmut:\n\traw voidptr\n\tvalue ${function_type_name}\n}\n\nfn ${helper_name}(value voidptr) ${function_type_name} {\n\tmut storage := ${storage_name}{}\n\tunsafe { storage.raw = value }\n\treturn unsafe { storage.value }\n}\n\n'
	}
	return helper_name
}

// cpp_member_function_pointer_signature splits `R (C::*)(A...) const` into
// its C return type and parameter types.
fn cpp_member_function_pointer_signature(pointer_type string) (string, []string) {
	marker := pointer_type.index('::*)') or { return '', []string{} }
	open := pointer_type.index_u8(`(`)
	if open < 0 || open > marker {
		return '', []string{}
	}
	mut param_list := pointer_type[marker + 4..].trim_space()
	close := param_list.last_index(')') or { return '', []string{} }
	param_list = param_list[..close + 1]
	params := function_type_params('void ${param_list}').filter(it != 'void')
	return pointer_type[..open].trim_space(), params
}

// A C++ member function pointer `R (C::*)(A...)` is stored as the address of
// a function taking the object first, i.e. `fn (voidptr, A...) R`.
fn (mut c C2V) cpp_member_function_pointer_v_type(pointer_type string) string {
	return_type, params := cpp_member_function_pointer_signature(pointer_type)
	if return_type == '' {
		return ''
	}
	mut result := 'fn (voidptr'
	for param in params {
		result += ', ' + c.prefix_external_type(c.convert_type(param).name)
	}
	result += ')'
	if return_type != 'void' {
		result += ' ' + c.prefix_external_type(c.convert_type(return_type).name)
	}
	return result
}

fn cpp_member_pointer_owner(pointer_type string) string {
	marker := pointer_type.index('::*') or { return '' }
	prefix := pointer_type[..marker].trim_space()
	open := prefix.last_index('(') or { return '' }
	if open + 1 >= prefix.len {
		return ''
	}
	return normalize_cpp_name_fragment(prefix[open + 1..])
}

fn cpp_method_has_empty_body(node Node) bool {
	for child in node.inner {
		if child.kindof(.compound_stmt) {
			return child.inner.len == 0
		}
	}
	return false
}

fn (mut c C2V) collect_seen_ids_recursive(mut node Node) {
	if node.id != '' {
		c.callback_seen_ids[node.id] = unsafe { node }
	}
	for mut child in node.inner {
		c.collect_seen_ids_recursive(mut child)
	}
}

// V has no expression for an unbound method such as `Class::method`. Preserve
// the callable shape of C++ member pointers with a closure whose first argument
// is the original receiver. Existing casts can then store that closure as a
// voidptr, which is how translated callback tables represent member pointers.
fn (mut c C2V) gen_cpp_member_pointer_callback(pointer Node, target Node) bool {
	if !c.is_cpp || !pointer.ast_type.qualified.contains('::*')
		|| target.ref_declaration.kind != .cxx_method_decl {
		return false
	}
	mut owner := cpp_member_pointer_owner(pointer.ast_type.qualified)
	mut referenced_method := Node{}
	mut has_referenced_method := false
	if target.ref_declaration.id != '' {
		if declaration := c.callback_seen_ids[target.ref_declaration.id] {
			referenced_method = *declaration
			has_referenced_method = true
			actual_owner := extract_class_from_mangled(declaration.mangled_name)
			if actual_owner != '' {
				// A C-style cast can erase the declaring class from the pointer type
				// (`Derived::*` -> `Base::*`). The closure still needs the concrete
				// receiver that owns the referenced V method.
				owner = actual_owner
			}
		}
	}
	method_name := if target.ref_declaration.name != '' {
		target.ref_declaration.name
	} else {
		target.name
	}
	if owner == '' || method_name == '' {
		return false
	}
	receiver_type := c.add_struct_name(mut c.types, owner)
	if !is_valid_v_receiver_type_name(receiver_type) {
		return false
	}
	method_type := if target.ref_declaration.ast_type.desugared_qualified != '' {
		target.ref_declaration.ast_type.desugared_qualified
	} else {
		target.ref_declaration.ast_type.qualified
	}
	open := method_type.index_u8(`(`)
	if open < 0 {
		return false
	}
	raw_return_type := method_type[..open].trim_space()
	return_type := c.prefix_external_type(c.convert_type(raw_return_type).name)
	params := function_type_params(method_type)
	if params.any(it == '...') {
		return false
	}

	c.gen('fn (mut c2v_this ${receiver_type}')
	for i, param in params {
		param_type := c.prefix_external_type(c.convert_type(param).name)
		c.gen(', c2v_arg_${i} ${param_type}')
	}
	if return_type != '' && return_type != 'void' {
		c.gen(') ${return_type} { return ')
	} else {
		c.gen(') { ')
	}
	// Included headers are intentionally not emitted wholesale. When a callback
	// targets an inline no-op method from one of those headers, preserve its exact
	// semantics directly in the closure instead of calling a method that cannot
	// exist in the generated source.
	if (return_type == '' || return_type == 'void') && has_referenced_method
		&& cpp_method_has_empty_body(referenced_method) {
		c.gen('}')
		return true
	}
	v_method_name := c.cpp_method_decl_names[target.ref_declaration.id] or {
		method_base_name_from_cpp_name(method_name)
	}
	c.gen('c2v_this.${v_method_name}(')
	for i in 0 .. params.len {
		if i > 0 {
			c.gen(', ')
		}
		c.gen('c2v_arg_${i}')
	}
	c.gen(') }')
	return true
}

fn is_char_pointer_param_type(param_type string) bool {
	mut t := param_type.replace('const ', '').replace(' const', '')
	t =
		t.replace('class ', '').replace('struct ', '').replace('signed ', '').replace('unsigned ', '')
	t = t.replace(' ', '')
	return t == 'char*' || t == 'charconst*' || t.ends_with('::char*')
}

fn node_effective_type_name(node Node) string {
	if node.ast_type.desugared_qualified != '' {
		return node.ast_type.desugared_qualified
	}
	return node.ast_type.qualified
}

fn anonymous_record_source_line(type_name string) int {
	t := type_name.trim_space().trim_right(')')
	if !(t.contains('unnamed struct at') || t.contains('unnamed union at')
		|| t.contains('anonymous struct at') || t.contains('anonymous union at')) {
		return 0
	}
	without_col := t.all_before_last(':')
	if without_col == t {
		return 0
	}
	line_text := without_col.all_after_last(':')
	if line_text == '' || !string_is_digits(line_text) {
		return 0
	}
	return line_text.int()
}

fn rendered_arg_is_pointerish(expr string) bool {
	trimmed := expr.trim_space()
	return trimmed.starts_with('&') || trimmed.starts_with("c'") || trimmed.starts_with('c"')
		|| trimmed.ends_with('.c_str()') || trimmed.ends_with('.to_string()')
		|| trimmed.starts_with('unsafe { &')
}

fn rendered_arg_is_addressable_lvalue(expr string) bool {
	trimmed := expr.trim_space()
	if trimmed == '' || rendered_arg_is_pointerish(trimmed) {
		return false
	}
	if trimmed in ['true', 'false'] {
		return false
	}
	first := trimmed[0]
	if !((first >= `a` && first <= `z`) || (first >= `A` && first <= `Z`) || first == `_`) {
		return false
	}
	for i := 0; i < trimmed.len; i++ {
		ch := trimmed[i]
		is_ident := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_` || ch == `.`
		if !is_ident {
			return false
		}
	}
	return true
}

fn rendered_address_of_unsafe_deref_pointer(expr string) ?string {
	trimmed := expr.trim_space()
	prefix := '&(unsafe { *'
	suffix := ' })'
	if !trimmed.starts_with(prefix) || !trimmed.ends_with(suffix) {
		return none
	}
	pointer := trimmed[prefix.len..trimmed.len - suffix.len].trim_space()
	if pointer == '' {
		return none
	}
	return pointer
}

fn rendered_inner_unsafe_expr(expr string) ?string {
	trimmed := expr.trim_space()
	prefix := 'unsafe { '
	suffix := ' }'
	if !trimmed.starts_with(prefix) || !trimmed.ends_with(suffix) {
		return none
	}
	inner := trimmed[prefix.len..trimmed.len - suffix.len].trim_space()
	if inner == '' {
		return none
	}
	return inner
}

fn cpp_call_expr_returns_reference_value(node Node) bool {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.expr_with_cleanups)
			|| current.kindof(.materialize_temporary_expr)
			|| current.kindof(.cxx_bind_temporary_expr) || current.kindof(.c_style_cast_expr)
			|| current.kindof(.cxx_static_cast_expr)
			|| current.kindof(.cxx_reinterpret_cast_expr)
			|| current.kindof(.cxx_const_cast_expr)
			|| current.kindof(.cxx_dynamic_cast_expr)
			|| current.kindof(.cxx_functional_cast_expr)) {
		current = current.inner[0]
	}
	if current.value_category == 'lvalue'
		&& (current.kindof(.call_expr) || current.kindof(.cxx_member_call_expr)
			|| current.kindof(.cxx_operator_call_expr)) {
		return true
	}
	if !(current.kindof(.call_expr) || current.kindof(.cxx_member_call_expr)
		|| current.kindof(.cxx_operator_call_expr)) || current.inner.len == 0 {
		return false
	}
	mut callee := current.inner[0]
	for callee.inner.len == 1 && callee.kindof(.implicit_cast_expr) {
		callee = callee.inner[0]
	}
	qualified_type := if callee.ref_declaration.ast_type.desugared_qualified != '' {
		callee.ref_declaration.ast_type.desugared_qualified
	} else {
		callee.ref_declaration.ast_type.qualified
	}
	return qualified_type.contains('(')
		&& qualified_type.all_before('(').trim_space().ends_with('&')
}

fn (c &C2V) cpp_expr_uses_reference_storage(node Node) bool {
	if cpp_call_expr_returns_reference_value(node) {
		return true
	}
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.expr_with_cleanups)
			|| current.kindof(.materialize_temporary_expr)
			|| current.kindof(.cxx_bind_temporary_expr)) {
		current = current.inner[0]
	}
	if current.kindof(.cxx_construct_expr) && current.inner.len == 1 {
		// A user-declared copy constructor runs through its helper, which returns
		// the constructed value (see cxx_construct_expr).
		constructor_key := cpp_constructor_signature_key(c.convert_type(node_effective_type_name(current)).name, current.ctor_type.qualified)
		if constructor_key != '' && constructor_key in c.cpp_constructor_signature_names {
			return false
		}
		// A copy from a V pointer variable (a C++ reference) is dereferenced by
		// the copy itself.
		child_ref := unwrap_cpp_operator_operand(&current.inner[0])
		if child_ref.kindof(.decl_ref_expr) {
			if declared_type := c.declared_local_var_types[c.decl_ref_v_name(*child_ref)] {
				if declared_type.starts_with('&') {
					return false
				}
			}
		}
		constructed_type := normalize_v_ptr_type(convert_type(node_effective_type_name(current)).name)
		child_type := normalize_v_ptr_type(convert_type(node_effective_type_name(current.inner[0])).name)
		if constructed_type != '' && constructed_type == child_type {
			return c.cpp_expr_uses_reference_storage(current.inner[0])
		}
	}
	return current.kindof(.decl_ref_expr)
		&& current.ref_declaration.ast_type.qualified.trim_space().ends_with('&')
		&& current.ref_declaration.id !in c.cpp_value_reference_params
}

fn cpp_expr_is_addressable_lvalue(node Node) bool {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.paren_expr) || current.kindof(.expr_with_cleanups)) {
		current = current.inner[0]
	}
	// Clang models a temporary bound to `const T&` as an lvalue
	// MaterializeTemporaryExpr. The generated V expression still has no storage
	// whose address can be taken, so bind it to our own temporary below instead.
	if current.kindof(.materialize_temporary_expr) || current.kindof(.cxx_bind_temporary_expr) {
		return false
	}
	return current.value_category == 'lvalue'
}

fn cpp_expr_is_materialized_temporary(node Node) bool {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.expr_with_cleanups)) {
		current = current.inner[0]
	}
	return current.kindof(.materialize_temporary_expr)
		|| current.kindof(.cxx_bind_temporary_expr)
}

fn normalize_v_ptr_type(type_name string) string {
	mut t := type_name.trim_space()
	for t.starts_with('&') {
		t = t[1..].trim_space()
	}
	return t
}

fn is_nonvoidptr_pointer_type(type_name string) bool {
	t := type_name.trim_space()
	return t.starts_with('&') && normalize_v_ptr_type(t) != 'voidptr'
}

fn (mut c C2V) receiver_surface_type_name(node Node) string {
	mut typ :=
		c.prefix_external_type(c.convert_type(node_effective_type_name(node)).name).trim_space()
	for typ.starts_with('&') {
		typ = typ[1..].trim_space()
	}
	return typ
}

fn (c &C2V) method_defined_in_current_output_dir(method_key string) bool {
	if method_key == '' || c.outv == '' {
		return false
	}
	out_dir := os.dir(c.outv)
	if out_dir == '' {
		return false
	}
	key := '${out_dir}|${method_key}'
	return key in c.project_dir_method_defs || key in c.project_emitted_method_defs
}

fn (c &C2V) method_defined_in_current_output_dir_from_sources(method_key string) bool {
	if method_key == '' || c.outv == '' {
		return false
	}
	return '${os.dir(c.outv)}|${method_key}' in c.project_dir_method_defs
}

fn should_cast_call_arg_to_pointer_param(v_arg_type string, v_param_type string) bool {
	if !is_nonvoidptr_pointer_type(v_param_type) {
		return false
	}
	arg_base := normalize_v_ptr_type(v_arg_type)
	param_base := normalize_v_ptr_type(v_param_type)
	if arg_base == '' || param_base == '' || arg_base == param_base {
		return false
	}
	// Recovery headers sometimes expose addressable compatibility constants as
	// `int` even though the called declaration has a concrete record pointer.
	// Casting that pointer to the typed parameter is safe; casting *to* primitive
	// pointers is still too broad and remains disabled.
	if param_base in v_primitive_type_names {
		return false
	}
	return true
}

fn cpp_pointer_param_cast(rendered string, target_type string, take_address bool, inside_unsafe bool) string {
	address := if take_address { '&' } else { '' }
	cast := '&${target_type}(${address}${rendered})'
	return if inside_unsafe { cast } else { 'unsafe { ${cast} }' }
}

fn (mut c C2V) render_expr_to_string(arg Node) string {
	// Expression lowering can flush intermediate statements with genln(), notably
	// for comma operators used inside a conditional expression. Capture both the
	// flushed builder segment and the final pending line. Previously those flushed
	// statements leaked into the surrounding function and only the last branch was
	// returned to the caller, turning declarations such as
	// `ptr := (cond ? (flag = true, a()) : (flag = false, b()))` into an orphaned
	// conditional followed by `ptr := b()` in its else branch.
	start := c.out.len
	old_cur_out := c.cur_out_line
	old_out_line_empty := c.out_line_empty
	old_indent := c.indent
	c.cur_out_line = ''
	c.out_line_empty = true
	c.indent = 0
	// Expression generation consumes current_child_id. Render a deep copy so a
	// later real emission of the same AST node still sees all of its children.
	mut render_arg := clone_cpp_operator_node(&arg)
	c.expr(&render_arg)
	rendered := c.out.cut_to(start) + c.cur_out_line
	c.cur_out_line = old_cur_out
	c.out_line_empty = old_out_line_empty
	c.indent = old_indent
	return rendered
}

fn cpp_unwrap_conditional_expression(node Node) ?Node {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr)
			|| current.kindof(.materialize_temporary_expr)
			|| current.kindof(.expr_with_cleanups)) {
		current = current.inner[0]
	}
	if current.kindof(.conditional_operator) && current.inner.len >= 3 {
		return current
	}
	return none
}

fn wrap_final_rendered_expr(rendered string, cast string) string {
	body := rendered.trim_right(' \t\r\n')
	if body == '' {
		return '${cast}(0)'
	}
	if newline := body.last_index('\n') {
		return body[..newline + 1] + '${cast}(${body[newline + 1..].trim_space()})'
	}
	return '${cast}(${body.trim_space()})'
}

fn (mut c C2V) write_voidptr_arg_expr(arg Node) {
	if !c.is_cpp && arg.kindof(.implicit_cast_expr) && arg.cast_kind == 'BitCast'
		&& arg.inner.len > 0 && arg.inner[0].kindof(.implicit_cast_expr)
		&& arg.inner[0].cast_kind == 'ArrayToPointerDecay' && arg.inner[0].inner.len > 0 {
		inner := arg.inner[0].inner[0]
		if inner.kindof(.member_expr) && inner.ast_type.qualified.contains('[')
			&& inner.ast_type.qualified.contains(']') {
			c.gen(c.render_expr_to_string(inner))
			return
		}
	}
	rendered := c.render_expr_to_string(arg)
	mut source_arg := arg
	for source_arg.inner.len > 0
		&& (source_arg.kindof(.implicit_cast_expr) || source_arg.kindof(.paren_expr)) {
		source_arg = source_arg.inner[0]
	}
	source_type := c.prefix_external_type(c.convert_type(node_effective_type_name(source_arg)).name)
	if c.is_cpp && normalize_v_ptr_type(source_type) in c.cpp_abstract_types {
		// A translated C++ abstract pointer is a V interface value, whose runtime
		// representation cannot be converted with the ordinary `voidptr(value)` cast.
		c.gen('(')
		c.gen(rendered)
		c.gen(' as voidptr)')
		return
	}
	if rendered.starts_with('voidptr(') && rendered.ends_with(')') {
		c.gen(rendered)
		return
	}
	if rendered.starts_with('unsafe { voidptr(') && rendered.ends_with(') }') {
		c.gen(rendered)
		return
	}
	if rendered.starts_with('voidptr(') || rendered.starts_with('unsafe { voidptr(') {
		c.gen(rendered)
		return
	}
	if c.is_cpp && rendered == 'this' {
		c.gen('voidptr(${c.this_pointer()})')
		return
	}
	if arg.kindof(.implicit_cast_expr) && arg.cast_kind == 'ArrayToPointerDecay'
		&& arg.inner.len > 0 {
		inner := arg.inner[0]
		if !inner.kindof(.string_literal) {
			inner_rendered := c.render_expr_to_string(inner)
			if rendered_arg_is_addressable_lvalue(inner_rendered) {
				c.gen('voidptr(&')
				c.gen(inner_rendered)
				c.gen('[0])')
				return
			}
		}
	}
	if rendered_arg_is_addressable_lvalue(rendered)
		&& cpp_raw_fixed_array_length(node_effective_type_name(arg)) > 0 {
		// A fixed C array passed through `...` decays to its first element.
		c.gen('voidptr(&')
		c.gen(rendered)
		c.gen('[0])')
		return
	}
	if rendered_arg_is_pointerish(rendered) {
		c.gen('voidptr(')
		c.gen(rendered)
		c.gen(')')
		return
	}
	v_arg_type := c.prefix_external_type(c.convert_type(node_effective_type_name(arg)).name)
	if v_arg_type.starts_with('&') || v_arg_type == 'voidptr' {
		c.gen('voidptr(')
		c.gen(rendered)
		c.gen(')')
		return
	}
	base_arg := unwrap_condition_atom(arg)
	if base_arg.kindof(.integer_literal) {
		c.gen('voidptr(')
		c.gen(rendered)
		c.gen(')')
		return
	}
	// Values other than pointers and small integer literals are passed by
	// address (see c2v_format_variadic). A V constant has no C address, and a
	// computed value no storage: the strict helper copies both to the heap.
	if rendered_arg_is_addressable_lvalue(rendered) && !c.is_v_const_ref(arg) {
		c.gen('voidptr(&')
		c.gen(rendered)
		c.gen(')')
	} else if c.project_require_no_stubs {
		// V cannot infer the type argument from an `if` or `match` expression.
		trimmed_rendered := rendered.trim_space()
		type_arg := if v_arg_type != '' && !v_arg_type.contains(' ')
			&& (trimmed_rendered.starts_with('if ') || trimmed_rendered.starts_with('match ')) {
			'[${v_arg_type}]'
		} else {
			''
		}
		c.gen('voidptr(c2v_ref_value${type_arg}(')
		c.gen(rendered)
		c.gen('))')
	} else {
		c.gen('voidptr(0)')
	}
}

// is_v_const_ref reports whether an expression names a C/C++ constant that is
// translated to a V `const`.
fn (c &C2V) is_v_const_ref(node Node) bool {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
		current = current.inner[0]
	}
	return current.kindof(.decl_ref_expr) && current.ref_declaration.name in c.consts
}

// gen_pointer_address emits a pointer's address as usize. V has no usize cast
// of function values (or pointers to them), which go through voidptr.
fn (mut c C2V) gen_pointer_address(expr Node) {
	v_type := c.resolve_type_alias(c.convert_type(node_effective_type_name(expr)).name).trim_left('&')
	is_function := v_type.starts_with('fn ')
	c.gen(if is_function { 'usize(voidptr(' } else { 'usize(' })
	c.gen_cxx_pointer_cast_source(expr)
	c.gen(if is_function { '))' } else { ')' })
}

// v_pointer_depth counts the pointer layers of a V type (`voidptr` is one).
fn v_pointer_depth(v_type string) int {
	t := v_type.trim_space()
	depth := t.len - t.trim_left('&').len
	return if t.trim_left('&') == 'voidptr' { depth + 1 } else { depth }
}

// cpp_return_v_type converts a C++ return type. A mutable reference to a
// pointer (`T *&`) designates the pointer's storage, which the caller may
// assign, so it is returned as a pointer to that pointer.
fn (mut c C2V) cpp_return_v_type(raw string) string {
	converted := c.prefix_external_type(c.convert_type(raw).name)
	if c.is_cpp && is_cpp_mutable_pointer_reference_type(raw)
		&& (converted.starts_with('&') || converted == 'voidptr'
			|| c.is_v_abstract_interface_type(converted)) {
		// (A pointer to an abstract class is the V interface value itself.)
		return '&' + converted
	}
	return converted
}

// is_cpp_pointer_slot_call reports whether an expression is a call returning a
// mutable reference to a pointer, i.e. the address of the pointer's storage
// (see cpp_return_v_type). Reading its value dereferences it.
fn is_cpp_pointer_slot_call(node Node) bool {
	mut current := node
	for current.inner.len == 1 && current.kindof(.paren_expr) {
		current = current.inner[0]
	}
	return (current.kindof(.call_expr) || current.kindof(.cxx_member_call_expr)
		|| current.kindof(.cxx_operator_call_expr)) && current.value_category == 'lvalue'
		&& current.ast_type.qualified.trim_space().ends_with('*')
}

// A mutable C++ reference to a pointer (`T *&`) can rebind the caller's
// pointer, so it is translated as a pointer to that pointer. A reference to a
// const pointer (`T *const &`) only borrows the pointer value.
fn is_cpp_mutable_pointer_reference_type(qualified string) bool {
	t := qualified.trim_space()
	if !t.ends_with('&') || t.ends_with('&&') {
		return false
	}
	return t[..t.len - 1].trim_space().ends_with('*')
}

fn is_cpp_mutable_pointer_reference_param(param &Node) bool {
	return is_cpp_mutable_pointer_reference_type(param.ast_type.qualified)
		|| is_cpp_mutable_pointer_reference_type(param.ast_type.desugared_qualified)
}

fn (mut c C2V) gen_call_arg(arg Node, param_type string, is_variadic_arg bool) {
	old_deref := c.deref_reference_call_values
	// An argument of a C variadic function is passed by value.
	c.deref_reference_call_values = param_type == '' && c.is_cpp && !is_variadic_arg
	defer {
		c.deref_reference_call_values = old_deref
	}
	converted_param_type := c.convert_type(param_type)
	mut v_param_type := c.prefix_external_type(converted_param_type.name)
	if converted_param_type.is_const && param_type.trim_space().ends_with('&')
		&& v_param_type.starts_with('&')
		&& normalize_v_ptr_type(v_param_type) in v_primitive_type_names {
		v_param_type = v_param_type[1..]
	}
	resolved_v_param_type := c.resolve_type_alias(v_param_type)
	if !is_variadic_arg && c.is_v_abstract_interface_type(v_param_type)
		&& is_cpp_null_pointer_expression(arg) {
		c.gen(c.v_abstract_interface_nil_literal(v_param_type))
		return
	}
	if !is_variadic_arg && (v_param_type.starts_with('&') || resolved_v_param_type == 'voidptr'
		|| resolved_v_param_type.starts_with('fn ')) && is_cpp_null_pointer_expression(arg) {
		// V takes the address of an argument to match a deeper pointer
		// parameter, so a null `T **` argument must be typed.
		null_value := if v_param_type.starts_with('&&') { '${v_param_type}(nil)' } else { 'nil' }
		c.gen(if c.inside_unsafe { null_value } else { 'unsafe { ${null_value} }' })
		return
	}
	if !is_variadic_arg && is_cpp_mutable_pointer_reference_type(param_type) {
		if reference_name := c.cpp_primitive_reference_v_name(&arg) {
			// Already a pointer to the caller's pointer.
			c.gen(reference_name)
		} else if is_cpp_pointer_slot_call(unwrap_condition_atom(arg)) {
			c.expr(arg)
		} else {
			c.gen('&')
			c.expr(arg)
		}
		return
	}
	mut conditional_arg := arg
	for conditional_arg.inner.len == 1
		&& (conditional_arg.kindof(.implicit_cast_expr) || conditional_arg.kindof(.paren_expr)
			|| conditional_arg.kindof(.materialize_temporary_expr)
			|| conditional_arg.kindof(.expr_with_cleanups)) {
		conditional_arg = conditional_arg.inner[0]
	}
	if !is_variadic_arg && v_param_type.starts_with('&')
		&& cpp_derived_to_base_source(&arg) == none
		&& conditional_arg.kindof(.conditional_operator) && conditional_arg.inner.len >= 3 {
		// Keep one outer unsafe expression around pointer-valued conditionals. The
		// translated formatter removes nested branch-local unsafe blocks, which can
		// otherwise leave a bare `nil` and produce uncompilable V.
		was_inside_unsafe := c.inside_unsafe
		if !was_inside_unsafe {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
		mut condition := clone_cpp_operator_node(&conditional_arg.inner[0])
		c.gen('if ')
		c.gen_bool(&condition)
		c.gen(' { ')
		c.gen_call_arg(conditional_arg.inner[1], param_type, false)
		c.gen(' } else { ')
		c.gen_call_arg(conditional_arg.inner[2], param_type, false)
		c.gen(' }')
		if !was_inside_unsafe {
			c.inside_unsafe = false
			c.gen(' }')
		}
		return
	}
	if !is_variadic_arg && param_type.trim_space().ends_with('&')
		&& c.cpp_primitive_reference_operator_source(&arg) != none {
		old_reference_lvalue := c.inside_cpp_reference_lvalue
		c.inside_cpp_reference_lvalue = true
		c.expr(arg)
		c.inside_cpp_reference_lvalue = old_reference_lvalue
		return
	}
	if is_variadic_arg {
		c.write_voidptr_arg_expr(arg)
		return
	}
	if !is_variadic_arg && (v_param_type == 'voidptr' || resolved_v_param_type == 'voidptr') {
		c.write_voidptr_arg_expr(arg)
		return
	}
	if !is_variadic_arg && resolved_v_param_type.starts_with('fn (')
		&& c.try_gen_cpp_function_pointer_adapter(arg, resolved_v_param_type) {
		return
	}
	base_arg := unwrap_condition_atom(arg)
	if !is_variadic_arg && v_param_type.starts_with('&')
		&& base_arg.kindof(.unary_operator) && base_arg.opcode == '&'
		&& base_arg.inner.len > 0 {
		reference_arg := unwrap_condition_atom(base_arg.inner[0])
		if reference_arg.kindof(.decl_ref_expr)
			&& reference_arg.ref_declaration.kind == .parm_var_decl
			&& reference_arg.ref_declaration.ast_type.qualified.trim_space().ends_with('&') {
			// Taking the address of a C++ reference parameter yields a pointer to
			// its referent. The V parameter already is that pointer, so another `&`
			// would incorrectly produce `&&T`.
			c.expr(reference_arg)
			return
		}
	}
	if !is_variadic_arg && v_param_type.starts_with('&') && base_arg.kindof(.decl_ref_expr)
		&& base_arg.ref_declaration.kind == .parm_var_decl
		&& base_arg.ref_declaration.ast_type.qualified.trim_space().ends_with('&') {
		declared_reference_type :=
			c.prefix_external_type(c.convert_type(base_arg.ref_declaration.ast_type.qualified).name)
		if normalize_v_ptr_type(c.resolve_type_alias(declared_reference_type)) == normalize_v_ptr_type(resolved_v_param_type) {
			// A translated non-primitive C++ reference parameter is already a V
			// pointer. Passing its address would incorrectly produce `&&T`.
			c.expr(arg)
			return
		}
	}
	if !is_variadic_arg && is_enum_ref_expr(base_arg)
		&& (v_param_type in ['i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize']
			|| resolved_v_param_type in ['i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
				'usize']
			|| v_param_type in c.enums) {
		c.gen('${v_param_type}(')
		c.expr(arg)
		c.gen(')')
		return
	}
	if !is_variadic_arg && param_type.trim_space().ends_with('&') {
		if reference_name := c.cpp_primitive_reference_v_name(&base_arg) {
			c.gen(reference_name)
			return
		}
	}
	arg_value_type := c.convert_type(node_effective_type_name(arg)).name
	if !is_variadic_arg && normalize_v_ptr_type(resolved_v_param_type) in v_primitive_type_names
		&& cpp_call_expr_returns_reference_value(arg) {
		// A C++ function returning `const T &` is represented as `&T` in V.
		// Passing it to a by-value primitive parameter must read the referent;
		// otherwise the V checker accepts the pointer but the C backend rejects it.
		reference_source := c.unwrap_expr_for_deref_check(arg)
		rendered_source := c.render_expr_to_string(reference_source)
		source_value_type := normalize_v_ptr_type(c.resolve_type_alias(c.prefix_external_type(c.convert_type(node_effective_type_name(reference_source)).name)))
		param_value_type := normalize_v_ptr_type(resolved_v_param_type)
		if source_value_type in v_primitive_type_names && source_value_type != param_value_type {
			c.gen('${param_value_type}(')
		}
		if rendered_source.trim_space().starts_with('unsafe { *')
			|| rendered_source.trim_space().starts_with('*') {
			c.gen(rendered_source)
		} else {
			c.gen('unsafe { *${rendered_source} }')
		}
		if source_value_type in v_primitive_type_names && source_value_type != param_value_type {
			c.gen(')')
		}
		return
	}
	if !is_variadic_arg && (base_arg.kindof(.character_literal) || arg_value_type == 'i8')
		&& (v_param_type == 'i8' || (c.is_cpp && param_type == '')) {
		c.gen('i8(')
		c.expr(arg)
		c.gen(')')
		return
	}
	if !is_variadic_arg && v_param_type.starts_with('&') {
		if source := cpp_derived_to_base_source(&arg) {
			target_type := normalize_v_ptr_type(v_param_type)
			if target_type != '' {
				if cpp_reference_operator_source(source) != none {
					// `*list[i]` can be a read through `T *const &`. The translated
					// operator already yields `&T`, so cast that pointer directly.
					c.gen_cpp_base_pointer_arg(source, target_type)
				} else {
					deref_source := c.unwrap_expr_for_deref_check(source)
					if deref_source.kindof(.unary_operator) && deref_source.opcode == '*'
						&& deref_source.inner.len > 0 {
						c.gen('unsafe { &${target_type}(')
						c.expr(deref_source.inner[0])
						c.gen(') }')
					} else {
						c.gen_cpp_base_pointer_arg(source, target_type)
					}
				}
				return
			}
		}
		if c.is_cpp {
			if array_source := cpp_array_decay_source(&arg) {
				if !array_source.kindof(.string_literal) {
					was_inside_unsafe := c.inside_unsafe
					if !was_inside_unsafe {
						c.gen('unsafe { ')
						c.inside_unsafe = true
					}
					c.gen('${v_param_type}(&')
					c.expr(array_source)
					c.gen('[0])')
					if !was_inside_unsafe {
						c.inside_unsafe = false
						c.gen(' }')
					}
					return
				}
			}
		}
	}
	if !is_variadic_arg && is_char_pointer_param_type(param_type) {
		if array_source := cpp_array_decay_source(&arg) {
			if !array_source.kindof(.string_literal) {
				was_inside_unsafe := c.inside_unsafe
				if !was_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('${v_param_type}(&')
				c.expr(array_source)
				c.gen('[0])')
				if !was_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
				return
			}
		}
		rendered := c.render_expr_to_string(arg)
		if local_type := c.declared_local_var_types[rendered] {
			if cpp_fixed_array_length(local_type) > 0 {
				c.gen('unsafe { ${v_param_type}(&${rendered}[0]) }')
				return
			}
		}
		c.gen(rendered)
		return
	}
	v_arg_type := c.prefix_external_type(c.convert_type(node_effective_type_name(arg)).name)
	if !is_variadic_arg && param_type == '...' && arg.kindof(.implicit_cast_expr)
		&& arg.cast_kind == 'ArrayToPointerDecay' && arg.inner.len > 0
		&& !arg.inner[0].kindof(.string_literal) {
		inner_rendered := c.render_expr_to_string(arg.inner[0])
		if c.global_uses_v_name(inner_rendered) {
			c.gen(inner_rendered)
			return
		}
	}
	if !is_variadic_arg && is_nonvoidptr_pointer_type(v_param_type) && !v_arg_type.starts_with('&') {
		arg_base := normalize_v_ptr_type(v_arg_type)
		param_base := normalize_v_ptr_type(v_param_type)
		if arg_base != '' && arg_base == param_base && arg_base !in v_primitive_type_names {
			deref_arg := c.unwrap_expr_for_deref_check(arg)
			if deref_arg.kindof(.unary_operator) && deref_arg.opcode == '*'
				&& deref_arg.inner.len > 0 {
				c.expr(deref_arg.inner[0])
				return
			}
			// A materialized C++ temporary is never an addressable V lvalue. Emit its
			// reference wrapper directly instead of rendering the whole expression to
			// a string first. Besides avoiding duplicate lowering work, this keeps
			// nested overloaded vector expressions within the translator's stack.
			if cpp_expr_is_materialized_temporary(arg) {
				if c.project_require_no_stubs {
					c.gen('c2v_ref_value(')
				} else {
					arg_id := c.expression_temp_id
					c.expression_temp_id++
					c.gen('__c2v_ref_arg_${arg_id}(')
				}
				c.expr(arg)
				c.gen(')')
				return
			}
			rendered := c.render_expr_to_string(arg)
			if local_typ := c.declared_local_var_types[rendered] {
				if local_typ.starts_with('&') && normalize_v_ptr_type(local_typ) == param_base {
					c.gen(rendered)
					return
				}
			}
			if rendered.starts_with('&') || rendered.starts_with('unsafe { &') {
				c.gen(rendered)
			} else if cpp_call_expr_returns_reference_value(arg) {
				// C++ reference-returning calls are translated to V pointer returns already.
				c.gen(rendered)
			} else if cpp_expr_is_addressable_lvalue(arg)
				|| rendered_arg_is_addressable_lvalue(rendered) {
				if rendered.trim_space().ends_with(']') && !c.inside_unsafe {
					// V takes the address of a mutable array element only in `unsafe`.
					c.gen('unsafe { &${rendered} }')
				} else {
					c.gen('&')
					c.gen(rendered)
				}
			} else {
				if c.project_require_no_stubs {
					// Strict project globals cannot materialize a statement-local
					// temporary before their initializer. The shared helper returns an
					// escaping address for both global and ordinary temporary values.
					c.gen('c2v_ref_value(')
				} else {
					arg_id := c.expression_temp_id
					c.expression_temp_id++
					c.gen('__c2v_ref_arg_${arg_id}(')
				}
				c.gen(rendered)
				c.gen(')')
			}
			return
		}
	}
	if !is_variadic_arg && should_cast_call_arg_to_pointer_param(v_arg_type, v_param_type) {
		deref_arg := c.unwrap_expr_for_deref_check(arg)
		mut simplified_address_deref := deref_arg.kindof(.unary_operator) && deref_arg.opcode == '*'
			&& deref_arg.inner.len > 0
		mut rendered := if simplified_address_deref {
			c.render_expr_to_string(deref_arg.inner[0])
		} else {
			c.render_expr_to_string(arg)
		}
		if !simplified_address_deref {
			if pointer := rendered_address_of_unsafe_deref_pointer(rendered) {
				rendered = pointer
				simplified_address_deref = true
			}
		}
		if inner := rendered_inner_unsafe_expr(rendered) {
			rendered = inner
			simplified_address_deref = true
		}
		target_type := normalize_v_ptr_type(v_param_type)
		if simplified_address_deref || v_arg_type.starts_with('&') || rendered.starts_with('&')
			|| rendered.starts_with('unsafe { &') {
			c.gen(cpp_pointer_param_cast(rendered, target_type, false, c.inside_unsafe))
		} else {
			c.gen(cpp_pointer_param_cast(rendered, target_type, true, c.inside_unsafe))
		}
		return
	}
	needs_param_cast := v_param_type.starts_with('&&')
	if !is_variadic_arg && needs_param_cast && arg.kindof(.unary_operator) && arg.opcode == '&' {
		c.gen(v_param_type + '(')
		c.expr(arg)
		c.gen(')')
		return
	}
	if !is_variadic_arg && arg.kindof(.implicit_cast_expr) && arg.cast_kind == 'ArrayToPointerDecay'
		&& arg.inner.len > 0 && !arg.inner[0].kindof(.string_literal) {
		if needs_param_cast {
			c.gen(v_param_type + '(')
		}
		c.gen('&')
		c.expr(arg.inner[0])
		c.gen('[0]')
		if needs_param_cast {
			c.gen(')')
		}
		return
	}
	c.expr(arg)
}

fn is_cpp_null_pointer_expression(node Node) bool {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.paren_expr) || current.kindof(.materialize_temporary_expr)
			|| current.kindof(.expr_with_cleanups) || current.kindof(.cxx_default_arg_expr)
			|| (current.kindof(.implicit_cast_expr) && current.cast_kind != 'NullToPointer')) {
		current = current.inner[0]
	}
	if current.kindof(.cxx_null_ptr_literal_expr) {
		return true
	}
	if current.kindof(.gnu_null_expr) {
		return true
	}
	if !current.kindof(.implicit_cast_expr) || current.cast_kind != 'NullToPointer'
		|| current.inner.len != 1 {
		return false
	}
	value := unwrap_struct_init_expr(current.inner[0])
	return value.kindof(.cxx_null_ptr_literal_expr) || value.kindof(.gnu_null_expr)
		|| (value.kindof(.integer_literal) && value.value.to_str() == '0')
}

fn v_function_return_type(fn_type string) string {
	close := fn_type.last_index(')') or { return '' }
	if close + 1 >= fn_type.len {
		return ''
	}
	return fn_type[close + 1..].trim_space()
}

fn (mut c C2V) try_gen_cpp_function_pointer_adapter(arg Node, target_fn_type string) bool {
	source := cpp_function_decl_ref_source(&arg) or { return false }
	source_signature := fn_call_callee_type(source)
	if source_signature == '' {
		return false
	}
	target_params := function_type_params(target_fn_type)
	source_cpp_params := function_type_params(source_signature)
	if target_params.len != source_cpp_params.len || target_params.len == 0 {
		return false
	}
	mut source_params := []string{cap: source_cpp_params.len}
	for source_param in source_cpp_params {
		source_params << c.prefix_external_type(c.convert_type(source_param).name)
	}
	if source_params == target_params {
		return false
	}
	target_return := v_function_return_type(target_fn_type)
	c.gen('fn (')
	for i, target_param in target_params {
		if i > 0 {
			c.gen(', ')
		}
		c.gen('__c2v_cb_arg_${i} ${target_param}')
	}
	c.gen(')')
	if target_return != '' {
		c.gen(' ${target_return}')
	}
	c.gen(' { ')
	if target_return != '' {
		c.gen('return ')
	}
	c.expr(source)
	c.gen('(')
	for i, source_param in source_params {
		if i > 0 {
			c.gen(', ')
		}
		arg_name := '__c2v_cb_arg_${i}'
		if source_param == target_params[i] {
			c.gen(arg_name)
		} else if source_param.starts_with('&') || source_param == 'voidptr' {
			c.gen('unsafe { ${source_param}(${arg_name}) }')
		} else {
			c.gen('${source_param}(${arg_name})')
		}
	}
	c.gen(') }')
	return true
}

fn sizeof_deref_type(expr Node) ?string {
	mut current := expr
	for current.kindof(.paren_expr) && current.inner.len == 1 {
		current = current.inner[0]
	}
	if current.kindof(.unary_operator) && current.opcode == '*' && current.ast_type.qualified != '' {
		return current.ast_type.qualified
	}
	return none
}

fn sizeof_expr_needs_type_operand(rendered string) bool {
	return rendered.contains('this.') || rendered.contains('.') || rendered.contains('[')
}

// collect_address_taken_pointer_params records the pointer parameters whose
// address a function body takes (e.g. `T **link = &head;`). V's `&` of a
// pointer parameter yields the pointer itself, so the body works on a local copy.
fn collect_address_taken_pointer_params(node Node, mut ids map[string]bool) {
	if node.kindof(.unary_operator) && node.opcode == '&' && node.inner.len > 0 {
		target := unwrap_address_target(node.inner[0])
		param_type := target.ref_declaration.ast_type.qualified.trim_space()
		if target.kindof(.decl_ref_expr) && target.ref_declaration.kind == .parm_var_decl
			&& target.ref_declaration.id != '' && param_type.contains('*')
			&& !param_type.ends_with('&') {
			ids[target.ref_declaration.id] = true
		}
	}
	for child in node.inner {
		collect_address_taken_pointer_params(child, mut ids)
	}
}

fn (mut c C2V) prepare_copied_pointer_params(node &Node) {
	c.copied_pointer_params = map[string]bool{}
	c.param_local_copies = []string{}
	c.copied_params_fn_id = node.id
	for child in node.inner {
		if child.kindof(.compound_stmt) {
			collect_address_taken_pointer_params(child, mut c.copied_pointer_params)
		}
	}
}

fn (mut c C2V) gen_param_local_copies() {
	for copy in c.param_local_copies {
		c.genln('\t${copy}')
	}
	c.param_local_copies = []string{}
	c.copied_params_fn_id = ''
}

fn collect_address_taken_decl_refs(node Node, mut names map[string]bool) {
	if node.kindof(.unary_operator) && node.opcode == '&' && node.inner.len > 0 {
		target := unwrap_address_target(node.inner[0])
		if target.kindof(.decl_ref_expr) && target.ref_declaration.kind == .var_decl {
			ref_name := if target.ref_declaration.name != '' {
				target.ref_declaration.name
			} else {
				target.name
			}
			if ref_name != '' {
				names[ref_name] = true
			}
		}
	}
	for child in node.inner {
		collect_address_taken_decl_refs(child, mut names)
	}
	for child in node.array_filler {
		collect_address_taken_decl_refs(child, mut names)
	}
}

fn collect_conditional_mutable_decl_refs(node Node, inside_conditional bool, mut refs map[string]bool) {
	now_inside_conditional := inside_conditional || node.kindof(.conditional_operator)
	is_assignment := (node.kindof(.binary_operator) && node.opcode == '=')
		|| node.kindof(.compound_assign_operator)
		|| (node.kindof(.unary_operator) && node.opcode in ['++', '--'])
	if now_inside_conditional && is_assignment && node.inner.len > 0 {
		target := unwrap_address_target(node.inner[0])
		if target.kindof(.decl_ref_expr) && target.ref_declaration.kind == .var_decl {
			if target.ref_declaration.id != '' {
				refs[target.ref_declaration.id] = true
			}
			ref_name := if target.ref_declaration.name != '' {
				target.ref_declaration.name
			} else {
				target.name
			}
			if ref_name != '' {
				refs['name:${ref_name}'] = true
			}
		}
	}
	for child in node.inner {
		collect_conditional_mutable_decl_refs(child, now_inside_conditional, mut refs)
	}
	for child in node.array_filler {
		collect_conditional_mutable_decl_refs(child, now_inside_conditional, mut refs)
	}
}

fn unwrap_address_target(node Node) Node {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.expr_with_cleanups)
			|| current.kindof(.materialize_temporary_expr)) {
		current = current.inner[0]
	}
	return current
}

fn (mut c C2V) fn_type_default_literal(fn_sig string) string {
	trimmed := fn_sig.trim_space()
	if !trimmed.starts_with('fn (') {
		return 'unsafe { nil }'
	}
	mut params_section := ''
	mut ret_type := ''
	if lpar := trimmed.index('(') {
		if rpar := trimmed.last_index(')') {
			if rpar > lpar {
				params_section = trimmed[lpar + 1..rpar].trim_space()
				ret_type = trimmed[rpar + 1..].trim_space()
			}
		}
	}
	mut params := []string{}
	if params_section != '' && params_section != 'void' {
		raw_params := params_section.split(',')
		for i, raw_p in raw_params {
			pt := raw_p.trim_space()
			if pt == '' {
				continue
			}
			params << 'arg${i} ${pt}'
		}
	}
	mut literal := 'fn (' + params.join(', ') + ')'
	if ret_type != '' && ret_type != 'void' {
		literal += ' ' + ret_type
		literal += ' { return ' + c.skeleton_default_value(ret_type) + ' }'
		return literal
	}
	literal += ' {}'
	return literal
}

fn (mut c C2V) skeleton_default_value(ret_type string) string {
	t := ret_type.trim_space()
	if t == '' {
		return ''
	}
	if t.starts_with('&') {
		return 'unsafe { nil }'
	}
	if t.starts_with('[]') || t.starts_with('map[') || (t.starts_with('[') && t.contains(']')) {
		return '${t}{}'
	}
	if t.starts_with('fn (') {
		return c.fn_type_default_literal(t)
	}
	mut resolved_t := t
	if resolved_t in c.type_aliases {
		resolved_t = c.resolve_type_alias(resolved_t)
	}
	if resolved_t.starts_with('fn (') {
		return c.fn_type_default_literal(resolved_t)
	}
	if resolved_t in c.cpp_abstract_types {
		return c.v_abstract_interface_nil_literal(resolved_t)
	}
	return match resolved_t {
		'bool' {
			'false'
		}
		'f32', 'f64' {
			'0.0'
		}
		'string' {
			"''"
		}
		'voidptr' {
			'voidptr(0)'
		}
		'i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize' {
			'0'
		}
		else {
			if resolved_t.len > 0 && resolved_t[0].is_capital() {
				if resolved_t.contains('.') {
					'${resolved_t}(0)'
				} else {
					'${resolved_t}{}'
				}
			} else {
				'0'
			}
		}
	}
}

fn (c &C2V) should_emit_skeleton_body() bool {
	return c.skeleton_mode
}

fn (c &C2V) should_emit_skeleton_body_for_node(node &Node) bool {
	return c.skeleton_mode
		|| (c.is_dir && c.is_cpp && c.project_generate_stubs && !c.project_require_no_stubs
			&& !c.node_body_in_main_file(node))
}

fn (c &C2V) has_function_definition(c_name string) bool {
	for node in c.tree.inner {
		if node.kindof(.function_decl) && node.name == c_name
			&& node.has_child_of_kind(.compound_stmt) {
			return true
		}
	}
	return false
}

fn is_c_linkage_function_decl(node &Node) bool {
	if (node.kind_str != 'FunctionDecl' && !node.kindof(.function_decl)) || node.name == '' {
		return false
	}
	// Clang spells a C symbol either verbatim (ELF and some builtins) or with
	// Darwin's leading underscore. C++ functions use a platform mangling prefix
	// such as `_Z` and must remain project-local V callables.
	return node.mangled_name == node.name || node.mangled_name == '_' + node.name
}

fn (c &C2V) function_ref_has_c_linkage(declaration RefDeclarationNode) bool {
	if full_declaration := c.callback_seen_ids[declaration.id] {
		return is_c_linkage_function_decl(full_declaration)
	}
	signature_key := cpp_function_signature_key(declaration.name, declaration.ast_type)
	return signature_key !in c.cpp_function_signature_v_names
}

fn (mut c C2V) register_external_c_function_decl(node &Node) {
	name := node.name
	if name == '' || name in c_known_fn_names || name in builtin_fn_names
		|| name in c.external_c_fn_declarations || node.is_implicit || name.starts_with('__builtin_') {
		// Compiler builtins are implicit declarations lowered at their call sites.
		return
	}
	if name in ['__builtin_alloca', '__builtin_va_start', '__builtin_va_end', '__builtin_va_copy'] {
		// These are lowered to V compatibility helpers rather than linked symbols.
		return
	}
	mut params := []string{}
	for child in node.inner {
		if child.kind_str != 'ParmVarDecl' && !child.kindof(.parm_var_decl) {
			continue
		}
		param_type := if child.ast_type.desugared_qualified.contains('(*)')
			&& !child.ast_type.qualified.contains('(*)') {
			child.ast_type.desugared_qualified
		} else {
			child.ast_type.qualified
		}
		converted := c.prefix_external_type(c.convert_type(param_type).name)
		params << c.external_decl_abi_type(converted)
	}
	if node.ast_type.qualified.contains('...') {
		params << '...voidptr'
	}
	raw_return_type := node.ast_type.qualified.before('(').trim_space()
	mut return_type := ''
	if raw_return_type != '' && raw_return_type != 'void' {
		converted := c.prefix_external_type(c.convert_type(raw_return_type).name)
		return_type = ' ' + c.external_decl_abi_type(converted)
	}
	c.external_c_fn_declarations[name] = 'fn C.${name}(${params.join(', ')})${return_type}'
	c.external_c_fn_signatures[name] = ExternalCFnSignature{
		params: params
		return_type: return_type.trim_space()
	}
	c.add_var_func_name(mut c.extern_fns, name)
}

// external_c_fn_declaration renders a typed C prototype once every type alias
// of the program is known. V declares no C typedef for an alias of a pointer
// type, so the prototype V emits must spell such an alias's pointer type.
fn (c &C2V) external_c_fn_declaration(name string) string {
	signature := c.external_c_fn_signatures[name] or { return c.external_c_fn_declarations[name] }
	params := signature.params.map(c.external_decl_pointer_alias_type(it))
	return_type := if signature.return_type == '' {
		''
	} else {
		' ' + c.external_decl_pointer_alias_type(signature.return_type)
	}
	return 'fn C.${name}(${params.join(', ')})${return_type}'
}

fn (c &C2V) external_decl_pointer_alias_type(typ string) string {
	if typ.starts_with('...') || typ.starts_with('C.') {
		return typ
	}
	resolved := c.resolve_type_alias(typ)
	if resolved != typ && resolved.starts_with('&') {
		return resolved
	}
	return typ
}

// System headers are deliberately omitted from the emission tree. Inspect the
// original Clang AST before it is released so calls into C libraries retain
// their typed ABI without translating the headers themselves.
fn (mut c C2V) collect_used_external_c_function_decls(node &Node) {
	// Functions declared at global scope by system headers are called through C
	// with their header included, whether compiled as C++ inline helpers or not:
	// the generated V is C, where the same header provides them.
	is_system_function := node.name in c.system.declaring_headers
	if node.kind_str == 'FunctionDecl' && c.used_fn.exists(node.name)
		&& (is_system_function || (is_c_linkage_function_decl(node)
			&& !has_direct_child_kind_str(*node, 'CompoundStmt'))) {
		c.register_external_c_function_decl(node)
	}
	for child in node.inner {
		c.collect_used_external_c_function_decls(&child)
	}
}

// Like external C functions, globals declared by system headers disappear when
// the header AST is removed. Preserve declarations for globals the translated
// source actually references (for example Darwin's mach_task_self_).
fn (mut c C2V) collect_used_external_c_global_decls(node &Node) {
	if node.kind_str == 'VarDecl' && node.class_modifier == 'extern'
		&& c.used_global.exists(node.name) {
		global_type := if node.ast_type.desugared_qualified.contains('(*)')
			&& !node.ast_type.qualified.contains('(*)') {
			node.ast_type.desugared_qualified
		} else {
			node.ast_type.qualified
		}
		converted := c.prefix_external_type(c.convert_type(global_type).name)
		if converted != '' {
			c.register_global_symbol(node.name, c.external_decl_abi_type(converted), true)
		}
	}
	for child in node.inner {
		c.collect_used_external_c_global_decls(&child)
	}
}

fn (mut c C2V) gen_skeleton_fn_body(ret_type string) {
	if ret_type.trim_space() != '' {
		c.genln('\treturn ${c.skeleton_default_value(ret_type)}')
	}
	c.genln('}')
	c.genln('')
}

fn (mut c C2V) fn_decl(mut node Node, gen_types string) {
	c.declared_local_vars.clear()
	c.declared_local_var_types.clear()
	c.local_decl_v_names.clear()
	c.for_init_vars.clear()
	c.current_fn_uses_va_arg = node_contains_kind(node, .va_arg_expr)
	vprintln('1FN DECL c_name="${node.name}" cur_file="${c.cur_file}" node.location.file="${node.location.file}"')
	if c.single_fn_def && node.name != c.fn_def_name {
		return
	}
	c.inside_main = false
	// No statements - it's a function declration, skip it
	no_stmts := if !node.has_child_of_kind(.compound_stmt) { true } else { false }
	if no_stmts && node.is_implicit {
		// Compiler-provided declarations (global allocation operators, builtins)
		// have no source prototype. Their uses are lowered at the call sites.
		return
	}
	// In C++ directory translation, retain typed declarations for used C-linkage
	// functions from system/native headers. Project C++ prototypes still resolve
	// to their translated definitions and do not become C ABI calls.
	if c.is_dir && c.is_cpp && no_stmts && !c.is_wrapper {
		if c.project_require_no_stubs && is_c_linkage_function_decl(&node)
			&& (c.used_fn.exists(node.name) || node.is_used) {
			c.register_external_c_function_decl(&node)
		}
		return
	}
	if c.is_cpp && !c.is_dir && no_stmts && !c.is_wrapper && is_c_linkage_function_decl(&node)
		&& !c.has_function_definition(node.name) {
		// A C-linkage prototype without a definition in this translation unit is
		// supplied by a C library. Calls use its C symbol through a typed declaration.
		c.register_external_c_function_decl(&node)
		return
	}
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
	mut c_name := node.name
	if c_name in ['invalid', 'referenced'] {
		return
	}
	if c_name.starts_with('__builtin_') {
		// Compiler builtins are either lowered at their call sites or supplied by
		// the compatibility preamble; they have no separately callable V ABI.
		return
	}
	// Skip unrecoverable C++ template placeholder signatures in dir mode.
	// These collide in V (no overloading/generics) and typically have a concrete
	// non-placeholder overload emitted nearby. A template specialization has a
	// concrete signature even if a typedef in it shares a template parameter's name.
	may_have_placeholders := c.is_dir && c.is_cpp && !node.has_child_of_kind(.template_argument)
	if may_have_placeholders && c.has_template_placeholder_type(node.ast_type.qualified) {
		return
	}
	if !c.single_fn_def && !c.used_fn.exists(c_name) && !node.is_used
		&& node.location.file_index != 0 && !node.has_child_of_kind(.template_argument) {
		vprintln('${c_name} => ${c.files[node.location.file_index]}')
		vprintln('RRRR2 ${c_name} not here, skipping')
		// This fn is not found in current .c file, means that it was only
		// in the include file, so it's declared and used in some other .c file,
		// no need to genenerate it here.
		return
	}
	if node.ast_type.qualified.contains('...)') && !c.is_cpp {
		// TODO handle this better (`...any` ?)
		c.genln('@[c2v_variadic]')
	}
	if c.is_wrapper {
		if c_name in c.fns {
			return
		}
		if node.class_modifier == 'static' {
			// Static functions are limited to their obejct files.
			// Cant include them into wrappers. Skip.
			vprintln('SKIPPING STATIC')
			return
		}
	}
	preassigned_cpp_name := c.cpp_function_decl_names[node.id] or { '' }
	registered_v_name := if preassigned_cpp_name != '' {
		preassigned_cpp_name
	} else {
		c.add_fn_name(c_name)
	}
	mut typ := node.ast_type.qualified.before('(').trim_space()
	enum_abi_for_decl := no_stmts && !c.is_dir && !c.is_wrapper
		&& !c.has_function_definition(c_name)
	if typ == 'void' {
		typ = ''
	} else {
		typ = c.cpp_return_v_type(typ)
		if enum_abi_for_decl {
			typ = c.external_decl_abi_type(typ)
		}
	}
	// Track current function's return type for handling bool-to-int returns
	c.cur_fn_ret_type = typ

	if typ.contains('...') {
		c.gen('F')
	}
	if c_name == 'main' {
		c.inside_main = true
		typ = ''
	}
	if typ != '' {
		typ = ' ${typ}'
	}
	// Build fn params
	c.prepare_copied_pointer_params(node)
	params := c.fn_params(mut node, enum_abi_for_decl)
	if may_have_placeholders {
		for p in params {
			if c.has_template_placeholder_type(p) {
				return
			}
		}
		if c.has_template_placeholder_type(typ) {
			return
		}
	}

	mut str_args := if c.inside_main { '' } else { params.join(', ') }
	if !c.inside_main && node.ast_type.qualified.contains('...') {
		if c.is_cpp {
			c.declared_local_vars.add('c2v_variadic_args')
			c.declared_local_var_types['c2v_variadic_args'] = '[]voidptr'
			str_args += if str_args == '' {
				'c2v_variadic_args ...voidptr'
			} else {
				', c2v_variadic_args ...voidptr'
			}
		} else {
			str_args += if str_args == '' { '...' } else { ', ...' }
		}
	}
	if !no_stmts || c.is_wrapper {
		c_name = c_name + gen_types
		if c.is_wrapper {
			fn_def := 'fn C.${c_name}(${str_args})${typ}\n'
			// Don't generate the wrapper for single fn def mode.
			// Just the definition and exit immediately.
			if c.single_fn_def {
				vprintln('is single fn def XXXXX ${fn_def}')
				// x := '/Users/alex/code/v/vlib/v/tests/include_c_gen_fn_headers/'
				mut f := os.open_append('__cdefs_autogen.v') or { panic(err) }
				f.write_string(fn_def) or { panic(err) }
				f.close()
				c.out_file.close()
				os.rm(c.outv) or { panic(err) } // we don't need file.c => file.v, just the autogen file
				exit(0)
				return
			}
			c.genln(fn_def)
		}
		mut v_name := registered_v_name
		if c.is_dir && c.is_cpp && !c.is_wrapper {
			fn_key := '${v_name}|${node.ast_type.qualified}'
			if fn_key in c.emitted_top_level_fns {
				return
			}
			c.emitted_top_level_fns[fn_key] = true
			if preassigned_cpp_name == '' {
				if n := c.emitted_top_level_name_counts[v_name] {
					next_n := n + 1
					c.emitted_top_level_name_counts[v_name] = next_n
					v_name = '${v_name}${next_n}'
				} else {
					c.emitted_top_level_name_counts[v_name] = 1
				}
			}
		}
		for declaration_id in [node.id, node.previous_declaration] {
			if declaration_id != '' {
				c.cpp_function_decl_names[declaration_id] = v_name
			}
		}
		is_template_specialization := node.has_child_of_kind(.template_argument)
		is_dir_exported_fn := c.is_dir && !c.is_wrapper && !is_template_specialization
			&& node.class_modifier != 'static' && c_name != 'main' && node.location.file_index == 0
			&& is_c_linkage_function_decl(&node)
		export_key := 'cpp_export:${c_name}'
		if is_dir_exported_fn && export_key !in c.generated_declarations {
			c.genln("@[export: '${c_name}']")
			c.generated_declarations[export_key] = true
		} else if !is_dir_exported_fn && v_name != c_name && !c.is_wrapper
			&& !is_template_specialization && !(c.is_dir && c.is_cpp)
			&& is_c_linkage_function_decl(&node) {
			c.genln("@[c:'${c_name}']")
		}
		if c.is_dir && !c.is_wrapper {
			c.genln('@[markused]')
		}
		old_current_fn_v_name := c.current_fn_v_name
		old_static_local_vars := c.static_local_vars.clone()
		old_address_taken_locals := c.address_taken_locals.clone()
		old_conditional_mutable_locals := c.conditional_mutable_locals.clone()
		c.current_fn_v_name = v_name
		c.static_local_vars = {}
		c.address_taken_locals = {}
		c.conditional_mutable_locals = {}
		if c.is_wrapper {
			// strip the "modulename__" from the start of the function
			stripped_name := v_name.replace(c.wrapper_module_name + '_', '')
			c.genln('pub fn ${stripped_name}(${str_args})${typ} {')
		} else {
			c.genln('fn ${v_name}(${str_args})${typ} {')
		}
		c.gen_param_local_copies()
		if c.inside_main && params.len >= 2 {
			argc_name := params[0].all_before(' ').trim_space()
			argv_name := params[1].all_before(' ').trim_space()
			if argc_name != '' && argv_name != '' {
				c.genln('\tmut c2v_main_argv_storage := []&i8{cap: os.args.len}')
				c.genln('\tfor arg in os.args {')
				c.genln('\t\tc2v_main_argv_storage << arg.str')
				c.genln('\t}')
				c.genln('\t${argc_name} := c2v_main_argv_storage.len')
				c.genln('\t${argv_name} := unsafe { &&i8(c2v_main_argv_storage.data) }')
			}
		}

		if c.should_emit_skeleton_body_for_node(&node) && !c.is_wrapper {
			c.gen_skeleton_fn_body(c.cur_fn_ret_type)
			c.current_fn_v_name = old_current_fn_v_name
			c.static_local_vars = old_static_local_vars.clone()
			c.address_taken_locals = old_address_taken_locals.clone()
			c.conditional_mutable_locals = old_conditional_mutable_locals.clone()
			return
		}

		if !c.is_wrapper {
			// For wrapper generation just generate function definitions without bodies
			mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
				println(add_place_data_to_error(err))
				bad_node
			}

			collect_address_taken_decl_refs(stmts, mut c.address_taken_locals)
			collect_conditional_mutable_decl_refs(stmts, false, mut c.conditional_mutable_locals)
			c.statements(mut stmts)
			c.current_fn_v_name = old_current_fn_v_name
			c.static_local_vars = old_static_local_vars.clone()
			c.address_taken_locals = old_address_taken_locals.clone()
			c.conditional_mutable_locals = old_conditional_mutable_locals.clone()
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
			c.current_fn_v_name = old_current_fn_v_name
			c.static_local_vars = old_static_local_vars.clone()
			c.address_taken_locals = old_address_taken_locals.clone()
			c.conditional_mutable_locals = old_conditional_mutable_locals.clone()
		}
	} else {
		if c_name !in ['__builtin___memset_chk', '__builtin_object_size', '__builtin___memmove_chk',
			'__builtin___memcpy_chk'] {
			v_name := registered_v_name
			project_local_fn_decl := c.is_dir && !c.is_wrapper && c.has_function_definition(c_name)
			// Only C-linkage symbols have an unmangled object-file name to preserve.
			if v_name != c_name && !project_local_fn_decl && is_c_linkage_function_decl(&node) {
				// This fixes unknown symbols errors when building separate .c => .v files into .o files
				// example:
				//
				// @[c: 'P_TryMove']
				// fn p_trymove(thing &Mobj_t, x int, y int) bool
				//
				// Now every time `p_trymove` is called, `P_TryMove` will be generated instead.
				c.genln("@[c:'${c_name}']")
			}
			if c_name in c_known_fn_names {
				c.genln('fn C.${c_name}(${str_args})${typ}')
				c.add_var_func_name(mut c.extern_fns, c_name)
			} else {
				c.genln('fn ${v_name}(${str_args})${typ}')
			}
		}
	}
	c.genln('')
	vprintln('END OF FN DECL ast line=${c.line_i}')
}

fn (mut c C2V) reserve_local_decl_v_name(decl_id string, c_name string) string {
	if decl_id != '' {
		if existing := c.local_decl_v_names[decl_id] {
			return existing
		}
	}
	mut base :=
		filter_name(c_identifier_to_v_name(c_name), false).camel_to_snake().all_after_last('c.')
	if base == '' {
		base = 'arg'
	}
	mut candidate := base
	mut suffix := 2
	for c.declared_local_vars.exists(candidate) || c.for_init_vars.exists(candidate)
		|| candidate in c.fns.values() || candidate in c.extern_fns.values()
		|| candidate in c.cpp_function_signature_v_names.values()
		|| candidate in c.cpp_method_signature_v_names.values()
		|| candidate in c.project_function_surfaces || candidate in c.consts.values() {
		// V resolves a local named like a module constant to the constant.
		candidate = '${base}_${suffix}'
		suffix++
	}
	if decl_id != '' {
		c.local_decl_v_names[decl_id] = candidate
	}
	return candidate
}

fn (mut c C2V) fn_params(mut node Node, enum_abi_for_decl bool) []string {
	mut str_args := []string{cap: 5}
	mut used_param_names := map[string]int{}
	nr_params := node.count_children_of_kind(.parm_var_decl)
	for i := 0; i < nr_params; i++ {
		// Instantiated C++ function templates place TemplateArgument nodes before
		// their ordinary parameters. Attributes can appear there as well.
		for node.current_child_id < node.inner.len
			&& !node.inner[node.current_child_id].kindof(.parm_var_decl) {
			node.current_child_id++
		}
		param := node.try_get_next_child_of_kind(.parm_var_decl) or {
			println(add_place_data_to_error(err))
			continue
		}
		arg_typ := c.convert_type(param.ast_type.qualified)

		mut c_param_name := param.name
		mut c_arg_typ_name := arg_typ.name
		mut v_arg_typ_name := arg_typ.name
		if arg_typ.is_const && param.ast_type.qualified.trim_space().ends_with('&')
			&& v_arg_typ_name.starts_with('&')
			&& normalize_v_ptr_type(v_arg_typ_name) in v_primitive_type_names {
			// A const primitive reference cannot be rebound or mutated by the callee.
			// Passing it by value preserves C++ behavior and lets V accept literals.
			v_arg_typ_name = v_arg_typ_name[1..]
			c_arg_typ_name = v_arg_typ_name
			if param.id != '' {
				c.cpp_value_reference_params[param.id] = true
			}
		}

		is_pointer_reference := is_cpp_mutable_pointer_reference_param(&param)
			&& (v_arg_typ_name.starts_with('&') || c.is_v_abstract_interface_type(v_arg_typ_name))
		if is_pointer_reference {
			v_arg_typ_name = '&' + v_arg_typ_name
			c_arg_typ_name = v_arg_typ_name
		}
		if c_arg_typ_name.contains('...') {
			vprintln('vararg: ' + c_arg_typ_name)
		} else if c_arg_typ_name.ends_with('*restrict') {
			c_arg_typ_name = fix_restrict_name(c_arg_typ_name)
			v_arg_typ_name = c.convert_type(c_arg_typ_name.trim_right('restrict')).name
		}
		// Apply external type prefix
		v_arg_typ_name = c.prefix_external_type(v_arg_typ_name)
		if enum_abi_for_decl {
			v_arg_typ_name = c.external_decl_abi_type(v_arg_typ_name)
		}
		// C++ callback parameters are often named exactly like a project-level
		// callback implementation (for example `GetJointTransform`). Since later
		// translation units are not known when this signature is emitted, reserve
		// an unambiguous name proactively for that convention.
		resolved_param_type := c.resolve_type_alias(v_arg_typ_name)
		parameter_reservation_name := if (v_arg_typ_name.starts_with('fn (')
			|| resolved_param_type.starts_with('fn (')) && c_param_name.len > 0
			&& c_param_name[0].is_capital() {
			c_param_name + '_callback'
		} else {
			c_param_name
		}
		mut v_param_name := c.reserve_local_decl_v_name(param.id, parameter_reservation_name)
		if v_param_name == '' {
			v_param_name = 'arg${i}'
		}
		// Avoid duplicate parameter names after normalization (e.g. R + r => r).
		if param.id == '' && v_param_name in used_param_names {
			used_param_names[v_param_name]++
			v_param_name = '${v_param_name}_${used_param_names[v_param_name] + 1}'
		} else {
			used_param_names[v_param_name] = 0
		}
		// Track parameter names as declared variables to avoid redefinition errors
		c.declared_local_vars.add(v_param_name)
		c.declared_local_var_types[v_param_name] = v_arg_typ_name
		if param.id != '' && v_arg_typ_name.starts_with('&')
			&& param.ast_type.qualified.trim_space().ends_with('&')
			&& (is_pointer_reference || normalize_v_ptr_type(v_arg_typ_name) in v_primitive_type_names) {
			c.cpp_primitive_reference_decls[param.id] = true
		}
		if param.id in c.copied_pointer_params && node.id == c.copied_params_fn_id {
			str_args << '${v_param_name}_param ${v_arg_typ_name}'
			c.param_local_copies << 'mut ${v_param_name} := ${v_param_name}_param'
		} else {
			str_args << '${v_param_name} ${v_arg_typ_name}'
		}
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
fn strip_cpp_type_qualifier(type_name string, qualifier string) (string, bool) {
	mut out := strings.new_builder(type_name.len)
	mut found := false
	mut i := 0
	for i < type_name.len {
		if i + qualifier.len <= type_name.len && type_name[i..i + qualifier.len] == qualifier {
			prev_is_ident := i > 0 && ((type_name[i - 1] >= `a` && type_name[i - 1] <= `z`)
				|| (type_name[i - 1] >= `A` && type_name[i - 1] <= `Z`)
				|| (type_name[i - 1] >= `0` && type_name[i - 1] <= `9`)
				|| type_name[i - 1] == `_`)
			next_i := i + qualifier.len
			next_is_ident := next_i < type_name.len
				&& ((type_name[next_i] >= `a` && type_name[next_i] <= `z`)
					|| (type_name[next_i] >= `A` && type_name[next_i] <= `Z`)
					|| (type_name[next_i] >= `0` && type_name[next_i] <= `9`)
					|| type_name[next_i] == `_`)
			if !prev_is_ident && !next_is_ident {
				found = true
				i += qualifier.len
				continue
			}
		}
		out.write_u8(type_name[i])
		i++
	}
	return out.str(), found
}

fn convert_type(typ_ string) Type {
	mut typ := typ_
	// Clang's Darwin headers retain pointer nullability in qualType spellings.
	// Nullability has no V ABI representation and otherwise hides the canonical
	// `(*)` token used by the function-pointer converter.
	for qualifier in ['_Nonnull', '_Nullable', '_Null_unspecified'] {
		cleaned, _ := strip_cpp_type_qualifier(typ, qualifier)
		typ = cleaned
	}
	typ = collapse_ascii_whitespace(typ)
	typ = typ.replace('(* )', '(*)')
	vprintln('\nconvert_type("${typ}")')

	if typ.contains('__va_list_tag *') {
		return Type{
			name: 'C.va_list'
		}
	}
	// A reference to a const pointer (`T *const &`) borrows the pointer value; it
	// must not gain the extra V pointer layer used for a mutable `T * &`.
	trimmed_original_type := typ.trim_space()
	last_pointer_index := trimmed_original_type.last_index('*') or { -1 }
	const_pointer_reference := last_pointer_index >= 0 && trimmed_original_type.ends_with('&')
		&& trimmed_original_type[last_pointer_index + 1..].contains('const')
	cleaned_const_type, is_const := strip_cpp_type_qualifier(typ, 'const')
	typ = cleaned_const_type
	cleaned_volatile_type, _ := strip_cpp_type_qualifier(typ, 'volatile')
	typ = collapse_ascii_whitespace(cleaned_volatile_type.trim_space())
	// `T *const *` loses its qualifier as `T * *`.
	for typ.contains('* *') {
		typ = typ.replace('* *', '**')
	}
	typ = typ.replace('std::', '')
	// Handle unnamed/anonymous enum types from clang AST → int
	if typ.contains('unnamed enum') || typ.contains('anonymous enum') {
		return Type{
			name: 'int'
		}
	}
	// Handle unnamed struct/union types with source location paths from clang AST
	// e.g. "(unnamed struct at /path/to/file.cpp:123:4)"
	if (typ.contains('unnamed struct at') || typ.contains('unnamed union at')
		|| typ.contains('anonymous struct at') || typ.contains('anonymous union at'))
		&& typ.contains('/') {
		return Type{
			name: 'voidptr'
		}
	}
	// Handle C++ member function pointers (::*) - convert to voidptr
	if typ.contains('::*') {
		return Type{
			name: 'voidptr'
		}
	}
	// Handle remaining C++ namespace qualifiers
	for typ.contains('::') {
		typ = typ.all_after('::')
	}
	// Handle C++ rvalue references (&&)
	typ = typ.replace(' &&', ' *')
	// Handle C++ pointer-to-reference (*&) - just use pointer
	typ = typ.replace('*&', '*')
	// Handle C++ lvalue references (&) - convert to pointer
	if typ.ends_with(' &') {
		typ = if const_pointer_reference {
			typ[..typ.len - 2].trim_space()
		} else {
			typ[..typ.len - 2] + ' *'
		}
	}
	// Handle C++ template types. Keep pointer or reference suffixes outside the
	// specialization token so pointer arguments and pointers to the whole
	// specialization remain distinct.
	template_open := typ.index('<') or { -1 }
	first_paren := typ.index('(') or { typ.len }
	if template_open >= 0 && template_open < first_paren && typ.contains('>') {
		close := typ.last_index('>') or { -1 }
		mut outer_ptr_depth := 0
		mut outer_array_suffix := ''
		if close >= 0 && close + 1 < typ.len {
			suffix := typ[close + 1..].trim_space()
			if suffix != '' && suffix.trim('*') == '' {
				outer_ptr_depth = suffix.count('*')
				typ = typ[..close + 1]
			} else if suffix.starts_with('[') && suffix.ends_with(']') {
				outer_array_suffix = suffix.replace(' ', '')
				typ = typ[..close + 1]
			}
		}
		// Sanitize template parameters for V compatibility
		// Remove C++ keywords from template parameters
		typ = typ.replace('class ', '').replace('struct ', '').replace('enum ', '')
		typ = typ.replace('<', '__').replace('>', '').replace(' *', 'Ptr').replace(',', '_')
		typ = sanitize_type_token(typ)
		if outer_ptr_depth > 0 {
			converted_template := convert_type(typ)
			return Type{
				name: strings.repeat(`&`, outer_ptr_depth) + converted_template.name
				is_const: is_const
			}
		}
		if outer_array_suffix != '' {
			converted_template := convert_type(typ)
			return Type{
				name: outer_array_suffix + converted_template.name
				is_const: is_const
			}
		}
	}
	if typ.trim_space() == 'char **' {
		return Type{
			name: '&&u8'
		}
	}
	if typ.trim_space() == 'void *' {
		return Type{
			name: 'voidptr'
		}
	} else if typ.trim_space() == 'void **' {
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
		enum_part := typ.substr('enum '.len, typ.len)
		// Handle pointer to enum: "enum X *" -> "&X"
		if enum_part.ends_with(' *') {
			return Type{
				name: '&' + enum_part[..enum_part.len - 2].capitalize()
				is_const: is_const
			}
		}
		return Type{
			name: enum_part.capitalize()
			is_const: is_const
		}
	}

	// Function parameters written as `T matrix[N][M]` decay in Clang to a
	// pointer-to-array type such as `T (*)[M]`. This is not a function pointer;
	// preserve the remaining fixed dimensions behind one V pointer layer.
	if typ.trim_space().ends_with('(*)') {
		// Parentheses are also permitted around an ordinary pointer declarator:
		// `const T (*items)` has Clang type `const T (*)`, with no following
		// argument list. Do not mistake that spelling for a zero-argument
		// function pointer.
		marker := typ.last_index('(*)') or { -1 }
		if marker >= 0 {
			typ = typ[..marker].trim_space() + ' *'
		}
	}
	if typ.contains('(*)[') && typ.ends_with(']') {
		marker := typ.index('(*)') or { -1 }
		if marker >= 0 {
			array_base := typ[..marker].trim_space()
			array_suffix := typ[marker + 3..].replace(' ', '')
			converted_base := convert_type(array_base)
			return Type{
				name: '&' + array_suffix + converted_base.name
				is_const: is_const
			}
		}
	}

	// int[3]
	mut idx := ''
	if typ.contains('[') && typ.contains(']') {
		pos := typ.index('[') or { panic('no [ in conver_type(${typ})') }
		idx = typ[pos..]
		typ = typ[..pos]
	}
	// leveldb::DB
	if typ.contains('::') {
		typ = typ.after('::')
	} else if typ.contains(':') {
		// boolean:boolean
		typ = typ.all_before(':')
	}
	// Replace void ** before void * to avoid partial matches
	typ = typ.replace(' void **', ' &voidptr')
	typ = typ.replace(' void *', ' voidptr')

	// char*** => ***char
	mut base := typ.trim_space()
	// Only remove 'struct '/'class '/'union ' at the beginning, not in the middle of type names
	if base.starts_with('struct ') {
		base = base['struct '.len..]
	}
	if base.starts_with('class ') {
		base = base['class '.len..]
	}
	if base.starts_with('union ') {
		base = base['union '.len..]
	}
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
			if c_long_size == 8 { 'i64' } else { 'int' }
		}
		'unsigned int' {
			'u32'
		}
		'unsigned long long' {
			'u64'
		}
		'unsigned long' {
			if c_long_size == 8 { 'u64' } else { 'u32' }
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
		'uint32_t', '__uint32_t', 'u_int32_t' {
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
		'time_t', '__time_t' {
			'i64'
		}
		'int16_t' {
			'i16'
		}
		'uint16_t', '__uint16_t', 'u_int16_t' {
			'u16'
		}
		'uint8_t', '__uint8_t', 'u_int8_t' {
			'u8'
		}
		'int8_t' {
			'u8'
		}
		'__int64_t' {
			'i64'
		}
		'__int32_t' {
			'int'
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
		'voidpf', 'voidp' {
			'voidptr'
		}
		'intptr_t' {
			'isize'
		}
		'uintptr_t' {
			'usize'
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
		'uintmax_t' {
			'u64'
		}
		'intmax_t' {
			'i64'
		}
		'va_list', '__builtin_va_list', '__gnuc_va_list' {
			'C.va_list'
		}
		'pthread_mutex_t' {
			'C.pthread_mutex_t'
		}
		'pthread_t' {
			'C.pthread_t'
		}
		'pthread_cond_t' {
			'C.pthread_cond_t'
		}
		'pthread_key_t' {
			'C.pthread_key_t'
		}
		'off_t' {
			'i64'
		}
		'uid_t', 'gid_t' {
			'u32'
		}
		'pid_t' {
			'int'
		}
		'mode_t' {
			'u32'
		}
		'dev_t' {
			'u64'
		}
		else {
			mut capitalized := trim_underscores(base).capitalize()
			// Check for conflict with V built-in type names (e.g., Option, Result)
			if capitalized in v_builtin_type_names {
				capitalized += '_'
			}
			capitalized
		}
	}

	mut amps := ''

	if typ.ends_with('*') {
		star_pos := typ.index('*') or { -1 }

		nr_stars := typ[star_pos..].count('*')
		amps = strings.repeat(`&`, nr_stars)
		typ = amps + base
	} else if typ.contains('(*)')
		|| (typ.contains('(') && !typ.starts_with('(') && typ.contains(',')) {
		// fn type
		// int (*)(void *, int, char **, char **)
		// fn (voidptr, int, *byteptr, *byteptr) int
		// Also handle: int (object_id *, ...) - function type without (*) syntax
		ret_typ := convert_type(typ.all_before('('))
		mut s := 'fn ('
		// For function pointer syntax: ret (*)(args), get args from after the second (
		// For function type syntax: ret (args), get args from the first (
		mut args_str := ''
		if typ.contains('(*)') {
			// Find the args portion after (*) - e.g., "int (*)(arg1, arg2)" -> "arg1, arg2"
			star_paren_pos := typ.index('(*)') or { 0 }
			rest := typ[star_paren_pos + 3..] // after "(*)""
			// Find balanced parens for the args
			if rest.len > 0 && rest[0] == `(` {
				mut d := 0
				mut end := 0
				for ci := 0; ci < rest.len; ci++ {
					if rest[ci] == `(` {
						d++
					} else if rest[ci] == `)` {
						d--
						if d == 0 {
							end = ci
							break
						}
					}
				}
				args_str = rest[1..end]
			}
		} else {
			// Function type syntax: ret (args)
			first_open := typ.index_u8(`(`)
			mut d := 0
			mut end := first_open
			for ci := first_open; ci < typ.len; ci++ {
				if typ[ci] == `(` {
					d++
				} else if typ[ci] == `)` {
					d--
					if d == 0 {
						end = ci
						break
					}
				}
			}
			args_str = typ[first_open + 1..end]
		}
		// Split args respecting nested parens
		mut args := []string{}
		mut arg_start := 0
		mut paren_depth := 0
		for ci := 0; ci < args_str.len; ci++ {
			if args_str[ci] == `(` {
				paren_depth++
			} else if args_str[ci] == `)` {
				paren_depth--
			} else if args_str[ci] == `,` && paren_depth == 0 {
				args << args_str[arg_start..ci]
				arg_start = ci + 1
			}
		}
		args << args_str[arg_start..]
		for i, arg in args {
			t := convert_type(arg.trim_space())
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

fn (c &C2V) convert_type(typ string) Type {
	anon_line := anonymous_record_source_line(typ)
	if anon_line > 0 {
		anon_name := 'AnonStruct_${anon_line}'
		if v_name := c.types[anon_name] {
			return Type{
				name: v_name
			}
		}
	}
	alias_normalized_type := c.normalize_cpp_template_alias_arguments(c.resolve_system_typedefs(typ))
	normalized_type := normalize_cpp_template_enum_arguments(alias_normalized_type, c.enum_int_vals)
	mut converted := convert_type(normalized_type)
	converted.name = c.map_system_record_names(converted.name)
	// Fixed array dimensions (`[4]&T`) prefix the element type.
	mut array_prefix := ''
	for converted.name.starts_with('[') {
		close := converted.name.index(']') or { break }
		array_prefix += converted.name[..close + 1]
		converted.name = converted.name[close + 1..]
	}
	mut abstract_base := converted.name
	mut pointer_depth := 0
	for abstract_base.starts_with('&') {
		abstract_base = abstract_base[1..]
		pointer_depth++
	}
	if pointer_depth > 0 && abstract_base in c.cpp_abstract_types {
		// A V interface already carries reference identity. One C++ pointer layer
		// maps to the interface value itself; additional pointer layers remain.
		converted.name = converted.name[1..]
		if pointer_depth > 1 && converted.is_const && typ.trim_space().ends_with('&') {
			// A const C++ reference to an interface pointer only borrows the pointer
			// value. V can pass the interface descriptor directly because the callee
			// cannot replace it.
			converted.name = converted.name[1..]
		}
	}
	converted.name = array_prefix + converted.name
	for alias, concrete in c.cpp_template_type_aliases {
		// Nested aliases such as `Block` must not rewrite the same substring in
		// unrelated template names.
		converted.name = replace_c_ref_token(converted.name, alias, concrete)
	}
	for source_alias, local_alias in c.file_type_alias_names {
		converted.name = replace_c_ref_token(converted.name, source_alias, local_alias)
	}
	if converted.name.starts_with('&') && converted.name.trim_left('&') in c.function_type_aliases {
		// A pointer to a C function type (`typedef int cmp_t(...)`, `cmp_t *`) is
		// the V function type itself.
		converted.name = converted.name[1..]
	}
	if converted.name.starts_with('&') {
		// V lowers a pointer to a function value to that function pointer, so a
		// pointer to a C function pointer is carried as a pointer to an address.
		base := converted.name.trim_left('&')
		if base.starts_with('fn (') || c.resolve_type_alias(base).starts_with('fn (') {
			converted.name = converted.name[..converted.name.len - base.len] + 'voidptr'
		}
	}
	return converted
}

fn (c &C2V) normalize_cpp_template_alias_arguments(type_name string) string {
	if !type_name.contains('<') || c.type_aliases.len == 0 {
		return type_name
	}
	mut out := strings.new_builder(type_name.len)
	mut angle_depth := 0
	mut i := 0
	for i < type_name.len {
		ch := type_name[i]
		if ch == `<` {
			angle_depth++
			out.write_u8(ch)
			i++
			continue
		}
		if ch == `>` {
			angle_depth--
			out.write_u8(ch)
			i++
			continue
		}
		is_identifier_start := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| ch == `_`
		if angle_depth > 0 && is_identifier_start {
			mut end := i + 1
			for end < type_name.len && is_identifier_char(type_name[end]) {
				end++
			}
			token := type_name[i..end]
			converted_token := convert_type(token).name
			resolved_token := c.resolve_type_alias(converted_token)
			if resolved_token != converted_token {
				out.write_string(resolved_token)
			} else {
				out.write_string(token)
			}
			i = end
			continue
		}
		out.write_u8(ch)
		i++
	}
	return out.str()
}

fn c_style_cast_type_spelling(ast_type AstJsonType) string {
	// Typedefs declared by external headers are not emitted as local V aliases.
	// Clang still records their canonical function-pointer signature, which is
	// required both for valid V syntax and for a correctly typed bit cast. Keep
	// the written spelling for every other typedef because desugaring scalar ABI
	// types (notably Darwin time_t) can change c2v's intentional width mapping.
	if ast_type.desugared_qualified.contains('(*)')
		&& !ast_type.qualified.contains('(*)') {
		return ast_type.desugared_qualified
	}
	return ast_type.qualified
}

fn (c &C2V) is_v_abstract_interface_type(v_type string) bool {
	trimmed := v_type.trim_space()
	return trimmed != '' && !trimmed.starts_with('&')
		&& normalize_v_ptr_type(trimmed) in c.cpp_abstract_types
}

fn cpp_interface_runtime_helpers_source() string {
	return 'union C2vNilInterfaceStorage[T] {\nmut:\n\traw [2]voidptr\n\tvalue T\n}\n\nstruct C2vInterfaceHeader {\n\tobject voidptr\n}\n\nfn c2v_nil_interface[T]() T {\n\tstorage := C2vNilInterfaceStorage[T]{}\n\treturn unsafe { storage.value }\n}\n\nfn c2v_interface_object[T](value T) voidptr {\n\treturn unsafe { (&C2vInterfaceHeader(&value)).object }\n}\n\nfn c2v_interface_is_nil[T](value T) bool {\n\treturn c2v_interface_object(value) == unsafe { nil }\n}\n\n' + '// Reinterprets an address as `&T`. Casting a raw pointer to `&Interface`\n' + '// would instead box the pointer into a new interface value.\n' + 'union C2vPointerStorage[T] {\nmut:\n\traw   voidptr\n\tvalue &T\n}\n\n' + 'fn c2v_pointer_as[T](raw voidptr) &T {\n\tmut storage := C2vPointerStorage[T]{\n\t\traw: raw\n\t}\n\treturn unsafe { storage.value }\n}\n\n' + 'fn c2v_pointer_at[T](base &T, index isize) &T {\n\treturn c2v_pointer_as[T](unsafe { voidptr(usize(voidptr(base)) + usize(index) * usize(sizeof(T))) })\n}\n\n'
}

fn (mut c C2V) ensure_cpp_interface_runtime_helpers() {
	if c.is_dir {
		return
	}
	helper_key := 'cpp_interface_runtime_helpers:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << cpp_interface_runtime_helpers_source()
	}
}

fn (mut c C2V) v_abstract_interface_nil_literal(v_type string) string {
	c.ensure_cpp_interface_runtime_helpers()
	return 'c2v_nil_interface[${v_type.trim_space()}]()'
}

fn normalize_cpp_template_enum_arguments(type_name string, enum_values map[string]i64) string {
	if !type_name.contains('<') || enum_values.len == 0 {
		return type_name
	}
	mut out := strings.new_builder(type_name.len)
	mut angle_depth := 0
	mut i := 0
	for i < type_name.len {
		ch := type_name[i]
		if ch == `<` {
			angle_depth++
			out.write_u8(ch)
			i++
			continue
		}
		if ch == `>` {
			angle_depth--
			out.write_u8(ch)
			i++
			continue
		}
		is_identifier_start := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch == `_`
		if angle_depth > 0 && is_identifier_start {
			mut end := i + 1
			for end < type_name.len {
				part := type_name[end]
				if !((part >= `a` && part <= `z`) || (part >= `A` && part <= `Z`)
					|| (part >= `0` && part <= `9`) || part == `_`) {
					break
				}
				end++
			}
			token := type_name[i..end]
			if value := enum_values[token] {
				if i < 2 || type_name[i - 2..i] != '::' {
					out.write_string(value.str())
					i = end
					continue
				}
			}
			out.write_string(token)
			i = end
			continue
		}
		out.write_u8(ch)
		i++
	}
	return out.str()
}

fn node_contains_owned_tag_id(node &Node, tag_id string) bool {
	if tag_id == '' {
		return false
	}
	if node.owned_tag_decl.id == tag_id {
		return true
	}
	for child in node.inner {
		if node_contains_owned_tag_id(child, tag_id) {
			return true
		}
	}
	return false
}

fn (c &C2V) typedef_name_for_tag_id(tag_id string) string {
	for _, declaration in c.callback_seen_ids {
		if declaration.kindof(.typedef_decl) && declaration.name != ''
			&& node_contains_owned_tag_id(declaration, tag_id) {
			return declaration.name
		}
	}
	return ''
}

fn (mut c C2V) enum_decl(mut node Node) {
	// Hack: typedef with the actual enum name is next, parse it and generate "enum NAME {" first
	mut c_enum_name := node.name // ''
	mut v_enum_name := c_enum_name
	// A typedef'ed anonymous enum nested in a C++ class is represented as sibling
	// EnumDecl/TypedefDecl nodes, so the top-level lookahead below cannot see it.
	// Clang does retain the typedef-qualified name on every enum constant.
	if c_enum_name == '' {
		for child in node.inner {
			if child.kindof(.enum_constant_decl) && child.ast_type.qualified.contains('::') {
				candidate := child.ast_type.qualified.all_after_last('::').trim_space()
				if candidate != '' && !candidate.contains_any_substr(['(', ')', ' ', '<', '>']) {
					c_enum_name = candidate
					break
				}
			}
		}
		if c_enum_name == '' {
			c_enum_name = c.typedef_name_for_tag_id(node.id)
		}
	}
	is_top_level_enum := c.node_i >= 0 && c.node_i < c.tree.inner.len
		&& c.tree.inner[c.node_i].id == node.id
	if is_top_level_enum && c.tree.inner.len > c.node_i + 1 {
		next_node := c.tree.inner[c.node_i + 1]
		if next_node.kind == .typedef_decl && node_contains_owned_tag_id(&next_node, node.id) {
			c_enum_name = next_node.name
		}
	}
	if c_enum_name == 'boolean' {
		return
	}
	if c_enum_name == '' {
		// empty enum means it's just a list of #define'ed consts
		c.genln('\n// empty enum')
		c.genln('const (')
	} else {
		if c_enum_name in c.enums {
			mut known_vals := c.enum_vals[c_enum_name]
			for child in node.inner {
				if child.kind == .enum_constant_decl && child.name != ''
					&& child.name !in known_vals {
					known_vals << child.name
				}
			}
			c.enum_vals[c_enum_name] = known_vals
			return
		}
		v_enum_name =
			c.add_struct_name(mut c.enums, c_enum_name) // .capitalize().replace('Enum ', '')
		c.gen_comment(node)
		c.genln('enum ${v_enum_name} {')
	}
	mut vals := c.enum_vals[c_enum_name]
	mut current_val := i64(0) // track current enum value
	// A V enum with repeated values compiles `match` arms to C `switch` cases
	// that collide, so a constant repeating an earlier value is an alias of it.
	mut members_by_value := map[i64]string{}
	mut needs_explicit_val := false
	for mut child in node.inner {
		if child.kind != .enum_constant_decl {
			c.gen_comment(child)
			continue
		}
		c.gen_comment(child)
		c_name := child.name
		if c_name == '' {
			continue
		}
		mut v_name := filter_name(c_identifier_to_v_name(c_name), false)
		vals << c_name
		// empty enum means it's just a list of #define'ed consts
		if c_enum_name == '' && c_name in c.consts {
			current_val++
			continue
		}
		// handle custom enum vals, e.g. `MF_SHOOTABLE = 4`
		mut got_explicit_val := false
		if child.inner.len > 0 {
			const_expr := child.inner[0]
			ok, value := c.eval_const_numeric_expr(const_expr)
			if ok {
				current_val = value.as_i64()
				got_explicit_val = true
			} else if const_expr.kind == .constant_expr {
				// Preserve the older fallback for ASTs that do not expose a
				// directly evaluable expression value.
				current_val = c.get_enum_int_value(const_expr, current_val)
				got_explicit_val = true
			}
		}
		// Store this enum constant's value for future reference
		c.enum_int_vals[c_name] = current_val
		if c_enum_name != '' {
			if canonical := members_by_value[current_val] {
				c.enum_value_aliases[c_name] = canonical
				// The next implicit value follows this constant, not the V field
				// before it.
				needs_explicit_val = true
				current_val++
				continue
			}
			members_by_value[current_val] = c_name
			c.gen('\t' + v_name)
		} else {
			v_name = c.add_var_func_name(mut c.consts, c_name)
			c.gen('\t${v_name}')
		}
		if got_explicit_val || needs_explicit_val || c_enum_name == '' {
			// Anonymous enums (const blocks) always get an explicit value.
			c.gen(' = ${current_val}')
		}
		needs_explicit_val = false
		current_val++ // next enum value defaults to +1
		c.genln('')
	}
	if c_enum_name != '' {
		if vals.len == 0 {
			// V does not allow empty enums.
			c.genln('\t_dummy = 0')
		}
		vprintln('decl enum "${c_enum_name}" with ${vals.len} vals')
		c.enum_vals[c_enum_name] = vals
		c.genln('}\n')
	} else {
		c.genln(')\n')
	}
	if c_enum_name != '' {
		c.add_var_func_name(mut c.enums, c_enum_name)
	}
}

// get_enum_int_value extracts the integer value from a ConstantExpr node.
// V requires enum values to be integer literals, but C allows references to other enum constants.
fn (mut c C2V) get_enum_int_value(const_expr Node, default_val i64) i64 {
	ok, value := c.eval_const_numeric_expr(const_expr)
	if ok {
		return value.as_i64()
	}
	// Try to get value from the ConstantExpr itself
	val_str := const_expr.value.to_str()
	if val_str != '' {
		return val_str.i64()
	}
	// Look at the inner expression
	if const_expr.inner.len > 0 {
		inner := const_expr.inner[0]
		// Integer literal - return its value
		if inner.kindof(.integer_literal) {
			return inner.value.to_str().i64()
		}
		// Reference to another enum constant - look up its value
		if inner.kindof(.decl_ref_expr) {
			ref_name := inner.ref_declaration.name
			if ref_name in c.enum_int_vals {
				return c.enum_int_vals[ref_name]
			}
		}
		// Implicit cast - look deeper
		if inner.kindof(.implicit_cast_expr) && inner.inner.len > 0 {
			inner2 := inner.inner[0]
			if inner2.kindof(.decl_ref_expr) {
				ref_name := inner2.ref_declaration.name
				if ref_name in c.enum_int_vals {
					return c.enum_int_vals[ref_name]
				}
			}
		}
	}
	return default_val
}

struct ConstEvalValue {
	is_float bool
	i        i64
	f        f64
}

fn const_eval_int(i i64) ConstEvalValue {
	return ConstEvalValue{
		i: i
		f: f64(i)
	}
}

fn const_eval_float(f f64) ConstEvalValue {
	return ConstEvalValue{
		is_float: true
		i: i64(f)
		f: f
	}
}

fn (v ConstEvalValue) as_i64() i64 {
	if v.is_float {
		return i64(v.f)
	}
	return v.i
}

fn (v ConstEvalValue) as_f64() f64 {
	if v.is_float {
		return v.f
	}
	return f64(v.i)
}

fn is_v_integer_const_type(type_name string) bool {
	return type_name in ['int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize']
}

fn const_expr_needs_fold(node Node) bool {
	if node.kindof(.floating_literal) {
		return true
	}
	if node.kindof(.binary_operator) && node.opcode in ['<<', '>>'] {
		return true
	}
	for child in node.inner {
		if const_expr_needs_fold(child) {
			return true
		}
	}
	return false
}

fn const_expr_contains_sizeof(node Node) bool {
	if node.kindof(.unary_expr_or_type_trait_expr) && node.name == 'sizeof' {
		return true
	}
	for child in node.inner {
		if const_expr_contains_sizeof(child) {
			return true
		}
	}
	return false
}

fn sizeof_operand_type(node Node) string {
	if !node.kindof(.unary_expr_or_type_trait_expr) || node.name != 'sizeof' {
		return ''
	}
	if node.ast_argument_type.qualified != '' {
		return node.ast_argument_type.qualified
	}
	if node.inner.len > 0 {
		return node.inner[0].ast_type.qualified
	}
	return ''
}

fn c_array_base_and_count(type_name string) (string, i64, bool) {
	clean := type_name.replace('const ', '').replace(' volatile', '').trim_space()
	first_bracket := clean.index('[') or { return clean, i64(1), true }
	base := clean[..first_bracket].trim_space()
	mut rest := clean[first_bracket..]
	mut count := i64(1)
	for rest.starts_with('[') {
		close := rest.index(']') or { return '', i64(0), false }
		dimension := rest[1..close].trim_space()
		if dimension == '' || !dimension.bytes().all(it >= `0` && it <= `9`) {
			return '', i64(0), false
		}
		count *= dimension.i64()
		rest = rest[close + 1..].trim_space()
	}
	if rest != '' {
		return '', i64(0), false
	}
	return base, count, true
}

fn eval_sizeof_array_ratio(left Node, right Node) (bool, i64) {
	left_type := sizeof_operand_type(left)
	right_type := sizeof_operand_type(right)
	if left_type == '' || right_type == '' {
		return false, 0
	}
	left_base, left_count, left_ok := c_array_base_and_count(left_type)
	right_base, right_count, right_ok := c_array_base_and_count(right_type)
	if !left_ok || !right_ok || left_base != right_base || right_count == 0
		|| left_count % right_count != 0 {
		return false, 0
	}
	return true, left_count / right_count
}

fn (c &C2V) eval_const_numeric_expr(node Node) (bool, ConstEvalValue) {
	if node.kindof(.integer_literal) {
		return true, const_eval_int(node.value.to_str().i64())
	}
	if node.kindof(.floating_literal) {
		return true, const_eval_float(node.value.to_str().f64())
	}
	if node.kindof(.decl_ref_expr) {
		c_name := if node.ref_declaration.name != '' {
			node.ref_declaration.name
		} else {
			node.name
		}
		if c_name in c.enum_int_vals {
			return true, const_eval_int(c.enum_int_vals[c_name])
		}
		return false, ConstEvalValue{}
	}
	if node.kindof(.constant_expr) || node.kindof(.paren_expr) || node.kindof(.implicit_cast_expr) {
		if node.inner.len == 0 {
			return false, ConstEvalValue{}
		}
		ok, value := c.eval_const_numeric_expr(node.inner[0])
		if !ok {
			return false, ConstEvalValue{}
		}
		if node.kindof(.implicit_cast_expr) {
			if node.cast_kind == 'FloatingToIntegral' {
				return true, const_eval_int(value.as_i64())
			}
			if node.cast_kind == 'IntegralToFloating' {
				return true, const_eval_float(value.as_f64())
			}
		}
		return true, value
	}
	if node.kindof(.c_style_cast_expr) {
		if node.inner.len == 0 {
			return false, ConstEvalValue{}
		}
		ok, value := c.eval_const_numeric_expr(node.inner[0])
		if !ok {
			return false, ConstEvalValue{}
		}
		cast_type := c.convert_type(node.ast_type.qualified).name
		if node.cast_kind == 'FloatingToIntegral' || is_v_integer_const_type(cast_type) {
			return true, const_eval_int(value.as_i64())
		}
		if cast_type in ['f32', 'f64'] {
			return true, const_eval_float(value.as_f64())
		}
		return true, value
	}
	if node.kindof(.unary_operator) {
		if node.inner.len == 0 {
			return false, ConstEvalValue{}
		}
		ok, value := c.eval_const_numeric_expr(node.inner[0])
		if !ok {
			return false, ConstEvalValue{}
		}
		return match node.opcode {
			'+' {
				true, value
			}
			'-' {
				if value.is_float {
					true, const_eval_float(-value.f)
				} else {
					true, const_eval_int(-value.i)
				}
			}
			'~' {
				true, const_eval_int(~value.as_i64())
			}
			'!' {
				true, const_eval_int(if value.as_i64() == 0 { i64(1) } else { i64(0) })
			}
			else {
				false, ConstEvalValue{}
			}
		}
	}
	if node.kindof(.binary_operator) {
		if node.inner.len < 2 {
			return false, ConstEvalValue{}
		}
		if node.opcode == '/' {
			ok, ratio := eval_sizeof_array_ratio(node.inner[0], node.inner[1])
			if ok {
				return true, const_eval_int(ratio)
			}
		}
		ok_left, left := c.eval_const_numeric_expr(node.inner[0])
		ok_right, right := c.eval_const_numeric_expr(node.inner[1])
		if !ok_left || !ok_right {
			return false, ConstEvalValue{}
		}
		if left.is_float || right.is_float {
			l := left.as_f64()
			r := right.as_f64()
			return match node.opcode {
				'+' {
					true, const_eval_float(l + r)
				}
				'-' {
					true, const_eval_float(l - r)
				}
				'*' {
					true, const_eval_float(l * r)
				}
				'/' {
					if r == 0.0 {
						false, ConstEvalValue{}
					} else {
						true, const_eval_float(l / r)
					}
				}
				else {
					false, ConstEvalValue{}
				}
			}
		}
		l := left.i
		r := right.i
		return match node.opcode {
			'+' {
				true, const_eval_int(l + r)
			}
			'-' {
				true, const_eval_int(l - r)
			}
			'*' {
				true, const_eval_int(l * r)
			}
			'/' {
				if r == 0 {
					false, ConstEvalValue{}
				} else {
					true, const_eval_int(l / r)
				}
			}
			'%' {
				if r == 0 {
					false, ConstEvalValue{}
				} else {
					true, const_eval_int(l % r)
				}
			}
			'<<' {
				if r < 0 || r > 62 {
					false, ConstEvalValue{}
				} else {
					true, const_eval_int(l << int(r))
				}
			}
			'>>' {
				if r < 0 || r > 62 {
					false, ConstEvalValue{}
				} else {
					true, const_eval_int(l >> int(r))
				}
			}
			'|' {
				true, const_eval_int(l | r)
			}
			'&' {
				true, const_eval_int(l & r)
			}
			'^' {
				true, const_eval_int(l ^ r)
			}
			else {
				false, ConstEvalValue{}
			}
		}
	}
	return false, ConstEvalValue{}
}

fn (c &C2V) const_numeric_literal(node Node) (bool, string) {
	if !const_expr_needs_fold(node) && !const_expr_contains_sizeof(node) {
		return false, ''
	}
	ok, value := c.eval_const_numeric_expr(node)
	if !ok {
		return false, ''
	}
	if value.is_float {
		return true, value.f.str()
	}
	return true, value.i.str()
}

fn (mut c C2V) statements(mut compound_stmt Node) {
	is_function_body := c.indent == 0
	outer_declared := c.declared_local_vars.copy()
	outer_declared_types := c.declared_local_var_types.clone()
	c.indent++
	c.gen_comment(compound_stmt)
	// Each CompoundStmt's child is a statement
	for i, _ in compound_stmt.inner {
		c.statement(mut compound_stmt.inner[i])
		c.blank_line_after_switch(compound_stmt, i)
	}
	if is_function_body && c.cur_fn_ret_type != '' && compound_stmt.inner.len > 0 {
		last_statement := compound_stmt.inner[compound_stmt.inner.len - 1]
		if is_unconditional_c_for(last_statement) || c.is_unconditional_c_while(last_statement) {
			c.genln("panic('unreachable after C for (;;)')")
		}
	}
	c.indent--
	c.declared_local_vars = outer_declared
	c.declared_local_var_types = outer_declared_types.clone()
	c.genln('}')
}

// blank_line_after_switch keeps a switch/match block visually separated from the
// statement that follows it, matching the original c2v output style. The blank
// line is only emitted when the switch is not the last statement in its block.
fn (mut c C2V) blank_line_after_switch(compound_stmt Node, i int) {
	if i + 1 >= compound_stmt.inner.len {
		return
	}
	if compound_stmt.inner[i].kindof(.switch_stmt) {
		c.genln('')
	}
}

fn (mut c C2V) statements_no_rcbr(mut compound_stmt Node) {
	outer_declared := c.declared_local_vars.copy()
	outer_declared_types := c.declared_local_var_types.clone()
	c.gen_comment(compound_stmt)
	for i, _ in compound_stmt.inner {
		c.statement(mut compound_stmt.inner[i])
		c.blank_line_after_switch(compound_stmt, i)
	}
	c.declared_local_vars = outer_declared
	c.declared_local_var_types = outer_declared_types.clone()
}

// V does not support a standalone lexical block as a statement. Flatten C/C++
// blocks that are not attached to control flow and keep their declarations in
// the translated V scope. reserve_local_decl_v_name() will rename a later C
// declaration when two source blocks reuse the same identifier.
fn (mut c C2V) statements_flattened(mut compound_stmt Node) {
	c.gen_comment(compound_stmt)
	for i, _ in compound_stmt.inner {
		c.statement(mut compound_stmt.inner[i])
		c.blank_line_after_switch(compound_stmt, i)
	}
}

fn spelling_source_snippet(node Node) string {
	path := node.range.begin.spelling_file.path
	if path == '' || !os.exists(path) {
		return ''
	}
	start := node.range.begin.spelling_file.offset
	end_offset := node.range.end.spelling_file.offset
	if start < 0 || end_offset < start {
		return ''
	}
	source := os.read_file(path) or { return '' }
	end := if end_offset + 1 <= source.len { end_offset + 1 } else { source.len }
	if start >= source.len || end <= start {
		return ''
	}
	return source[start..end]
}

// node_source_snippet returns the source text of a node: its macro spelling
// when it came from a macro expansion, otherwise its own source range.
fn (c &C2V) node_source_snippet(node Node) string {
	spelled := spelling_source_snippet(node)
	if spelled != '' {
		return spelled
	}
	path := c.node_source_path(node)
	start := node.range.begin.offset
	end_offset := node.range.end.offset
	if path == '' || !os.exists(path) || start < 0 || end_offset < start {
		return ''
	}
	source := os.read_file(path) or { return '' }
	end := if end_offset + 1 <= source.len { end_offset + 1 } else { source.len }
	if start >= source.len || end <= start {
		return ''
	}
	return source[start..end]
}

// Operand-free inline assembly such as `__asm__ volatile("yield")` is a list of
// instructions for the target architecture; V's asm block expresses the same.
fn (mut c C2V) gen_known_gcc_asm(node Node) bool {
	snippet := c.node_source_snippet(node)
	open := snippet.index('"') or { return false }
	close := snippet.index_after('"', open + 1) or { return false }
	if close <= open {
		return false
	}
	// After the template come `: outputs : inputs : clobbers`. Clobbers such as
	// `::: "memory"` are allowed; output and input operands are not.
	sections := snippet[close + 1..].trim_space().all_before_last(')').split(':')
	has_operands := sections[0].trim_space() != ''
		|| (sections.len > 1 && sections[1].trim_space() != '')
		|| (sections.len > 2 && sections[2].trim_space() != '')
	if has_operands {
		return false
	}
	instructions := snippet[open + 1..close].replace('\\n', ';').replace('\\t', ' ').split(';').map(it.trim_space()).filter(it != '')
	arch := v_asm_target_arch()
	if instructions.len == 0 || arch == '' || instructions.any(it.contains('%')) {
		return false
	}
	c.genln('asm ${arch} {')
	for instruction in instructions {
		c.genln('\t${instruction}')
	}
	c.genln('}')
	return true
}

fn v_asm_target_arch() string {
	return match os.uname().machine {
		'arm64', 'aarch64' { 'arm64' }
		'x86_64', 'amd64' { 'amd64' }
		else { '' }
	}
}

fn (mut c C2V) statement(mut child Node) {
	c.gen_comment(child)
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
	} else if child.kindof(.compound_stmt) {
		// Just  { }
		c.statements_flattened(mut child)
	} else if child.kindof(.gcc_asm_stmt) {
		if c.gen_known_gcc_asm(child) {
			return
		}
		if c.project_require_no_stubs {
			c.verror('inline assembly is not translated in strict mode: ${c.cur_file}')
		}
		c.genln('__asm__') // TODO
	} else if child.kindof(.goto_stmt) {
		c.goto_stmt(child)
	} else if child.kindof(.label_stmt) {
		label := child.name // child.get_val(-1)
		c.labels[child.declaration_id] = child.name
		// c.genln('// RRRREG ${child.name} id=${child.declaration_id}')
		c.genln('${label}: ')
		c.statements_no_rcbr(mut child)
	} else if child.kindof(.cxx_for_range_stmt) {
		// C++
		c.for_range(child)
	} else {
		if is_noop_zero_expression(child) {
			return
		}
		c.expr(child)
		c.genln('')
	}
}

fn is_noop_zero_expression(node Node) bool {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.constant_expr) || current.kindof(.c_style_cast_expr)
			|| current.kindof(.cxx_static_cast_expr)
			|| current.kindof(.cxx_functional_cast_expr)) {
		current = current.inner[0]
	}
	if current.kindof(.conditional_operator) && current.inner.len > 0 {
		condition := current.inner[0]
		if condition.kindof(.implicit_cast_expr) && condition.inner.len > 0
			&& condition.inner[0].kindof(.call_expr) && condition.inner[0].inner.len > 0 {
			mut callee := condition.inner[0].inner[0]
			for callee.inner.len == 1 && callee.kindof(.implicit_cast_expr) {
				callee = callee.inner[0]
			}
			if callee.kindof(.decl_ref_expr) && callee.ref_declaration.name == '__builtin_expect' {
				return true
			}
		}
	}
	return current.kindof(.integer_literal) && current.value.to_str() == '0'
}

fn (mut c C2V) goto_stmt(node &Node) {
	mut label := c.labels[node.label_id]
	if label == '' {
		label = '_GOTO_PLACEHOLDER_' + node.label_id
	}
	c.genln('unsafe { goto ${label} }')
}

fn reference_return_lvalue(expr Node) (Node, bool) {
	mut current := expr
	for current.inner.len > 0 && (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
		|| current.kindof(.constant_expr)) {
		current = current.inner[0]
	}
	return current, current.kindof(.array_subscript_expr) || current.kindof(.member_expr)
		|| current.kindof(.decl_ref_expr)
}

fn (c &C2V) implicit_numeric_cast_will_render(node Node) bool {
	if !node.kindof(.implicit_cast_expr) || node.inner.len == 0 {
		return false
	}
	expr := node.inner[0]
	to_type := c.convert_type(node.ast_type.qualified).name
	from_type := c.convert_type(expr.ast_type.qualified).name
	resolved_to_type := c.resolve_type_alias(to_type)
	if ((c.is_dir
		&& node.cast_kind in ['IntegralCast', 'IntegralToFloating', 'FloatingToIntegral'])
		|| (node.cast_kind == 'FloatingCast' && !expr.kindof(.floating_literal)))
		&& to_type != from_type && resolved_to_type in v_primitive_type_names {
		return true
	}
	// File-mode fixtures still make an integer literal's floating type explicit.
	// Callers must not add a second cast around the implicit-cast expression.
	return expr.kindof(.integer_literal) && to_type in ['f32', 'f64']
}

fn (c &C2V) expr_renders_with_leading_unary_minus(node Node) bool {
	if node.kindof(.paren_expr) {
		return false
	}
	if node.kindof(.implicit_cast_expr) {
		if c.implicit_numeric_cast_will_render(node) || node.inner.len == 0 {
			return false
		}
		return c.expr_renders_with_leading_unary_minus(node.inner[0])
	}
	if node.kindof(.constant_expr) || node.kindof(.expr_with_cleanups)
		|| node.kindof(.materialize_temporary_expr) || node.kindof(.cxx_bind_temporary_expr) {
		return node.inner.len > 0 && c.expr_renders_with_leading_unary_minus(node.inner[0])
	}
	if node.kindof(.unary_operator) {
		if node.opcode == '-' {
			return true
		}
		return node.opcode == '+' && node.inner.len > 0
			&& c.expr_renders_with_leading_unary_minus(node.inner[0])
	}
	// Multiplication and other nested binary expressions render their leftmost
	// operand first, so `x - (-y * z)` otherwise becomes the invalid `x - -y * z`.
	return node.kindof(.binary_operator) && node.inner.len > 0
		&& c.expr_renders_with_leading_unary_minus(node.inner[0])
}

fn (mut c C2V) return_st(mut node Node) {
	old_inside_return_stmt := c.inside_return_stmt
	c.inside_return_stmt = true
	defer {
		c.inside_return_stmt = old_inside_return_stmt
	}
	if c.inside_main && node.inner.len > 0 && c.is_dir {
		c.gen('exit(')
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(expr)
		c.gen(')')
		return
	}
	// returning expression?
	if node.inner.len > 0 && !c.inside_main {
		mut expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		assignment := unwrap_condition_atom(expr)
		if assignment.kindof(.binary_operator) && assignment.opcode == '='
			&& assignment.inner.len >= 2 {
			mut lhs := assignment.inner[0]
			mut rhs := assignment.inner[1]
			c.gen_simple_assign(mut lhs, mut rhs)
			c.genln('')
			c.gen('return ')
			c.expr(lhs)
			return
		}
		cpp_lhs, cpp_rhs, is_cpp_assignment := cpp_assignment_expr_parts(expr)
		if is_cpp_assignment {
			mut lhs := cpp_lhs
			mut rhs := cpp_rhs
			c.gen_simple_assign(mut lhs, mut rhs)
			c.genln('')
			c.gen('return ')
			if !c.cur_fn_ret_type.starts_with('&') && c.cpp_expr_uses_reference_storage(lhs) {
				rendered := c.render_expr_to_string(lhs)
				c.gen('unsafe { *(${rendered}) }')
			} else {
				c.expr(lhs)
			}
			return
		}
		c.gen('return ')
		if expr.kindof(.implicit_cast_expr) {
			if expr.ast_type.qualified == 'bool' {
				// Handle `return 1` which is actually `return true`
				// TODO handle `return x == 2`
				c.returning_bool = true
			}
		}
		// Check if function returns int but expression is a comparison (returns bool in V)
		// C comparison operators return int (0 or 1), but V returns bool
		needs_int_cast := c.cur_fn_ret_type == 'int'
			&& (c.is_comparison_expr(expr) || node_references_function(expr, 'ftell'))
		numeric_types := ['i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize',
			'f32', 'f64']
		return_base_type := c.resolve_type_alias(c.cur_fn_ret_type)
		expr_v_type := c.prefix_external_type(c.convert_type(node_effective_type_name(expr)).name)
		expr_base_type := c.resolve_type_alias(expr_v_type)
		implicit_cast_inner_type := if expr.kindof(.implicit_cast_expr) && expr.inner.len > 0 {
			c.resolve_type_alias(c.prefix_external_type(c.convert_type(node_effective_type_name(expr.inner[0])).name))
		} else {
			''
		}
		implicit_cast_will_render := c.implicit_numeric_cast_will_render(expr)
		missing_outer_implicit_cast := expr.kindof(.implicit_cast_expr)
			&& expr.cast_kind in ['IntegralCast', 'IntegralToFloating', 'FloatingToIntegral',
				'FloatingCast'] && implicit_cast_inner_type in numeric_types
			&& implicit_cast_inner_type != return_base_type && !implicit_cast_will_render
		implicit_numeric_cast := !needs_int_cast && return_base_type in numeric_types
			&& ((expr_base_type in numeric_types && return_base_type != expr_base_type)
				|| missing_outer_implicit_cast)
		return_cast_type := if needs_int_cast {
			'int'
		} else if implicit_numeric_cast {
			c.cur_fn_ret_type
		} else {
			''
		}
		if return_cast_type != '' {
			c.gen('${return_cast_type}(')
		}
		if c.cur_fn_ret_type == '&i8' {
			if c.is_cpp && expr.value_category == 'lvalue'
				&& c.convert_type(expr.ast_type.qualified).name == 'i8' {
				was_inside_unsafe := c.inside_unsafe
				if !was_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('&')
				c.expr(expr)
				if !was_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
			} else if array_source := cpp_array_decay_source(&expr) {
				was_inside_unsafe := c.inside_unsafe
				if !was_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('&i8(&')
				c.expr(array_source)
				c.gen('[0])')
				if !was_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
			} else {
				c.expr(expr)
			}
		} else if c.cur_fn_ret_type.starts_with('&') {
			target, is_lvalue := reference_return_lvalue(expr)
			target_value_type := c.convert_type(target.ast_type.qualified).name
			array_decay_source := cpp_array_decay_source(&expr)
			if c.is_cpp && expr.kindof(.implicit_cast_expr)
				&& expr.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase'] {
				// C++ pointers and references implicitly convert from a derived object
				// to its base subobject. V embedding needs an explicit pointer cast.
				base_type := c.cur_fn_ret_type.trim_left('&').trim_space()
				c.gen('unsafe { &${base_type}(')
				if target.kindof(.unary_operator) && target.opcode == '*' && target.inner.len > 0 {
					c.expr(target.inner[0])
				} else {
					c.expr(target)
				}
				c.gen(') }')
			} else if array_source := array_decay_source {
				was_inside_unsafe := c.inside_unsafe
				if !was_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('&')
				c.expr(array_source)
				c.gen('[0]')
				if !was_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
			} else if is_lvalue && v_pointer_depth(c.cur_fn_ret_type) > v_pointer_depth(target_value_type) {
				was_inside_unsafe := c.inside_unsafe
				if !was_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('&')
				c.expr(target)
				if !was_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
			} else if target.kindof(.unary_operator) && target.opcode == '*' && target.inner.len > 0 {
				c.expr(target.inner[0])
			} else {
				c.expr(expr)
			}
		} else if c.is_cpp && c.cpp_expr_uses_reference_storage(expr)
			&& !(expr.kindof(.implicit_cast_expr) && expr.cast_kind == 'LValueToRValue'
				&& expr.inner.len > 0 && cpp_operator_call_returns_reference(expr.inner[0]))
			&& normalize_v_ptr_type(c.prefix_external_type(c.convert_type(node_effective_type_name(expr)).name)) == normalize_v_ptr_type(c.cur_fn_ret_type) {
			// A C++ function returning T copies a value selected through `const T&`.
			// Reference-returning operators are represented as V pointers, so perform
			// the copy explicitly at the return boundary.
			rendered := c.render_expr_to_string(expr)
			c.gen('unsafe { *(${rendered}) }')
		} else {
			c.expr(expr)
		}
		if return_cast_type != '' {
			c.gen(')')
		}
		c.returning_bool = false
		return
	}
	c.gen('return')
}

fn node_references_function(node &Node, function_name string) bool {
	if node.kindof(.decl_ref_expr) && node.ref_declaration.kind == .function_decl
		&& node.ref_declaration.name == function_name {
		return true
	}
	for child in node.inner {
		if node_references_function(child, function_name) {
			return true
		}
	}
	return false
}

// is_comparison_expr checks if an expression is a comparison that returns bool
fn (c &C2V) is_comparison_expr(node Node) bool {
	// Check direct binary comparison
	if node.kindof(.binary_operator) {
		return node.opcode in ['==', '!=', '<', '>', '<=', '>=', '&&', '||']
	}
	// Check through implicit cast
	if node.kindof(.implicit_cast_expr) && node.inner.len > 0 {
		return c.is_comparison_expr(node.inner[0])
	}
	return false
}

fn if_stmt_condition_needs_pre_cond(node Node) bool {
	if node.inner.len == 0 {
		return false
	}
	return expr_needs_pre_cond(node.inner[0])
}

fn expr_needs_pre_cond(node Node) bool {
	if node.kindof(.unary_operator) && node.opcode in ['++', '--'] && !node.is_postfix {
		return true
	}
	if (node.kindof(.binary_operator) && node.opcode == '=')
		|| node.kindof(.compound_assign_operator) {
		return true
	}
	for child in node.inner {
		if expr_needs_pre_cond(child) {
			return true
		}
	}
	for child in node.array_filler {
		if expr_needs_pre_cond(child) {
			return true
		}
	}
	return false
}

fn unwrap_condition_atom(node Node) Node {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
		current = current.inner[0]
	}
	return current
}

fn condition_decl_ref_c_name(node Node) string {
	current := unwrap_condition_atom(node)
	if !current.kindof(.decl_ref_expr) {
		return ''
	}
	if current.ref_declaration.name != '' {
		return current.ref_declaration.name
	}
	return current.name
}

fn (c &C2V) and_not_prefix_update_target(cond Node) (string, string) {
	current := unwrap_condition_atom(cond)
	if !current.kindof(.binary_operator) || current.opcode != '&&' || current.inner.len < 2 {
		return '', ''
	}
	left_name := condition_decl_ref_c_name(current.inner[0])
	if left_name == '' {
		return '', ''
	}
	mut right := unwrap_condition_atom(current.inner[1])
	if !right.kindof(.unary_operator) || right.opcode != '!' || right.inner.len == 0 {
		return '', ''
	}
	mut update := unwrap_condition_atom(right.inner[0])
	if !update.kindof(.unary_operator) || update.is_postfix || update.opcode !in ['++', '--'] || update.inner.len == 0 {
		return '', ''
	}
	target := unwrap_condition_atom(update.inner[0])
	target_name := condition_decl_ref_c_name(target)
	if target_name == '' || target_name != left_name {
		return '', ''
	}
	return c.decl_ref_v_name(target), update.opcode
}

fn (mut c C2V) if_statement(mut node Node) {
	expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.gen_comment(expr)
	if node.inner.len == 2 {
		target, update_op := c.and_not_prefix_update_target(expr)
		if target != '' {
			c.genln('if ${target} {')
			c.indent++
			c.genln('${target}${update_op}')
			c.gen('if !${target}')
			mut child := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			c.gen_comment(child)
			c.st_block(mut child)
			c.indent--
			c.genln('}')
			return
		}
	}
	// Clear pre-condition statements before processing condition
	c.pre_cond_stmts.clear()
	// First pass: just evaluate to collect any assignment-in-condition patterns
	old_cur_out := c.cur_out_line
	old_collecting_pre_cond := c.collecting_pre_cond
	c.cur_out_line = ''
	c.collecting_pre_cond = true
	c.gen('if ')
	c.gen_bool(expr)
	c.collecting_pre_cond = old_collecting_pre_cond
	cond_output := c.cur_out_line
	c.cur_out_line = old_cur_out
	// Output any collected pre-condition statements
	for stmt in c.pre_cond_stmts {
		c.genln(stmt)
	}
	c.pre_cond_stmts.clear()
	// Output the condition
	c.gen(cond_output)
	// Main if block
	mut child := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.gen_comment(child)
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
	c.gen_comment(else_st)
	if else_st.kindof(.compound_stmt) || else_st.kindof(.return_stmt) {
		c.put_on_same_line_as_close_brace('else {', true)
		c.st_block_no_start(mut else_st)
	} else if else_st.kindof(.if_stmt) {
		// else if
		if if_stmt_condition_needs_pre_cond(else_st) {
			c.put_on_same_line_as_close_brace('else {', true)
			c.if_statement(mut else_st)
			c.genln('\n}')
		} else {
			c.put_on_same_line_as_close_brace('', false)
			c.gen('else ')
			c.if_statement(mut else_st)
		}
	} else if !else_st.kindof(.bad) && !else_st.kindof(.null) {
		// `else expr() ;` else statement in one line without {}
		c.put_on_same_line_as_close_brace('else {', true)
		if else_st.kind in [.while_stmt, .goto_stmt, .switch_stmt, .gcc_asm_stmt, .label_stmt,
			.do_stmt, .for_stmt] {
			c.statement(mut else_st)
		} else {
			c.expr(else_st)
		}
		c.genln('\n}')
	}
}

fn (mut c C2V) while_st(mut node Node) {
	c.continue_labels << ''
	defer {
		c.continue_labels.delete_last()
	}
	expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	mut stmts := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	is_constant, constant_value := c.eval_const_numeric_expr(expr)
	if is_constant && constant_value.as_i64() != 0 {
		// Preserve an infinite C `while (1)` as V's unconditional loop form so
		// control-flow analysis knows a non-void function cannot fall through.
		c.genln('for {')
		c.st_block_no_start(mut stmts)
		return
	}
	if expr_needs_pre_cond(expr) {
		cond_output, pre_cond := c.render_condition_with_pre_cond(expr)
		c.genln('for {')
		c.indent++
		for stmt in pre_cond {
			c.genln(stmt)
		}
		c.genln('if !(${cond_output}) {')
		c.indent++
		c.genln('break')
		c.indent--
		c.genln('}')
		if stmts.kindof(.compound_stmt) {
			c.statements_no_rcbr(mut stmts)
		} else {
			c.statement(mut stmts)
		}
		c.indent--
		c.genln('}')
		return
	}
	c.gen('for ')
	c.gen_bool(expr)
	c.genln(' {')
	c.st_block_no_start(mut stmts)
}

fn is_unconditional_c_for(node &Node) bool {
	if !node.kindof(.for_stmt) || node.inner.len == 0 {
		return false
	}
	for i := 0; i < node.inner.len - 1; i++ {
		clause := node.inner[i]
		if clause.kind_str != '' && !clause.kindof(.null_stmt) {
			return false
		}
	}
	return true
}

fn (c &C2V) is_unconditional_c_while(node &Node) bool {
	if !node.kindof(.while_stmt) || node.inner.len == 0 {
		return false
	}
	is_constant, constant_value := c.eval_const_numeric_expr(node.inner[0])
	return is_constant && constant_value.as_i64() != 0
}

fn (mut c C2V) for_st(mut node Node) {
	// Clang represents every omitted clause in `for (;;) body` as an empty AST
	// child. Emit V's unconditional-loop form so its control-flow checker knows
	// that execution cannot fall through the loop.
	if is_unconditional_c_for(node) {
		mut body := node.inner[node.inner.len - 1]
		c.genln('for {')
		c.continue_labels << ''
		c.st_block_no_start(mut body)
		c.continue_labels.delete_last()
		return
	}
	outer_for_init_vars := c.for_init_vars.copy()
	c.for_init_vars.clear()
	c.inside_for = true
	mut use_while_style := false
	mut init := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.for_clause_root_id = init.id
	// A conditional expression becomes a V `if` expression, which V cannot
	// compile in a C-style loop header: emit such clauses as statements.
	post_clause := if node.inner.len >= 2 { node.inner[node.inner.len - 2] } else { bad_node }
	header_needs_statements := node_contains_kind(init, .conditional_operator)
		|| node_contains_kind(post_clause, .conditional_operator)
	// Can be "for (int i = ...)"
	if header_needs_statements && !init.kindof(.decl_stmt) {
		mut expr := init
		c.expr(expr)
		c.genln('')
		c.gen('for ')
		use_while_style = true
	} else if init.kindof(.decl_stmt) {
		mut decl_stmt := init
		// V allows a single init statement in C-style `for`.
		// When C has multiple declarations, emit them before the loop and keep init empty.
		if decl_stmt.inner.len > 1 || header_needs_statements {
			old_inside_for := c.inside_for
			c.inside_for = false
			c.var_decl(mut decl_stmt)
			c.inside_for = old_inside_for
			c.gen('for ')
			use_while_style = true
		} else {
			c.gen('for ')
			c.inside_for_init = true
			c.var_decl(mut decl_stmt)
			c.inside_for_init = false
		}
	} else {
		// Or "for (i = ....)"
		mut expr := init
		// Handle comma expressions: output all but last before "for", last in init
		if expr.kindof(.binary_operator) && expr.opcode == ',' {
			if !c.for_comma_init(mut expr) {
				use_while_style = true
			}
		} else if expr.kindof(.binary_operator) && expr.opcode == '=' && expr.inner.len >= 2 {
			// Handle chained assignments: for (i = j = 0; ...)
			// Output inner assignments before for, keep outermost in init
			second := expr.inner[1]
			// Check for chained assignment, possibly wrapped in ImplicitCastExpr
			mut is_chained := second.kindof(.binary_operator) && second.opcode == '='
			if !is_chained && second.kindof(.implicit_cast_expr) && second.inner.len > 0 {
				is_chained = second.inner[0].kindof(.binary_operator)
					&& second.inner[0].opcode == '='
			}
			if is_chained {
				if !c.for_chained_assign(mut expr) {
					use_while_style = true
				}
			} else {
				// Check if left side is a member access (this.field) which V doesn't allow in for init
				first := expr.inner[0]
				if first.kindof(.decl_ref_expr) {
					v_name := c.decl_ref_v_name(first)
					if c.for_init_assigns_existing_name(v_name) {
						c.gen('for ')
						c.expr(expr)
					} else {
						// Prefer `:=` in V for C-style loop init assignments.
						c.gen('for ')
						c.expr(first)
						c.gen(' := ')
						c.expr(second)
						c.for_init_vars.add(v_name)
					}
				} else if first.kindof(.member_expr) || c.expr_contains_deref(first) {
					c.expr(expr)
					c.genln('')
					c.gen('for ')
					use_while_style = true
				} else {
					c.gen('for ')
					c.expr(expr)
				}
			}
		} else {
			c.gen('for ')
			c.expr(expr)
		}
	}
	c.for_clause_root_id = ''
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
	mut condition_output := ''
	mut condition_pre := []string{}
	if !use_while_style {
		c.gen(' ; ')
		if expr_needs_pre_cond(expr2) {
			condition_output, condition_pre = c.render_condition_with_pre_cond(&expr2)
			c.gen('true')
		} else {
			c.expr(expr2)
		}
		c.gen(' ; ')
	}
	expr3 := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	c.for_clause_root_id = expr3.id
	// Check if the post-expression is a comma operator (e.g., i++, t += 100)
	// V doesn't support comma expressions, so split: keep first in for, add rest to body end
	mut extra_post_exprs := []&Node{}
	mut while_post_exprs := []&Node{}
	if use_while_style {
		if expr3.kindof(.binary_operator) && expr3.opcode == ',' && expr3.inner.len >= 2 {
			mut comma := unsafe { &expr3 }
			for comma.kindof(.binary_operator) && comma.opcode == ',' && comma.inner.len >= 2 {
				extra_post_exprs << unsafe { &comma.inner[1] }
				comma = unsafe { &comma.inner[0] }
			}
			while_post_exprs << comma
			for i := extra_post_exprs.len - 1; i >= 0; i-- {
				while_post_exprs << extra_post_exprs[i]
			}
			extra_post_exprs = []&Node{}
		} else if !expr3.kindof(.null_stmt) && expr3.kind_str != '' {
			while_post_exprs << unsafe { &expr3 }
		}
	} else {
		if expr3.kindof(.binary_operator) && expr3.opcode == ',' && expr3.inner.len >= 2 {
			mut comma := unsafe { &expr3 }
			// Collect all comma-separated expressions
			for comma.kindof(.binary_operator) && comma.opcode == ',' && comma.inner.len >= 2 {
				extra_post_exprs << unsafe { &comma.inner[1] }
				comma = unsafe { &comma.inner[0] }
			}
			c.for_clause_root_id = comma.id
			c.inside_for_post = true
			c.expr(comma)
			c.inside_for_post = false
		} else {
			c.inside_for_post = true
			c.expr(expr3)
			c.inside_for_post = false
		}
	}
	c.for_clause_root_id = ''
	c.inside_for = false
	mut child := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	// Post-statements emitted at the end of the V body must still run on
	// `continue`, which then jumps to them.
	posts_in_body := (use_while_style && while_post_exprs.len > 0) || extra_post_exprs.len > 0
	continue_label := if posts_in_body {
		c.continue_label_count++
		'c2v_for_next_${c.continue_label_count}'
	} else {
		''
	}
	c.continue_labels << continue_label
	defer {
		c.continue_labels.delete_last()
	}
	if use_while_style {
		if expr2.kindof(.null_stmt) || expr2.kind_str == '' {
			c.genln(' {')
		} else {
			c.gen_bool(expr2)
			c.genln(' {')
		}
		if child.kindof(.compound_stmt) {
			c.statements_no_rcbr(mut child)
		} else {
			c.statement(mut child)
		}
		c.gen_continue_label(continue_label)
		for post_expr in while_post_exprs {
			c.expr(post_expr)
			c.genln('')
		}
		c.genln('}')
		c.for_init_vars = outer_for_init_vars.copy()
		return
	}
	if condition_pre.len > 0 {
		// C and C++ permit assignments in a for-loop condition. V does not, so
		// retain the C-style init/post clauses and evaluate the condition at the
		// beginning of every iteration.
		c.genln(' {')
		for stmt in condition_pre {
			c.genln(stmt)
		}
		c.genln('if !(${condition_output}) {')
		c.genln('\tbreak')
		c.genln('}')
		if child.kindof(.compound_stmt) {
			c.statements_no_rcbr(mut child)
		} else {
			c.statement(mut child)
		}
		c.gen_continue_label(continue_label)
		for i := extra_post_exprs.len - 1; i >= 0; i-- {
			c.expr(extra_post_exprs[i])
			c.genln('')
		}
		c.genln('}')
	} else if extra_post_exprs.len > 0 {
		// Emit body with extra post expressions before closing brace
		c.genln(' {')
		if child.kindof(.compound_stmt) {
			c.statements_no_rcbr(mut child)
		} else {
			c.statement(mut child)
		}
		c.gen_continue_label(continue_label)
		// Output in reverse order since they were collected right-to-left
		for i := extra_post_exprs.len - 1; i >= 0; i-- {
			c.expr(extra_post_exprs[i])
			c.genln('')
		}
		c.genln('}')
	} else {
		c.st_block(mut child)
	}
	c.for_init_vars = outer_for_init_vars.copy()
}

fn is_cpp_lvalue_reference_decl(decl Node) bool {
	t := decl.ast_type.qualified.trim_space()
	return t.ends_with('&') && !t.ends_with('&&')
}

fn unwrap_cpp_reference_binding(node Node) Node {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.paren_expr) || current.kindof(.expr_with_cleanups)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind in ['NoOp', 'DerivedToBase',
			'UncheckedDerivedToBase'])) {
		current = current.inner[0]
	}
	return current
}

// cpp_reference_binding_needs_address reports whether a C++ reference is bound
// to an object that the translation holds by value (an array element, a field
// or a variable). Calls returning references and reference variables are V
// pointers already.
fn cpp_reference_binding_needs_address(init Node) bool {
	bound := unwrap_cpp_reference_binding(init)
	if bound.value_category != 'lvalue' {
		return false
	}
	if bound.kindof(.unary_operator) && bound.opcode == '*' {
		return true
	}
	if bound.kindof(.decl_ref_expr) {
		return !bound.ref_declaration.ast_type.qualified.trim_space().ends_with('&')
			&& bound.ref_declaration.kind in [.var_decl, .parm_var_decl]
	}
	return bound.kindof(.array_subscript_expr) || bound.kindof(.member_expr)
}

// is_v_object_type reports whether a V type holds a C++ object by value (a
// record, an array of them or an interface value). Such a local is declared
// `mut`: V only lets a method change an object reached through a chain of
// calls when the chain starts from a mutable variable.
fn (c &C2V) is_v_object_type(v_type string) bool {
	t := v_type.trim_space()
	if t == '' || t.starts_with('&') || t.starts_with('fn ') || t == 'voidptr' {
		return false
	}
	mut base := c.resolve_type_alias(t)
	for cpp_fixed_array_length(base) > 0 {
		base = cpp_fixed_array_element_type(base)
	}
	return base !in v_primitive_type_names && !base.starts_with('&') && !base.starts_with('fn ')
		&& base != 'voidptr' && base !in c.enums.values() && !base.starts_with('C.')
}

// this_pointer spells C++'s `this` pointer. A `mut` or value V receiver
// designates the object itself, a reference receiver its address.
fn (c &C2V) this_pointer() string {
	return if c.cur_receiver_is_ref { 'this' } else { '&this' }
}

// this_object spells C++'s `*this` (see this_pointer).
fn (c &C2V) this_object() string {
	return if !c.cur_receiver_is_ref {
		'this'
	} else if c.inside_unsafe {
		'*this'
	} else {
		'(unsafe { *this })'
	}
}

// is_constant_scalar_initializer reports whether an initializer consists of
// scalar compile-time constants only (literals, enum and V constants, and
// arithmetic on them, in nested arrays).
fn (c &C2V) is_constant_scalar_initializer(node Node) bool {
	if node.kindof(.init_list_expr) {
		if node.ast_type.qualified.contains('struct') || node.ast_type.qualified.contains('class')
			|| !node.ast_type.qualified.contains('[') {
			return false
		}
		return node.inner.all(c.is_constant_scalar_initializer(it))
			&& node.array_filler.all(c.is_constant_scalar_initializer(it))
	}
	if node.kindof(.implicit_value_init_expr) || node.kindof(.integer_literal)
		|| node.kindof(.floating_literal) || node.kindof(.character_literal)
		|| node.kindof(.cxx_bool_literal_expr) || node.kindof(.string_literal) {
		return true
	}
	if node.kindof(.implicit_cast_expr) || node.kindof(.paren_expr) || node.kindof(.constant_expr)
		|| node.kindof(.c_style_cast_expr) {
		return node.inner.len == 1 && node.inner[0].ast_type.qualified.contains('[') == false
			&& c.is_constant_scalar_initializer(node.inner[0])
	}
	if node.kindof(.unary_operator) && node.opcode in ['-', '+', '~', '!'] {
		return node.inner.len == 1 && c.is_constant_scalar_initializer(node.inner[0])
	}
	if node.kindof(.binary_operator) && node.opcode in ['+', '-', '*', '/', '%', '<<', '>>', '&',
		'|', '^'] {
		return node.inner.len == 2 && c.is_constant_scalar_initializer(node.inner[0])
			&& c.is_constant_scalar_initializer(node.inner[1])
	}
	if node.kindof(.decl_ref_expr) {
		return node.ref_declaration.kind == .enum_constant_decl
			|| node.ref_declaration.name in c.consts
	}
	return false
}

// collect_namespace_var_ids records the variables declared at namespace scope.
// A reference to one of them never names a static data member, even if a
// class has a static member with the same name.
fn collect_namespace_var_ids(nodes []Node, mut ids map[string]bool) {
	for node in nodes {
		if node.kind_str == 'VarDecl' && node.id != '' {
			ids[node.id] = true
		} else if node.kind_str in ['NamespaceDecl', 'LinkageSpecDecl'] {
			collect_namespace_var_ids(node.inner, mut ids)
		}
	}
}

// global_constructors_source runs the constructors of C++ global objects on the
// zero-initialized globals, in declaration order, once V has initialized all
// globals (as C++ dynamic initialization follows constant initialization).
fn (c &C2V) global_constructors_source(replacements map[string]string) string {
	if c.global_constructor_order.len == 0 {
		return ''
	}
	mut out := strings.new_builder(1024)
	out.writeln('fn init() {')
	for name in c.global_constructor_order {
		call := c.global_constructor_calls[name] or { continue }
		// (Concatenation: the pinned V miscompiles interpolation in this call.)
		out.writeln('\t' + replace_defined_global_refs_in_text(call, replacements))
	}
	out.writeln('}')
	out.writeln('')
	return out.str()
}

fn (mut c C2V) gen_continue_label(label string) {
	if label != '' && label in c.used_continue_labels {
		c.genln('${label}:')
	}
}

fn (c &C2V) decl_ref_v_name(node Node) string {
	if node.ref_declaration.id != '' {
		if local_name := c.local_decl_v_names[node.ref_declaration.id] {
			return local_name
		}
		if static_global_name := c.file_static_global_decl_v_names[node.ref_declaration.id] {
			return static_global_name
		}
		if function_name := c.cpp_function_decl_names[node.ref_declaration.id] {
			return function_name
		}
	}
	mut c_name := node.name
	if c_name == '' {
		c_name = node.ref_declaration.name
	}
	if c_name in c.external_c_fn_declarations {
		return 'C.${c_name}'
	}
	if node.ref_declaration.kind == .function_decl
		|| node.ref_declaration.kind == .enum_constant_decl {
		c_known_name := c_known_symbol_v_name(c_name)
		if c_known_name != '' && (node.ref_declaration.kind != .function_decl || !c.is_cpp
			|| c.function_ref_has_c_linkage(node.ref_declaration)) {
			return c_known_name
		}
		if node.ref_declaration.kind == .function_decl && c_name in c.extern_fns {
			return 'C.${c_name}'
		}
	}
	stream_name := c_stdio_stream_v_name(c_name)
	if stream_name != '' {
		return filter_name(stream_name, node.ref_declaration.kind == .var_decl)
	}
	if node.ref_declaration.kind == .var_decl {
		if static_name := c.static_local_vars[c_name] {
			return static_name
		}
		extern_global_name := c.extern_global_v_name(c_name)
		if extern_global_name != '' {
			return extern_global_name
		}
	}
	return filter_name(c_identifier_to_v_name(c_name), node.ref_declaration.kind == .var_decl)
}

fn is_recovery_ident_char(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
		|| (ch >= `0` && ch <= `9`) || ch == `_`
}

fn (c &C2V) source_snippet_for_node(node Node) string {
	if c.source_text == '' {
		return ''
	}
	mut start := node.range.begin.offset
	if start <= 0 {
		start = node.location.offset
	}
	if start < 0 || start >= c.source_text.len {
		return ''
	}
	mut end := node.range.end.offset
	if end < start {
		end = start
	}
	for end < c.source_text.len && is_recovery_ident_char(c.source_text[end]) {
		end++
	}
	if end <= start {
		return ''
	}
	return c.source_text[start..end].trim_space()
}

fn (c &C2V) translate_recovered_cpp_expr_text(text string) string {
	mut s := text.trim_space()
	if s == '' {
		return ''
	}
	s = s.replace('->', '.').replace('::', '.')
	mut out := ''
	mut token := ''
	for i := 0; i < s.len; i++ {
		ch := s[i]
		if is_recovery_ident_char(ch) {
			token += s[i..i + 1]
			continue
		}
		if token != '' {
			out += filter_name(c_identifier_to_v_name(token), false)
			token = ''
		}
		out += s[i..i + 1]
	}
	if token != '' {
		out += filter_name(c_identifier_to_v_name(token), false)
	}
	return out
}

fn (mut c C2V) recovery_expr(node Node) {
	if node.inner.len > 0 {
		// Clang often keeps the base object as a child even when member lookup failed.
		if node.inner.len == 1 && node.inner[0].kindof(.decl_ref_expr) {
			snippet := c.source_snippet_for_node(node)
			recovered := c.translate_recovered_cpp_expr_text(snippet)
			if recovered != '' {
				c.gen(recovered)
				return
			}
		}
		c.expr(node.inner[0])
		return
	}
	snippet := c.source_snippet_for_node(node)
	recovered := c.translate_recovered_cpp_expr_text(snippet)
	if recovered != '' {
		c.gen(recovered)
	}
}

fn is_enum_ref_expr(node Node) bool {
	mut current := node
	for {
		if current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.constant_expr) {
			if current.inner.len == 0 {
				return false
			}
			current = current.inner[0]
			continue
		}
		break
	}
	return current.kindof(.decl_ref_expr) && current.ref_declaration.kind == .enum_constant_decl
}

fn is_bool_expr(node Node) bool {
	mut current := node
	for {
		if current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr) {
			if current.kindof(.implicit_cast_expr)
				&& current.cast_kind in ['IntegralToBoolean', 'PointerToBoolean',
					'MemberPointerToBoolean'] {
				return true
			}
			if current.inner.len == 0 {
				return false
			}
			current = current.inner[0]
			continue
		}
		break
	}
	if current.ast_type.qualified in ['bool', '_Bool'] {
		return true
	}
	if current.kindof(.binary_operator) {
		return current.opcode in ['<', '>', '<=', '>=', '==', '!=', '&&', '||']
	}
	return current.kindof(.unary_operator) && current.opcode == '!'
}

fn is_v_small_integer_type(type_name string) bool {
	return type_name in ['i8', 'u8', 'i16', 'u16', 'bool']
}

fn (c &C2V) shift_lhs_needs_int_cast(node Node) bool {
	promoted_type := c.convert_type(node.ast_type.qualified).name
	unwrapped := c.unwrap_expr_for_deref_check(node)
	source_type := c.convert_type(unwrapped.ast_type.qualified).name
	return promoted_type == 'int' && is_v_small_integer_type(source_type)
}

fn (c &C2V) for_init_assigns_existing_name(v_name string) bool {
	return c.declared_local_vars.exists(v_name) || c.global_uses_v_name(v_name)
}

// Handle comma expressions in for loop init: for (a = 0, b = 0; ...)
// Returns true if a valid V init expression was emitted after `for`.
fn (mut c C2V) for_comma_init(mut node Node) bool {
	mut exprs := []Node{}
	c.collect_comma_exprs(mut node, mut exprs)
	// Output all but the last expression before "for"
	for i := 0; i < exprs.len - 1; i++ {
		c.expr(exprs[i])
		c.genln('')
	}
	// Output the last expression as the for loop init
	if exprs.len > 0 {
		last := exprs[exprs.len - 1]
		if last.kindof(.binary_operator) && last.opcode == '=' && last.inner.len >= 2
			&& last.inner[0].kindof(.decl_ref_expr) {
			v_name := c.decl_ref_v_name(last.inner[0])
			c.gen('for ')
			c.expr(last.inner[0])
			if c.for_init_assigns_existing_name(v_name) {
				c.gen(' = ')
			} else {
				c.gen(' := ')
				c.for_init_vars.add(v_name)
			}
			c.expr(last.inner[1])
			return true
		}
		// Fallback: keep init empty in V and move expression before the loop.
		c.expr(last)
		c.genln('')
		c.gen('for ')
		return false
	}
	c.gen('for ')
	return false
}

// Recursively collect all expressions from nested comma operators
fn (mut c C2V) collect_comma_exprs(mut node Node, mut exprs []Node) {
	if node.kindof(.binary_operator) && node.opcode == ',' {
		mut first := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			return
		}
		c.collect_comma_exprs(mut first, mut exprs)
		mut second := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			return
		}
		c.collect_comma_exprs(mut second, mut exprs)
	} else {
		exprs << node
	}
}

// Handle chained assignments in for loop init: for (i = j = 0; ...)
// Outputs inner assignments before "for", keeps outermost assignment in init
// Returns true if a valid V init expression was emitted after `for`.
fn (mut c C2V) for_chained_assign(mut node Node) bool {
	// Collect all chained assignments: i = j = k = 0 -> [(i, j), (j, k), (k, 0)]
	// Output all inner ones before for, use last value for outer in for init
	mut assigns := []Node{}
	mut values := []Node{}
	c.collect_chained_assigns(mut node, mut assigns, mut values)

	// Output inner assignments before for (skip the outermost)
	if values.len > 0 {
		final_value := values[values.len - 1]
		for i := 1; i < assigns.len; i++ {
			c.expr(assigns[i])
			c.gen(' = ')
			c.expr(final_value)
			c.genln('')
		}
	}

	if assigns.len > 0 && values.len > 0 {
		if assigns[0].kindof(.decl_ref_expr) {
			v_name := c.decl_ref_v_name(assigns[0])
			c.gen('for ')
			c.expr(assigns[0])
			if c.for_init_assigns_existing_name(v_name) {
				c.gen(' = ')
			} else {
				c.gen(' := ')
				c.for_init_vars.add(v_name)
			}
			c.expr(values[values.len - 1])
			return true
		}
		c.expr(assigns[0])
		c.gen(' = ')
		c.expr(values[values.len - 1])
		c.genln('')
		c.gen('for ')
		return false
	}
	c.gen('for ')
	return false
}

// Collect variables and final value from chained assignment
fn (mut c C2V) collect_chained_assigns(mut node Node, mut assigns []Node, mut values []Node) {
	if node.kindof(.binary_operator) && node.opcode == '=' && node.inner.len >= 2 {
		first := node.inner[0]
		assigns << first
		mut second := node.inner[1]
		// Unwrap ImplicitCastExpr that wraps chained assignments in C++
		if second.kindof(.implicit_cast_expr) && second.inner.len > 0
			&& second.inner[0].kindof(.binary_operator) && second.inner[0].opcode == '=' {
			second = second.inner[0]
		}
		if second.kindof(.binary_operator) && second.opcode == '=' {
			c.collect_chained_assigns(mut second, mut assigns, mut values)
		} else {
			values << second
		}
	}
}

// has_explicit_value_conversion reports whether an explicit cast that changes
// the value's representation (e.g. `(void *)integer`) wraps the expression.
fn has_explicit_value_conversion(node Node) bool {
	mut cur := node
	for cur.inner.len > 0 {
		if cur.kindof(.c_style_cast_expr) || cur.kindof(.cxx_static_cast_expr)
			|| cur.kindof(.cxx_reinterpret_cast_expr) || cur.kindof(.cxx_functional_cast_expr) {
			if cur.cast_kind !in ['NoOp', 'BitCast', 'LValueToRValue'] {
				return true
			}
		} else if !cur.kindof(.implicit_cast_expr) && !cur.kindof(.paren_expr)
			&& !cur.kindof(.cxx_const_cast_expr) {
			return false
		}
		cur = cur.inner[0]
	}
	return false
}

fn (c &C2V) unwrap_expr_for_deref_check(node Node) Node {
	mut cur := node
	for {
		if cur.kindof(.implicit_cast_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		if cur.kindof(.paren_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		if cur.kindof(.c_style_cast_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		if cur.kindof(.cxx_static_cast_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		if cur.kindof(.cxx_reinterpret_cast_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		if cur.kindof(.cxx_const_cast_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		if cur.kindof(.cxx_dynamic_cast_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		if cur.kindof(.cxx_functional_cast_expr) && cur.inner.len > 0 {
			cur = cur.inner[0]
			continue
		}
		break
	}
	return cur
}

fn (c &C2V) expr_contains_deref(node Node) bool {
	cur := c.unwrap_expr_for_deref_check(node)
	if cur.kindof(.unary_operator) && cur.opcode == '*' {
		// `(*this)[i]` is emitted as `this.op_index(i)`: the receiver dereference
		// disappears in V and must not force an outer unsafe assignment wrapper.
		if is_cpp_dereferenced_this_expr(&cur) {
			return false
		}
		return true
	}
	for child in cur.inner {
		if c.expr_contains_deref(child) {
			return true
		}
	}
	return false
}

fn (mut c C2V) gen_assign_rhs_deref_no_parens(mut node Node) bool {
	if c.inside_sizeof || has_explicit_value_conversion(node) {
		return false
	}
	mut cur := c.unwrap_expr_for_deref_check(node)
	if !cur.kindof(.unary_operator) || cur.opcode != '*' || cur.inner.len == 0 {
		return false
	}
	if c.is_cpp && is_cpp_dereferenced_this_expr(&cur) {
		c.gen(c.this_object())
		return true
	}
	mut ptr_expr := cur.inner[0]
	if c.inside_unsafe {
		c.gen('*')
		c.expr(ptr_expr)
		return true
	}
	c.gen('unsafe { *')
	old_inside_unsafe := c.inside_unsafe
	c.inside_unsafe = true
	c.expr(ptr_expr)
	c.inside_unsafe = old_inside_unsafe
	c.gen(' }')
	return true
}

fn (mut c C2V) gen_simple_assign(mut first_expr Node, mut second_expr Node) {
	if reference_name := c.cpp_record_reference_lvalue_v_name(&first_expr) {
		old_inside_unsafe := c.inside_unsafe
		if !old_inside_unsafe {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
		c.gen('*${reference_name} = ')
		if c.cpp_expr_uses_reference_storage(second_expr) {
			c.gen('*')
			c.expr(second_expr)
		} else if !c.gen_assign_rhs_deref_no_parens(mut second_expr) {
			c.expr(second_expr)
		}
		if !old_inside_unsafe {
			c.inside_unsafe = false
			c.gen(' }')
		}
		return
	}
	if reference_name := c.cpp_primitive_reference_v_name(&first_expr) {
		old_inside_unsafe := c.inside_unsafe
		if !old_inside_unsafe {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
		c.gen('*${reference_name} = ')
		if !c.gen_assign_rhs_deref_no_parens(mut second_expr) {
			c.expr(second_expr)
		}
		if !old_inside_unsafe {
			c.inside_unsafe = false
			c.gen(' }')
		}
		return
	}
	if cpp_reference_operator_source(&first_expr) != none
		|| cpp_call_expr_returns_reference_value(first_expr) {
		old_inside_unsafe := c.inside_unsafe
		old_reference_lvalue := c.inside_cpp_reference_lvalue
		if !old_inside_unsafe {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
		c.gen('*(')
		c.inside_cpp_reference_lvalue = true
		c.expr(first_expr)
		c.inside_cpp_reference_lvalue = old_reference_lvalue
		c.gen(') = ')
		if !c.gen_assign_rhs_deref_no_parens(mut second_expr) {
			c.expr(second_expr)
		}
		if !old_inside_unsafe {
			c.inside_unsafe = false
			c.gen(' }')
		}
		return
	}
	rhs_postfix := c.unwrap_expr_for_deref_check(second_expr)
	if rhs_postfix.kindof(.unary_operator) && rhs_postfix.is_postfix
		&& rhs_postfix.opcode in ['++', '--'] && rhs_postfix.inner.len > 0 {
		// `dst = value++` assigns the old value and then updates value. V does not
		// accept postfix updates as expressions, so make the sequencing explicit.
		tmp_name := '__c2v_postfix_value_${c.expression_temp_id}'
		c.expression_temp_id++
		mut update_target := rhs_postfix.inner[0]
		c.gen('mut ${tmp_name} := ')
		c.expr(update_target)
		c.genln('')
		c.expr(rhs_postfix)
		c.genln('')
		c.expr(first_expr)
		c.gen(' = ${tmp_name}')
		return
	}
	// The legacy V checker used for translated C++ can mis-resolve a direct
	// member copy as a call to the containing record's `op_assign` overload.
	// Besides producing a spurious assignment-mismatch diagnostic, that makes
	// the RHS field or enum member appear unknown. An explicit lvalue store has
	// the same C++ semantics and keeps overload lookup out of this primitive
	// assignment path (selected C++ operator= calls are lowered before here).
	rhs_direct := c.unwrap_expr_for_deref_check(second_expr)
	lhs_direct := c.unwrap_expr_for_deref_check(first_expr)
	lhs_is_dereference := lhs_direct.kindof(.unary_operator) && lhs_direct.opcode == '*'
	rhs_is_enum_value := rhs_direct.kindof(.decl_ref_expr)
		&& c.enum_val_to_enum_name(rhs_direct.ref_declaration.name) != ''
	if c.is_cpp && !c.inside_for && !lhs_is_dereference
		&& (rhs_direct.kindof(.member_expr) || rhs_is_enum_value) {
		old_inside_unsafe := c.inside_unsafe
		if !old_inside_unsafe {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
		c.gen('*(&')
		c.expr(first_expr)
		c.gen(') = ')
		if !c.gen_assign_rhs_deref_no_parens(mut second_expr) {
			c.expr(second_expr)
		}
		if !old_inside_unsafe {
			c.inside_unsafe = false
			c.gen(' }')
		}
		return
	}
	// Check if this is an assignment to a dereferenced pointer.
	// The dereference may be wrapped in casts/parentheses.
	mut deref_expr := c.unwrap_expr_for_deref_check(first_expr)
	mut is_deref_assign := deref_expr.kindof(.unary_operator) && deref_expr.opcode == '*'
	mut deref_func_call := false
	mut lhs_contains_deref := false
	if !is_deref_assign {
		// Some casted lvalues are emitted as `(unsafe { *ptr })` expressions.
		// Use the inner `unsafe { *ptr }` directly on assignment LHS.
		old_cur_out := c.cur_out_line
		c.cur_out_line = ''
		mut lhs_preview := clone_cpp_operator_node(&first_expr)
		c.expr(lhs_preview)
		lhs_rendered := c.cur_out_line
		c.cur_out_line = old_cur_out
		if lhs_rendered.starts_with('(unsafe { *') && lhs_rendered.ends_with(' })') {
			c.gen(lhs_rendered.replace('(unsafe { *', 'unsafe { *').replace(' })', ' }'))
			c.gen(' = ')
			if !c.gen_assign_rhs_deref_no_parens(mut second_expr) {
				c.expr(second_expr)
			}
			return
		}
	}
	if is_deref_assign {
		if deref_expr.inner.len == 0 {
			is_deref_assign = false
		} else {
			// Get the pointer expression without the dereference wrapper.
			ptr_expr := deref_expr.inner[0]
			// Check if we're dereferencing a function call - V doesn't allow this on the left side.
			if ptr_expr.kindof(.call_expr) || (ptr_expr.kindof(.implicit_cast_expr)
				&& ptr_expr.inner.len > 0 && ptr_expr.inner[0].kindof(.call_expr)) {
				// Generate a temporary variable for the function result.
				deref_func_call = true
				c.genln('{')
				c.indent++
				c.gen('tmp := ')
				c.expr(ptr_expr)
				c.genln('')
				c.gen('unsafe { *tmp')
			} else {
				// For assignments to dereferenced pointers, wrap the entire assignment in unsafe.
				c.gen('unsafe { ')
				c.inside_unsafe = true
				c.gen('*')
				c.expr(ptr_expr)
			}
		}
	}
	if !is_deref_assign {
		lhs_contains_deref = c.expr_contains_deref(first_expr)
		if lhs_contains_deref {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
	}
	if !is_deref_assign {
		c.expr(first_expr)
	}
	c.gen(' = ')
	lhs_v_type := c.prefix_external_type(c.convert_type(node_effective_type_name(first_expr)).name)
	if c.is_v_abstract_interface_type(lhs_v_type) && is_cpp_null_pointer_expression(second_expr) {
		c.gen(c.v_abstract_interface_nil_literal(lhs_v_type))
	} else if !c.gen_assign_rhs_deref_no_parens(mut second_expr) {
		c.expr(second_expr)
	}
	if is_deref_assign {
		if !deref_func_call {
			c.inside_unsafe = false
		}
		c.gen(' }')
		if deref_func_call {
			c.indent--
			c.genln('')
			c.gen('}')
		}
	} else if lhs_contains_deref {
		c.inside_unsafe = false
		c.gen(' }')
	}
}

fn (mut c C2V) do_st(mut node Node) {
	c.continue_labels << ''
	defer {
		c.continue_labels.delete_last()
	}
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

fn switch_enum_expr_source(node Node) Node {
	mut current := node
	for current.inner.len == 1 {
		if current.kindof(.constant_expr) || current.kindof(.paren_expr) {
			current = current.inner[0]
			continue
		}
		if current.kindof(.implicit_cast_expr)
			&& current.cast_kind in ['IntegralCast', 'LValueToRValue', 'NoOp'] {
			current = current.inner[0]
			continue
		}
		break
	}
	return current
}

fn switch_labeled_statement(node Node) ?Node {
	mut current := node
	for current.kindof(.case_stmt) || current.kindof(.default_stmt) {
		start_i := if current.kindof(.case_stmt) { 1 } else { 0 }
		mut found := false
		for i := start_i; i < current.inner.len; i++ {
			if current.inner[i].kindof(.null) {
				continue
			}
			current = current.inner[i]
			found = true
			break
		}
		if !found {
			return none
		}
	}
	return current
}

fn switch_statement_falls_through(node Node) bool {
	if node.kindof(.case_stmt) || node.kindof(.default_stmt) {
		if statement := switch_labeled_statement(node) {
			return switch_statement_falls_through(statement)
		}
		return true
	}
	if node.kindof(.return_stmt) || node.kindof(.break_stmt) || node.kindof(.continue_stmt)
		|| node.kindof(.goto_stmt) {
		return false
	}
	if node.kindof(.compound_stmt) && node.inner.len > 0 {
		return switch_statement_falls_through(node.inner.last())
	}
	return true
}

fn (mut c C2V) gen_switch_case_expr(case_expr Node, is_enum bool) {
	if is_enum {
		enum_case_expr := switch_enum_expr_source(case_expr)
		c.expr(enum_case_expr)
	} else if node_contains_kind(case_expr, .character_literal) {
		// C/C++ applies integral promotion to a switch operand. V character
		// literals are runes, so explicitly match their promoted integer value.
		c.gen('int(')
		c.expr(case_expr)
		c.gen(')')
	} else {
		c.expr(case_expr)
	}
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
		c.gen_switch_case_expr(case_expr, is_enum)
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
			c.genln(' {')
			c.genln('// case comp stmt')
			c.inside_switch_enum = false
			c.statements_no_rcbr(mut a)
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
				c.gen_switch_case_expr(e, is_enum)
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
			c.genln(' {')
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
			// Case falls through to default (e.g. case X: default: break;)
			// Just close the arm; the default body is handled by switch_st
			c.genln(' {')
			c.inside_switch_enum = false
		} else {
			// case body
			c.inside_switch_enum = false
			c.genln(' { // case comp body kind=${a.kind} is_enum=${is_enum}')
			c.statement(mut a)
			if a.kindof(.return_stmt) {
			} else if a.kindof(.break_stmt) {
				return true
			}
		}
	}
	return false
}

fn switch_case_enum_constant_name(node Node) string {
	if node.kindof(.case_stmt) && node.inner.len > 0 {
		mut expr := node.inner[0]
		for expr.inner.len > 0 && (expr.kindof(.constant_expr) || expr.kindof(.implicit_cast_expr)
			|| expr.kindof(.paren_expr)) {
			expr = expr.inner[0]
		}
		if expr.kindof(.decl_ref_expr) && expr.ref_declaration.kind == .enum_constant_decl {
			return expr.ref_declaration.name
		}
	}
	for child in node.inner {
		name := switch_case_enum_constant_name(child)
		if name != '' {
			return name
		}
	}
	return ''
}

fn switch_has_character_case(node Node) bool {
	if node.kindof(.case_stmt) && node.inner.len > 0
		&& node_contains_kind(node.inner[0], .character_literal) {
		return true
	}
	for child in node.inner {
		if switch_has_character_case(child) {
			return true
		}
	}
	return false
}

fn flatten_nested_switch_labels(mut compound Node) {
	mut expanded := []Node{}
	for child_idx := 0; child_idx < compound.inner.len; child_idx++ {
		mut child := &compound.inner[child_idx]
		if !child.kindof(.case_stmt) {
			expanded << compound.inner[child_idx]
			continue
		}
		mut body_idx := -1
		for i, part in child.inner {
			if part.kindof(.compound_stmt) {
				body_idx = i
				break
			}
		}
		if body_idx < 0 {
			expanded << compound.inner[child_idx]
			continue
		}
		mut body := &child.inner[body_idx]
		mut nested_label_idx := -1
		for i, statement_node in body.inner {
			if statement_node.kindof(.case_stmt) || statement_node.kindof(.default_stmt) {
				nested_label_idx = i
				break
			}
		}
		if nested_label_idx < 0 {
			expanded << compound.inner[child_idx]
			continue
		}
		trailing := body.inner[nested_label_idx..].clone()
		body.inner = body.inner[..nested_label_idx].clone()
		expanded << compound.inner[child_idx]
		expanded << trailing
	}
	compound.inner = expanded
}

// `case A: case B: default: body` is `default: body`: duplicate case values are
// invalid, so no other arm matches A or B and V's `else` arm covers them.
fn switch_case_chain_default(node Node) ?Node {
	if !node.kindof(.case_stmt) {
		return none
	}
	mut current := node
	for current.kindof(.case_stmt) && current.inner.len > 0 {
		current = current.inner.last()
	}
	if current.kindof(.default_stmt) {
		return current
	}
	return none
}

// Switch statements are a mess in C...
fn (mut c C2V) switch_st(mut switch_node Node) {
	c.inside_switch++
	mut expr := switch_node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	mut is_enum := false
	if expr.inner.len > 0 {
		x := expr.inner[0]
		x_type := c.convert_type(x.ast_type.qualified).name
		if x_type in v_primitive_type_names {
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
	flatten_nested_switch_labels(mut comp_stmt)
	for mut child in comp_stmt.inner {
		if default_label := switch_case_chain_default(child) {
			child = default_label
		}
	}
	// Find index of the first case/default statement.
	// C allows code before the first case in a switch, V doesn't.
	// Emit such pre-case statements before the match block.
	mut first_case_idx := comp_stmt.inner.len
	for i, child in comp_stmt.inner {
		if child.kindof(.case_stmt) || child.kindof(.default_stmt) {
			first_case_idx = i
			break
		}
	}
	if first_case_idx > 0 {
		for j := 0; j < first_case_idx; j++ {
			mut pre_child := comp_stmt.inner[j]
			c.statement(mut pre_child)
		}
	}
	// A top-level binary switch expression must be grouped as a whole. Without
	// the extra pair, `match (a) ^ b {` is parsed as a call to `match` by V.
	mut switch_root := expr
	for switch_root.inner.len == 1
		&& (switch_root.kindof(.implicit_cast_expr) || switch_root.kindof(.paren_expr)
			|| switch_root.kindof(.constant_expr)) {
		switch_root = switch_root.inner[0]
	}
	wrap_switch_expression := switch_root.kindof(.binary_operator)
	// Now emit the match keyword
	c.gen(if wrap_switch_expression { 'match (' } else { 'match ' })
	// Detect if this switch statement runs on an enum (have to look at the first
	// value being compared). This means that the integer will have to be cast to this enum
	// in V.
	// switch (x) { case enum_val: ... }   ==>
	// match MyEnum(x) { .enum_val { ... } }
	// Don't cast if it's already an enum and not an int. Enum(enum) compiles, but still.
	mut second_par := false
	switch_enum_constant := switch_case_enum_constant_name(comp_stmt)
	if switch_enum_constant != '' {
		is_enum = true
		c.inside_switch_enum = true
		mut switch_value_expr := expr
		for switch_value_expr.inner.len > 0 && (switch_value_expr.kindof(.implicit_cast_expr)
			|| switch_value_expr.kindof(.paren_expr)
			|| switch_value_expr.kindof(.constant_expr)) {
			switch_value_expr = switch_value_expr.inner[0]
		}
		expr_type := c.convert_type(switch_value_expr.ast_type.qualified).name
		if is_cpp_operator_primitive_type(expr_type) {
			enum_name := c.enum_val_to_enum_name(switch_enum_constant)
			// Enum constants from system headers do not have a translated V enum.
			// Compare them through C's promoted integer type.
			if enum_name == '' && c.is_system_enum_constant(switch_enum_constant) {
				c.gen('int')
			} else {
				c.gen(enum_name)
			}
			c.gen('(')
			second_par = true
		}
	} else if first_case_idx < comp_stmt.inner.len {
		mut child := comp_stmt.inner[first_case_idx]
		if child.kindof(.case_stmt) {
			mut case_expr := child.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			if case_expr.kindof(.constant_expr) {
				mut x := case_expr.try_get_next_child() or {
					println(add_place_data_to_error(err))
					bad_node
				}
				vprintln('YEP')
				// Unwrap ImplicitCastExpr to find the DeclRefExpr for enum detection
				for {
					if !(x.kindof(.implicit_cast_expr) && x.inner.len > 0) {
						break
					}
					x = x.inner[0]
				}

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
	mut emitted_switch_expr := expr
	if is_enum {
		candidate := switch_enum_expr_source(expr)
		candidate_type := c.convert_type(candidate.ast_type.qualified).name
		if candidate_type !in v_primitive_type_names {
			emitted_switch_expr = candidate
		}
	}
	promote_character_switch := !is_enum && switch_has_character_case(comp_stmt)
	if promote_character_switch {
		c.gen('int(')
	}
	// Short `.value` enum syntax is only valid in the case labels (see case_st).
	c.inside_switch_enum = false
	c.expr(emitted_switch_expr)
	if promote_character_switch {
		c.gen(')')
	}
	if is_enum {
	}
	if second_par {
		c.gen(')')
	}
	if wrap_switch_expression {
		c.gen(')')
	}
	c.genln(' {')
	mut default_node := bad_node
	mut default_fallthrough_case := bad_node
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
	mut in_default_body := false
	mut default_body_nodes := []&Node{}
	for i, mut child in comp_stmt.inner {
		if i < first_case_idx {
			continue // already emitted pre-case statements
		}
		c.gen_comment(child)
		if child.kindof(.case_stmt) {
			if got_else && default_fallthrough_case == bad_node {
				default_fallthrough_case = clone_cpp_operator_node(&child)
			}
			in_default_body = false // stop collecting default body siblings
			if has_case {
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
			in_default_body = true
		} else {
			if in_default_body {
				// This sibling belongs to the default/else body, collect it
				default_body_nodes << unsafe { &comp_stmt.inner[i] }
			} else {
				// handle weird children-siblings (part of current case arm body)
				c.inside_switch_enum = false
				c.statement(mut child)
			}
		}
	}
	if got_else {
		if has_case {
			c.genln('}')
		}
		if default_node != bad_node {
			if default_node.kindof(.case_stmt) {
				c.case_st(mut default_node, is_enum)
				// Statements after `default: case X: first_statement` are siblings in
				// Clang's AST, but belong to both the explicit case and the default arm.
				for default_sibling in default_body_nodes {
					mut case_sibling := clone_cpp_operator_node(default_sibling)
					c.statement(mut case_sibling)
				}
				c.genln('}')
			}
		}
		c.genln('else {')
		if default_node != bad_node {
			if default_node.kindof(.case_stmt) {
				// `default: case X: body` gives both labels the same body in C/C++.
				// The case arm was emitted above; duplicate its statement for V's else arm.
				if default_body := switch_labeled_statement(default_node) {
					mut body := clone_cpp_operator_node(&default_body)
					c.statement(mut body)
				}
			} else {
				c.statement(mut default_node)
			}
		}
		// Emit collected default body sibling statements
		for dnode in default_body_nodes {
			mut else_sibling := clone_cpp_operator_node(dnode)
			c.statement(mut else_sibling)
		}
		mut default_can_fall_through := switch_statement_falls_through(default_node)
		for dnode in default_body_nodes {
			if !switch_statement_falls_through(dnode) {
				default_can_fall_through = false
			}
		}
		if default_can_fall_through && default_fallthrough_case != bad_node {
			if fallthrough_body := switch_labeled_statement(default_fallthrough_case) {
				mut body := clone_cpp_operator_node(&fallthrough_body)
				c.statement(mut body)
			}
		}
		c.genln('}')
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
	c.gen_comment(node)
	c.st_block2(mut node, false)
}

fn (mut c C2V) st_block(mut node Node) {
	c.gen_comment(node)
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

fn (c &C2V) is_pointer_ast_type(type_name string) bool {
	if type_name == '' {
		return false
	}
	v_type := c.convert_type(type_name).name
	return v_type.starts_with('&') || v_type == 'voidptr'
}

fn (c &C2V) should_compare_ptr_cond_to_nil(node &Node) bool {
	if is_bool_expr(*node) || c.is_comparison_expr(*node) {
		return false
	}
	if !c.expr_contains_deref(*node) {
		return false
	}
	if c.is_pointer_ast_type(node.ast_type.qualified) {
		return true
	}
	unwrapped := c.unwrap_expr_for_deref_check(*node)
	return c.is_pointer_ast_type(unwrapped.ast_type.qualified)
}

fn (mut c C2V) gen_bool(node &Node) {
	if c.should_compare_ptr_cond_to_nil(node) {
		if c.expr_contains_deref(*node) && !c.inside_unsafe {
			c.gen('unsafe { ')
			old_inside_unsafe := c.inside_unsafe
			c.inside_unsafe = true
			c.expr(node)
			c.inside_unsafe = old_inside_unsafe
			c.gen(' != nil }')
		} else {
			c.expr(node)
			c.gen(' != nil')
		}
		return
	}
	c.expr(node)
}

fn (mut c C2V) render_condition_with_pre_cond(expr &Node) (string, []string) {
	c.pre_cond_stmts.clear()
	old_cur_out := c.cur_out_line
	old_collecting_pre_cond := c.collecting_pre_cond
	c.cur_out_line = ''
	c.collecting_pre_cond = true
	c.gen_bool(expr)
	c.collecting_pre_cond = old_collecting_pre_cond
	cond_output := c.cur_out_line
	c.cur_out_line = old_cur_out
	pre_cond := c.pre_cond_stmts.clone()
	c.pre_cond_stmts.clear()
	return cond_output, pre_cond
}

fn (c &C2V) extern_global_v_name(c_name string) string {
	global := c.globals[c_name] or { return '' }
	if !global.is_extern {
		return ''
	}
	return c_global_decl_v_name(c_name, true)
}

fn c_global_decl_v_name(c_name string, is_extern bool) string {
	if is_extern && filter_name(c_identifier_to_v_name(c_name), true) != c_name {
		return 'C.${c_name}'
	}
	return filter_name(c_name, true)
}

fn (c &C2V) file_static_global_v_name(c_name string) string {
	stem := os.file_name(c.cur_file).all_before_last('.')
	parent := os.file_name(os.dir(c.cur_file))
	return filter_name(c_identifier_to_v_name('${parent}_${stem}_${c_name}'), true)
}

fn (c &C2V) has_extern_global_decl(c_name string, var_decl Node) bool {
	if var_decl.previous_declaration != '' {
		if pnode := c.seen_ids[var_decl.previous_declaration] {
			if pnode.kindof(.var_decl) && pnode.class_modifier == 'extern' {
				return true
			}
		}
	}
	for node in c.tree.inner {
		if node.id == var_decl.id {
			continue
		}
		if node.kindof(.var_decl) && node.name == c_name && node.class_modifier == 'extern' {
			return true
		}
	}
	return false
}

fn cpp_static_member_v_name(owner string, member string, _is_const bool) string {
	c_name := '${owner}_${member}'
	// Keep declarations, definitions, and cross-file references identical. A
	// mutable static member can be defined in a later translation unit, while a
	// header-only reference only sees its class declaration.
	return filter_name(c_identifier_to_v_name(c_name), true)
}

fn (mut c C2V) register_cpp_static_member_v_name(owner string, member string, is_const bool, decl_id string) {
	if owner == '' || member == '' {
		return
	}
	v_static_name := cpp_static_member_v_name(owner, member, is_const)
	if decl_id != '' {
		c.cpp_static_member_decl_names[decl_id] = v_static_name
	}
	if existing := c.cpp_static_member_v_names[member] {
		if existing != v_static_name {
			c.cpp_static_member_v_names.delete(member)
			c.cpp_ambiguous_static_members[member] = true
		}
	} else if member !in c.cpp_ambiguous_static_members {
		c.cpp_static_member_v_names[member] = v_static_name
	}
}

fn (mut c C2V) var_decl(mut decl_stmt Node) {
	for _ in 0 .. decl_stmt.inner.len {
		mut var_decl := decl_stmt.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.gen_comment(var_decl)
		if var_decl.is_nrvo && var_decl.id != '' {
			c.cpp_nrvo_vars[var_decl.id] = true
		}
		if var_decl.kindof(.record_decl) || var_decl.kindof(.cxx_record_decl) {
			// Clang keeps a function-local named record and the variable that uses it
			// in the same DeclStmt. V record declarations are module scoped, so emit
			// the layout now, capture it, and prepend it to this output file in save().
			// Keeping the layout map populated also lets aggregate initializers use
			// field names instead of silently degrading to positional output.
			start := c.out.len
			old_indent := c.indent
			c.indent = 0
			if var_decl.kindof(.cxx_record_decl) {
				if var_decl.name == '' {
					// C headers included from a C++ translation unit are represented as
					// CXXRecordDecl even for an anonymous `struct { ... } variable`.
					// Give that local record a deterministic name before hoisting it.
					anon_name := 'AnonStruct_${var_decl.location.line}_${var_decl.location.offset}'
					local_record := Node{
						...var_decl
						name: anon_name
					}
					c.last_declared_type_name = anon_name
					c.cxx_record_decl(&local_record)
				} else {
					c.cxx_record_decl(var_decl)
				}
			} else {
				c.record_decl(var_decl)
			}
			c.indent = old_indent
			local_decl := c.out.cut_to(start)
			if local_decl != '' && local_decl !in c.local_type_declarations {
				c.local_type_declarations << local_decl
			}
			continue
		}
		if var_decl.kindof(.enum_decl) {
			// C and C++ allow function-local enum declarations. V declarations are
			// module scoped, so hoist the enum (or anonymous enum constants) while
			// retaining the local variable that follows it in this DeclStmt.
			start := c.out.len
			old_indent := c.indent
			c.indent = 0
			mut local_enum := var_decl
			c.enum_decl(mut local_enum)
			c.indent = old_indent
			local_decl := c.out.cut_to(start)
			if local_decl != '' && local_decl !in c.local_type_declarations {
				c.local_type_declarations << local_decl
			}
			continue
		}
		if var_decl.kindof(.typedef_decl) {
			// Function-local typedefs share the same module-scope restriction as
			// their record declarations. Hoist the alias as well so later locals do
			// not refer to an undeclared typedef spelling.
			start := c.out.len
			old_indent := c.indent
			c.indent = 0
			c.typedef_decl(var_decl)
			c.indent = old_indent
			local_decl := c.out.cut_to(start)
			if local_decl != '' && local_decl !in c.local_type_declarations {
				c.local_type_declarations << local_decl
			}
			continue
		}
		if var_decl.class_modifier == 'extern' {
			eprintln('WARNING: local extern var skipped: ${var_decl.name} in ${c.cur_file}:${c.line_i}')
			return
		}
		if var_decl.name.trim_space() == '' {
			// Skip unnamed local declarations produced by clang for anonymous temporaries/types.
			continue
		}
		// cinit means we have an initialization together with var declaration:
		// `int a = 0;`
		// Clang distinguishes C-style `=` initialization (`c`) from direct
		// constructor initialization (`call`) and list initialization. All carry
		// the value expression as a VarDecl child and must be emitted here.
		cinit := var_decl.initialization_type != '' && var_decl.inner.len > 0
		v_name := c.reserve_local_decl_v_name(var_decl.id, var_decl.name)
		// Clang names concrete template specializations with canonical arguments.
		// Use that same spelling for locals so typedef arguments such as
		// `commandDef_t` resolve to the already emitted `commandDef_s` specialization.
		local_cpp_type := if var_decl.ast_type.qualified.contains('<') {
			node_effective_type_name(var_decl)
		} else {
			var_decl.ast_type.qualified
		}
		typ_ := if (local_cpp_type.contains('unnamed struct')
			|| local_cpp_type.contains('unnamed union') || local_cpp_type.contains('anonymous struct')
			|| local_cpp_type.contains('anonymous union') || local_cpp_type.contains('(unnamed at')
			|| local_cpp_type.contains('(anonymous at')) && c.last_declared_type_name != '' {
			c.convert_type(c.last_declared_type_name)
		} else {
			c.convert_type(local_cpp_type)
		}
		mut declared_typ_name := c.prefix_external_type(typ_.name)
		if c.declared_local_vars.exists('c2v_variadic_args') && c.current_fn_uses_va_arg
			&& (var_decl.ast_type.qualified in ['va_list', '__builtin_va_list', '__gnuc_va_list']
				|| var_decl.ast_type.desugared_qualified.contains('__va_list_tag')) {
			declared_typ_name = 'int'
		}
		if c.is_dir && var_decl.class_modifier == 'static' && c.current_fn_v_name != ''
			&& c.address_taken_locals[var_decl.name] {
			static_name := '${c.current_fn_v_name}_${v_name}'
			if var_decl.id != '' {
				c.local_decl_v_names[var_decl.id] = static_name
			}
			c.static_local_vars[var_decl.name] = static_name
			mut typ := declared_typ_name
			if typ == '' {
				typ = 'int'
			}
			start := c.out.len
			c.genln('@[weak] __global ${static_name} ${typ}\n')
			c.globals_out[static_name] = c.out.cut_to(start)
			if static_name !in c.defined_globals {
				c.defined_global_order << static_name
			}
			c.defined_globals[static_name] = true
			c.register_global_symbol(static_name, typ, false)
			if cinit {
				expr := var_decl.try_get_next_child() or {
					println(add_place_data_to_error(err))
					bad_node
				}
				init_name := '${static_name}_inited'
				init_start := c.out.len
				c.genln('@[weak] __global ${init_name} bool\n')
				c.globals_out[init_name] = c.out.cut_to(init_start)
				if init_name !in c.defined_globals {
					c.defined_global_order << init_name
				}
				c.defined_globals[init_name] = true
				c.register_global_symbol(init_name, 'bool', false)
				c.genln('if !${init_name} {')
				c.indent++
				c.gen('${static_name} = ')
				old_inside_global_init := c.inside_global_init
				old_global_struct_init := c.global_struct_init
				c.inside_global_init = true
				c.global_struct_init = typ
				c.expr(expr)
				c.inside_global_init = old_inside_global_init
				c.global_struct_init = old_global_struct_init
				c.genln('')
				c.genln('${init_name} = true')
				c.indent--
				c.genln('}')
			}
			continue
		}
		if typ_.is_static || var_decl.class_modifier == 'static' {
			c.gen('static ')
		}
		if cinit {
			expr := var_decl.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			// Use := for new declarations, = for redeclarations
			// inside_for: for loop init always creates new scope, so always use :=
			// Use = for redeclarations, := for new declarations.
			// For-init variables are scoped to the for loop, so they don't count
			// as outer declarations (tracked separately in for_init_vars).
			decl_op := if c.declared_local_vars.exists(v_name) { '=' } else { ':=' }
			if c.is_cpp && !c.inside_for && decl_op == ':=' && !(typ_.is_static
				|| var_decl.class_modifier == 'static') {
				construction := unwrap_cpp_reference_binding(expr)
				constructed_type := c.convert_type(node_effective_type_name(construction)).name
				// A local returned through NRVO is built in the caller's storage in
				// C++; without a copy constructor to run at the return, keep it off
				// the V stack (see is_cpp_elided_copy).
				nrvo_off_stack := var_decl.is_nrvo && !c.cpp_has_user_copy_constructor(constructed_type)
				if !nrvo_off_stack && cpp_fixed_array_length(declared_typ_name) == 0
					&& c.resolve_type_alias(constructed_type) == c.resolve_type_alias(declared_typ_name) {
					if init_name := c.cpp_user_constructor_init_name(&construction) {
						// C++ constructs a local object in place, so the constructor sees
						// its final address (e.g. to point at an inline buffer).
						c.genln('mut ${v_name} := ${declared_typ_name}{}')
						c.declared_local_vars.add(v_name)
						c.declared_local_var_types[v_name] = declared_typ_name
						c.gen_cpp_constructor_call_on(v_name, init_name, &construction)
						c.genln('')
						continue
					}
				}
			}
			mut_prefix := if decl_op == ':='
				&& (c.conditional_mutable_locals[var_decl.id]
					|| c.conditional_mutable_locals['name:${var_decl.name}']
					|| (c.is_cpp && c.is_v_object_type(declared_typ_name))) {
				'mut '
			} else {
				''
			}
			c.gen('${mut_prefix}${v_name} ${decl_op} ')
			if c.inside_for {
				c.for_init_vars.add(v_name)
			} else {
				c.declared_local_vars.add(v_name)
				c.declared_local_var_types[v_name] = declared_typ_name
			}
			initializer_base := unwrap_condition_atom(expr)
			initializer_v_type := c.prefix_external_type(c.convert_type(node_effective_type_name(expr)).name)
			if cpp_fixed_array_length(declared_typ_name) > 0
				&& (initializer_base.kindof(.cxx_construct_expr)
					|| is_zero_initializer_expr(expr)) {
				// Clang models default construction of a C++ object array as one
				// element CXXConstructExpr, while `T values[N] = {}` is an empty
				// InitListExpr. Preserve the declared array shape in both cases rather
				// than inferring a single object or letting the sanitizer reduce `[]!`
				// to scalar zero.
				c.gen('${declared_typ_name}{}')
			} else if !declared_typ_name.starts_with('&') && c.cpp_expr_uses_reference_storage(expr)
				&& c.cpp_primitive_reference_operator_source(&expr) == none
				&& c.cpp_primitive_reference_v_name(&initializer_base) == none
				&& !node_effective_type_name(expr).contains('*')
				&& normalize_v_ptr_type(initializer_v_type) == normalize_v_ptr_type(declared_typ_name) {
				// A C++ value initialized from `const T&` copies T. Reference-returning
				// calls and reference variables are V pointers, so dereference them at
				// the copy boundary instead of letting `:=` infer `&T`.
				rendered := c.render_expr_to_string(expr)
				c.gen('unsafe { *(${rendered}) }')
			} else if declared_typ_name == 'i8' && initializer_base.kindof(.character_literal) {
				// V infers backtick literals as rune. Preserve C/C++ `char` locals as
				// i8 so character overloads receive the right type.
				c.gen('i8(')
				c.expr(expr)
				c.gen(')')
			} else if declared_typ_name == 'f32' && (initializer_base.kindof(.floating_literal)
				|| initializer_base.kindof(.integer_literal)) {
				rendered := c.render_expr_to_string(expr)
				if rendered.trim_space().starts_with('f32(') {
					c.gen(rendered)
				} else {
					c.gen('f32(${rendered})')
				}
			} else if initializer_base.kindof(.integer_literal)
				&& declared_typ_name in ['u32', 'u64', 'usize']
				&& initializer_base.value.to_str().i64() > i64(2147483647) {
				// V initially infers a bare integer literal as `int`. Preserve the
				// declared unsigned width before inference rejects values above INT_MAX.
				c.gen('${declared_typ_name}(')
				c.expr(expr)
				c.gen(')')
			} else if c.resolve_type_alias(declared_typ_name).starts_with('fn (')
				&& is_cpp_null_pointer_expression(expr) {
				// A bare nil initializer would lose the function pointer type.
				c.gen('unsafe { ${declared_typ_name}(nil) }')
			} else if c.is_v_abstract_interface_type(declared_typ_name)
				&& is_cpp_null_pointer_expression(expr) {
				// A C++ abstract pointer is represented by the V interface descriptor
				// itself. Keep a null initializer typed as that interface so later
				// address-taking produces `&Interface`, not `&voidptr`.
				c.gen(c.v_abstract_interface_nil_literal(declared_typ_name))
			} else if declared_typ_name.starts_with('&') && c.is_cpp
				&& is_cpp_lvalue_reference_decl(var_decl)
				&& cpp_reference_binding_needs_address(expr) {
				// A C++ reference is the V address of the object it is bound to.
				if var_decl.id != '' && normalize_v_ptr_type(declared_typ_name) in v_primitive_type_names {
					// Reads and writes of a primitive reference go through the pointer.
					c.cpp_primitive_reference_decls[var_decl.id] = true
				}
				bound := unwrap_cpp_reference_binding(expr)
				if bound.kindof(.unary_operator) && bound.opcode == '*' && bound.inner.len == 1 {
					c.expr(bound.inner[0])
				} else {
					c.gen('unsafe { &')
					old_inside_unsafe := c.inside_unsafe
					c.inside_unsafe = true
					c.expr(bound)
					c.inside_unsafe = old_inside_unsafe
					c.gen(' }')
				}
			} else if declared_typ_name.starts_with('&') {
				if array_source := cpp_array_decay_source(&expr) {
					if !array_source.kindof(.string_literal) {
						c.gen('unsafe { ${declared_typ_name}(&')
						c.expr(array_source)
						c.gen('[0]) }')
					} else {
						c.expr(expr)
					}
				} else {
					rendered := c.render_expr_to_string(expr)
					if rendered.trim_space() in ['nil', 'unsafe { nil }'] {
						// Preserve the declared pointer type. A bare nil initializer is
						// inferred as `nil`, which loses both record methods and abstract
						// interface conformance on later assignments/calls.
						c.gen('unsafe { ${declared_typ_name}(nil) }')
					} else {
						c.gen(rendered)
					}
				}
			} else {
				c.expr(expr)
			}
			if decl_stmt.inner.len > 1 {
				c.gen('\n')
			}
		} else {
			oldtyp := var_decl.ast_type.qualified
			mut typ := typ_.name
			vprintln('oldtyp="${oldtyp}" typ="${typ}"')
			// Prefix external types with C.
			typ = declared_typ_name
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
			} else if c.resolve_type_alias(typ).starts_with('fn (') {
				def = c.skeleton_default_value(typ)
			} else if oldtyp.ends_with('*') {
				// *sqlite3_mutex ==>
				// &sqlite3_mutex{!}
				// println2('!!! $oldtyp $typ')
				// def = '&${typ.right(1)}{!}'
				tt := if typ.starts_with('&') { typ[1..] } else { typ }
				def = if c.cpp_abstract_types[tt] {
					// Abstract C++ classes are V interfaces. Casting integer zero to a
					// V interface triggers one diagnostic per method. The interface value
					// itself represents the first C++ pointer layer.
					if typ.starts_with('&') {
						'unsafe { nil }'
					} else {
						c.v_abstract_interface_nil_literal(tt)
					}
				} else {
					'&${tt}(0)'
				}
			} else if typ.starts_with('[') {
				// Empty array init
				def = '${typ}{}'
			} else {
				// We assume that everything else is a struct, because C AST doesn't
				// give us any info that typedef'ed structs are structs

				if c.resolve_type_alias(typ) in ['u8', 'u16', 'u32', 'u64', 'i8', 'i16', 'int',
					'i64', 'f32', 'f64', 'usize', 'isize', 'bool', 'voidptr'] {
					def = '${typ}(0)'
				} else {
					// Check if this is a type alias to a primitive type
					// V doesn't allow TypeAlias{} for primitive type aliases, use TypeAlias(0) instead
					underlying := c.resolve_type_alias(typ)
					if underlying in ['u8', 'u16', 'u32', 'u64', 'i8', 'i16', 'int', 'i64', 'f32',
						'f64', 'usize', 'isize', 'bool', 'voidptr'] {
						def = '${typ}(0)'
					} else {
						def = '${typ}{}'
					}
				}
			}
			// vector<int> => int => []int
			if typ.starts_with('vector<') {
				def = typ.substr('vector<'.len, typ.len - 1)
				def = '[]${def}'
			}
			decl_op2 := if c.declared_local_vars.exists(v_name) { '=' } else { ':=' }
			mut_prefix := if decl_op2 == ':='
				&& (c.conditional_mutable_locals[var_decl.id]
					|| c.conditional_mutable_locals['name:${var_decl.name}']) {
				'mut '
			} else {
				''
			}
			c.gen('${mut_prefix}${v_name} ${decl_op2} ${def}')
			if c.inside_for {
				c.for_init_vars.add(v_name)
			} else {
				c.declared_local_vars.add(v_name)
				c.declared_local_var_types[v_name] = typ
			}
			if decl_stmt.inner.len > 1 {
				c.genln('')
			}
		}
	}
}

fn (mut c C2V) global_var_decl(mut var_decl Node) {
	// if the global has children, that means it's initialized, parse the expression
	// but only if those children are actual init expressions, not just comments or attributes
	mut is_inited := false
	for child in var_decl.inner {
		if !child.kindof(.visibility_attr) && !child.kindof(.full_comment)
			&& !child.kindof(.record_decl) && !child.kindof(.cxx_record_decl)
			&& !child.kindof(.enum_decl) && !child.kindof(.typedef_decl) {
			is_inited = true
			break
		}
	}

	vprintln('\nglobal name=${var_decl.name} typ=${var_decl.ast_type.qualified}')
	vprintln(var_decl.str())

	mut c_name := var_decl.name
	original_c_name := c_name
	// v_name := filter_name(c_name, true).camel_to_snake()
	typ := c.convert_type(node_effective_type_name(var_decl))

	// In C++, static class members appear as top-level VarDecl nodes.
	// Prefix with the class name to avoid conflicts between classes.
	class_name := extract_class_from_mangled(var_decl.mangled_name)
	if class_name != '' {
		c_name = class_name + '_' + c_name
		c.register_cpp_static_member_v_name(class_name, original_c_name, typ.is_const, var_decl.id)
	} else if c.is_dir && var_decl.class_modifier == 'static' {
		// File-scope static symbols have translation-unit linkage. Flattening a
		// project into one V module must not merge identically named statics from
		// unrelated C/C++ files (for example the renderer and dmap `silEdges`).
		c_name = c.file_static_global_v_name(original_c_name)
		if var_decl.id != '' {
			c.file_static_global_decl_v_names[var_decl.id] = c_name
		}
	}

	if var_decl.ast_type.qualified.starts_with('[]') {
		return
	}
	global_v_type := c.prefix_external_type(typ.name)
	if c_name in c.globals {
		existing := c.globals[c_name]
		if !types_are_equal(c.resolve_type_alias(existing.typ), c.resolve_type_alias(typ.name)) {
			c.genln('// skipped conflicting global "${c_name}" typ="${typ.name}" existing="${existing.typ}"')
			return
		}
		// In directory mode a translation unit that does not use a global only
		// registers its symbol; a later unit that uses it must still define it.
		if !existing.is_extern && (!c.is_dir || c_name in c.globals_out) {
			c.genln('// skipping global dup "' + c_name + '"')
			return
		}
	}
	// Skip extern globals that are initialized later in the file.
	// We'll have go thru all top level nodes, find a VarDecl with the same name
	// and make sure it's inited (has a child expressinon).
	is_extern := var_decl.class_modifier == 'extern'
	if is_extern && !is_inited {
		for x in c.tree.inner {
			if x.kindof(.var_decl) && x.name == c_name && x.id != var_decl.id {
				if x.inner.len > 0 {
					return
				}
			}
		}
	}
	mut emitted_global_name := ''
	is_fixed_array := var_decl.ast_type.qualified.contains('[')
		&& var_decl.ast_type.qualified.contains(']')
	// In directory mode the matching extern declaration often came from a
	// different translation unit and is no longer present in the current AST.
	// Retain that project-wide linkage knowledge when the definition arrives.
	mut has_project_extern_decl := false
	if c.is_dir {
		if existing := c.globals[c_name] {
			has_project_extern_decl = existing.is_extern
		}
	}
	has_matching_extern_decl := c.has_extern_global_decl(c_name, var_decl)
		|| has_project_extern_decl
	// Namespace-scope `const` objects have internal linkage in C++ unless an
	// extern declaration gives them external linkage.
	has_external_linkage := !is_extern && var_decl.class_modifier != 'static' && !(c.is_cpp
		&& typ.is_const && !has_matching_extern_decl)
	is_mutable_fixed_array := is_fixed_array
		&& (has_matching_extern_decl || c_name in c_known_mutable_fixed_array_global_names)
	is_external_const_array := has_external_linkage && is_fixed_array && typ.is_const
	is_pointer_element_fixed_array := is_fixed_array && typ.name.contains(']&')
	should_emit_dir_external_global := c.is_dir && is_inited && has_external_linkage
	should_define_static_init_global := c.is_dir && is_inited && var_decl.class_modifier == 'static'
		&& (!is_fixed_array || typ.name.contains(']&'))
	// Fixed array globals usually translate more reliably as V consts. Keep declared C ABI
	// globals mutable so translated object files still provide the expected symbol.
	// Pointer-bearing file-scope arrays must have stable storage. V may materialize a
	// `const` fixed array as a temporary when its address is taken; retaining that
	// address then leaves a dangling pointer after global initialization (for example
	// a const char-pointer lookup table). Emit arrays already selected for
	// shared static initialization as real module globals instead.
	is_const := is_inited && !should_emit_dir_external_global && !should_define_static_init_global
		&& !is_external_const_array && !is_pointer_element_fixed_array
		&& (typ.is_const || (is_fixed_array && (!c.is_dir || var_decl.class_modifier != 'static')
			&& !is_mutable_fixed_array))
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
		c.add_var_func_name(mut c.consts, c_name)
		c.gen("@[export: '${c_name}']\n")
		c.gen('const ${c_identifier_to_v_name(c_name)} ')
	} else {
		if !c.used_global.exists(c_name) && !c.used_global.exists(original_c_name)
			&& !should_emit_dir_external_global {
			vprintln('RRRR global ${c_name} not here, skipping')
			if c.is_dir {
				// Keep symbol/type knowledge for cross-directory 0_globals.v generation,
				// even when this declaration is not referenced in the current file.
				c.register_global_symbol(c_name, typ.name, is_extern)
			}
			// This global is not found in current .c file, means that it was only
			// in the include file, so it's declared and used in some other .c file,
			// no need to genenerate it here.
			// TODO perf right now this searches an entire .c file for each global.
			return
		}
		if c_name in builtin_global_names {
			return
		}

		v_global_name := if class_name != '' {
			cpp_static_member_v_name(class_name, original_c_name, typ.is_const)
		} else {
			c_global_decl_v_name(c_name, is_extern)
		}
		emitted_global_name = v_global_name
		if has_external_linkage {
			c.gen('@[markused]\n')
		}
		if is_inited {
			c.gen('@[weak] __global ${v_global_name} ')
		} else {
			mut typ_name := global_v_type
			if typ_name.contains('anonymous enum') || typ_name.contains('unnamed enum') {
				// Skip anon enums, they are declared as consts in V
				return
			}

			if is_extern {
				c.gen('@[c_extern] ')
			} else {
				c.gen('@[weak] ')
			}

			if typ_name.contains('unnamed at') {
				typ_name = c.last_declared_type_name
			}
			c.gen('__global ${v_global_name} ${typ_name} ')
		}
		c.global_struct_init = typ.name
	}
	if is_fixed_array && var_decl.ast_type.qualified.contains('[]')
		&& !var_decl.ast_type.qualified.contains('*') && !is_inited {
		// Do not allow uninitialized fixed arrays for now, since they are not supported by V
		eprintln('WARNING: ${c.cur_file}: uninitialized fixed array without the size "${c_name}" typ="${var_decl.ast_type.qualified}"')
		return
	}

	// if the global has children, that means it's initialized, parse the expression
	if is_inited {
		child := var_decl.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if is_fixed_array && emitted_global_name != '' && c.is_constant_scalar_initializer(child) {
			// C++ initializes it statically, before any dynamic initialization.
			c.static_global_arrays[emitted_global_name] = true
		}
		construction := unwrap_cpp_reference_binding(child)
		if c.is_cpp && emitted_global_name != '' && !is_fixed_array
			&& c.resolve_type_alias(c.convert_type(node_effective_type_name(construction)).name) == c.resolve_type_alias(global_v_type) {
			if init_name := c.cpp_user_constructor_init_name(&construction) {
				// C++ constructs a global object in place, so its constructor sees
				// the object's own address (e.g. to register it). Zero the storage
				// and construct it in the global initialization sequence.
				// (`= T{}`: V emits invalid C to zero a field-less struct global that
				// has no initializer.)
				c.genln('= ${global_v_type}{}')
				c.genln('\n')
				old_line := c.cur_out_line
				c.cur_out_line = ''
				old_inside_global_init := c.inside_global_init
				c.inside_global_init = true
				c.gen_cpp_constructor_call_on(emitted_global_name, init_name, &construction)
				c.inside_global_init = old_inside_global_init
				call := c.cur_out_line
				c.cur_out_line = old_line
				if c_name !in c.global_constructor_calls {
					c.global_constructor_order << c_name
				}
				c.global_constructor_calls[c_name] = call.trim_space()
				if c.is_dir {
					s := c.out.cut_to(start)
					if c_name !in c.defined_globals {
						c.defined_global_order << c_name
					}
					c.defined_globals[c_name] = true
					c.register_global_symbol(c_name, typ.name, is_extern)
					c.globals_out[c_name] = s
				}
				c.global_struct_init = ''
				c.register_global_symbol(c_name, typ.name, is_extern)
				return
			}
		}
		c.gen('= ')
		is_struct := child.kindof(.init_list_expr) && !is_fixed_array
		is_fn_ptr := typ.name.starts_with('fn ')
		literal_child := unwrap_struct_init_expr(child)
		is_numeric_literal := literal_child.kindof(.integer_literal)
			|| literal_child.kindof(.floating_literal)
		initializer_v_type := c.prefix_external_type(c.convert_type(node_effective_type_name(child)).name)
		is_trivial_external_record_construct := literal_child.kindof(.cxx_construct_expr)
			&& literal_child.inner.len == 0 && initializer_v_type.starts_with('C.')
		is_default_record_init := (is_zero_initializer_expr(child)
			|| is_trivial_external_record_construct)
			&& global_v_type !in v_primitive_type_names && initializer_v_type == global_v_type
		is_same_record_type := global_v_type !in v_primitive_type_names && c.resolve_type_alias(initializer_v_type) == c.resolve_type_alias(global_v_type)
		is_typed_pointer_literal := global_v_type.starts_with('&')
			&& (is_cpp_null_pointer_expression(child) || literal_child.kindof(.string_literal))
		needs_cast := (!is_const || (c.is_dir && is_numeric_literal)) && !is_struct && !is_fn_ptr
			&& !is_fixed_array && (!is_default_record_init || is_typed_pointer_literal)
			&& (!is_same_record_type || is_typed_pointer_literal)
			&& !c.is_v_abstract_interface_type(global_v_type) // Don't cast function pointers, struct inits, fixed arrays, or interface descriptors.
		// V can neither cast nor infer the type of an `if` expression in a global
		// initializer, so a conditional is evaluated by a typed function literal.
		conditional_init := if needs_cast {
			cpp_unwrap_conditional_expression(child)
		} else {
			none
		}
		old_inside_global_init := c.inside_global_init
		old_static_init_owner := c.current_static_init_owner
		c.inside_global_init = true
		c.current_static_init_owner = class_name
		if conditional := conditional_init {
			mut condition := clone_cpp_operator_node(&conditional.inner[0])
			c.gen('fn () ${global_v_type} {\n\treturn if ')
			c.gen_bool(&condition)
			c.gen(' { ${global_v_type}(${c.render_expr_to_string(conditional.inner[1])}) } else { ${global_v_type}(${c.render_expr_to_string(conditional.inner[2])}) }\n}()')
		} else if needs_cast {
			c.gen(global_v_type + '(') ///* typ=$typ   KIND= $child.kind isf=$is_fixed_array*/(')
		}
		if conditional_init != none {
		} else if is_fixed_array && (child.kindof(.cxx_construct_expr)
			|| (child.kindof(.init_list_expr) && child.inner.len == 0
				&& child.array_filler.all(it.kindof(.implicit_value_init_expr)))) {
			// Clang represents an uninitialized global array of C++ objects as a
			// single array-typed CXXConstructExpr. Keep the declared fixed-array
			// shape instead of lowering that node as one constructed element.
			c.gen('${typ.name}{}')
		} else {
			c.expr(child)
		}
		c.inside_global_init = old_inside_global_init
		c.current_static_init_owner = old_static_init_owner
		if needs_cast && conditional_init == none {
			c.gen(')')
		}
		c.genln('')
	} else {
		c.genln('\n')
	}
	c.genln('\n')
	if c.is_dir {
		mut s := c.out.cut_to(start)
		if should_emit_dir_external_global || should_define_static_init_global {
			if c_name !in c.defined_globals {
				c.defined_global_order << c_name
			}
			c.defined_globals[c_name] = true
			c.register_global_symbol(c_name, typ.name, is_extern)
			c.global_struct_init = ''
		}
		c.globals_out[c_name] = s
	}
	c.global_struct_init = ''
	c.register_global_symbol(c_name, typ.name, is_extern)
}

fn (mut c C2V) register_global_symbol(c_name string, typ_name string, is_extern bool) {
	// Directory translation sees the same header declarations before every source
	// file. Once a real definition has been collected, a later ABI/header pre-scan
	// must not downgrade it back to extern and replace its saved initializer.
	if existing := c.globals[c_name] {
		if is_extern && !existing.is_extern {
			return
		}
	}
	mut clean_typ := collapse_ascii_whitespace(typ_name)
	if !clean_typ.starts_with('fn ') && clean_typ.contains(' ') {
		parts := clean_typ.split(' ').filter(it != '')
		if parts.len > 0 {
			if parts[0] in ['struct', 'class', 'union', 'enum'] && parts.len > 1 {
				clean_typ = parts[1]
			} else {
				clean_typ = parts[0]
			}
		}
	}
	c.globals[c_name] = Global{
		name: c_name
		is_extern: is_extern
		typ: clean_typ
	}
}

// `"red"` => `"Color"`
fn (c &C2V) enum_val_to_enum_name(enum_val string) string {
	filtered_enum_val := filter_name(c_identifier_to_v_name(enum_val), false)
	for enum_name, vals in c.enum_vals {
		for val in vals {
			if filtered_enum_val == filter_name(c_identifier_to_v_name(val), false) {
				return enum_name.capitalize()
			}
		}
	}
	return ''
}

// expr is a spcial one. we dont know what type node has.
// can be multiple.
fn (mut c C2V) expr(_node &Node) string {
	mut node := unsafe { _node }
	c.gen_comment(node)
	// Just gen a number
	if node.kindof(.null) || node.kindof(.visibility_attr) {
		return ''
	}
	if c.inside_global_init || const_expr_contains_sizeof(node) {
		ok, literal := c.const_numeric_literal(node)
		if ok {
			c.gen(literal)
			return literal
		}
	}
	if node.kindof(.integer_literal) {
		value := node.value.to_str()
		if c.returning_bool && value in ['1', '0'] {
			if value == '1' {
				c.gen('true')
			} else {
				c.gen('false')
			}
		} else {
			literal_type := c.convert_type(node.ast_type.qualified).name
			if integer_literal_needs_unsigned_cast(value, literal_type) {
				c.gen('${literal_type}(${value})')
			} else {
				c.gen(value)
			}
		}
	} else if node.kindof(.character_literal) {
		// 'a'
		match rune(node.value as int) {
			`\0` { c.gen('`\\0`') }
			`\`` { c.gen('`\\``') }
			`'` { c.gen("`\\'`") }
			`\"` { c.gen('`\\"`') }
			`\\` { c.gen('`\\\\`') }
			`\a` { c.gen('`\\a`') }
			`\b` { c.gen('`\\b`') }
			`\f` { c.gen('`\\f`') }
			`\n` { c.gen('`\\n`') }
			`\r` { c.gen('`\\r`') }
			`\t` { c.gen('`\\t`') }
			`\v` { c.gen('`\\v`') }
			else { c.gen('`' + rune(node.value as int).str() + '`') }
		}
	} else if node.kindof(.floating_literal) {
		// 1e80
		c.gen(node.value.to_str())
	} else if node.kindof(.constant_expr) {
		n := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		c.expr(&n)
	} else if node.kindof(.null_stmt) {
		// null
		c.gen('0')
	} else if node.kindof(.cold_attr) {
	} else if node.kindof(.binary_operator) {
		// = + - *
		op := node.opcode
		was_inside_comma := c.inside_comma_expr
		if op == ',' {
			c.inside_comma_expr = true
		}
		rhs_for_chain := if node.inner.len > 1 && node.inner[1].kindof(.implicit_cast_expr)
			&& node.inner[1].inner.len > 0 {
			node.inner[1].inner[0]
		} else if node.inner.len > 1 {
			node.inner[1]
		} else {
			bad_node
		}
		is_chained_assign := op == '=' && node.inner.len > 1
			&& rhs_for_chain.kindof(.binary_operator) && rhs_for_chain.opcode == '='
		if is_chained_assign {
			// Expand `a = b = c` into assignment statements from right to left:
			// b = c
			// a = b
			mut assigns := []Node{}
			mut values := []Node{}
			mut chain := node
			c.collect_chained_assigns(mut chain, mut assigns, mut values)
			if assigns.len > 0 && values.len > 0 {
				final_value := values[values.len - 1]
				for i := assigns.len - 1; i >= 0; i-- {
					mut lhs := assigns[i]
					mut rhs := if i == assigns.len - 1 { final_value } else { assigns[i + 1] }
					c.gen_simple_assign(mut lhs, mut rhs)
					if i > 0 {
						c.genln('')
					}
				}
			}
			c.inside_comma_expr = was_inside_comma
			vprintln('done!')
			return ''
		}
		mut first_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if op == '=' {
			mut second_expr := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			rhs_unwrapped := c.unwrap_expr_for_deref_check(second_expr)
			// `a = (b += c)` -> `b += c ; a = b`
			if rhs_unwrapped.kindof(.compound_assign_operator) && rhs_unwrapped.inner.len >= 2 {
				mut inner_lhs := rhs_unwrapped.inner[0]
				mut inner_rhs := rhs_unwrapped.inner[1]
				c.expr(inner_lhs)
				c.gen(' ${rhs_unwrapped.opcode} ')
				c.expr(inner_rhs)
				c.genln('')
				mut inner_lhs_assign := rhs_unwrapped.inner[0]
				c.gen_simple_assign(mut first_expr, mut inner_lhs_assign)
			} else if rhs_unwrapped.kindof(.binary_operator) && rhs_unwrapped.opcode == '='
				&& rhs_unwrapped.inner.len >= 2 {
				// `a = (b = c)` -> `b = c ; a = b`
				mut inner_lhs := rhs_unwrapped.inner[0]
				mut inner_rhs := rhs_unwrapped.inner[1]
				c.gen_simple_assign(mut inner_lhs, mut inner_rhs)
				c.genln('')
				mut inner_lhs_assign := rhs_unwrapped.inner[0]
				c.gen_simple_assign(mut first_expr, mut inner_lhs_assign)
			} else {
				c.gen_simple_assign(mut first_expr, mut second_expr)
			}
		} else if op == ',' {
			c.expr(first_expr)
			if c.inside_for_post {
				// Keep comma-separated updates in `for` post expressions.
				c.gen(', ')
			} else {
				// Convert C comma operator to separate statements.
				c.genln('')
			}
			mut second_expr := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			c.expr(second_expr)
		} else if op == '->*' || op == '.*' {
			// C++ pointer-to-member operators: obj->*pmf or obj.*pmf
			// These are not directly representable in V, generate a method call comment
			c.expr(first_expr)
			c.gen('/* ${op} */')
			mut second_expr := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			c.expr(second_expr)
		} else {
			mut second_expr := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			first_is_null := is_cpp_null_pointer_expression(first_expr)
			second_is_null := is_cpp_null_pointer_expression(second_expr)
			mut abstract_comparison_type := ''
			if op in ['==', '!='] && first_is_null != second_is_null {
				other_expr := if first_is_null { second_expr } else { first_expr }
				other_type :=
					c.prefix_external_type(c.convert_type(node_effective_type_name(other_expr)).name)
				other_base_type := normalize_v_ptr_type(other_type)
				if c.is_v_abstract_interface_type(other_type)
					|| other_base_type in c.cpp_abstract_types {
					abstract_comparison_type = other_base_type
				}
			}
			if abstract_comparison_type != '' {
				c.ensure_cpp_interface_runtime_helpers()
				if op == '!=' {
					c.gen('!')
				}
				c.gen('c2v_interface_is_nil[${abstract_comparison_type}](')
				if first_is_null {
					c.expr(second_expr)
				} else {
					c.expr(first_expr)
				}
				c.gen(')')
			} else if op in ['==', '!=']
				&& c.is_v_abstract_interface_type(c.prefix_external_type(c.convert_type(node_effective_type_name(first_expr)).name))
				&& c.is_v_abstract_interface_type(c.prefix_external_type(c.convert_type(node_effective_type_name(second_expr)).name)) {
				// A V interface is a two-word descriptor and cannot be cast directly to
				// usize. C++ pointer equality compares the concrete object slot. Keep the
				// type arguments explicit because V cannot infer a generic argument from
				// every conditional interface expression.
				first_interface_type := c.prefix_external_type(c.convert_type(node_effective_type_name(first_expr)).name)
				second_interface_type := c.prefix_external_type(c.convert_type(node_effective_type_name(second_expr)).name)
				c.ensure_cpp_interface_runtime_helpers()
				c.gen('c2v_interface_object[${first_interface_type}](')
				c.expr(first_expr)
				c.gen(') ${op} c2v_interface_object[${second_interface_type}](')
				c.expr(second_expr)
				c.gen(')')
			} else if op in ['==', '!=']
				&& c.is_pointer_ast_type(node_effective_type_name(first_expr))
				&& c.is_pointer_ast_type(node_effective_type_name(second_expr)) {
				// V compares typed pointers through their pointee values. C and C++
				// pointer equality is address identity, and dereferencing a negative
				// sentinel crashes during static initialization.
				c.gen_pointer_address(first_expr)
				c.gen(' ${op} ')
				c.gen_pointer_address(second_expr)
			} else if op == '-' && c.is_pointer_ast_type(node_effective_type_name(first_expr))
				&& c.is_pointer_ast_type(node_effective_type_name(second_expr)) {
				element_type :=
					normalize_v_ptr_type(c.prefix_external_type(c.convert_type(node_effective_type_name(first_expr)).name))
				result_type :=
					c.prefix_external_type(c.convert_type(node_effective_type_name(node)).name)
				if result_type != '' && result_type != 'isize' {
					c.gen('${result_type}(')
				}
				c.gen('(isize(')
				c.gen_cxx_pointer_cast_source(first_expr)
				c.gen(') - isize(')
				c.gen_cxx_pointer_cast_source(second_expr)
				c.gen(')) / isize(sizeof(${element_type}))')
				if result_type != '' && result_type != 'isize' {
					c.gen(')')
				}
			} else if op in ['<', '>', '<=', '>=']
				&& c.is_pointer_ast_type(node_effective_type_name(first_expr))
				&& c.is_pointer_ast_type(node_effective_type_name(second_expr)) {
				// V only defines equality for raw pointers. Preserve C/C++ address
				// ordering by comparing their machine-sized integer representations.
				c.gen_pointer_address(first_expr)
				c.gen(' ${op} ')
				c.gen_pointer_address(second_expr)
			} else if op in ['+', '-'] && c.is_cpp
				&& cpp_array_decay_source(&first_expr) != none {
				array_source := cpp_array_decay_source(&first_expr) or { bad_node }
				if array_source.kindof(.string_literal) {
					c.expr(first_expr)
					c.gen(' ${op} ')
					c.expr(second_expr)
				} else {
					old_inside_unsafe := c.inside_unsafe
					if !old_inside_unsafe {
						c.gen('unsafe { ')
						c.inside_unsafe = true
					}
					c.gen('&')
					c.expr(array_source)
					c.gen('[0] ${op} ')
					c.expr(second_expr)
					if !old_inside_unsafe {
						c.inside_unsafe = false
						c.gen(' }')
					}
				}
			} else if op in ['+', '-']
				&& c.is_pointer_ast_type(node_effective_type_name(first_expr))
				&& c.unwrap_expr_for_deref_check(second_expr).kindof(.binary_operator) {
				// C/C++ bitwise operators bind less tightly than pointer addition.
				// Keep the source grouping for forms such as `ptr + (index ^ 1)`;
				// Clang's ParenExpr is otherwise intentionally transparent in V output.
				c.expr(first_expr)
				c.gen(' ${op} (')
				c.expr(second_expr)
				c.gen(')')
			} else if op in ['<<', '>>']
				&& (is_bool_expr(first_expr) || c.shift_lhs_needs_int_cast(first_expr)) {
				c.gen('int(')
				c.expr(first_expr)
				c.gen(')')
				c.gen(' ${op} ')
				c.expr(second_expr)
			} else if op == '-' && c.expr_renders_with_leading_unary_minus(second_expr) {
				c.expr(first_expr)
				c.gen(' - (')
				c.expr(second_expr)
				c.gen(')')
			} else {
				c.expr(first_expr)
				c.gen(' ${op} ')
				c.expr(second_expr)
			}
		}
		c.inside_comma_expr = was_inside_comma
		vprintln('done!')
		if op == '<' || op == '>' || op == '==' {
			return 'bool'
		}
	} else if node.kindof(.compound_assign_operator) {
		// +=
		op := node.opcode // get_val(-3)
		first_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		second_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if reference_name := c.cpp_primitive_reference_v_name(&first_expr) {
			old_inside_unsafe := c.inside_unsafe
			if !old_inside_unsafe {
				c.gen('unsafe { ')
				c.inside_unsafe = true
			}
			c.gen('*${reference_name} ${op} ')
			c.expr(second_expr)
			if !old_inside_unsafe {
				c.inside_unsafe = false
				c.gen(' }')
			}
			return ''
		}
		if c.cpp_primitive_reference_operator_source(&first_expr) != none {
			old_inside_unsafe := c.inside_unsafe
			old_reference_lvalue := c.inside_cpp_reference_lvalue
			if !old_inside_unsafe {
				c.gen('unsafe { ')
				c.inside_unsafe = true
			}
			c.gen('*(')
			c.inside_cpp_reference_lvalue = true
			c.expr(first_expr)
			c.inside_cpp_reference_lvalue = old_reference_lvalue
			c.gen(') ${op} ')
			c.expr(second_expr)
			if !old_inside_unsafe {
				c.inside_unsafe = false
				c.gen(' }')
			}
			return ''
		}
		if op in ['+=', '-='] && c.is_pointer_ast_type(node_effective_type_name(first_expr)) {
			target := c.render_expr_to_string(first_expr)
			if c.inside_for && node.id == c.for_clause_root_id {
				c.gen(target)
				c.gen(' = unsafe { ')
				c.gen(target)
				c.gen(if op == '+=' { ' + ' } else { ' - ' })
				c.expr(second_expr)
				c.gen(' }')
				return ''
			}
			// As with pointer ++/-- below, pass the storage address through
			// voidptr so the C backend does not emit Clang's `&&label` syntax.
			c.gen('c2v_pointer_prefix(voidptr(&${target}), ${target}, isize(')
			if op == '-=' {
				c.gen('-(')
			}
			c.expr(second_expr)
			if op == '-=' {
				c.gen(')')
			}
			c.gen('))')
			return ''
		}
		lhs_unwrapped := c.unwrap_expr_for_deref_check(first_expr)
		if lhs_unwrapped.kindof(.unary_operator) && lhs_unwrapped.opcode == '*'
			&& lhs_unwrapped.inner.len > 0 {
			old_inside_unsafe := c.inside_unsafe
			if !c.inside_unsafe {
				c.gen('unsafe { ')
				c.inside_unsafe = true
			}
			c.gen('*')
			c.expr(lhs_unwrapped.inner[0])
			c.gen(' ${op} ')
			c.expr(second_expr)
			if !old_inside_unsafe {
				c.inside_unsafe = old_inside_unsafe
				c.gen(' }')
			}
		} else {
			// Handle casted dereference forms emitted as `(unsafe { *ptr })`.
			old_cur_out := c.cur_out_line
			c.cur_out_line = ''
			mut lhs_preview := clone_cpp_operator_node(&first_expr)
			c.expr(lhs_preview)
			lhs_rendered := c.cur_out_line
			c.cur_out_line = old_cur_out
			if lhs_rendered.starts_with('(unsafe { *') && lhs_rendered.ends_with(' })') {
				c.gen(lhs_rendered.replace('(unsafe { *', 'unsafe { *').replace(' })', ' }'))
				c.gen(' ${op} ')
				c.expr(second_expr)
			} else {
				c.expr(first_expr)
				c.gen(' ${op} ')
				c.expr(second_expr)
			}
		}
	} else if node.kindof(.unary_operator) {
		// ++ --
		op := node.opcode
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if op in ['--', '++'] {
			if node.is_postfix {
				if reference_name := c.cpp_primitive_reference_v_name(&expr) {
					value_type := c.convert_type(node_effective_type_name(expr)).name
					if value_type in ['i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
						'usize', 'f32', 'f64'] {
						helper_name := 'c2v_${value_type}_reference_postfix'
						helper_key := '${helper_name}:${os.dir(c.outv)}'
						if helper_key !in c.generated_declarations {
							c.generated_declarations[helper_key] = true
							c.local_type_declarations << 'fn ${helper_name}(value &${value_type}, delta ${value_type}) ${value_type} {\n\tunsafe {\n\t\tprevious := *value\n\t\t*value += delta\n\t\treturn previous\n\t}\n}\n\n'
						}
						delta := if op == '++' { '1' } else { '-1' }
						c.gen('${helper_name}(${reference_name}, ${value_type}(${delta}))')
						return ''
					}
				}
			}
			if c.is_pointer_ast_type(node_effective_type_name(expr)) {
				target := c.render_expr_to_string(expr)
				if c.inside_for && node.id == c.for_clause_root_id {
					arithmetic_op := if op == '++' { '+' } else { '-' }
					c.gen('${target} = unsafe { ${target} ${arithmetic_op} 1 }')
					return ''
				}
				helper := if node.is_postfix { 'c2v_pointer_postfix' } else { 'c2v_pointer_prefix' }
				delta := if op == '++' { '1' } else { '-1' }
				// Pass the storage address through voidptr. Directly passing `&target`
				// to a generic &&T parameter makes the V C backend emit `&&target`,
				// which Clang parses as a label address.
				c.gen('${helper}(voidptr(&${target}), ${target}, isize(${delta}))')
				return ''
			}
			if c.collecting_pre_cond && !node.is_postfix {
				old_cur_out := c.cur_out_line
				old_collecting_pre_cond := c.collecting_pre_cond
				c.cur_out_line = ''
				c.collecting_pre_cond = false
				c.expr(expr)
				target := c.cur_out_line
				c.cur_out_line = old_cur_out
				c.collecting_pre_cond = old_collecting_pre_cond
				c.pre_cond_stmts << '${target}${op}'
				c.gen(target)
				return ''
			}
			c.expr(expr)
			c.gen(op)
			if !c.inside_for && !c.inside_comma_expr && !node.is_postfix {
				// prefix ++
				// but do not generate `++i` in for loops, it breaks in V for some reason
				c.gen('\$')
			}
		} else if op == '+' {
			// Unary plus is a no-op, just emit the expression
			c.expr(expr)
		} else if op == '-' || op == '!' || op == '~' {
			c.gen(op)
			c.expr(expr)
		} else if op == '&' {
			// C++ sometimes wraps method-call temporaries in address-of nodes.
			// V cannot take the address of such temporaries, so emit the call directly.
			mut addr_target := expr
			for addr_target.inner.len > 0
				&& (addr_target.kindof(.implicit_cast_expr) || addr_target.kindof(.paren_expr)
					|| addr_target.kindof(.expr_with_cleanups)
					|| addr_target.kindof(.materialize_temporary_expr)
					|| addr_target.kindof(.cxx_bind_temporary_expr)
					|| addr_target.kindof(.cxx_functional_cast_expr)
					|| addr_target.kindof(.cxx_static_cast_expr)
					|| addr_target.kindof(.cxx_const_cast_expr)
					|| addr_target.kindof(.cxx_reinterpret_cast_expr)
					|| addr_target.kindof(.cxx_dynamic_cast_expr)
					|| addr_target.kindof(.c_style_cast_expr)) {
				addr_target = addr_target.inner[0]
			}
			if c.gen_cpp_member_pointer_callback(node, addr_target) {
				// Generated above as a receiver-first closure.
			} else if c.is_cpp && addr_target.kindof(.decl_ref_expr)
				&& addr_target.ref_declaration.ast_type.qualified.trim_space().ends_with('&')
				&& addr_target.ref_declaration.id !in c.cpp_value_reference_params && addr_target.ref_declaration.id in c.local_decl_v_names {
				// The address of a C++ reference is its referent's address, which the
				// translated V pointer already holds.
				c.gen(c.local_decl_v_names[addr_target.ref_declaration.id])
			} else if c.is_cpp
				&& (addr_target.kindof(.call_expr) || addr_target.kindof(.cxx_member_call_expr)
					|| addr_target.kindof(.cxx_operator_call_expr)) {
				old_reference_lvalue := c.inside_cpp_reference_lvalue
				c.inside_cpp_reference_lvalue = true
				c.expr(addr_target)
				c.inside_cpp_reference_lvalue = old_reference_lvalue
			} else if addr_target.kindof(.array_subscript_expr) && addr_target.inner.len >= 2 {
				// Render `&array[index]` as pointer arithmetic. Besides matching C, this
				// permits the legal one-past address `&array[len]`, which V rejects as
				// an indexed element even inside an unsafe block.
				old_inside_unsafe := c.inside_unsafe
				if !old_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.expr(addr_target.inner[0])
				c.gen(' + ')
				index_expr := addr_target.inner[1]
				index_base := c.unwrap_expr_for_deref_check(index_expr)
				if index_base.kindof(.binary_operator) || index_base.kindof(.conditional_operator) {
					c.gen('(')
					c.expr(index_expr)
					c.gen(')')
				} else {
					c.expr(index_expr)
				}
				if !old_inside_unsafe {
					c.inside_unsafe = old_inside_unsafe
					c.gen(' }')
				}
			} else {
				c.gen('&')
				c.expr(expr)
			}
		} else if op == '*' {
			if c.is_cpp && is_cpp_dereferenced_this_expr(node) {
				c.gen(c.this_object())
				return ''
			}
			// Pointer dereference - wrap in unsafe block for V
			// Exception: inside sizeof, we don't need unsafe since sizeof doesn't evaluate its operand
			// Exception: already inside unsafe, to prevent nested unsafe blocks
			if c.inside_sizeof || c.inside_unsafe {
				c.gen('*')
				c.expr(expr)
			} else {
				// Use parentheses to ensure proper operator precedence
				c.gen('(unsafe { *')
				c.inside_unsafe = true
				c.expr(expr)
				c.inside_unsafe = false
				c.gen(' })')
			}
		}
	} else if node.kindof(.paren_expr) {
		// ()
		child := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		// Skip parentheses around comma expressions since they become separate statements
		// Skip parentheses around compound/simple assignments since they are statements in V
		is_comma_expr := child.kindof(.binary_operator) && child.opcode == ','
		is_compound_assign := child.kindof(.compound_assign_operator)
		is_simple_assign := child.kindof(.binary_operator) && child.opcode == '='
		skip := c.skip_parens || is_comma_expr || is_compound_assign || is_simple_assign
		// Handle assignment in condition: `(x = expr)` / `(x += expr)` -> collect assignment, output `x`
		if c.collecting_pre_cond && (is_simple_assign || is_compound_assign) && child.inner.len > 0 {
			var_node := child.inner[0]
			// Temporarily capture the assignment output
			old_cur_out := c.cur_out_line
			c.cur_out_line = ''
			c.expr(child) // generates the assignment
			assign_stmt := c.cur_out_line
			c.cur_out_line = old_cur_out
			// Store assignment for output before the condition
			c.pre_cond_stmts << assign_stmt
			// Output just the variable
			c.expr(var_node)
			return ''
		}
		paren_start := c.cur_out_line.len
		if !skip {
			c.gen('(')
		}
		c.expr(child)
		if !skip {
			if c.cur_out_line.len < paren_start + 1 {
				// The child emitted one or more complete statements and started a new line.
				// The opening parenthesis was flushed with those statements, so it still
				// needs a matching close on the child's final line.
				c.gen(')')
			} else if c.cur_out_line[paren_start + 1..].trim_space() == '' {
				c.cur_out_line = c.cur_out_line[..paren_start]
			} else {
				c.gen(')')
			}
		}
	} else if node.kindof(.implicit_cast_expr) {
		// This junk means go again for its child
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		// Handle BitCast from void* to unsigned char* (byte pointer)
		// This is common for byte-level operations
		mut handled := false
		if node.cast_kind == 'LValueToRValue' && (is_cpp_pointer_slot_call(expr)
			|| (c.deref_reference_call_values && cpp_call_expr_returns_reference_value(expr)
				&& c.cpp_primitive_reference_operator_source(&expr) == none)) {
			// (An operator returning a primitive reference reads the value itself.)
			// The call returns a V pointer to the value that is read.
			old_inside_unsafe := c.inside_unsafe
			c.gen(if old_inside_unsafe { '(*' } else { '(unsafe { *' })
			c.inside_unsafe = true
			c.expr(expr)
			c.inside_unsafe = old_inside_unsafe
			c.gen(if old_inside_unsafe { ')' } else { ' })' })
			return ''
		}
		if node.cast_kind == 'ArrayToPointerDecay' && !expr.kindof(.string_literal) {
			old_inside_unsafe := c.inside_unsafe
			if !old_inside_unsafe {
				c.gen('unsafe { ')
				c.inside_unsafe = true
			}
			c.gen('&')
			c.expr(expr)
			c.gen('[0]')
			if !old_inside_unsafe {
				c.inside_unsafe = false
				c.gen(' }')
			}
			handled = true
		} else if node.cast_kind == 'NullToPointer' {
			to_type := c.prefix_external_type(c.convert_type(node.ast_type.qualified).name)
			resolved_to_type := c.resolve_type_alias(to_type)
			if c.is_v_abstract_interface_type(to_type) {
				c.gen(c.v_abstract_interface_nil_literal(to_type))
				handled = true
			} else if c.is_cpp && is_cpp_null_pointer_expression(*node)
				&& (resolved_to_type.starts_with('&')
					|| resolved_to_type == 'voidptr' || resolved_to_type.starts_with('fn ')) {
				c.gen(if c.inside_unsafe { 'nil' } else { 'unsafe { nil }' })
				handled = true
			}
		}
		// Clang represents a read through a reference-returning overloaded operator
		// as LValueToRValue(CXXOperatorCallExpr). The translated V method returns a
		// pointer, so preserve the C++ value read with an explicit dereference.
		if !handled
			&& node.cast_kind in ['IntegralToBoolean', 'PointerToBoolean', 'MemberPointerToBoolean'] {
			from_type := c.prefix_external_type(c.convert_type(expr.ast_type.qualified).name)
			rendered := c.render_expr_to_string(expr)
			rendered_is_bool := is_bool_expr(expr) || rendered.contains(' != nil')
				|| rendered.contains(' != unsafe { nil }')
			if c.is_v_abstract_interface_type(from_type) && !rendered_is_bool {
				c.ensure_cpp_interface_runtime_helpers()
				c.gen('(!c2v_interface_is_nil(${rendered}))')
			} else if (from_type.starts_with('&') || from_type == 'voidptr' || from_type.starts_with('fn (')) && !rendered_is_bool {
				c.gen('(')
				c.gen(rendered)
				c.gen(if c.inside_unsafe { ' != nil)' } else { ' != unsafe { nil })' })
			} else if from_type != 'bool' && !c.is_comparison_expr(expr) {
				c.gen('(${rendered} != 0)')
			} else {
				c.gen('(${rendered})')
			}
			handled = true
		} else if node.cast_kind == 'LValueToRValue' && cpp_operator_call_returns_reference(expr) {
			operator_value_type := c.convert_type(node_effective_type_name(expr)).name
			if c.cpp_operator_call_returns_primitive_reference(expr) {
				// Primitive reference-returning operators perform their own value read,
				// including macro expansions where Clang omits this cast wrapper.
				c.expr(expr)
			} else if operator_value_type.starts_with('&') || operator_value_type == 'voidptr'
				|| node_effective_type_name(expr).contains('*') {
				// A C++ `T *&` read produces the pointer value. The translated index
				// operator already returns the V pointer/interface value, so another
				// dereference would turn it into a struct value or corrupt an interface.
				c.expr(expr)
			} else {
				was_inside_unsafe := c.inside_unsafe
				if !was_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('*(')
				c.expr(expr)
				c.gen(')')
				if !was_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
			}
			handled = true
		} else if node.cast_kind == 'BitCast' {
			from_type := c.convert_type(expr.ast_type.qualified).name
			to_type := c.convert_type(node.ast_type.qualified).name
			// void* -> &u8 cast
			if from_type == 'voidptr' && to_type == '&u8' {
				c.gen('&u8(')
				c.expr(expr)
				c.gen(')')
				handled = true
			} else if from_type == 'voidptr' && to_type == '&i8' {
				// void* -> &i8 cast
				c.gen('&i8(')
				c.expr(expr)
				c.gen(')')
				handled = true
			}
		}
		if handled {
			// Cast was handled, skip the rest
		} else if (c.is_dir
			&& node.cast_kind in ['IntegralCast', 'IntegralToFloating', 'FloatingToIntegral'])
			|| (node.cast_kind == 'FloatingCast' && !expr.kindof(.floating_literal)) {
			to_type := c.prefix_external_type(c.convert_type(node.ast_type.qualified).name)
			from_type := c.prefix_external_type(c.convert_type(expr.ast_type.qualified).name)
			resolved_to_type := c.resolve_type_alias(to_type)
			if to_type != from_type && resolved_to_type in v_primitive_type_names {
				c.gen('${to_type}(')
				c.expr(expr)
				c.gen(')')
			} else {
				c.expr(expr)
			}
		} else if expr.kindof(.integer_literal) {
			typ := c.convert_type(node.ast_type.qualified).name
			match typ {
				'f32', 'f64' {
					c.gen('${typ}(')
					c.expr(expr)
					c.gen(')')
				}
				else {
					c.expr(expr)
				}
			}
		} else if expr.kindof(.floating_literal) && expr.value == Value('0') {
			// 0.0f
			c.gen('0.0')
		} else {
			c.expr(expr)
		}
	} else if node.kindof(.decl_ref_expr) {
		// var  name
		c.name_expr(node)
	} else if node.kindof(.non_type_template_parm_decl) {
		// Clang can leave the declaration as the only child of a
		// SubstNonTypeTemplateParmExpr. Resolve it from the concrete class-template
		// specialization currently being emitted.
		if value := c.cpp_template_values[node.name] {
			c.gen(value)
		} else if c.project_require_no_stubs {
			c.verror('unresolved non-type template parameter ${node.name} in ${c.current_fn_v_name} at ${c.cur_file}:${node.location.line}')
		} else {
			c.gen(filter_name(node.name, false))
		}
	} else if node.kindof(.string_literal) {
		// "string literal"
		str := node.value.to_str()
		// "a" => 'a'
		no_quotes := str.substr(1, str.len - 1)
		if no_quotes.contains("'") {
			// same quoting logic as in vfmt
			c.gen('c"${no_quotes}"')
		} else {
			c.gen("c'${no_quotes}'")
		}
	} else if node.kindof(.call_expr) {
		// fn call
		c.fn_call(mut node)
	} else if node.kindof(.member_expr) {
		// `user.age`
		if c.is_cpp && node.referenced_member_decl != '' {
			if static_name := c.cpp_static_member_decl_names[node.referenced_member_decl] {
				// C++ permits accessing a static data member through an object or
				// pointer. It still denotes class storage, so do not emit the
				// syntactic receiver as a V instance-field access.
				c.gen(static_name)
				return ''
			}
		}
		mut field := node.name
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		// A pointer container's `operator[]` can return `T *const &`. The V operator
		// method already returns `&T`, so a surrounding LValueToRValue must not
		// introduce another dereference before an arrow-member access.
		operator_reference_base := expr.kindof(.implicit_cast_expr)
			&& expr.cast_kind == 'LValueToRValue' && expr.inner.len == 1
			&& cpp_operator_call_returns_reference(expr.inner[0])
			&& !is_cpp_pointer_slot_call(expr.inner[0])
		// Optimize (*ptr).field -> ptr.field
		// In V, '.' works on pointers directly, so dereferencing is unnecessary
		if operator_reference_base {
			c.expr(expr.inner[0])
		} else if expr.kindof(.paren_expr) && expr.inner.len > 0
			&& expr.inner[0].kindof(.unary_operator) && expr.inner[0].opcode == '*'
			&& expr.inner[0].inner.len > 0 {
			c.expr(expr.inner[0].inner[0])
		} else if c.is_cpp_reference_param_ref(expr) {
			// A pointer reference reads as `unsafe { *p }`, and V compiles
			// `unsafe { *p }.field` to the C `*p->field`.
			c.gen('(')
			c.expr(expr)
			c.gen(')')
		} else {
			c.expr(expr)
		}
		mut raw_field := field.replace('->', '')
		if raw_field.starts_with('.') {
			raw_field = raw_field[1..]
		}
		raw_is_all_upper := is_all_upper_identifier(raw_field)
		receiver_v_type := c.convert_type(expr.ast_type.qualified).name.trim_left('&')
		if receiver_v_type.starts_with('C.') {
			field = if raw_field in v_reserved_words { '@' + raw_field } else { raw_field }
		} else if raw_is_all_upper {
			field = filter_name(raw_field.to_lower(), false).all_after_last('.')
		} else {
			field = filter_name(raw_field, false).all_after_last('.')
		}
		if c.is_cpp && !receiver_v_type.starts_with('C.') {
			field = field.camel_to_snake().trim_left('_')
			class_v_name := if c.cur_class != '' {
				c.types[c.cur_class] or { c.cur_class }
			} else {
				c.receiver_surface_type_name(expr)
			}
			if class_v_name != '' {
				field = c.cpp_field_v_names['${class_v_name}.${field}'] or { field }
			}
		}
		if field != '' {
			c.gen('.${field}')
		}
	} else if node.kindof(.unary_expr_or_type_trait_expr) {
		// sizeof
		c.gen('sizeof')
		// sizeof (expr) ?
		if node.inner.len > 0 {
			expr := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			if deref_type := sizeof_deref_type(expr) {
				typ := c.convert_type(deref_type)
				c.gen('(${typ.name})')
				return ''
			}

			// Generate the expression to check if it involves member access
			old_line := c.cur_out_line
			c.cur_out_line = ''
			c.inside_sizeof = true
			c.expr(expr)
			c.inside_sizeof = false
			sizeof_expr := c.cur_out_line
			c.cur_out_line = old_line
			// V cannot parse several sizeof expression forms produced from C/C++ member
			// accesses. An indexed multidimensional array is especially hazardous:
			// vfmt can reinterpret `sizeof(buffers[0])` as `sizeof(buffers)[0]` and
			// corrupt the surrounding statement. Use the AST operand type instead.
			needs_type_sizeof := sizeof_expr_needs_type_operand(sizeof_expr)
				|| expr.ast_type.qualified.contains('[')
			if needs_type_sizeof {
				expr_type := expr.ast_type.qualified
				if expr_type != '' {
					typ := c.convert_type(expr_type)
					c.gen('(${typ.name})')
				} else {
					// Fallback: output expression
					c.gen('(${sizeof_expr})')
				}
			} else {
				mut cleaned_sizeof := sizeof_expr
				// Strip pointer dereference: sizeof((*ptr)) -> sizeof(ptr)
				if cleaned_sizeof.starts_with('(*') && cleaned_sizeof.ends_with(')') {
					cleaned_sizeof = cleaned_sizeof[2..cleaned_sizeof.len - 1]
				}
				// Strip wrapping parentheses: sizeof((expr)) -> sizeof(expr)
				for cleaned_sizeof.starts_with('(') && cleaned_sizeof.ends_with(')') {
					cleaned_sizeof = cleaned_sizeof[1..cleaned_sizeof.len - 1]
				}
				c.gen('(${cleaned_sizeof})')
			}
		} else {
			// sizeof (Type) ?
			typ := c.convert_type(node.ast_argument_type.qualified)
			if typ.name.starts_with('&') || typ.name.starts_with('fn (') {
				c.gen('(voidptr)')
			} else {
				c.gen('(${typ.name})')
			}
		}
	} else if node.kindof(.array_subscript_expr) {
		// a[0]
		first_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		// An ordinary multidimensional array is presented here through an
		// ArrayToPointerDecay whose result is also `T (*)[N]`. Only explicit
		// pointer values need the extra V dereference; decayed arrays already
		// retain their row dimension when we unwrap that cast below.
		// A C++ pointer to abstract-class pointers is a V pointer to interface
		// values. V's `[]` does not step through such a pointer, so it gets the same
		// explicit pointer arithmetic.
		base_v_type := c.convert_type(first_expr.ast_type.qualified).name
		pointer_to_interface_base := first_expr.cast_kind != 'ArrayToPointerDecay'
			&& base_v_type.starts_with('&') && !base_v_type.starts_with('&&')
			&& c.is_v_abstract_interface_type(base_v_type[1..])
		pointer_to_array_base := first_expr.ast_type.qualified.contains('(*)[')
			&& first_expr.cast_kind != 'ArrayToPointerDecay'
		// Skip parentheses around simple identifiers in array access (e.g., (arr)[0] -> arr[0])
		// This is needed because V doesn't handle sizeof((arr)[0]) well
		// The AST structure is: ArraySubscriptExpr -> ImplicitCastExpr -> ParenExpr -> DeclRefExpr
		mut actual_expr := first_expr
		if decay_source := cpp_array_decay_source(&first_expr) {
			actual_expr = decay_source
		} else if first_expr.kindof(.implicit_cast_expr) && first_expr.inner.len > 0 {
			inner := first_expr.inner[0]
			if first_expr.cast_kind == 'ArrayToPointerDecay' {
				// Indexing already supplies the pointer operation. Emitting the
				// decay's `&array[0]` here would add a second index level.
				actual_expr = inner
			} else if inner.kindof(.paren_expr) && inner.inner.len == 1 {
				paren_inner := inner.inner[0]
				if paren_inner.kindof(.decl_ref_expr) {
					// Skip both the ImplicitCastExpr and ParenExpr, output just the identifier
					actual_expr = paren_inner
				}
			}
		}
		second_expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		if pointer_to_interface_base {
			c.ensure_cpp_interface_runtime_helpers()
			c.gen('unsafe { *c2v_pointer_at(')
			c.expr(actual_expr)
			c.gen(', ')
			c.expr(second_expr)
			c.gen(') }')
			return ''
		}
		if pointer_to_array_base {
			// V flattens indexing through `&[N]T` to T. Preserve C pointer
			// arithmetic explicitly, then dereference the selected row array. The
			// outer parentheses keep V from compiling `(*row)[i]` as `*row[i]`.
			c.gen('(unsafe { *(')
			c.expr(actual_expr)
			c.gen(' + ')
			c.expr(second_expr)
			c.gen(') })')
			return ''
		}
		c.expr(actual_expr)
		c.gen('[')

		c.inside_array_index = true
		bool_index := c.convert_type(second_expr.ast_type.qualified).name == 'bool'
			|| c.is_comparison_expr(second_expr)
		if bool_index {
			c.gen('int(')
		}
		c.expr(second_expr)
		if bool_index {
			c.gen(')')
		}
		c.inside_array_index = false
		c.gen(']')
	} else if node.kindof(.init_list_expr) {
		// int a[] = {1,2,3};
		c.init_list_expr(mut node)
	} else if node.kindof(.c_style_cast_expr) {
		// (int*)a  => (int*)(a)
		// CStyleCastExpr 'const char **' <BitCast>
		expr := node.try_get_next_child() or {
			println(add_place_data_to_error(err))
			bad_node
		}
		// Preserve the explicit spelling here. Desugaring can erase target-width
		// typedef semantics that c2v maps deliberately (notably Darwin `time_t`,
		// whose Clang underlying `long` maps differently from the typedef itself).
		typ := c.convert_type(c_style_cast_type_spelling(node.ast_type))
		mut cast := c.prefix_external_type(typ.name)
		// Skip void casts like (void)0 - they're no-ops in C
		if cast == 'void' {
			return ''
		}
		if c.is_cpp && cast.starts_with('&') && cpp_receiver_is_direct_this(expr) {
			c.gen('unsafe { ${cast}(${c.this_pointer()}) }')
			return ''
		}
		mut source_expr := expr
		for source_expr.inner.len > 0
			&& (source_expr.kindof(.implicit_cast_expr) || source_expr.kindof(.paren_expr)) {
			source_expr = source_expr.inner[0]
		}
		source_type := c.prefix_external_type(c.convert_type(node_effective_type_name(source_expr)).name)
		source_is_abstract_interface := c.is_v_abstract_interface_type(source_type)
			|| normalize_v_ptr_type(source_type) in c.cpp_abstract_types
		if cast == 'voidptr' && source_is_abstract_interface {
			// Interface values are two-word runtime values in V. The language only
			// permits their explicit erasure through an `as voidptr` assertion.
			c.gen('(')
			c.expr(expr)
			c.gen(' as voidptr)')
			return ''
		}
		abstract_to_integer := is_v_integer_const_type(cast)
			&& c.is_v_abstract_interface_type(source_type)
		integer_to_abstract := c.is_v_abstract_interface_type(cast) && source_type != cast
			&& !c.is_v_abstract_interface_type(source_type)
		if abstract_to_integer || integer_to_abstract {
			helper_key := 'cpp_abstract_pointer_cast_helper:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'union C2vAbstractPointerCastStorage[T] {\nmut:\n\traw [2]voidptr\n\tvalue T\n}\n\nfn c2v_abstract_pointer_cast[T](value voidptr) T {\n\tmut storage := C2vAbstractPointerCastStorage[T]{}\n\tunsafe {\n\t\tstorage.raw[0] = value\n\t\treturn storage.value\n\t}\n}\n\nfn c2v_abstract_pointer_value[T](value T) voidptr {\n\tstorage := C2vAbstractPointerCastStorage[T]{\n\t\tvalue: value\n\t}\n\treturn unsafe { storage.raw[0] }\n}\n\n'
			}
			if abstract_to_integer {
				c.gen('${cast}(usize(c2v_abstract_pointer_value[${source_type}](')
				c.expr(expr)
				c.gen(')))')
				return ''
			}
			if integer_to_abstract {
				// An integer/void pointer sometimes carries a previously erased C++
				// abstract-base pointer. A direct V interface cast treats the integer as
				// a concrete implementor and emits one conformance error per method.
				// Reinterpret it through a union so V does not apply that conversion.
				c.gen('c2v_abstract_pointer_cast[${cast}](voidptr(')
				c.expr(expr)
				c.gen('))')
				return ''
			}
		}
		interface_downcast := source_type != cast && c.is_v_abstract_interface_type(source_type)
			&& (c.is_v_abstract_interface_type(cast) || cast.starts_with('&'))
		if interface_downcast {
			// A C++ cast from an abstract base pointer is a V type assertion. A
			// constructor-style cast instead asks the source interface itself to
			// implement the target interface or concrete record.
			c.gen('(')
			c.expr(expr)
			c.gen(' as ${cast})')
			return ''
		}
		if (node.ast_type.qualified.trim_space().ends_with('&') || node.value_category == 'lvalue')
			&& source_type.starts_with('&')
			&& !cast.starts_with('&') && cast != '' && cast[0].is_capital() {
			// Reinterpret a pointer variable through a record reference. The reference
			// aliases the pointer's storage; it is not
			// a value-construction cast from the pointed-to record.
			c.gen('unsafe { *(&${cast}(&')
			c.expr(expr)
			c.gen(')) }')
			return ''
		}
		// Special case: casting 0 to a pointer type should generate voidptr(0)
		// to avoid V's "cannot dereference nil pointer" errors
		if expr.kindof(.integer_literal) && expr.value.to_str() == '0'
			&& (cast.starts_with('&') || cast == 'voidptr') {
			c.gen('voidptr(0)')
			return ''
		}
		// The old V compiler cannot infer a value from a voidptr-valued `if`
		// expression nested inside a pointer cast. C allocation macros commonly
		// expand to exactly that shape. Push the pointer cast into each ternary
		// branch so both branches have the concrete pointer type.
		if cast.starts_with('&') {
			if conditional := cpp_unwrap_conditional_expression(expr) {
				mut condition := clone_cpp_operator_node(&conditional.inner[0])
				case1 := c.render_expr_to_string(conditional.inner[1])
				case2 := c.render_expr_to_string(conditional.inner[2])
				c.gen('if ')
				c.expr(&condition)
				c.gen(' { ')
				c.gen(wrap_final_rendered_expr(case1, cast))
				c.gen(' } else { ')
				c.gen(wrap_final_rendered_expr(case2, cast))
				c.gen(' }')
				return ''
			}
		}
		if cast.starts_with('&') && !cast.starts_with('&&')
			&& c.is_v_abstract_interface_type(cast[1..]) {
			// A pointer to abstract-class pointers addresses V interface values; the
			// cast reinterprets the address rather than boxing it into an interface.
			c.ensure_cpp_interface_runtime_helpers()
			c.gen('c2v_pointer_as[${cast[1..]}](voidptr(')
			c.expr(expr)
			c.gen('))')
			return ''
		}
		// Function-pointer casts need a bit reinterpretation. V parses a raw
		// `fn (Type)(expr)` as an anonymous function. A signature-specific union
		// also works on the pinned compiler, which rejects a generic helper whose
		// type parameter is itself a function type.
		if cast.starts_with('fn (') {
			helper_name := c.function_pointer_cast_helper_name(cast)
			c.gen('${helper_name}(voidptr(')
			c.expr(expr)
			c.gen('))')
			return ''
		}
		if cast.contains('*') {
			cast = '(${cast})'
		}
		c.gen('${cast}(')
		old_inside_switch := c.inside_switch
		if is_enum_ref_expr(expr) {
			c.inside_switch = 0
		}
		c.expr(expr)
		c.inside_switch = old_inside_switch
		c.gen(')')
	} else if node.kindof(.conditional_operator) {
		// ? :
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
		// Detect C assert() macro pattern: __builtin_expect(!(cond), 0) ? __assert_rtn(...) : (void)0
		// The ternary condition is ImplicitCastExpr -> CallExpr -> ImplicitCastExpr -> DeclRefExpr(__builtin_expect)
		mut is_assert := false
		if expr.kindof(.implicit_cast_expr) && expr.inner.len > 0
			&& expr.inner[0].kindof(.call_expr) && expr.inner[0].inner.len > 0
			&& expr.inner[0].inner[0].kindof(.implicit_cast_expr)
			&& expr.inner[0].inner[0].inner.len > 0
			&& expr.inner[0].inner[0].inner[0].ref_declaration.name == '__builtin_expect' {
			is_assert = true
		}
		if is_assert {
			// Skip assert macros — they're debug-only and produce invalid V syntax
			c.gen('0')
		} else {
			c.gen('if ')
			c.expr(expr)
			c.gen(' { ')
			c.expr(case1)
			c.gen(' } else {')
			c.expr(case2)
			c.gen('}')
		}
	} else if node.kindof(.break_stmt) {
		if c.inside_switch == 0 {
			c.genln('break')
		}
	} else if node.kindof(.continue_stmt) {
		label := if c.continue_labels.len > 0 { c.continue_labels.last() } else { '' }
		if label != '' {
			// The loop's C post-statements are emitted at the end of its V body.
			c.used_continue_labels[label] = true
			c.genln('unsafe { goto ${label} }')
		} else {
			c.genln('continue')
		}
	} else if node.kindof(.goto_stmt) {
		c.goto_stmt(node)
	} else if node.kindof(.opaque_value_expr) {
		// Process inner expression
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
	} else if node.kindof(.paren_list_expr) {
	} else if node.kindof(.va_arg_expr) {
		typ := c.prefix_external_type(c.convert_type(node.ast_type.qualified).name)
		if !c.declared_local_vars.exists('c2v_variadic_args') {
			if !c.is_dir {
				helper_key := 'cpp_native_va_arg_helper:${os.dir(c.outv)}'
				if helper_key !in c.generated_declarations {
					c.generated_declarations[helper_key] = true
					c.local_type_declarations << 'fn C.va_arg(voidptr, voidptr) voidptr\n\n'
				}
			}
			c.gen('C.va_arg(${typ}, ')
			if node.inner.len > 0 {
				c.expr(node.inner[0])
			} else {
				c.gen('C.va_list{}')
			}
			c.gen(')')
			return ''
		}
		helper_key := 'cpp_variadic_arg_helper:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_next_variadic_arg(args []voidptr, index &int) voidptr {\n\tcurrent := unsafe { *index }\n\tif current < 0 || current >= args.len {\n\t\treturn unsafe { nil }\n\t}\n\tvalue := args[current]\n\tunsafe { *index = current + 1 }\n\treturn value\n}\n\n'
		}
		if typ.starts_with('&') {
			c.gen('unsafe { ${typ}(c2v_next_variadic_arg(c2v_variadic_args, &')
		} else {
			c.gen('${typ}(c2v_next_variadic_arg(c2v_variadic_args, &')
		}
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		} else {
			c.gen('c2v_va_index')
		}
		if typ.starts_with('&') {
			c.gen(')) }')
		} else {
			c.gen('))')
		}
	} else if node.kindof(.compound_stmt) {
	} else if node.kindof(.offset_of_expr) {
		if c.project_require_no_stubs {
			c.verror('offsetof is not translated in strict mode: ${c.cur_file}')
		}
		// Compatibility mode retains the historical placeholder.
		c.gen('0 /*offsetof*/')
	} else if node.kindof(.gnu_null_expr) {
		if c.inside_unsafe {
			c.gen('nil')
		} else {
			c.gen('unsafe { nil }')
		}
	} else if node.kindof(.array_filler) {
	} else if node.kindof(.goto_stmt) {
	} else if node.kindof(.implicit_value_init_expr) {
	} else if node.kindof(.recovery_expr) {
		c.recovery_expr(node)
	} else if c.cpp_expr(node) {
	} else if node.kindof(.deprecated_attr) {
	} else if node.kindof(.full_comment) {
	} else if node.kindof(.text_comment) {
	} else if node.kindof(.compound_literal_expr) {
		c.compound_literal_expr(mut node)
	} else if node.kindof(.bad) {
		vprintln('BAD node in expr()')
		vprintln(node.str())
	} else if node.kindof(.predefined_expr) {
		v_predefined := match node.name {
			'__FUNCTION__', '__func__' { '@FN.str' } // .str for C compatibility
			'__line__' { '@LINE' }
			'__file__' { '@FILE' }
			else { '' }
		}

		if v_predefined != '' {
			c.gen(v_predefined)
		} else {
			if c.project_require_no_stubs {
				c.verror('unhandled predefined expression ${node.name} in ${c.cur_file}')
			}
			eprintln('\n\nUnhandled PredefinedExpr: ${node.name}')
			eprintln(node.str())
		}
	} else {
		if c.project_require_no_stubs {
			c.verror('unhandled expression node ${node.kind} in ${c.current_fn_v_name} at ${c.cur_file}:${node.location.line} (offset ${node.range.begin.offset})')
		}
		eprintln('WARNING: Unhandled expr() node {${node.kind}} (cur_file: "${c.cur_file}")')
		c.gen('/* unhandled: ${node.kind} */')
	}
	return node.value.to_str() // get_val(0)
}

fn (mut c C2V) name_expr(node &Node) {
	// `GREEN` => `Color.GREEN`
	// Find the enum that has this value
	// vals:
	// ["int", "EnumConstant", "MT_SPAWNFIRE", "int"]
	is_enum_val := node.ref_declaration.kind == .enum_constant_decl
	is_func_call := node.ref_declaration.kind == .function_decl
	is_cpp_method_ref := node.ref_declaration.kind == .cxx_method_decl
	if is_func_call && node.ref_declaration.id != '' {
		if function_name := c.cpp_function_decl_names[node.ref_declaration.id] {
			c.gen(function_name)
			return
		}
	}
	// A local can legitimately have the same spelling as a C++ static member.
	// Clang declaration ids are exact, so resolve them before the name-only
	// static-member fallback. This is especially common in instantiated template
	// methods whose local names could otherwise be rewritten
	// to an unrelated class static.
	if node.ref_declaration.id != '' && node.ref_declaration.kind in [.var_decl, .parm_var_decl] {
		if local_name := c.local_decl_v_names[node.ref_declaration.id] {
			if node.ref_declaration.id in c.cpp_primitive_reference_decls {
				if c.inside_unsafe {
					c.gen('*${local_name}')
				} else {
					c.gen('unsafe { *${local_name} }')
				}
			} else {
				c.gen(local_name)
			}
			return
		}
		if static_global_name := c.file_static_global_decl_v_names[node.ref_declaration.id] {
			c.gen(static_global_name)
			return
		}
	}
	if node.ref_declaration.kind == .var_decl && node.ref_declaration.id != '' {
		if static_name := c.cpp_static_member_decl_names[node.ref_declaration.id] {
			c.gen(static_name)
			return
		}
	}
	if is_cpp_method_ref && node.ref_declaration.id != '' {
		if method_name := c.cpp_method_decl_names[node.ref_declaration.id] {
			c.gen(method_name)
			return
		}
	}
	is_namespace_var := node.ref_declaration.id in c.namespace_var_ids
	if node.ref_declaration.kind == .var_decl && !is_namespace_var
		&& node.ref_declaration.name in c.cpp_ambiguous_static_members {
		owner := if c.current_static_init_owner != '' {
			c.current_static_init_owner
		} else {
			c.cur_class
		}
		if owner != '' {
			is_const := c.convert_type(node.ref_declaration.ast_type.qualified).is_const
			c.gen(cpp_static_member_v_name(owner, node.ref_declaration.name, is_const))
			return
		}
	}
	if node.ref_declaration.kind == .var_decl && !is_namespace_var
		&& node.ref_declaration.name !in c.cpp_ambiguous_static_members {
		if static_name := c.cpp_static_member_v_names[node.ref_declaration.name] {
			c.gen(static_name)
			return
		}
	}
	if node.ref_declaration.kind == .non_type_template_parm_decl {
		if value := c.cpp_template_values[node.ref_declaration.name] {
			c.gen(value)
			return
		}
	}
	mut c_name := node.ref_declaration.name
	if is_enum_val {
		c_name = c.enum_value_aliases[c_name] or { c_name }
	}
	mut v_name := c_name
	if is_func_call && c_name in c.external_c_fn_declarations {
		c.gen('C.${c_name}')
		return
	}
	c_known_name := c_known_symbol_v_name(c_name)
	if (is_enum_val || is_func_call) && c_known_name != ''
		&& (!is_func_call || !c.is_cpp || c.function_ref_has_c_linkage(node.ref_declaration)) {
		if is_func_call {
			float_overload := c_float_math_overload_v_name(c_name, node.ref_declaration.ast_type.qualified)
			if float_overload != '' {
				c.gen(float_overload)
				return
			}
		}
		c.gen(c_known_name)
		return
	}
	if !is_enum_val && !is_func_call {
		if static_name := c.static_local_vars[c_name] {
			c.gen(static_name)
			return
		}
		extern_global_name := c.extern_global_v_name(c_name)
		if extern_global_name != '' {
			c.gen(extern_global_name)
			return
		}
	}

	if is_enum_val {
		c_enum_val := c_name
		mut need_full_enum := true // need `Color.green` instead of just `.green`

		if c.inside_switch_enum {
			// In match/switch arms, prefer short enum syntax `.val`.
			// Fully-qualified enum names can break multi-value match arms.
			need_full_enum = false
		}
		if c.inside_array_index {
			need_full_enum = true
		}
		enum_name := c.enum_val_to_enum_name(c_enum_val)
		if c.inside_array_index {
			// `foo[ENUM_VAL]` => `foo(int(ENUM_NAME.ENUM_VAL))`
			c.gen('int(')
		}
		if need_full_enum {
			c.gen(enum_name)
		}
		if enum_name == '' && c.is_system_enum_constant(c_enum_val) {
			if c.inside_switch_enum {
				c.gen('int(C.${c_enum_val})')
			} else {
				c.gen('C.${c_enum_val}')
			}
			if c.inside_array_index {
				c.gen(')')
			}
			return
		}
		if c_enum_val !in ['true', 'false'] && enum_name != '' {
			// Don't add a `.` before "const" enum vals so that e.g. `tmbbox[BOXLEFT]`
			// won't get translated to `tmbbox[.boxleft]`
			// (empty enum name means its enum vals are consts)

			c.gen('.')
		}
	} else if is_func_call {
		if c_name in c.extern_fns {
			c_name = 'C.${c_name}'
		}
	}

	if is_enum_val {
		v_name = c_identifier_to_v_name(c_name)
	} else if is_cpp_method_ref {
		v_name = method_base_name_from_cpp_name(c_name)
	} else if c_name !in c.globals || c_name in c.consts {
		// Functions and variables are all snake_case in V
		// Constants also need to be snake_case
		if is_func_call {
			if fn_name := c.fns[c_name] {
				v_name = fn_name
			} else {
				v_name = c_identifier_to_v_name(c_name)
			}
		} else if c_stdio_stream_v_name(c_name) != '' {
			stream_name := c_stdio_stream_v_name(c_name)
			v_name = stream_name
		} else {
			v_name = c_identifier_to_v_name(c_name)
		}
		if v_name.starts_with('c.') {
			v_name = 'C.' + v_name[2..]
		}
	}

	c.gen(filter_name(v_name, node.ref_declaration.kind == .var_decl || is_cpp_method_ref))
	if is_enum_val && c.inside_array_index {
		c.gen(')')
	}
}

// is_cpp_reference_param_ref reports whether an expression reads a reference
// parameter that is dereferenced on use (see cpp_primitive_reference_decls).
fn (c &C2V) is_cpp_reference_param_ref(node &Node) bool {
	mut current := unsafe { node }
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind in [
			'LValueToRValue',
			'NoOp',
		])) {
		current = unsafe { &current.inner[0] }
	}
	return current.kindof(.decl_ref_expr) && current.ref_declaration.id != ''
		&& current.ref_declaration.id in c.cpp_primitive_reference_decls
}

fn (c &C2V) cpp_primitive_reference_v_name(node &Node) ?string {
	mut current := *node
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind == 'NoOp')) {
		current = current.inner[0]
	}
	if !current.kindof(.decl_ref_expr) || current.ref_declaration.id == ''
		|| current.ref_declaration.id !in c.cpp_primitive_reference_decls {
		return none
	}
	if local_name := c.local_decl_v_names[current.ref_declaration.id] {
		return local_name
	}
	return none
}

fn (c &C2V) cpp_record_reference_lvalue_v_name(node &Node) ?string {
	mut current := *node
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind == 'NoOp')) {
		current = current.inner[0]
	}
	if !current.kindof(.decl_ref_expr) || current.ref_declaration.id == ''
		|| current.ref_declaration.id in c.cpp_primitive_reference_decls
		|| !current.ref_declaration.ast_type.qualified.trim_space().ends_with('&') {
		return none
	}
	if local_name := c.local_decl_v_names[current.ref_declaration.id] {
		return local_name
	}
	return none
}

fn unwrap_struct_init_expr(node Node) Node {
	mut current := node
	for current.inner.len > 0 && (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
		|| current.kindof(.constant_expr)) {
		current = current.inner[0]
	}
	return current
}

fn is_zero_initializer_expr(node Node) bool {
	base := unwrap_struct_init_expr(node)
	base_kind := if base.kind == .bad && base.kind_str != '' {
		convert_str_into_node_kind(base.kind_str)
	} else {
		base.kind
	}
	if base_kind == .implicit_value_init_expr {
		return true
	}
	if base_kind in [.integer_literal, .character_literal] {
		return base.value.to_str().i64() == 0
	}
	if base_kind == .floating_literal {
		return base.value.to_str().f64() == 0.0
	}
	if base_kind == .cxx_construct_expr && base.inner.len == 0
		&& base.ctor_type.qualified in ['void () throw()', 'void () noexcept'] {
		// Value-initializing a C record in C++ (`struct stat value = {}`) runs the
		// implicit trivial default constructor of each record member.
		return true
	}
	if base_kind != .init_list_expr {
		return false
	}
	return base.inner.all(is_zero_initializer_expr(it))
		&& base.array_filler.all(is_zero_initializer_expr(it))
}

fn (c &C2V) struct_init_cast_type(expected_type string, child Node) string {
	expected := expected_type.trim_space()
	if expected == '' {
		return ''
	}
	resolved_expected := c.resolve_type_alias(expected)
	child_type := c.resolve_type_alias(c.convert_type(node_effective_type_name(child)).name)
	if child_type == resolved_expected && c.implicit_numeric_cast_will_render(child) {
		return ''
	}
	base := unwrap_struct_init_expr(child)
	if base.kindof(.decl_ref_expr) && base.ref_declaration.kind == .enum_constant_decl {
		enum_type := c.enum_val_to_enum_name(base.ref_declaration.name)
		if enum_type == expected {
			return ''
		}
		if expected in v_primitive_type_names || expected.starts_with('C.') {
			return expected
		}
	}
	if base.kindof(.character_literal)
		&& resolved_expected in ['i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
			'usize'] {
		return expected
	}
	if base.kindof(.integer_literal)
		&& resolved_expected in ['i8', 'i16', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize',
			'f32', 'f64'] {
		return expected
	}
	if base.kindof(.floating_literal) && resolved_expected in ['f32', 'f64'] {
		return expected
	}
	return ''
}

fn (mut c C2V) init_list_expr(mut node Node) {
	t := node.ast_type.qualified
	// c.gen(' /* list init $t */ ')
	// C list init can be an array (`numbers = {1,2,3}` => `numbers = [1,2,3]``)
	// or a struct init (`user = {"Bob", 20}` => `user = {'Bob', 20}`)
	is_arr := t.contains('[')
	mut array_element_type := ''
	if is_arr {
		converted_array_type := c.convert_type(t).name
		first_close := converted_array_type.index(']') or { -1 }
		if first_close >= 0 && first_close + 1 < converted_array_type.len {
			array_element_type = converted_array_type[first_close + 1..]
		}
	}
	// Clang expands C's canonical `{0}` zero initializer into the first field
	// followed by ImplicitValueInitExpr nodes. It is semantically the same as an
	// empty V record literal and does not require a field layout, which is
	// especially important for records supplied by filtered system headers.
	is_empty_record_init := !is_arr && is_zero_initializer_expr(node)
	mut c_struct_name := ''
	if !is_arr {
		// Struct init
		if (t.contains('unnamed struct') || t.contains('unnamed union')
			|| t.contains('anonymous struct') || t.contains('anonymous union')
			|| t.contains('(unnamed at') || t.contains('(anonymous at'))
			&& c.last_declared_type_name != '' {
			// A local anonymous record declaration immediately precedes the variable
			// and initializer in Clang's DeclStmt. record_decl() assigns its stable V
			// name and saves it here; the AST type itself only contains a source path.
			c_struct_name = c.last_declared_type_name
		} else {
			c_struct_name = parse_c_struct_name(t)
		}
		// Sanitize C++ template types: Type<Arg> -> Type__Arg
		if c_struct_name.contains('<') {
			c_struct_name =
				c_struct_name.replace('<', '__').replace('>', '').replace('*', 'Ptr').replace(',', '_')
			c_struct_name = sanitize_type_token(c_struct_name)
		}
		converted_struct_literal := if c_struct_name != ''
			&& (t.contains('unnamed') || t.contains('anonymous')) {
			c.prefix_external_type(c.convert_type(c_struct_name).name)
		} else {
			c.prefix_external_type(c.convert_type(t).name)
		}
		struct_literal_name := if converted_struct_literal != '' {
			converted_struct_literal
		} else {
			c_struct_name.capitalize()
		}
		c.genln('${struct_literal_name}{')
		c.indent++
	} else {
		c.gen('[')
	}
	c.gen_comment(node)
	if is_empty_record_init {
		// The empty literal emitted above already zero-initializes every field.
	} else if node.array_filler.len > 0 {
		for mut child in node.array_filler {
			child.initialize_node_and_children()
		}
		mut child_indices := []int{cap: node.array_filler.len}
		// Clang 21 serializes a partially initialized fixed array with its
		// synthesized zero-fill element first, followed by the explicit source
		// elements. The filler semantically follows those elements, so restore
		// that order before emitting the V literal.
		if node.array_filler.len > 1 && is_zero_initializer_expr(node.array_filler[0]) {
			for i := 1; i < node.array_filler.len; i++ {
				if !node.array_filler[i].kindof(.implicit_value_init_expr) {
					child_indices << i
				}
			}
			child_indices << 0
		} else {
			for i, child in node.array_filler {
				if !child.kindof(.implicit_value_init_expr) {
					child_indices << i
				}
			}
		}
		for output_i, child_idx in child_indices {
			mut child := node.array_filler[child_idx]
			c.gen_comment(child)
			cast_type := c.struct_init_cast_type(array_element_type, child)
			if cast_type != '' {
				c.gen(cast_type + '(')
			}
			c.expr(child)
			if cast_type != '' {
				c.gen(')')
			}
			if output_i < child_indices.len - 1 {
				if child.kindof(.init_list_expr) {
					c.put_on_same_line_as_close_brace(',', true)
				} else {
					c.gen(', ')
				}
			}
		}
	} else {
		mut struct_ := Struct{}
		if c_struct_name != '' && !is_empty_record_init {
			struct_ = c.structs[c_struct_name] or {
				c.structs[c_struct_name.capitalize()] or {
					if c.project_require_no_stubs {
						child_kinds := node.inner.map('${if it.kind_str != '' {
							it.kind_str
						} else {
							it.kind.str()
						}}:${node_effective_type_name(it)}:${it.ctor_type.qualified}:${it.inner.len}')
						filler_kinds := node.array_filler.map(if it.kind_str != '' {
							it.kind_str
						} else {
							it.kind.str()
						})
						c.verror('missing struct layout ${c_struct_name.capitalize()} for aggregate initializer in ${c.cur_file}:${node.location.line} (${node.kind_str}, children=${child_kinds}, filler=${filler_kinds})')
					}
					c.genln('//FAILED TO FIND STRUCT ${c_struct_name.capitalize()}')
					Struct{}
				}
			}
		}
		for i, mut child in node.inner {
			c.gen_comment(child)
			if child.kind == .bad {
				child.kind =
					convert_str_into_node_kind(child.kind_str) // array_filler nodes were not handled by set_kind_enum
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

			mut expected_field_type := ''
			mut cast_type := if is_arr {
				c.struct_init_cast_type(array_element_type, child)
			} else {
				''
			}
			if !is_arr && i < struct_.field_types.len {
				expected_field_type = struct_.field_types[i]
				cast_type = c.struct_init_cast_type(expected_field_type, child)
			}
			if cpp_fixed_array_length(expected_field_type) > 0 && child.kindof(.string_literal) {
				// A C string initializes the bytes of an inline character array. C
				// cannot initialize an array member from an array expression, so spell
				// the bytes as a fixed array literal.
				c.gen(c_string_fixed_array_literal(child.value.to_str(), expected_field_type))
			} else if cast_type != '' {
				c.gen(cast_type + '(')
				c.expr(child)
				c.gen(')')
			} else {
				c.expr(child)
			}
			if field_name != '' {
				c.genln('')
			} else if i < node.inner.len - 1 {
				if child.kindof(.init_list_expr) {
					c.put_on_same_line_as_close_brace(',', true)
				} else {
					c.gen(', ')
				}
			}
		}
	}
	is_fixed := node.ast_type.qualified.contains('[') && node.ast_type.qualified.contains(']')
	if !is_arr {
		c.indent--
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
	// V requires identifiers (variable/field names) to start with lowercase.
	// If the first character is uppercase, lowercase it.
	if name.len > 0 && name[0] >= `A` && name[0] <= `Z` {
		return name[0..1].to_lower() + name[1..]
	}
	return name
}

fn normalize_path_for_match(path string) string {
	return path.replace('\\', '/')
}

fn (c &C2V) project_output_relative_path(source_path string, source_ext string, output_ext string) string {
	mut rel_path := normalize_path_for_match(source_path)
	if rel_path.starts_with('./') {
		rel_path = rel_path[2..]
	}
	if source_ext != '' && rel_path.ends_with(source_ext) {
		rel_path = rel_path[..rel_path.len - source_ext.len]
	}
	if c.project_single_module {
		// A V directory is one module and does not recursively include child directories.
		// Encode the original relative path in the filename so equally named translation
		// units (for example game/Entity.cpp and renderer/RenderEntity.cpp) stay unique.
		rel_path = rel_path.replace('/', '__')
	}
	return rel_path + output_ext
}

fn is_synthetic_source_path(path string) bool {
	p := path.trim_space()
	if p == '' {
		return true
	}
	return p.starts_with('<')
}

fn source_path_exists(path string) bool {
	if is_synthetic_source_path(path) {
		return false
	}
	return os.exists(path)
}

// has_template_placeholder_type reports whether a signature still mentions a
// template type parameter, i.e. belongs to an uninstantiated template pattern.
fn (c &C2V) has_template_placeholder_type(sig string) bool {
	if c.cpp_template_param_names.len == 0 {
		return false
	}
	mut norm := sig
	for ch in ['*', '&', '(', ')', ',', '[', ']', '<', '>'] {
		norm = norm.replace(ch, ' ')
	}
	for tok in norm.split(' ') {
		t := tok.trim_space()
		if t in c.cpp_template_param_names && t !in c.known_types && t !in c.project_known_types {
			return true
		}
	}
	return false
}

fn (mut c C2V) collect_cpp_template_param_names(node &Node) {
	if node.kindof(.template_type_parm_decl) && node.name != '' {
		c.cpp_template_param_names[node.name] = true
		c.cpp_template_param_names[node.name.capitalize()] = true
	}
	for child in node.inner {
		c.collect_cpp_template_param_names(&child)
	}
}

fn should_skip_source_path(path string, output_dirname string) bool {
	p := normalize_path_for_match(path)
	if p.contains('/.git/') || p.contains('/CMakeFiles/') || p.contains('/cmake-build/')
		|| p.contains('/build/') || p.contains('/dist/') || p.contains('/docs/') {
		return true
	}
	// Skip generated translation output folders to prevent recursive retranslating.
	if output_dirname != ''
		&& (p.contains('/${output_dirname}/') || p.ends_with('/${output_dirname}')) {
		return true
	}
	return false
}

fn strip_cpp_only_flags(flags string) string {
	mut res := flags
	for cpp_flag in ['-std=c++11', '-std=gnu++11', '-std=c++14', '-std=gnu++14', '-std=c++17',
		'-std=gnu++17', '-std=c++20', '-std=gnu++20'] {
		res = res.replace(cpp_flag, '')
	}
	return res
}

fn strip_cpp_line_comment(line string) string {
	comment_idx := line.index('//') or { return line }
	return line[..comment_idx]
}

fn extract_cpp_method_def_token(line string) string {
	if !line.contains('::') || !line.contains('(') {
		return ''
	}
	before_paren := collapse_ascii_whitespace(strip_cpp_line_comment(line).all_before('('))
	if before_paren == '' || !before_paren.contains('::') {
		return ''
	}
	parts := before_paren.split(' ').filter(it.trim_space() != '')
	if parts.len == 0 {
		return ''
	}
	token := parts[parts.len - 1].trim_space()
	if !token.contains('::') {
		return ''
	}
	return token
}

fn sanitize_cpp_metadata_source(source string) string {
	mut out := strings.new_builder(source.len)
	mut i := 0
	mut in_line_comment := false
	mut in_block_comment := false
	mut quote := u8(0)
	for i < source.len {
		ch := source[i]
		if in_line_comment {
			if ch == `\n` {
				in_line_comment = false
				out.write_u8(ch)
			} else {
				out.write_u8(` `)
			}
			i++
			continue
		}
		if in_block_comment {
			if ch == `*` && i + 1 < source.len && source[i + 1] == `/` {
				out.write_string('  ')
				i += 2
				in_block_comment = false
			} else {
				out.write_u8(if ch == `\n` { ch } else { ` ` })
				i++
			}
			continue
		}
		if quote != 0 {
			if ch == `\\` && i + 1 < source.len {
				out.write_string('  ')
				i += 2
				continue
			}
			out.write_u8(if ch == `\n` { ch } else { ` ` })
			if ch == quote {
				quote = 0
			}
			i++
			continue
		}
		if ch == `/` && i + 1 < source.len && source[i + 1] == `/` {
			out.write_string('  ')
			i += 2
			in_line_comment = true
			continue
		}
		if ch == `/` && i + 1 < source.len && source[i + 1] == `*` {
			out.write_string('  ')
			i += 2
			in_block_comment = true
			continue
		}
		if ch == `'` || ch == `"` {
			quote = ch
			out.write_u8(` `)
			i++
			continue
		}
		out.write_u8(ch)
		i++
	}
	return out.str()
}

fn cpp_class_body_has_direct_pure_virtual(source string, open_brace int, close_brace int) bool {
	mut depth := 1
	mut i := open_brace + 1
	for i < close_brace {
		ch := source[i]
		if ch == `{` {
			depth++
			i++
			continue
		}
		if ch == `}` {
			depth--
			i++
			continue
		}
		if depth == 1 && ch == `=` {
			mut j := i + 1
			for j < close_brace && source[j].is_space() {
				j++
			}
			if j < close_brace && source[j] == `0` {
				j++
				for j < close_brace && source[j].is_space() {
					j++
				}
				if j < close_brace && source[j] == `;` {
					return true
				}
			}
		}
		i++
	}
	return false
}

fn scan_cpp_abstract_type_names(source string) []string {
	clean := sanitize_cpp_metadata_source(source)
	mut names := map[string]bool{}
	mut i := 0
	for i < clean.len {
		tail := clean[i..]
		if !((tail.starts_with('class') || tail.starts_with('struct'))
			&& (i == 0 || !is_identifier_char(clean[i - 1]))) {
			i++
			continue
		}
		keyword_len := if tail.starts_with('class') { 5 } else { 6 }
		keyword_end := i + keyword_len
		if keyword_end < clean.len && is_identifier_char(clean[keyword_end]) {
			i = keyword_end
			continue
		}
		mut cursor := keyword_end
		for cursor < clean.len && clean[cursor].is_space() {
			cursor++
		}
		mut name_start := cursor
		for cursor < clean.len && is_identifier_char(clean[cursor]) {
			cursor++
		}
		if cursor == name_start {
			i = keyword_end
			continue
		}
		mut name := clean[name_start..cursor]
		// Export/visibility macros can appear between `class` and the actual name.
		if is_all_upper_identifier(name) {
			for cursor < clean.len && clean[cursor].is_space() {
				cursor++
			}
			name_start = cursor
			for cursor < clean.len && is_identifier_char(clean[cursor]) {
				cursor++
			}
			if cursor > name_start {
				name = clean[name_start..cursor]
			}
		}
		mut open_brace := -1
		mut is_record_definition := true
		mut scan := cursor
		for scan < clean.len {
			if clean[scan] == `;` {
				break
			}
			if clean[scan] == `(` || clean[scan] == `)` {
				// `const struct Foo *arg) {` is a function definition, not a
				// definition of Foo. Do not consume the function body as a record.
				is_record_definition = false
				break
			}
			if clean[scan] == `{` {
				open_brace = scan
				break
			}
			scan++
		}
		if !is_record_definition || open_brace < 0 {
			i = scan + 1
			continue
		}
		mut depth := 1
		mut close_brace := open_brace + 1
		for close_brace < clean.len && depth > 0 {
			if clean[close_brace] == `{` {
				depth++
			} else if clean[close_brace] == `}` {
				depth--
			}
			close_brace++
		}
		if depth == 0 && cpp_class_body_has_direct_pure_virtual(clean, open_brace, close_brace - 1) {
			names[name] = true
		}
		// Continue inside the body so nested abstract classes are discovered too.
		i = open_brace + 1
	}
	mut result := names.keys()
	result.sort()
	return result
}

// common_source_root returns the deepest directory containing every file.
fn common_source_root(files []string) string {
	mut root := ''
	for file in files {
		dir := os.dir(os.real_path(file))
		if root == '' {
			root = dir
			continue
		}
		for root != '' && root != '/' && dir != root && !dir.starts_with(root + '/') {
			root = os.dir(root)
		}
	}
	return if root == '' { '.' } else { root }
}

fn (mut c2v C2V) scan_project_dir_method_defs(files []string) {
	c2v.project_dir_method_defs.clear()
	mut metadata_files := map[string]bool{}
	for file in files {
		metadata_files[file] = true
	}
	// Headers anywhere under the translated sources' common root can declare the
	// abstract classes (V interfaces) that the first translation units refer to.
	header_root := common_source_root(files)
	for extension in ['.h', '.hh', '.hpp', '.hxx'] {
		for file in os.walk_ext(header_root, extension) {
			metadata_files[file] = true
		}
	}
	for file in metadata_files.keys() {
		source := os.read_file(file) or { continue }
		for cpp_name in scan_cpp_abstract_type_names(source) {
			v_name := c2v.add_struct_name(mut c2v.types, cpp_name)
			if is_valid_v_receiver_type_name(v_name) {
				c2v.cpp_abstract_types[v_name] = true
			}
		}
	}
	for file in files {
		ext := os.file_ext(file)
		if ext !in ['.cpp', '.cc', '.cxx', '.C'] {
			continue
		}
		rel_path := if file.starts_with('./') { file[2..] } else { file }
		out_v := os.join_path(c2v.project_output_root, c2v.project_output_relative_path(rel_path, ext, '.v'))
		out_dir := os.dir(out_v)
		if out_dir == '' {
			continue
		}
		source := os.read_file(file) or { continue }
		for raw_line in source.split_into_lines() {
			token := extract_cpp_method_def_token(raw_line)
			if token == '' {
				continue
			}
			class_name_raw := normalize_cpp_name_fragment(token.all_before_last('::'))
			method_name_raw := token.all_after_last('::').trim_space()
			if class_name_raw == '' || method_name_raw == '' || class_name_raw.contains('<') {
				continue
			}
			method_name := method_base_name_from_cpp_name(method_name_raw)
			if method_name == '' || !is_valid_v_callable_name(method_name) {
				continue
			}
			class_name := c2v.add_struct_name(mut c2v.types, class_name_raw)
			if !is_valid_v_receiver_type_name(class_name) {
				continue
			}
			c2v.project_dir_method_defs['${out_dir}|${class_name}.${method_name}'] = true
		}
	}
}

fn compute_dir_scan_root(path string, c2v &C2V) string {
	root_abs := os.real_path(path)
	scan_abs := os.real_path(c2v.source_scan_root)
	if scan_abs == '' || scan_abs == root_abs {
		return '.'
	}
	if scan_abs.starts_with(root_abs + os.path_separator.str()) {
		rel := scan_abs[root_abs.len + 1..]
		if rel != '' {
			return './' + rel
		}
	}
	return '.'
}

fn (c2v &C2V) reset_output_root() {
	if !c2v.is_dir || c2v.project_output_root == '' {
		return
	}
	if !os.exists(c2v.project_output_root) {
		return
	}
	// Safety guard: only remove named subdirectories, never obvious root-like targets.
	bad_targets := ['/', '.', '..', os.home_dir(), os.getwd()]
	if c2v.project_output_root in bad_targets {
		return
	}
	os.rmdir_all(c2v.project_output_root) or {
		eprintln('WARNING: failed to clean output dir "${c2v.project_output_root}": ${err}')
	}
}

fn (c2v &C2V) source_manifest_files() []string {
	if c2v.project_source_manifest == '' {
		return []string{}
	}
	manifest_path := if os.is_abs_path(c2v.project_source_manifest) {
		c2v.project_source_manifest
	} else {
		os.join_path(c2v.project_folder, c2v.project_source_manifest)
	}
	if !os.exists(manifest_path) {
		c2v.verror('source manifest does not exist: ${manifest_path}')
	}
	cwd := os.real_path(os.getwd())
	mut files := []string{}
	mut seen := map[string]bool{}
	manifest_lines := os.read_lines(manifest_path) or {
		c2v.verror('cannot read source manifest ${manifest_path}: ${err}')
		return []string{}
	}
	for raw_line in manifest_lines {
		line := raw_line.all_before('#').trim_space()
		if line == '' {
			continue
		}
		abs_path := os.real_path(if os.is_abs_path(line) {
			line
		} else {
			os.join_path(c2v.project_folder, line)
		})
		if abs_path == '' || !os.exists(abs_path) {
			c2v.verror('source manifest entry does not exist: ${line}')
		}
		ext := os.file_ext(abs_path)
		if ext !in ['.c', '.cpp', '.cc', '.cxx', '.C'] {
			c2v.verror('unsupported source extension in manifest: ${line}')
		}
		mut path := abs_path
		if cwd != '' && abs_path.starts_with(cwd + os.path_separator.str()) {
			path = './' + normalize_path_for_match(abs_path[cwd.len + 1..])
		}
		if path !in seen {
			files << path
			seen[path] = true
		}
	}
	return files
}

fn (c2v &C2V) native_manifest_files() []string {
	if c2v.project_native_manifest == '' {
		return []string{}
	}
	manifest_path := if os.is_abs_path(c2v.project_native_manifest) {
		c2v.project_native_manifest
	} else {
		os.join_path(c2v.project_folder, c2v.project_native_manifest)
	}
	manifest_lines := os.read_lines(manifest_path) or {
		c2v.verror('cannot read native source manifest ${manifest_path}: ${err}')
		return []string{}
	}
	mut files := []string{}
	for raw_line in manifest_lines {
		line := raw_line.all_before('#').trim_space()
		if line == '' {
			continue
		}
		abs_path := os.real_path(if os.is_abs_path(line) {
			line
		} else {
			os.join_path(c2v.project_folder, line)
		})
		if abs_path == '' || !os.exists(abs_path) {
			c2v.verror('native source manifest entry does not exist: ${line}')
		}
		if os.file_ext(abs_path) !in ['.c', '.m'] {
			c2v.verror('native source manifest only accepts C/Objective-C sources: ${line}')
		}
		files << abs_path
	}
	return files
}

fn trim_compiler_flag_quotes(value string) string {
	trimmed := value.trim_space()
	if trimmed.len >= 2
		&& ((trimmed[0] == `'` && trimmed[trimmed.len - 1] == `'`)
			|| (trimmed[0] == `"` && trimmed[trimmed.len - 1] == `"`)) {
		return trimmed[1..trimmed.len - 1]
	}
	return trimmed
}

fn configured_include_dirs(project_folder string, compiler_flags string) []string {
	tokens := compiler_flags.fields()
	mut dirs := []string{}
	mut seen := map[string]bool{}
	mut i := 0
	for i < tokens.len {
		mut include_path := ''
		if tokens[i] == '-I' && i + 1 < tokens.len {
			i++
			include_path = tokens[i]
		} else if tokens[i].starts_with('-I') && tokens[i].len > 2 {
			include_path = tokens[i][2..]
		}
		include_path = trim_compiler_flag_quotes(include_path)
		if include_path != '' {
			candidate := if os.is_abs_path(include_path) {
				include_path
			} else {
				os.join_path(project_folder, include_path)
			}
			resolved := os.real_path(candidate)
			if resolved != '' && resolved !in seen {
				dirs << resolved
				seen[resolved] = true
			}
		}
		i++
	}
	return dirs
}

fn (c2v &C2V) verify_no_generated_stubs() {
	if !c2v.project_require_no_stubs {
		return
	}
	markers := [
		"panic('c2v globals stub')",
		'// c2v skeleton output:',
		'// c2v skeleton dependency declarations',
		'// Temporarily reduced:',
		'fn main() {}',
	]
	mut has_main := false
	for file in os.walk_ext(c2v.project_output_root, '.v') {
		src := os.read_file(file) or {
			c2v.verror('cannot audit generated file ${file}: ${err}')
			return
		}
		for marker in markers {
			if src.contains(marker) {
				c2v.verror('strict translation generated placeholder `${marker}` in ${file}')
			}
		}
		if src.contains('fn main() {') {
			has_main = true
		}
	}
	if c2v.project_require_main && !has_main {
		c2v.verror('strict project did not translate a main entrypoint')
	}
}

fn main() {
	if os.args.len < 2 {
		eprintln('Usage:')
		eprintln('  c2v file.c')
		eprintln('  c2v wrapper file.h')
		eprintln('  c2v folder/')
		eprintln('  c2v version # show the tool version')
		eprintln('')
		eprintln('args:')
		eprintln('  -keep_ast\t\tkeep ast files')
		eprintln('  -print_tree\t\tprint the entire tree')
		eprintln('  -check_comment\tcheck unused comments')
		exit(1)
	}
	vprintln(os.args.str())

	if os.args.len > 1 && (os.args[1] == 'version' || os.args[1] == '--version') {
		println('c2v version ${version}')
		exit(0)
	}

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
		scan_root := compute_dir_scan_root(path, c2v)
		println('"${path}" is a directory, processing all C/C++ files in "${scan_root}" recursively...\n')
		c2v.reset_output_root()
		mut files := c2v.source_manifest_files()
		if files.len == 0 {
			files << os.walk_ext(scan_root, '.c')
			files << os.walk_ext(scan_root, '.cpp')
			files << os.walk_ext(scan_root, '.cc')
			files << os.walk_ext(scan_root, '.cxx')
			files = files.filter(!should_skip_source_path(it, c2v.project_output_dirname))
		}
		if !is_wrapper {
			if files.len > 0 {
				files.sort()
				if c2v.project_has_cpp
					|| files.any(os.file_ext(it) in ['.cpp', '.cc', '.cxx', '.C']) {
					c2v.scan_project_dir_method_defs(files)
				}
				for file in files {
					c2v.translate_file(file)
					// Collect again after `translate_file` has returned, so conservative GC
					// cannot retain its large JSON/tree locals through stale stack roots.
					gc_collect()
				}
				c2v.sanitize_single_module_outputs()
				c2v.rewrite_project_defined_function_decls()
				c2v.rewrite_project_defined_global_refs()
				c2v.save_globals()
				c2v.sanitize_strict_cpp_backend_outputs()
				c2v.verify_no_generated_stubs()
			}
		}
	} else {
		c2v.translate_file(path)
	}
	delta_ticks := time.ticks() - c2v.translation_start_ticks
	println('Translated ${c2v.translations:3} files in ${delta_ticks:5} ms.')
}

fn strip_redundant_multiline_value_dereferences(src string) string {
	mut lines := src.split('\n')
	mut pending_closing_paren := false
	for i, line in lines {
		if line.contains(':= *(unsafe {') || line.contains('= *(unsafe {') {
			lines[i] = line.replace('*(unsafe {', 'unsafe {')
			pending_closing_paren = true
			continue
		}
		if pending_closing_paren && line.trim_space() == '})' {
			lines[i] = line[..line.len - 2] + '}'
			pending_closing_paren = false
		}
	}
	return lines.join('\n')
}

fn sanitize_strict_cpp_backend_output(src string) string {
	mut s := strip_redundant_multiline_value_dereferences(src)
	s = ensure_variadic_argument_slice_setup(s)
	return s
}

fn ensure_variadic_argument_slice_setup(src string) string {
	lines := src.split('\n')
	mut result := []string{cap: lines.len}
	for i, line in lines {
		result << line
		if !line.contains('c2v_variadic_args ...voidptr)') || !line.trim_space().ends_with('{') {
			continue
		}
		if i + 1 < lines.len && lines[i + 1].trim_space().ends_with('c2v_set_variadic_args(c2v_variadic_args)') {
			continue
		}
		// Restore the caller's arguments when this variadic function returns.
		result << '\tc2v_caller_variadic_args := c2v_set_variadic_args(c2v_variadic_args)'
		result << '\tdefer {'
		result << '\t\tc2v_set_variadic_args(c2v_caller_variadic_args)'
		result << '\t}'
	}
	return result.join('\n')
}

fn (c2v &C2V) sanitize_strict_cpp_backend_outputs() {
	if !c2v.project_single_module || !c2v.project_has_cpp {
		return
	}
	for file in os.walk_ext(c2v.project_output_root, '.v') {
		src := os.read_file(file) or {
			c2v.verror('cannot read generated file for strict C++ backend sanitization ${file}: ${err}')
			return
		}
		sanitized := sanitize_strict_cpp_backend_output(src)
		if sanitized != src {
			os.write_file(file, sanitized) or {
				c2v.verror('cannot write strict C++ backend sanitization ${file}: ${err}')
				return
			}
		}
	}
}

// insert_comment_node recursively insert comment node into c2v.tree.inner
fn (mut c C2V) insert_comment_node(mut root_node Node, comment_node Node) bool {
	mut inserted := false
	mut begin_offset := 0
	mut end_offset := 0
	for mut node in root_node.inner {
		begin_offset = if node.range.begin.offset == 0 {
			node.range.begin.expansion_file.offset
		} else {
			node.range.begin.offset
		}
		end_offset = if node.range.end.offset == 0 {
			node.range.end.expansion_file.offset
		} else {
			node.range.end.offset
		}
		if begin_offset < comment_node.location.offset && end_offset > comment_node.location.offset {
			inserted = c.insert_comment_node(mut node, comment_node)
			return false
		} else if begin_offset > comment_node.location.offset {
			vprintln('${@FN} ${comment_node.comment}')
			vprintln('offset=[${node.location.offset},${node.range.begin.offset},${node.range.end.offset}] ${node.kind} n="${node.name}"\n')
			comment_id := node.unique_id
			if v := c.can_output_comment[comment_id] {
				if node.comment.len == 0 {
					vprintln('${@FN} ERROR duplicate node id! ${comment_id}=${v} node_id=${node.id} node_kind=${node.kind}')
				}
			}
			node.comment += comment_node.comment
			c.can_output_comment[comment_id] = true
			inserted = true
			return true
		}
	}
	if inserted == false {
		if c.is_dir {
			// In directory translation mode, unmapped comments are usually from inactive
			// preprocessor branches and create large comment-only blocks.
			return false
		}
		// Keep old behavior in single-file mode for test compatibility.
		root_node.inner << comment_node
		comment_id := comment_node.unique_id
		c.can_output_comment[comment_id] = true
	}
	return true
}

enum CommentState {
	s0
	s1
	s2
	s3
	s4
	s5
	s6
}

// parse_comment parse comment in the c file
// It use a DFA recognize the c comment // and /**/
// multi-line comment will convert to single comment
// Then it modify the c2v.tree, add the comment nodes to it based on the comment nodes' offset
fn (mut c2v C2V) parse_comment(mut root_node Node, path string) {
	if !source_path_exists(path) {
		return
	}
	str := os.read_file(path) or { return }
	// In dir mode, only collect comments inside this AST segment to avoid
	// repeated comment blocks from the same file across disjoint segments.
	mut seg_begin := 0
	mut seg_end := str.len
	if c2v.is_dir {
		seg_begin = int(1 << 30)
		seg_end = -1
		for node in root_node.inner {
			b := if node.range.begin.offset == 0 {
				node.range.begin.expansion_file.offset
			} else {
				node.range.begin.offset
			}
			e := if node.range.end.offset == 0 {
				node.range.end.expansion_file.offset
			} else {
				node.range.end.offset
			}
			if b < seg_begin {
				seg_begin = b
			}
			if e > seg_end {
				seg_end = e
			}
		}
		if seg_end < 0 {
			return
		}
	}

	mut curr_state := CommentState.s0
	mut comment_nodes := []Node{}
	mut comment := strings.new_builder(1024)
	mut comment_str := ''

	mut offset := 0
	mut location := NodeLocation{}
	mut comment_id := 0

	// scan c file for comments
	for c in str {
		match curr_state {
			.s0 {
				if c == `/` {
					location.offset = offset
					curr_state = .s3
				} else if c == `"` {
					curr_state = .s1
				} else if c == `'` {
					curr_state = .s2
				}
			}
			.s1 {
				if c == `"` {
					curr_state = .s0
				}
			}
			.s2 {
				if c == `'` {
					curr_state = .s0
				}
			}
			.s3 {
				if c == `*` {
					comment = strings.new_builder(1024)
					comment.write_string('/*')
					curr_state = .s4
				} else if c == `/` {
					comment = strings.new_builder(1024)
					comment.write_string('//')
					curr_state = .s6
				} else {
					curr_state = .s0
				}
			}
			.s4 {
				if c == `*` {
					curr_state = .s5
				}
				comment.write_rune(c)
			}
			.s5 {
				if c == `/` {
					comment.write_rune(c)
					comment_str = comment.str()
					// convert multi-line comment to single-line comment
					comment_str = comment_str.replace('\n', '\n//')
					comment_str = '//' + comment_str[2..comment_str.len - 2] + '\n'
					mut comment_lines := []string{}
					for line in comment_str.split('\n') {
						comment_lines << line.trim_right(' \t')
					}
					comment_str = comment_lines.join('\n') + '\n'
					vprintln('multi-line comment[offset:${location.offset}] : ${comment_str}')
					if location.offset >= seg_begin && location.offset <= seg_end {
						comment_key := '${path}:${location.offset}:${comment_str}'
						if c2v.seen_comments[comment_key] {
							curr_state = .s0
							continue
						}
						c2v.seen_comments[comment_key] = true
						comment_nodes << Node{
							unique_id: c2v.cnt
							id: 'text_comment_${comment_id}'
							comment: comment_str
							location: location
							kind: .text_comment
							kind_str: 'TextComment'
						}
						c2v.cnt++
						comment_id++
					}
					curr_state = .s0
				} else {
					curr_state = .s4
				}
			}
			.s6 {
				if c == `\n` {
					comment.write_rune(c)
					comment_str = comment.str()
					vprintln('single-line comment[offset:${location.offset}] : ${comment_str}')
					if location.offset >= seg_begin && location.offset <= seg_end {
						comment_key := '${path}:${location.offset}:${comment_str}'
						if c2v.seen_comments[comment_key] {
							curr_state = .s0
							continue
						}
						c2v.seen_comments[comment_key] = true
						comment_nodes << Node{
							unique_id: c2v.cnt
							id: 'text_comment_${comment_id}'
							comment: comment_str
							location: location
							kind: .text_comment
							kind_str: 'TextComment'
						}
						c2v.cnt++
						comment_id++
					}
					curr_state = .s0
				} else {
					comment.write_rune(c)
				}
			}
		}

		offset++
	}

	unsafe { comment.free() }

	for node in comment_nodes {
		c2v.insert_comment_node(mut root_node, node)
	}
}

fn (mut c2v C2V) translate_file(path string) {
	start_ticks := time.ticks()
	print('  translating ${path:-15s} ... ')
	flush_stdout()
	c2v.set_config_overrides_for_file(path)
	mut ast_path := path
	ext := os.file_ext(path)
	c2v.is_cpp = ext in ['.cpp', '.cc', '.cxx', '.C']
	if c2v.is_cpp {
		c2v.project_has_cpp = true
	}

	mut additional_clang_flags := c2v.get_additional_flags(path)
	if ext == '.c' {
		additional_clang_flags = strip_cpp_only_flags(additional_clang_flags)
	}
	cmd := '${clang_exe} ${additional_clang_flags} -w -Xclang -ast-dump=json -fsyntax-only -fno-diagnostics-color -c ${os.quoted_path(path)}'
	vprintln('DA CMD')
	vprintln(cmd)
	mut rel_path := path
	if rel_path.starts_with('./') {
		rel_path = rel_path[2..]
	}
	mut out_ast := if c2v.is_dir {
		os.join_path(c2v.project_output_root, c2v.project_output_relative_path(rel_path, ext, '.json'))
	} else {
		// file.c => file.json
		vprintln(path)
		replace_file_extension(path, ext, '.json')
	}
	mut out_ast_dir := os.dir(out_ast)
	if c2v.is_dir && !os.exists(out_ast_dir) {
		os.mkdir_all(out_ast_dir) or {
			// Fallback for non-writable target roots: keep output in the invocation cwd.
			c2v.project_output_root = os.join_path(c2v.invocation_cwd, c2v.project_output_dirname)
			c2v.project_globals_path = os.join_path(c2v.project_output_root, '0_globals.v')
			out_ast = os.join_path(c2v.project_output_root, c2v.project_output_relative_path(rel_path, ext, '.json'))
			out_ast_dir = os.dir(out_ast)
			os.mkdir_all(out_ast_dir) or { panic(err) }
		}
	}
	vprintln('running in path: ${os.abs_path('.')}')
	vprintln('EXT=${ext} out_ast=${out_ast}')
	vprintln('out_ast=${out_ast}')
	vprintln('${cmd} > "${out_ast}"')
	mut clang_result := os.system('${cmd} > "${out_ast}"')
	vprintln('${clang_result}')
	if clang_result != 0 {
		if c2v.project_require_no_stubs {
			c2v.verror('clang could not parse ${path} cleanly; strict translation will not use a recovered AST')
		}
		// Clang can still emit a usable JSON AST when semantic errors are present.
		// For large C++ codebases, proceed when AST output exists and is non-empty.
		if os.exists(out_ast) && os.file_size(out_ast) > 64 {
			eprintln('\nWARNING: clang reported errors for ${path}, continuing with recovered AST.')
		} else {
			eprintln('\nThe file ' + path + ' could not be parsed as a C/C++ source file.')
			if c2v.is_dir {
				return
			}
			exit(1)
		}
	}
	ast_path = out_ast
	vprintln('out_ast bytes=${os.file_size(out_ast)}')
	vprintln(os.read_file(path) or { panic(err) })
	vprintln('path=${path}')
	out_v := out_ast.replace('.json', '.v')
	short_output_path := out_v.replace(os.getwd() + '/', '')
	mut c_file := os.real_path(path)
	if c_file == '' {
		c_file = path
	}
	c2v.add_file(ast_path, out_v, c_file) or {
		eprintln('Failed to parse AST for ${path}: ${err}')
		if !c2v.keep_ast {
			os.rm(out_ast) or {}
		}
		if c2v.is_dir {
			return
		}
		exit(1)
	}

	// preparation pass, fill all seen_ids ...
	c2v.seen_ids = {}
	c2v.callback_seen_ids = {}
	for i, mut node in c2v.tree.inner {
		c2v.node_i = i
		c2v.seen_ids[node.id] = unsafe { node }
		c2v.collect_seen_ids_recursive(mut node)
	}
	// preparation pass part 2, fill in the Node redeclarations field, based on *all* seen nodes
	for _, mut node in c2v.tree.inner {
		if node.previous_declaration == '' {
			continue
		}
		if mut pnode := c2v.seen_ids[node.previous_declaration] {
			pnode.redeclarations_count++
		}
	}

	// Pre-scan pass: collect all type names that will be defined in this translation unit.
	// This prevents types from being incorrectly marked as external when they appear
	// before their definition in the AST ordering (e.g., mobj_t referencing subsector_t
	// when subsector_t's definition appears later in the AST).
	c2v.known_types = {}
	for i, node in c2v.tree.inner {
		if c2v.is_cpp && node.location.file_index != 0 {
			node_path := c2v.node_source_path(node)
			if node_path != '' && line_is_builtin_header(normalize_cpp_source_path(node_path)) {
				continue
			}
		}
		if (node.kindof(.record_decl) || node.kindof(.cxx_record_decl)) && node.inner.len > 0 {
			mut c_name := node.name
			if c2v.tree.inner.len > i + 1 {
				next_node := c2v.tree.inner[i + 1]
				if next_node.kind == .typedef_decl {
					c_name = next_node.name
				}
			}
			if c_name != '' && c_name !in builtin_type_names {
				c2v.known_types[c_name.trim_left('_').capitalize()] = true
			}
		} else if node.kindof(.enum_decl) {
			mut c_name := node.name
			if c2v.tree.inner.len > i + 1 {
				next_node := c2v.tree.inner[i + 1]
				if next_node.kind == .typedef_decl {
					c_name = next_node.name
				}
			}
			if c_name != '' && c_name !in builtin_type_names {
				c2v.known_types[c_name.trim_left('_').capitalize()] = true
			}
		}
	}
	for type_name, _ in c2v.known_types {
		c2v.project_known_types[type_name] = true
	}
	if c2v.is_cpp {
		c2v.collect_cpp_class_method_bases()
		for node in c2v.tree.inner {
			c2v.collect_cpp_template_param_names(&node)
		}
	}

	// Main parse loop
	vprintln('main loop ${c2v.tree.inner.len}')
	for i, node in c2v.tree.inner {
		vprintln('\ndoing top node ${i} ${node.kind} name="${node.name}"')
		c2v.node_i = i
		c2v.top_level(node)
	}
	if c2v.is_dir && c2v.project_has_cpp {
		c2v.collect_project_callable_surfaces_from_ast()
	}
	if os.args.contains('-print_tree') {
		c2v.print_entire_tree()
	}
	if os.args.contains('-check_comment') {
		c2v.check_comment_entire_tree()
	}
	if !c2v.keep_ast {
		os.rm(out_ast) or {}
	}
	vprintln('c2v: translate_file() DONE')
	c2v.save()
	c2v.release_translation_ast()
	c2v.translations++
	delta_ticks := time.ticks() - start_ticks
	println(' c2v translate_file() took ${delta_ticks:5} ms ; output .v file: ${short_output_path}')
}

fn (mut c2v C2V) print_entire_tree() {
	for _, node in c2v.tree.inner {
		print_node_recursive(node, 0)
	}
}

fn print_node_recursive(node &Node, ident int) {
	print('  '.repeat(ident))
	println('offset=[${node.location.offset},${node.range.begin.offset},${node.range.end.offset}] ${node.kind} n="${node.name}"')
	for child in node.inner {
		print_node_recursive(child, ident + 1)
	}
	if node.array_filler.len > 0 {
		for child in node.array_filler {
			print_node_recursive(child, ident + 1)
		}
	}
}

fn (mut c2v C2V) check_comment_entire_tree() {
	for _, node in c2v.tree.inner {
		c2v.check_comment_node_recursive(node, 0)
	}
}

fn (mut c2v C2V) check_comment_node_recursive(node &Node, ident int) {
	comment_id := node.unique_id
	if node.comment.len != 0 && c2v.can_output_comment[comment_id] == true {
		vprint('====>Error! node comment not output! ${node.comment}')
		vprint('  '.repeat(ident))
		vprintln('offset=[${node.location.offset},${node.range.begin.offset},${node.range.end.offset}] ${node.kind} n="${node.name}"\n')
	}
	for child in node.inner {
		c2v.check_comment_node_recursive(child, ident + 1)
	}
	if node.array_filler.len > 0 {
		for child in node.array_filler {
			c2v.check_comment_node_recursive(child, ident + 1)
		}
	}
}

// recursive
fn (mut c2v C2V) set_unique_id(mut n Node) {
	n.unique_id = c2v.cnt
	c2v.cnt += 1

	for mut child in n.inner {
		c2v.set_unique_id(mut child)
	}

	for mut child in n.array_filler {
		c2v.set_unique_id(mut child)
	}
}

fn resolve_node_file_path(n Node) string {
	mut node_file := n.location.file
	if node_file == '' {
		node_file = n.range.begin.file
	}
	if node_file == '' {
		node_file = n.range.end.file
	}
	if node_file == '' {
		node_file = n.range.begin.expansion_file.path
	}
	if node_file == '' {
		node_file = n.range.end.expansion_file.path
	}
	if node_file == '' {
		node_file = n.range.begin.spelling_file.path
	}
	if node_file == '' {
		node_file = n.location.spelling_file.path
	}
	if node_file == '' {
		node_file = n.range.end.spelling_file.path
	}
	if node_file == '' && n.location.source_file.path != '' {
		// `includedFrom` names the includer rather than the declaration file, so it
		// cannot generally attribute a node (for example, a libc declaration may
		// name the project .cpp that included it). It is nevertheless conclusive
		// when that includer is itself a Clang/system header: an unattributed inline
		// intrinsic nested there must not be reassigned to the main source file.
		included_from := normalize_cpp_source_path(n.location.source_file.path)
		if line_is_builtin_header(included_from) {
			node_file = included_from
		}
	}
	return node_file
}

fn has_direct_child_kind_str(n Node, kind_str string) bool {
	for child in n.inner {
		if child.kind_str == kind_str {
			return true
		}
	}
	return false
}

fn is_cpp_body_decl_node_by_kind_str(n Node) bool {
	return n.kind_str in ['CXXMethodDecl', 'CXXConstructorDecl', 'CXXDestructorDecl', 'FunctionDecl']
		&& has_direct_child_kind_str(n, 'CompoundStmt')
}

fn has_unattributed_cpp_body_decl_descendant_by_kind_str(n Node) bool {
	for child in n.inner {
		if is_cpp_body_decl_node_by_kind_str(child) && resolve_node_file_path(child) == '' {
			return true
		}
		if has_unattributed_cpp_body_decl_descendant_by_kind_str(child) {
			return true
		}
	}
	return false
}

fn is_cpp_body_container_node_by_kind_str(n Node) bool {
	return n.kind_str in ['LinkageSpecDecl', 'NamespaceDecl']
		&& has_unattributed_cpp_body_decl_descendant_by_kind_str(n)
}

// recursive
fn (mut c2v C2V) set_file_index(mut n Node) {
	parent_file := c2v.cur_file
	mut node_file := resolve_node_file_path(n)
	if c2v.is_cpp && node_file == ''
		&& (is_cpp_body_decl_node_by_kind_str(n) || is_cpp_body_container_node_by_kind_str(n))
		&& parent_file != '' {
		// Clang commonly omits file metadata from inline method bodies. Inherit
		// the enclosing record/header path instead of treating every such body as
		// if it were defined in the translation unit's main .cpp file.
		node_file = parent_file
		n.location.file = node_file
	}
	if node_file != '' && !is_synthetic_source_path(node_file) {
		c2v.cur_file = os.real_path(node_file)
		if c2v.cur_file == '' {
			c2v.cur_file = node_file
		}
		if c2v.cur_file !in c2v.files {
			c2v.files << c2v.cur_file
		}
	}
	n.location.file_index = c2v.files.index(c2v.cur_file)

	for mut child in n.inner {
		c2v.set_file_index(mut child)
	}

	for mut child in n.array_filler {
		c2v.set_file_index(mut child)
	}
	c2v.cur_file = parent_file
}

// recursive
fn (mut c2v C2V) get_used_fn(n Node) {
	if n.kind_str == 'FunctionDecl' && n.location.source_file.path == '' {
		// println('==>add ${n.name} n.location.file_index=${n.location.file_index} file = ${c2v.files[n.location.file_index]}')
		c2v.used_fn.add(n.name)
	}
	if n.ref_declaration.kind_str == 'FunctionDecl' {
		c2v.used_fn.add(n.ref_declaration.name)
	}
	for child in n.inner {
		c2v.get_used_fn(child)
	}

	for child in n.array_filler {
		c2v.get_used_fn(child)
	}
}

// recursive
fn (mut c2v C2V) get_used_global(n Node) {
	if n.kind_str == 'VarDecl' && n.location.source_file.path == '' {
		c2v.used_global.add(n.name)
	}
	if n.ref_declaration.kind_str == 'VarDecl' {
		c2v.used_global.add(n.ref_declaration.name)
	}
	for child in n.inner {
		c2v.get_used_global(child)
	}

	for child in n.array_filler {
		c2v.get_used_global(child)
	}
}

fn (mut c C2V) top_level(_node &Node) {
	mut node := unsafe { _node }
	is_included_cpp_member_body := (is_cpp_method_like_decl(node)
		|| node.kindof(.cxx_constructor_decl) || node.kindof(.cxx_destructor_decl))
		&& node.has_child_of_kind(.compound_stmt)
	if c.is_cpp && node.location.file_index != 0 {
		node_path := c.node_source_path(node)
		if node_path != '' && line_is_builtin_header(normalize_cpp_source_path(node_path))
			&& !node.kindof(.function_decl) && !node.kindof(.linkage_spec_decl) {
			return
		}
	}
	// For C++ translation, keep type declarations from included headers.
	// Without these, method receiver/field types become unknown in generated V.
	if c.is_cpp && node.location.file_index != 0 && !node.kindof(.function_decl)
		&& !node.kindof(.function_template_decl) && !node.kindof(.record_decl)
		&& !node.kindof(.cxx_record_decl) && !node.kindof(.class_template_decl)
		&& !node.kindof(.class_template_specialization_decl) && !node.kindof(.typedef_decl)
		&& !node.kindof(.linkage_spec_decl) && !node.kindof(.namespace_decl)
		&& !node.kindof(.enum_decl) && !is_included_cpp_member_body && !(node.kindof(.var_decl)
		&& should_collect_callable_surface_path(c.node_source_path(node))) {
		return
	}
	c.gen_comment(node)
	if node.kindof(.typedef_decl) {
		if c.is_cpp && c.is_dir && c.project_require_no_stubs && !node.is_referenced {
			// An unreferenced typedef can name a template instantiation that no part
			// of the program ever needs (and so is never laid out).
			return
		}
		c.typedef_decl(node)
	} else if node.kindof(.function_decl) {
		c.fn_decl(mut node, '')
	} else if node.kindof(.record_decl) {
		c.record_decl(node)
	} else if node.kindof(.var_decl) {
		c.global_var_decl(mut node)
	} else if node.kindof(.enum_decl) {
		c.enum_decl(mut node)
	} else if node.kindof(.text_comment) {
	} else if node.kindof(.static_assert_decl) {
		// Skip static_assert_decl as they're just compile-time assertions in C/C++
		// and don't need a V equivalent in the wrapper
	} else if !c.cpp_top_level(node) {
		if c.project_require_no_stubs && c.is_main_source_path(c.node_source_path(node)) {
			c.verror('unhandled top-level node ${node.kind} at ${c.cur_file}:${node.location.line}')
		}
		eprintln('WARNING: Unhandled top level node kind=${node.kind} name="${node.name}" typ=${node.ast_type}')
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
	res = res.replace('const ', '')
	res = res.trim_space()
	if res.contains('[') {
		res = res.all_before('[').trim_space()
	}
	for res.ends_with('*') {
		res = res[..res.len - 1].trim_space()
	}
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

// fn capitalize_type(s string) string {
//	mut name := s
//	if name.starts_with('_') {
//		// Trim "_" from the start of the struct name
//		// TODO this can result in conflicts
//		name = trim_underscores(name)
//	}
//	if !name.starts_with('fn ') {
//		name = name.capitalize()
//	}
//	return name
// }

fn sanitize_type_token(name string) string {
	mut out := strings.new_builder(name.len)
	mut last_sep := false
	for i := 0; i < name.len; i++ {
		ch := name[i]
		is_alnum := (ch >= `0` && ch <= `9`) || (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
		if is_alnum || ch == `_` {
			if ch == `_` {
				if last_sep {
					continue
				}
				out.write_u8(`_`)
				last_sep = true
			} else {
				out.write_u8(ch)
				last_sep = false
			}
		} else if !last_sep {
			out.write_u8(`_`)
			last_sep = true
		}
	}
	mut s := out.str().trim('_')
	if s == '' {
		s = 'AnonType'
	}
	if s[0] >= `0` && s[0] <= `9` {
		return '_' + s
	}
	return s
}

// Function signatures need an injective identifier encoding. Punctuation stripping
// makes distinct callbacks such as `fn (T) U` and `fn (T, U)` collide after their
// generated union declarations are flattened into one V module.
fn function_pointer_cast_type_token(signature string) string {
	hex := '0123456789abcdef'
	mut out := strings.new_builder(signature.len * 2)
	for ch in signature.bytes() {
		out.write_u8(hex[ch >> 4])
		out.write_u8(hex[ch & 15])
	}
	return out.str()
}

// c_string_literal_bytes decodes the bytes of a C string literal's spelling,
// e.g. `"a\n\000"`, without the terminating NUL.
fn c_string_literal_bytes(spelling string) []u8 {
	mut text := spelling.trim_space()
	if text.len >= 2 && text[0] == `"` && text[text.len - 1] == `"` {
		text = text[1..text.len - 1]
	}
	mut bytes := []u8{cap: text.len}
	mut i := 0
	for i < text.len {
		ch := text[i]
		if ch != `\\` || i + 1 >= text.len {
			bytes << ch
			i++
			continue
		}
		next := text[i + 1]
		i += 2
		match next {
			`n` { bytes << `\n` }
			`t` { bytes << `\t` }
			`r` { bytes << `\r` }
			`a` { bytes << 7 }
			`b` { bytes << 8 }
			`f` { bytes << 12 }
			`v` { bytes << 11 }
			`x` {
				mut value := 0
				for i < text.len && text[i].is_hex_digit() {
					value = value * 16 + hex_digit_value(text[i])
					i++
				}
				bytes << u8(value)
			}
			`0`, `1`, `2`, `3`, `4`, `5`, `6`, `7` {
				mut value := int(next - `0`)
				for digits := 1; digits < 3 && i < text.len && text[i] >= `0` && text[i] <= `7`; digits++ {
					value = value * 8 + int(text[i] - `0`)
					i++
				}
				bytes << u8(value)
			}
			else { bytes << next }
		}
	}
	return bytes
}

fn hex_digit_value(ch u8) int {
	return if ch >= `0` && ch <= `9` {
		int(ch - `0`)
	} else if ch >= `a` && ch <= `f` {
		int(ch - `a`) + 10
	} else {
		int(ch - `A`) + 10
	}
}

// c_string_fixed_array_literal spells the bytes a C string literal stores in a
// character array of the V type `array_type` (e.g. `[16]i8`), zero padded.
fn c_string_fixed_array_literal(spelling string, array_type string) string {
	length := cpp_fixed_array_length(array_type)
	element_type := cpp_fixed_array_element_type(array_type)
	bytes := c_string_literal_bytes(spelling)
	mut values := []string{cap: length}
	for i in 0 .. length {
		b := if i < bytes.len { int(bytes[i]) } else { 0 }
		values << if element_type == 'i8' && b > 127 { (b - 256).str() } else { b.str() }
	}
	if values.len > 0 {
		values[0] = '${element_type}(${values[0]})'
	}
	return '[${values.join(', ')}]!'
}

fn integer_literal_needs_unsigned_cast(value string, literal_type string) bool {
	if literal_type !in ['u32', 'u64', 'usize'] {
		return false
	}
	mut digits := value.trim_space()
	if digits.starts_with('+') {
		digits = digits[1..]
	}
	if digits == '' || !digits.bytes().all(it >= `0` && it <= `9`) {
		return false
	}
	digits = digits.trim_left('0')
	if digits == '' {
		return false
	}
	threshold := '2147483647'
	if digits.len != threshold.len {
		return digits.len > threshold.len
	}
	for i, digit in digits.bytes() {
		if digit != threshold[i] {
			return digit > threshold[i]
		}
	}
	return false
}

fn extract_declared_type_name(line string) string {
	mut t := line.trim_space()
	if t == '' || t.starts_with('//') {
		return ''
	}
	if t.starts_with('pub ') {
		t = t[4..].trim_space()
	}
	for kw in ['struct ', 'interface ', 'type ', 'enum ', 'union '] {
		if !t.starts_with(kw) {
			continue
		}
		mut rest := t[kw.len..].trim_space()
		if kw == 'type ' {
			eq := rest.index('=') or { return '' }
			rest = rest[..eq].trim_space()
		}
		if rest == '' {
			return ''
		}
		mut end := rest.len
		for sep in [' ', '{', '('] {
			if idx := rest.index(sep) {
				if idx < end {
					end = idx
				}
			}
		}
		name := rest[..end].trim_space()
		if name == '' {
			return ''
		}
		return name
	}
	return ''
}

fn extract_type_alias_target(line string) (string, string) {
	mut t := line.trim_space()
	if t == '' || t.starts_with('//') {
		return '', ''
	}
	if t.starts_with('pub ') {
		t = t[4..].trim_space()
	}
	if !t.starts_with('type ') {
		return '', ''
	}
	mut rest := t[5..].trim_space()
	eq := rest.index('=') or { return '', '' }
	name := rest[..eq].trim_space()
	rest = rest[eq + 1..].trim_space()
	target := rest.all_before('//').trim_space()
	if name == '' || target == '' {
		return '', ''
	}
	return name, target
}

fn append_unique_string(mut values []string, value string) {
	if value == '' {
		return
	}
	if value in values {
		return
	}
	values << value
}

fn is_v_fn_header_start(line string) bool {
	mut start := line.trim_space()
	if start.starts_with('pub ') {
		start = start[4..].trim_space()
	}
	return start.starts_with('fn ')
}

fn is_valid_v_callable_name(name string) bool {
	if name == '' {
		return false
	}
	first := name[0]
	if !((first >= `a` && first <= `z`) || (first >= `A` && first <= `Z`) || first == `_`) {
		return false
	}
	for i := 0; i < name.len; i++ {
		ch := name[i]
		is_alnum := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_`
		if !is_alnum {
			return false
		}
	}
	return true
}

fn normalize_space_runs(s string) string {
	mut out := strings.new_builder(s.len)
	mut prev_space := false
	for i := 0; i < s.len; i++ {
		ch := s[i]
		is_space := ch == ` ` || ch == `\t` || ch == `\n` || ch == `\r`
		if is_space {
			if !prev_space {
				out.write_u8(` `)
				prev_space = true
			}
			continue
		}
		out.write_u8(ch)
		prev_space = false
	}
	return out.str().trim_space()
}

fn extract_fn_headers_from_lines(lines []string) []string {
	mut headers := []string{}
	mut i := 0
	for i < lines.len {
		if !is_v_fn_header_start(lines[i]) {
			i++
			continue
		}
		mut pieces := []string{}
		mut j := i
		mut found_open := false
		for j < lines.len {
			seg := lines[j].trim_space()
			if seg == '' || seg.starts_with('//') {
				j++
				continue
			}
			if pieces.len > 0 && is_v_fn_header_start(seg) {
				break
			}
			pieces << seg
			if seg.contains('{') {
				found_open = true
				break
			}
			j++
		}
		if !found_open || pieces.len == 0 {
			if j > i && j < lines.len && is_v_fn_header_start(lines[j]) {
				i = j
			} else {
				i++
			}
			continue
		}
		mut header := normalize_space_runs(pieces.join(' '))
		if header.starts_with('pub ') {
			header = header[4..].trim_space()
		}
		header = normalize_space_runs(header.all_before('{').trim_space())
		if header.starts_with('fn ') {
			headers << header
		}
		i = j + 1
	}
	return headers
}

fn extract_method_surface_key_from_fn_header(header string) string {
	if !header.starts_with('fn (') {
		return ''
	}
	close_idx := header.index(') ') or { return '' }
	receiver := header['fn ('.len..close_idx].trim_space()
	receiver_type := receiver.all_after_last(' ').trim_space()
	if receiver_type == '' {
		return ''
	}
	tail := header[close_idx + 2..]
	method_name := tail.all_before('(').trim_space()
	if method_name == '' {
		return ''
	}
	return '${receiver_type}.${strip_v_generic_suffix(method_name)}'
}

fn strip_v_generic_suffix(name string) string {
	if !name.contains('[') {
		return name
	}
	return name.all_before('[').trim_space()
}

fn extract_top_level_function_name_from_fn_header(header string) string {
	if !header.starts_with('fn ') || header.starts_with('fn (') {
		return ''
	}
	return strip_v_generic_suffix(header[3..].all_before('(').trim_space())
}

fn (c2v &C2V) collect_output_callable_names_by_dir() (map[string][]string, map[string][]string) {
	mut local_functions := map[string][]string{}
	mut local_methods := map[string][]string{}
	if c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return local_functions, local_methods
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		dir := os.dir(file)
		if dir !in local_functions {
			local_functions[dir] = []string{}
		}
		if dir !in local_methods {
			local_methods[dir] = []string{}
		}
		lines := os.read_lines(file) or { continue }
		headers := extract_fn_headers_from_lines(lines)
		mut dir_functions := local_functions[dir]
		mut dir_methods := local_methods[dir]
		for header in headers {
			method_key := extract_method_surface_key_from_fn_header(header)
			if method_key != '' {
				append_unique_string(mut dir_methods, method_key)
				continue
			}
			fn_name := extract_top_level_function_name_from_fn_header(header)
			if fn_name == '' || fn_name == 'main' {
				continue
			}
			append_unique_string(mut dir_functions, fn_name)
		}
		local_functions[dir] = dir_functions
		local_methods[dir] = dir_methods
	}
	return local_functions, local_methods
}

// is_project_source_path reports whether a declaration belongs to the program
// being translated. Sources listed in a manifest can live outside the translated
// directory, so everything except system headers is project code.
fn (c2v &C2V) is_project_source_path(path string) bool {
	if path == '' {
		return false
	}
	normalized := normalize_cpp_source_path(path)
	return normalized != '' && !is_synthetic_source_path(normalized)
		&& !line_is_builtin_header(normalized)
}

fn should_collect_callable_surface_path(path string) bool {
	if path == '' {
		return true
	}
	normalized := normalize_cpp_source_path(path)
	if normalized == '' || is_synthetic_source_path(normalized) {
		return false
	}
	system_prefixes := [
		'/Applications/Xcode.app/',
		'/Library/Developer/CommandLineTools/',
		'/System/Library/',
		'/usr/include/',
		'/opt/homebrew/include/',
		'/usr/local/include/',
	]
	for prefix in system_prefixes {
		if normalized.starts_with(prefix) {
			return false
		}
	}
	return true
}

fn (mut c2v C2V) extract_stub_ret_type_from_ast(ast_sig string) string {
	mut ret := ast_sig.before('(').trim_space()
	if ret == '' || ret == 'void' {
		return ''
	}
	ret = c2v.prefix_external_type(c2v.convert_type(ret).name)
	if ret == '' || ret == 'void' || ret == '?void' {
		return ''
	}
	return ' ' + ret
}

fn normalize_stub_method_ret_type(method_name string, ret_type string) string {
	if !ret_type.starts_with(' &') {
		return ret_type
	}
	base := ret_type[2..].trim_space()
	if base == '' {
		return ret_type
	}
	if method_name == 'op_index' {
		// Prefer value semantics for translated index operations.
		// Pointer-returning index stubs trigger pointer arithmetic errors
		// in generated V code (`vec.op_index(i) * 32`, etc.).
		return ' ' + base
	}
	return ret_type
}

fn (mut c2v C2V) register_project_function_surface(name string, signature string) {
	if name == '' || signature == '' {
		return
	}
	if name in c2v.project_function_surfaces {
		return
	}
	c2v.project_function_surfaces[name] = signature
}

fn (mut c2v C2V) register_project_method_surface(key string, signature string) {
	if key == '' || signature == '' {
		return
	}
	if key in c2v.project_method_surfaces {
		return
	}
	c2v.project_method_surfaces[key] = signature
}

fn fallback_args_signature(param_count int) string {
	_ = param_count
	return '(args ...voidptr)'
}

fn fallback_function_signature(name string, param_count int, ret_type string) string {
	return 'fn ${name}${fallback_args_signature(param_count)}${ret_type}'
}

fn fallback_method_signature(receiver string, method_name string, param_count int, ret_type string) string {
	return 'fn (${receiver}) ${method_name}${fallback_args_signature(param_count)}${ret_type}'
}

fn fallback_method_param_count(method_name string, node Node) int {
	param_count := node.count_children_of_kind(.parm_var_decl)
	if method_name.starts_with('op_') && param_count == 0 {
		return 1
	}
	return param_count
}

fn (mut c2v C2V) collect_project_callable_surfaces_from_ast() {
	for node in c2v.tree.inner {
		node_path := c2v.node_source_path(&node)
		if !should_collect_callable_surface_path(node_path) {
			continue
		}
		if node.kindof(.function_decl) && node.name != '' {
			if node.name.starts_with('__builtin_') {
				continue
			}
			if node.name.starts_with('operator') {
				continue
			}
			fn_name := filter_name(node.name, false).camel_to_snake()
			if fn_name == '' || fn_name == 'main' {
				continue
			}
			if !is_valid_v_callable_name(fn_name) {
				continue
			}
			if fn_name in v_reserved_fn_names {
				continue
			}
			ret_type := c2v.extract_stub_ret_type_from_ast(node.ast_type.qualified)
			param_count := node.count_children_of_kind(.parm_var_decl)
			signature := fallback_function_signature(fn_name, param_count, ret_type)
			if c2v.has_template_placeholder_type(signature) {
				continue
			}
			c2v.register_project_function_surface(fn_name, signature)
			continue
		}
		if !node.kindof(.cxx_record_decl) || node.name == '' {
			continue
		}
		mut class_name := c2v.types[node.name]
		if class_name == '' {
			class_name = c2v.add_struct_name(mut c2v.types, node.name)
		}
		if !is_valid_v_receiver_type_name(class_name) {
			continue
		}
		for child in node.inner {
			if child.kindof(.cxx_method_decl) {
				if child.is_implicit || child.explicitly_defaulted != '' {
					continue
				}
				method_name := method_base_name_from_cpp_name(child.name)
				if method_name == '' {
					continue
				}
				if !is_valid_v_callable_name(method_name) {
					continue
				}
				mut ret_type := c2v.extract_stub_ret_type_from_ast(child.ast_type.qualified)
				ret_type = normalize_stub_method_ret_type(method_name, ret_type)
				key := '${class_name}.${method_name}'
				param_count := fallback_method_param_count(method_name, child)
				signature := fallback_method_signature('this ${class_name}', method_name, param_count, ret_type)
				if c2v.has_template_placeholder_type(signature) {
					continue
				}
				c2v.register_project_method_surface(key, signature)
			} else if child.kindof(.cxx_constructor_decl) {
				if child.is_implicit || child.explicitly_defaulted != '' {
					continue
				}
				key := '${class_name}.init'
				param_count := child.count_children_of_kind(.parm_var_decl)
				signature := fallback_method_signature('mut this ${class_name}', 'init', param_count, '')
				c2v.register_project_method_surface(key, signature)
			}
		}
	}
}

fn extract_base_stub_type_name(type_expr string) string {
	mut t := collapse_ascii_whitespace(type_expr)
	if t == '' {
		return ''
	}
	if eq := t.index('=') {
		t = t[..eq].trim_space()
	}
	if t.starts_with('fn ') || t.contains('|') {
		return ''
	}
	if t.contains(' ') {
		parts := t.split(' ').filter(it != '')
		if parts.len == 0 {
			return ''
		}
		if parts[0] in ['struct', 'class', 'union', 'enum'] && parts.len > 1 {
			t = parts[1]
		} else {
			t = parts[0]
		}
	}
	for t.starts_with('&') {
		t = t[1..].trim_space()
	}
	for t.starts_with('*') {
		t = t[1..].trim_space()
	}
	for t.starts_with('[]') {
		t = t[2..].trim_space()
	}
	if t.contains('[') && t.ends_with(']') && !t.starts_with('[') {
		t = t.all_before('[').trim_space()
	}
	if t.starts_with('[') && t.contains(']') {
		t = t.all_after(']').trim_space()
	}
	if t.starts_with('map[') && t.contains(']') {
		t = t.all_after(']').trim_space()
	}
	// Array wrappers can expose pointer prefixes again (e.g. `[4]&SDL_cond`).
	for t.starts_with('&') {
		t = t[1..].trim_space()
	}
	for t.starts_with('*') {
		t = t[1..].trim_space()
	}
	for t.starts_with('[]') {
		t = t[2..].trim_space()
	}
	for t.ends_with('.') {
		t = t[..t.len - 1].trim_space()
	}
	t = t.trim_left('(').trim_right(')').trim_space()
	if t.contains('.') {
		t = t.all_after_last('.')
	}
	if !is_valid_stub_type_name(t) {
		return ''
	}
	return t
}

fn (c2v &C2V) collect_struct_referenced_stub_types(struct_defs map[string]string) []string {
	mut names := map[string]bool{}
	for _, struct_def in struct_defs {
		for line in struct_def.split_into_lines() {
			trimmed := line.trim_space()
			if trimmed == '' || trimmed.starts_with('//') {
				continue
			}
			if trimmed.starts_with('struct ') || trimmed == '{' || trimmed == '}'
				|| trimmed.ends_with('{') || trimmed.ends_with(':') {
				continue
			}
			field_line := trimmed.all_before('//').trim_space()
			if field_line == '' {
				continue
			}
			// A one-token struct line is V's embedded-base syntax. It is still a
			// type dependency and must receive a fallback when the base template
			// specialization was absent from Clang's recovered AST.
			type_expr := if field_line.contains(' ') {
				field_line.all_after_last(' ').trim_space()
			} else {
				field_line
			}
			type_name := extract_base_stub_type_name(type_expr)
			if type_name != '' {
				names[type_name] = true
			}
		}
	}
	mut out := names.keys()
	out.sort()
	return out
}

fn (c2v &C2V) collect_output_declared_types() map[string]bool {
	mut declared := map[string]bool{}
	if c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return declared
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		lines := os.read_lines(file) or { continue }
		for line in lines {
			name := extract_declared_type_name(line)
			if name != '' {
				declared[name] = true
			}
		}
	}
	return declared
}

fn extract_struct_name(line string) string {
	mut t := line.trim_space()
	if t == '' || t.starts_with('//') {
		return ''
	}
	if t.starts_with('pub ') {
		t = t[4..].trim_space()
	}
	if !t.starts_with('struct ') {
		return ''
	}
	mut rest := t[7..].trim_space()
	if rest == '' || !rest.contains('{') {
		return ''
	}
	rest = rest.all_before('{').trim_space()
	if rest == '' {
		return ''
	}
	mut end := rest.len
	for sep in [' ', '(', '['] {
		if idx := rest.index(sep) {
			if idx < end {
				end = idx
			}
		}
	}
	name := rest[..end].trim_space()
	if name == '' {
		return ''
	}
	return name
}

fn (c2v &C2V) collect_output_struct_definitions() map[string]string {
	mut defs := map[string]string{}
	if c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return defs
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		lines := os.read_lines(file) or { continue }
		mut i := 0
		for i < lines.len {
			line := lines[i]
			name := extract_struct_name(line)
			if name == '' || name in defs {
				i++
				continue
			}
			mut depth := 0
			mut block := []string{}
			mut j := i
			for j < lines.len {
				l := lines[j]
				block << l
				depth += l.count('{')
				depth -= l.count('}')
				if depth <= 0 {
					break
				}
				j++
			}
			if depth == 0 && block.len > 0 {
				defs[name] = block.join('\n')
				i = j + 1
				continue
			}
			i++
		}
	}
	return defs
}

fn (c2v &C2V) collect_output_alias_targets() map[string]string {
	mut aliases := map[string]string{}
	if c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return aliases
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		lines := os.read_lines(file) or { continue }
		for line in lines {
			name, target := extract_type_alias_target(line)
			if name == '' || target == '' {
				continue
			}
			if name == target {
				continue
			}
			aliases[name] = target
		}
	}
	return aliases
}

fn (c2v &C2V) collect_output_declared_types_by_dir() map[string][]string {
	mut declared_by_dir := map[string][]string{}
	if c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return declared_by_dir
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		dir := os.dir(file)
		if dir !in declared_by_dir {
			declared_by_dir[dir] = []string{}
		}
		lines := os.read_lines(file) or { continue }
		mut dir_declared := declared_by_dir[dir]
		for line in lines {
			name := extract_declared_type_name(line)
			if name != '' {
				if name !in dir_declared {
					dir_declared << name
				}
			}
		}
		declared_by_dir[dir] = dir_declared
	}
	return declared_by_dir
}

fn is_valid_stub_type_name(name string) bool {
	if name == '' || name in builtin_type_names || name in v_primitive_type_names {
		return false
	}
	if name.contains('.') || name.contains('(') || name.contains(')') || name.contains('[')
		|| name.contains(']') || name.contains('<') || name.contains('>') || name.contains('&')
		|| name.contains('*') || name.contains(':') || name.contains(',') || name.contains('!')
		|| name.contains('?') {
		return false
	}
	first := name[0]
	if !((first >= `a` && first <= `z`) || (first >= `A` && first <= `Z`) || first == `_`) {
		return false
	}
	for i := 1; i < name.len; i++ {
		ch := name[i]
		is_alnum := (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
			|| (ch >= `0` && ch <= `9`) || ch == `_`
		if !is_alnum {
			return false
		}
	}
	return true
}

fn is_safe_stub_alias_target(target string) bool {
	mut base := target.trim_space()
	if base == '' {
		return false
	}
	if base.starts_with('fn (') {
		return true
	}
	for base.starts_with('&') {
		base = base[1..].trim_space()
	}
	return base in ['bool', 'i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize',
		'f32', 'f64', 'byte', 'voidptr']
}

fn (c2v &C2V) collect_shared_stub_type_names(all_declared map[string]bool) []string {
	mut names := map[string]bool{}
	for _, type_name in c2v.types {
		if is_valid_stub_type_name(type_name) {
			names[type_name] = true
		}
	}
	for type_name, _ in all_declared {
		if is_valid_stub_type_name(type_name) {
			names[type_name] = true
		}
	}
	for ext_type, _ in c2v.external_types {
		if is_valid_stub_type_name(ext_type) {
			names[ext_type] = true
		}
	}
	for _, global_info in c2v.globals {
		global_type := extract_base_stub_type_name(global_info.typ)
		if is_valid_stub_type_name(global_type) {
			names[global_type] = true
		}
	}
	mut out := names.keys()
	out.sort()
	return out
}

fn is_decimal_token(token string) bool {
	if token == '' {
		return false
	}
	for ch in token {
		if ch < `0` || ch > `9` {
			return false
		}
	}
	return true
}

fn split_numeric_suffix_tokens(token string) (string, []string) {
	parts := token.split('_')
	mut base_end := parts.len
	for base_end > 1 && is_decimal_token(parts[base_end - 1]) {
		base_end--
	}
	if base_end == parts.len {
		return token, []string{}
	}
	return parts[..base_end].join('_'), parts[base_end..].clone()
}

fn fixed_array_alias_target_for_stub_type(type_name string, known_type_set map[string]bool) string {
	base, dims := split_numeric_suffix_tokens(type_name)
	if dims.len == 0 || base == '' || base !in known_type_set {
		return ''
	}
	mut target := base
	for dim in dims {
		target = '[' + dim + ']' + target
	}
	return target
}

fn callable_signature_ret_type(signature string) string {
	trimmed := signature.trim_space()
	if trimmed == '' {
		return ''
	}
	rpar := trimmed.last_index(')') or { return '' }
	if rpar + 1 >= trimmed.len {
		return ''
	}
	ret_type := trimmed[rpar + 1..].trim_space()
	if ret_type == 'void' {
		return ''
	}
	return ret_type
}

fn (mut c2v C2V) write_fallback_callable_body(mut out strings.Builder, signature string) {
	ret_type := callable_signature_ret_type(signature)
	if ret_type != '' {
		out.writeln('\treturn ' + c2v.skeleton_default_value(ret_type))
	}
	out.writeln('}\n')
}

fn emit_weak_global_decl(mut out strings.Builder, name string, typ_name string, markused bool, mut emitted map[string]bool) {
	if name == '' || typ_name == '' || name in v_keywords {
		return
	}
	if name in emitted {
		return
	}
	if markused {
		out.writeln('@[markused]')
	}
	out.writeln('@[weak] __global ' + name + ' ' + typ_name)
	emitted[name] = true
}

fn emit_c_extern_global_decl(mut out strings.Builder, c_name string, typ_name string, mut emitted map[string]bool) {
	if c_name == '' || typ_name == '' {
		return
	}
	extern_name := c_global_decl_v_name(c_name, true)
	if extern_name in emitted {
		return
	}
	out.writeln('@[c_extern]')
	out.writeln('__global ' + extern_name + ' ' + typ_name)
	emitted[extern_name] = true
}

fn string_is_digits(s string) bool {
	if s == '' {
		return false
	}
	for ch in s {
		if ch < `0` || ch > `9` {
			return false
		}
	}
	return true
}

fn strip_leading_v_attributes(line string) string {
	mut rest := line.trim_space()
	for rest.starts_with('@[') {
		close_idx := rest.index(']') or { break }
		rest = rest[close_idx + 1..].trim_space()
	}
	return rest
}

fn collect_v_const_names(lines []string) map[string]bool {
	mut names := map[string]bool{}
	mut in_block := false
	for line in lines {
		trimmed := strip_leading_v_attributes(line)
		if trimmed == '' || trimmed.starts_with('//') {
			continue
		}
		if trimmed == 'const (' {
			in_block = true
			continue
		}
		if in_block && trimmed == ')' {
			in_block = false
			continue
		}
		mut declaration := trimmed
		if declaration.starts_with('const ') {
			declaration = declaration['const '.len..].trim_space()
		} else if !in_block {
			continue
		}
		name := declaration.all_before('=').trim_space().all_before(' ').trim_space()
		if name != '' && is_valid_stub_type_name(name) {
			names[name] = true
		}
	}
	return names
}

fn extract_v_global_name(line string) string {
	rest := strip_leading_v_attributes(line)
	if !rest.starts_with('__global ') {
		return ''
	}
	name := rest['__global '.len..].trim_space().all_before(' ').trim_space()
	if name == '' {
		return ''
	}
	return name
}

fn order_initialized_global_names(names []string, declarations map[string]string) []string {
	mut owner_by_declared_name := map[string]string{}
	for name in names {
		declared_name := extract_v_global_name(declarations[name] or { continue })
		if declared_name != '' {
			owner_by_declared_name[declared_name] = name
		}
		// Initializers are collected before final C/V name reconciliation, so a
		// dependency can use the original C++ spelling, lower-first spelling, or
		// snake-case spelling while still referring to this same declaration.
		for alias in [name, filter_name(name.uncapitalize(), true),
			filter_name(c_identifier_to_v_name(name), true)] {
			if alias != '' {
				owner_by_declared_name[alias] = name
			}
		}
	}
	mut dependencies := map[string]map[string]bool{}
	for name in names {
		mut name_dependencies := map[string]bool{}
		for token in strict_global_reference_tokens(declarations[name] or { '' }).keys() {
			if dependency := owner_by_declared_name[token] {
				if dependency != name {
					name_dependencies[dependency] = true
				}
			}
		}
		dependencies[name] = name_dependencies.clone()
	}
	mut ordered := []string{cap: names.len}
	mut emitted := map[string]bool{}
	for ordered.len < names.len {
		mut made_progress := false
		for name in names {
			if name in emitted || !dependencies[name].keys().all(it in emitted) {
				continue
			}
			ordered << name
			emitted[name] = true
			made_progress = true
		}
		if made_progress {
			continue
		}
		// Retain deterministic source order if the C++ initializers form a cycle.
		for name in names {
			if name !in emitted {
				ordered << name
				emitted[name] = true
				break
			}
		}
	}
	return ordered
}

fn filter_single_module_globals(src string, local_types map[string]bool, local_interfaces map[string]bool, local_functions map[string]bool, local_methods map[string]bool, local_consts map[string]bool) string {
	lines := src.split_into_lines()
	mut reserved_consts := collect_v_const_names(lines)
	for name, _ in local_consts {
		reserved_consts[name] = true
	}
	mut seen_globals := map[string]bool{}
	mut seen_types := map[string]bool{}
	mut seen_functions := map[string]bool{}
	mut seen_methods := map[string]bool{}
	mut pending_attrs := []string{}
	mut out := strings.new_builder(src.len)
	mut i := 0
	for i < lines.len {
		line := lines[i]
		trimmed := line.trim_space()
		declaration := strip_leading_v_attributes(line)
		if trimmed.starts_with('@[') && declaration == '' {
			pending_attrs << line
			i++
			continue
		}

		mut remove := false
		mut block_depth := 0
		declared_type := extract_declared_type_name(declaration)
		if declared_type != '' {
			if declared_type in local_types || declared_type in seen_types {
				remove = true
			}
			seen_types[declared_type] = true
			if declaration.starts_with('struct ') || declaration.starts_with('interface ')
				|| declaration.starts_with('enum ') || declaration.starts_with('union ') {
				block_depth = line.count('{') - line.count('}')
			}
		} else if declaration.starts_with('fn ') {
			header := normalize_space_runs(declaration.all_before('{').trim_space())
			method_key := extract_method_surface_key_from_fn_header(header)
			fn_name := extract_top_level_function_name_from_fn_header(header)
			receiver_type := method_key.all_before('.')
			if (method_key != ''
				&& (method_key in local_methods || receiver_type in local_interfaces
					|| method_key in seen_methods))
				|| (fn_name != '' && (fn_name in local_functions || fn_name in seen_functions)) {
				remove = true
				block_depth = line.count('{') - line.count('}')
			}
			if method_key != '' {
				seen_methods[method_key] = true
			}
			if fn_name != '' {
				seen_functions[fn_name] = true
			}
		} else if declaration.starts_with('const ') && declaration.contains('=') {
			const_name := declaration['const '.len..].trim_space().all_before('=').trim_space()
			if const_name in local_consts {
				remove = true
			}
		} else {
			global_name := extract_v_global_name(line)
			if global_name != '' {
				if global_name in reserved_consts || global_name in seen_globals {
					remove = true
				}
				seen_globals[global_name] = true
			}
		}

		if remove {
			pending_attrs = []
			i++
			for block_depth > 0 && i < lines.len {
				block_depth += lines[i].count('{') - lines[i].count('}')
				i++
			}
			continue
		}
		for attr in pending_attrs {
			out.writeln(attr)
		}
		pending_attrs = []
		out.write_string(line)
		if i < lines.len - 1 {
			out.write_u8(`\n`)
		}
		i++
	}
	return out.str()
}

fn (mut c2v C2V) write_globals_stub_file(path string, local_declared []string, shared_stub_types []string, alias_targets map[string]string, struct_defs map[string]string, local_functions []string, local_methods []string) {
	mut out := strings.new_builder(1024)
	out.writeln('@[translated]\nmodule main\n')
	mut local_function_set := map[string]bool{}
	for name in local_functions {
		if name != '' {
			local_function_set[name] = true
		}
	}
	mut local_method_set := map[string]bool{}
	for key in local_methods {
		if key != '' {
			local_method_set[key] = true
		}
	}
	mut local_const_set := map[string]bool{}
	mut local_interface_set := map[string]bool{}
	mut actual_local_declared_set := map[string]bool{}
	local_dir := os.dir(path)
	if local_dir != '' && os.exists(local_dir) {
		for entry in os.ls(local_dir) or { []string{} } {
			file := os.join_path(local_dir, entry)
			if is_c2v_globals_file(file) || os.file_ext(file) != '.v' || os.is_dir(file) {
				continue
			}
			lines := os.read_lines(file) or { continue }
			for line in lines {
				trimmed := line.trim_space()
				declared_type := extract_declared_type_name(strip_leading_v_attributes(line))
				if declared_type != '' {
					actual_local_declared_set[declared_type] = true
				}
				if trimmed.starts_with('interface ') {
					name := extract_declared_type_name(trimmed)
					if name != '' {
						local_interface_set[name] = true
					}
				}
			}
			for name, _ in collect_v_const_names(lines) {
				local_const_set[name] = true
			}
			for header in extract_fn_headers_from_lines(lines) {
				method_key := extract_method_surface_key_from_fn_header(header)
				if method_key != '' {
					local_method_set[method_key] = true
					continue
				}
				fn_name := extract_top_level_function_name_from_fn_header(header)
				if fn_name != '' && fn_name != 'main' {
					local_function_set[fn_name] = true
				}
			}
		}
	}
	mut local_declared_set := actual_local_declared_set.clone()
	if !c2v.project_single_module {
		for type_name in local_declared {
			if type_name != '' {
				local_declared_set[type_name] = true
			}
		}
	}
	mut emitted_stub_types := map[string]bool{}
	mut shared_type_set := map[string]bool{}
	for type_name in shared_stub_types {
		shared_type_set[type_name] = true
	}
	if c2v.has_cfile {
		out.writeln('@[typedef]\nstruct C.FILE {}')
	}
	if shared_stub_types.len > 0 {
		out.writeln('// External type declarations (from headers and translated units)')
		for type_name in shared_stub_types {
			if type_name in local_declared_set {
				continue
			}
			if struct_def := struct_defs[type_name] {
				if struct_def.trim_space() != '' {
					out.writeln(struct_def + '\n')
					emitted_stub_types[type_name] = true
					continue
				}
			}
			if target := alias_targets[type_name] {
				if target != '' && target != type_name && is_safe_stub_alias_target(target) {
					out.writeln('type ' + type_name + ' = ' + target + '\n')
					emitted_stub_types[type_name] = true
					continue
				}
			}
			fixed_array_target := fixed_array_alias_target_for_stub_type(type_name, shared_type_set)
			if fixed_array_target != '' {
				out.writeln('type ' + type_name + ' = ' + fixed_array_target + '\n')
				emitted_stub_types[type_name] = true
				continue
			}
			out.writeln('struct ' + type_name + ' {}\n')
			emitted_stub_types[type_name] = true
		}
	}
	mut defined_global_names := map[string]bool{}
	for name in c2v.defined_globals.keys() {
		defined_global_names[name] = true
	}
	if c2v.globals.len > 0 {
		mut supplemental_type_set := map[string]bool{}
		for _, global_info in c2v.globals {
			type_name := extract_base_stub_type_name(global_info.typ)
			if !is_valid_stub_type_name(type_name) {
				continue
			}
			if type_name in local_declared_set || type_name in emitted_stub_types {
				continue
			}
			supplemental_type_set[type_name] = true
		}
		if supplemental_type_set.len > 0 {
			out.writeln('// Supplemental global type declarations')
			mut supplemental_types := supplemental_type_set.keys()
			supplemental_types.sort()
			for type_name in supplemental_types {
				if type_name in local_declared_set {
					continue
				}
				if target := alias_targets[type_name] {
					if target != '' && target != type_name && is_safe_stub_alias_target(target) {
						out.writeln('type ' + type_name + ' = ' + target + '\n')
						emitted_stub_types[type_name] = true
						continue
					}
				}
				fixed_array_target := fixed_array_alias_target_for_stub_type(type_name, shared_type_set)
				if fixed_array_target != '' {
					out.writeln('type ' + type_name + ' = ' + fixed_array_target + '\n')
					emitted_stub_types[type_name] = true
					continue
				}
				out.writeln('struct ' + type_name + ' {}\n')
				emitted_stub_types[type_name] = true
			}
		}
	}
	if c2v.globals.len > 0 {
		out.writeln('// Cross-directory globals')
		mut emitted_global_names := map[string]bool{}
		mut global_names := c2v.globals.keys()
		global_names.sort()
		for global_name in global_names {
			if global_name == '' || global_name in v_keywords {
				continue
			}
			global_info := c2v.globals[global_name]
			mut typ_name := collapse_ascii_whitespace(global_info.typ)
			if typ_name == '' {
				typ_name = 'int'
			}
			if !typ_name.starts_with('fn ') && typ_name.contains(' ') {
				parts := typ_name.split(' ').filter(it != '')
				if parts.len == 0 {
					continue
				}
				if parts[0] in ['struct', 'class', 'union', 'enum'] && parts.len > 1 {
					typ_name = parts[1]
				} else {
					typ_name = parts[0]
				}
			}
			for typ_name.ends_with('.') {
				typ_name = typ_name[..typ_name.len - 1].trim_space()
			}
			typ_name = c2v.prefix_external_type(typ_name)
			if typ_name == '' || c2v.has_template_placeholder_type(typ_name) {
				continue
			}
			if c2v.skeleton_mode && c2v.project_single_module {
				// A flattened skeleton is self-contained: zero-valued weak globals stand
				// in for both native externs and complex C++ static initializers. Emitting
				// a C extern with the same symbol as a fallback (or a later translated
				// initializer) creates duplicate exports in V.
				emit_weak_global_decl(mut out, global_name, typ_name, true, mut emitted_global_names)
				lower_first_alias := filter_name(global_name.uncapitalize(), true)
				if lower_first_alias != '' && lower_first_alias != global_name {
					emit_weak_global_decl(mut out, lower_first_alias, typ_name, false, mut emitted_global_names)
				}
				snake_alias := filter_name(c_identifier_to_v_name(global_name), true)
				if snake_alias != '' && snake_alias != global_name {
					emit_weak_global_decl(mut out, snake_alias, typ_name, false, mut emitted_global_names)
				}
				continue
			}
			if global_name in defined_global_names {
				// The real translated initializer carries an export attribute for the C++
				// symbol. A parallel C extern or weak alias creates the same C export twice.
				continue
			}
			emit_c_extern_global_decl(mut out, global_name, typ_name, mut emitted_global_names)
			emit_weak_global_decl(mut out, global_name, typ_name, true, mut emitted_global_names)
			lower_first_alias := filter_name(global_name.uncapitalize(), true)
			if lower_first_alias != '' && lower_first_alias != global_name {
				emit_weak_global_decl(mut out, lower_first_alias, typ_name, false, mut emitted_global_names)
			}
			snake_alias := filter_name(c_identifier_to_v_name(global_name), true)
			if snake_alias != '' && snake_alias != global_name {
				emit_weak_global_decl(mut out, snake_alias, typ_name, false, mut emitted_global_names)
			}
		}
		out.writeln('')
	}
	if defined_global_names.len > 0 && !(c2v.skeleton_mode && c2v.project_single_module) {
		replacements := c2v.defined_global_ref_replacements()
		mut real_global_names := []string{}
		mut seen_real_global_names := map[string]bool{}
		for global_name in c2v.defined_global_order {
			if global_name in defined_global_names && global_name !in seen_real_global_names {
				real_global_names << global_name
				seen_real_global_names[global_name] = true
			}
		}
		mut remaining_real_global_names := defined_global_names.keys()
		remaining_real_global_names.sort()
		for global_name in remaining_real_global_names {
			if global_name !in seen_real_global_names {
				real_global_names << global_name
				seen_real_global_names[global_name] = true
			}
		}
		real_global_names = order_initialized_global_names(real_global_names, c2v.globals_out)
		mut wrote_header := false
		for global_name in real_global_names {
			mut global_decl := c2v.globals_out[global_name] or { continue }
			mut local_replacements := replacements.clone()
			local_replacements.delete(c_global_decl_v_name(global_name, true))
			global_decl = replace_defined_global_refs_in_text(global_decl, local_replacements)
			if global_decl.trim_space() == '' {
				continue
			}
			if !wrote_header {
				out.writeln('// Cross-directory initialized globals')
				wrote_header = true
			}
			out.writeln(global_decl)
		}
		if wrote_header {
			out.writeln('')
		}
	}
	out.write_string(c2v.global_constructors_source(c2v.defined_global_ref_replacements()))
	if c2v.project_function_surfaces.len > 0 {
		out.writeln('// Cross-directory top-level callable fallbacks')
		mut fn_keys := c2v.project_function_surfaces.keys()
		fn_keys.sort()
		for fn_key in fn_keys {
			if fn_key == '' || fn_key == 'main' {
				continue
			}
			if fn_key in local_function_set {
				continue
			}
			fn_signature := c2v.project_function_surfaces[fn_key]
			if fn_signature == '' {
				continue
			}
			out.writeln(fn_signature + ' {')
			c2v.write_fallback_callable_body(mut out, fn_signature)
		}
	}
	if c2v.project_method_surfaces.len > 0 {
		out.writeln('// Cross-directory method callable fallbacks')
		mut method_keys := c2v.project_method_surfaces.keys()
		method_keys.sort()
		for method_key in method_keys {
			if method_key == '' {
				continue
			}
			if method_key in local_method_set {
				continue
			}
			method_signature := c2v.project_method_surfaces[method_key]
			if method_signature == '' {
				continue
			}
			out.writeln(method_signature + ' {')
			c2v.write_fallback_callable_body(mut out, method_signature)
		}
	}
	out.writeln('\nfn main() {}\n')
	mut globals_src := out.str()
	if c2v.project_single_module {
		globals_src = filter_single_module_globals(globals_src, local_declared_set, local_interface_set, local_function_set, local_method_set, local_const_set)
	}
	os.write_file(path, globals_src) or { panic(err) }
}

fn c2v_variadic_compat_source() string {
	return [
		'__global c2v_current_variadic_args []voidptr',
		'',
		'fn c2v_set_variadic_args(args []voidptr) []voidptr {',
		'\tprevious := c2v_current_variadic_args',
		'\tc2v_current_variadic_args = args',
		'\treturn previous',
		'}',
		'',
		'// The C `v*printf` functions of translated code format the arguments of',
		'// the innermost translated variadic function (see c2v_set_variadic_args).',
		'fn c2v_vsnprintf[T](dest &i8, size T, fmt &i8, ap C.va_list) int {',
		'\t_ = ap',
		'\treturn c2v_format_variadic(dest, int(size), fmt, c2v_current_variadic_args)',
		'}',
		'',
		'fn c2v_vsprintf(dest &i8, fmt &i8, ap C.va_list) int {',
		'\t_ = ap',
		'\treturn c2v_format_variadic(dest, max_i32, fmt, c2v_current_variadic_args)',
		'}',
		'',
		'fn c2v_vfprintf(stream &C.FILE, fmt &i8, ap C.va_list) int {',
		'\t_ = ap',
		'\tmut buffer := [16384]i8{}',
		'\twritten := c2v_format_variadic(unsafe { &buffer[0] }, buffer.len, fmt, c2v_current_variadic_args)',
		'\tC.fputs(unsafe { &buffer[0] }, stream)',
		'\treturn written',
		'}',
		'',
		'fn c2v_vprintf(fmt &i8, ap C.va_list) int {',
		'\treturn c2v_vfprintf(C.stdout, fmt, ap)',
		'}',
		'',
		'fn c2v_variadic_is_immediate(raw usize) bool {',
		'\treturn raw < usize(1048576) || raw > ~usize(0) - usize(1048576)',
		'}',
		'',
		'fn c2v_variadic_signed(arg voidptr, wide bool) i64 {',
		'\traw := usize(arg)',
		'\tif c2v_variadic_is_immediate(raw) {',
		'\t\treturn i64(isize(raw))',
		'\t}',
		'\tif wide {',
		'\t\treturn unsafe { *(&i64(arg)) }',
		'\t}',
		'\treturn i64(unsafe { *(&int(arg)) })',
		'}',
		'',
		'fn c2v_variadic_unsigned(arg voidptr, wide bool) u64 {',
		'\traw := usize(arg)',
		'\tif c2v_variadic_is_immediate(raw) {',
		'\t\treturn u64(raw)',
		'\t}',
		'\tif wide {',
		'\t\treturn unsafe { *(&u64(arg)) }',
		'\t}',
		'\treturn u64(unsafe { *(&u32(arg)) })',
		'}',
		'',
		'fn c2v_is_printf_conversion(ch u8) bool {',
		'\treturn ch in [`d`, `i`, `u`, `o`, `x`, `X`, `f`, `F`, `e`, `E`, `g`, `G`, `a`, `A`, `c`, `s`, `p`, `n`]',
		'}',
		'',
		'fn c2v_format_variadic(dest &i8, size_2 int, fmt &i8, args []voidptr) int {',
		'\tif size_2 <= 0 || usize(dest) == 0 || usize(fmt) == 0 {',
		'\t\treturn 0',
		'\t}',
		'\tmut out_pos := 0',
		'\tmut fmt_pos := 0',
		'\tmut arg_pos := 0',
		'\tfor out_pos < size_2 - 1 && unsafe { fmt[fmt_pos] != 0 } {',
		'\t\tif unsafe { fmt[fmt_pos] } != i8(`%`) {',
		'\t\t\tunsafe { dest[out_pos] = fmt[fmt_pos] }',
		'\t\t\tout_pos++',
		'\t\t\tfmt_pos++',
		'\t\t\tcontinue',
		'\t\t}',
		'\t\tif unsafe { fmt[fmt_pos + 1] } == i8(`%`) {',
		'\t\t\tunsafe { dest[out_pos] = i8(`%`) }',
		'\t\t\tout_pos++',
		'\t\t\tfmt_pos += 2',
		'\t\t\tcontinue',
		'\t\t}',
		'\t\tmut spec := [64]i8{}',
		'\t\tmut spec_len := 0',
		'\t\tmut conversion := u8(0)',
		'\t\tmut wide := false',
		'\t\tfor spec_len < 62 && unsafe { fmt[fmt_pos] != 0 } {',
		'\t\t\tch := u8(unsafe { fmt[fmt_pos] })',
		'\t\t\tspec[spec_len] = i8(ch)',
		'\t\t\tspec_len++',
		'\t\t\tfmt_pos++',
		'\t\t\tif ch in [`l`, `L`, `j`, `z`, `t`] {',
		'\t\t\t\twide = true',
		'\t\t\t}',
		'\t\t\tif c2v_is_printf_conversion(ch) {',
		'\t\t\t\tconversion = ch',
		'\t\t\t\tbreak',
		'\t\t\t}',
		'\t\t}',
		'\t\tspec[spec_len] = 0',
		'\t\tif conversion == 0 {',
		'\t\t\tbreak',
		'\t\t}',
		'\t\tmut arg := voidptr(0)',
		'\t\tif arg_pos < args.len {',
		'\t\t\targ = args[arg_pos]',
		'\t\t}',
		'\t\targ_pos++',
		'\t\tif conversion == `n` {',
		'\t\t\tif usize(arg) != 0 {',
		'\t\t\t\tunsafe { *(&int(arg)) = out_pos }',
		'\t\t\t}',
		'\t\t\tcontinue',
		'\t\t}',
		'\t\tmut temp := [512]i8{}',
		'\t\tmut rendered := 0',
		'\t\tmatch conversion {',
		'\t\t\t`s` {',
		"\t\t\t\tstring_arg := if usize(arg) == 0 { c'(null)' } else { &i8(arg) }",
		'\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, string_arg)',
		'\t\t\t}',
		'\t\t\t`c` {',
		'\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, int(c2v_variadic_signed(arg, false)))',
		'\t\t\t}',
		'\t\t\t`d`, `i` {',
		'\t\t\t\tif wide {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, c2v_variadic_signed(arg, true))',
		'\t\t\t\t} else {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, int(c2v_variadic_signed(arg, false)))',
		'\t\t\t\t}',
		'\t\t\t}',
		'\t\t\t`u`, `o`, `x`, `X` {',
		'\t\t\t\tif wide {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, c2v_variadic_unsigned(arg, true))',
		'\t\t\t\t} else {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, u32(c2v_variadic_unsigned(arg, false)))',
		'\t\t\t\t}',
		'\t\t\t}',
		'\t\t\t`f`, `F`, `e`, `E`, `g`, `G`, `a`, `A` {',
		'\t\t\t\tfloat_arg := if usize(arg) == 0 { f64(0) } else if c2v_variadic_is_immediate(usize(arg)) { f64(isize(usize(arg))) } else { unsafe { *(&f64(arg)) } }',
		'\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, float_arg)',
		'\t\t\t}',
		'\t\t\t`p` {',
		'\t\t\t\trendered = C.snprintf(unsafe { &temp[0] }, usize(temp.len), unsafe { &spec[0] }, arg)',
		'\t\t\t}',
		'\t\t\telse {}',
		'\t\t}',
		'\t\tif rendered < 0 {',
		'\t\t\tcontinue',
		'\t\t}',
		'\t\tcopy_len := if rendered < temp.len - 1 { rendered } else { temp.len - 1 }',
		'\t\tfor i := 0; i < copy_len && out_pos < size_2 - 1; i++ {',
		'\t\t\tunsafe { dest[out_pos] = temp[i] }',
		'\t\t\tout_pos++',
		'\t\t}',
		'\t}',
		'\tunsafe { dest[out_pos] = 0 }',
		'\treturn out_pos',
		'}',
		'',
	].join('\n')
}

fn extract_named_attr_arg(line string, attr_name string) string {
	t := line.trim_space()
	prefix := '@[' + attr_name + ':'
	if !t.starts_with(prefix) {
		return ''
	}
	mut rest := t[prefix.len..].trim_space()
	if rest == '' {
		return ''
	}
	if rest.starts_with("'") {
		rest = rest[1..]
		return rest.all_before("'")
	}
	if rest.starts_with('"') {
		rest = rest[1..]
		return rest.all_before('"')
	}
	return rest.all_before(']').trim_space()
}

fn extract_top_level_v_fn_name(line string) string {
	t := line.trim_space()
	if !t.starts_with('fn ') {
		return ''
	}
	mut rest := t[3..].trim_space()
	if rest.starts_with('(') {
		return ''
	}
	return rest.all_before('(').trim_space()
}

fn find_next_top_level_v_fn_name(lines []string, start int) string {
	for i := start + 1; i < lines.len; i++ {
		t := lines[i].trim_space()
		if t == '' || t.starts_with('@[') || t.starts_with('//') {
			continue
		}
		return extract_top_level_v_fn_name(t)
	}
	return ''
}

fn (c2v &C2V) collect_exported_project_function_names() map[string]string {
	mut exported := map[string]string{}
	if c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return exported
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		lines := os.read_lines(file) or { continue }
		for i, line in lines {
			c_name := extract_named_attr_arg(line, 'export')
			if c_name == '' {
				continue
			}
			v_name := find_next_top_level_v_fn_name(lines, i)
			if v_name == '' {
				continue
			}
			exported[c_name] = v_name
		}
	}
	return exported
}

fn (mut c2v C2V) rewrite_project_defined_function_decls() {
	if !c2v.is_dir || c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return
	}
	exported := c2v.collect_exported_project_function_names()
	if exported.len == 0 {
		return
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		lines := os.read_lines(file) or { continue }
		mut out_lines := []string{cap: lines.len}
		mut changed := false
		for i, line in lines {
			c_name := extract_named_attr_arg(line, 'c')
			if c_name != '' {
				if v_name := exported[c_name] {
					if find_next_top_level_v_fn_name(lines, i) == v_name {
						changed = true
						continue
					}
				}
			}
			out_lines << line
		}
		if changed {
			os.write_file(file, out_lines.join('\n') + '\n') or { panic(err) }
		}
	}
}

fn is_identifier_char(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`)
		|| (ch >= `0` && ch <= `9`) || ch == `_`
}

fn replace_c_ref_token(s string, from string, to string) string {
	if s == '' || from == '' || from == to {
		return s
	}
	mut out := strings.new_builder(s.len)
	mut pos := 0
	for pos < s.len {
		idx := s.index_after(from, pos) or {
			out.write_string(s[pos..])
			break
		}
		before_ok := idx == 0 || !is_identifier_char(s[idx - 1])
		after_idx := idx + from.len
		after_ok := after_idx >= s.len || !is_identifier_char(s[after_idx])
		if before_ok && after_ok {
			out.write_string(s[pos..idx])
			out.write_string(to)
			pos = after_idx
		} else {
			out.write_string(s[pos..idx + 1])
			pos = idx + 1
		}
	}
	return out.str()
}

fn (c2v &C2V) defined_global_ref_replacements() map[string]string {
	mut replacements := map[string]string{}
	mut c_names := c2v.defined_globals.keys()
	for c_name in c2v.globals_out.keys() {
		global := c2v.globals[c_name] or { Global{} }
		if c_name !in c2v.defined_globals && !global.is_extern {
			c_names << c_name
		}
	}
	for c_name in c_names {
		c_ref_name := c_global_decl_v_name(c_name, true)
		mut v_name := c_global_decl_v_name(c_name, false)
		declared_v_name := v_name
		snake_ref_name := filter_name(c_identifier_to_v_name(c_name), true)
		if c2v.project_require_no_stubs && snake_ref_name != '' {
			// Strict V rejects module globals containing uppercase letters. Keep the
			// native spelling in the export attribute while reconciling every V-side
			// declaration/reference to the stable snake-case name.
			v_name = snake_ref_name
		} else if global_decl := c2v.globals_out[c_name] {
			if global_decl.contains('__global ${c_name} ') {
				v_name = c_name
			}
		}
		if v_name == '' {
			continue
		}
		if c_ref_name.starts_with('C.') && v_name != c_ref_name {
			replacements[c_ref_name] = v_name
		}
		if declared_v_name != '' && declared_v_name != v_name {
			replacements[declared_v_name] = v_name
		}
		// Header declarations are collected before a later definition and use
		// c_identifier_to_v_name(), while the historical global declaration path
		// only lowercases the first character. Reconcile both spellings once the
		// project has seen the actual definition.
		if snake_ref_name != '' && snake_ref_name != v_name {
			replacements[snake_ref_name] = v_name
		}
	}
	return replacements
}

fn replace_defined_global_refs_in_text(s string, replacements map[string]string) string {
	if replacements.len == 0 || s == '' {
		return s
	}
	// The old implementation made one complete pass over `s` for every known
	// global. A large single-module project can have thousands of globals and
	// millions of generated tokens, turning final reconciliation into a lengthy
	// quadratic phase. Scan each identifier/C-qualified token once instead.
	mut out := strings.new_builder(s.len)
	mut i := 0
	for i < s.len {
		if s[i] == `'` || s[i] == `"` {
			quote := s[i]
			start := i
			i++
			for i < s.len {
				if s[i] == `\\` && i + 1 < s.len {
					i += 2
					continue
				}
				i++
				if s[i - 1] == quote {
					break
				}
			}
			out.write_string(s[start..i])
			continue
		}
		if s[i] == `/` && i + 1 < s.len && s[i + 1] == `/` {
			end := s.index_after('\n', i + 2) or { s.len }
			out.write_string(s[i..end])
			i = end
			continue
		}
		if s[i] == `/` && i + 1 < s.len && s[i + 1] == `*` {
			end_start := s.index_after('*/', i + 2) or { s.len - 2 }
			end := if end_start + 2 <= s.len { end_start + 2 } else { s.len }
			out.write_string(s[i..end])
			i = end
			continue
		}
		if !is_identifier_char(s[i]) {
			out.write_u8(s[i])
			i++
			continue
		}
		start := i
		for i < s.len && is_identifier_char(s[i]) {
			i++
		}
		if s[start..i] == 'C' && i + 1 < s.len && s[i] == `.` && is_identifier_char(s[i + 1]) {
			i++
			for i < s.len && is_identifier_char(s[i]) {
				i++
			}
		}
		token := s[start..i]
		out.write_string(replacements[token] or { token })
	}
	return out.str()
}

fn (mut c2v C2V) rewrite_project_defined_global_refs() {
	if !c2v.is_dir || c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return
	}
	replacements := c2v.defined_global_ref_replacements()
	if replacements.len == 0 {
		return
	}
	files := os.walk_ext(c2v.project_output_root, '.v')
	for file in files {
		if is_c2v_globals_file(file) {
			continue
		}
		s := os.read_file(file) or { continue }
		replaced := replace_defined_global_refs_in_translated_source(s, replacements)
		if replaced != s {
			os.write_file(file, replaced) or { panic(err) }
		}
	}
}

fn replace_defined_global_refs_in_translated_source(s string, replacements map[string]string) string {
	mut out := strings.new_builder(s.len)
	mut enum_depth := 0
	for line in s.split_into_lines() {
		trimmed := line.trim_space()
		starts_enum := enum_depth == 0 && (trimmed.starts_with('enum ')
			|| trimmed.starts_with('pub enum ')) && trimmed.ends_with('{')
		if starts_enum {
			enum_depth = line.count('{') - line.count('}')
			out.writeln(line)
			continue
		}
		if enum_depth > 0 {
			out.writeln(line)
			enum_depth += line.count('{') - line.count('}')
			continue
		}
		out.writeln(replace_defined_global_refs_in_text(line, replacements))
	}
	return out.str().trim_right('\n') + if s.ends_with('\n') {
		'\n'
	} else {
		''
	}
}

fn method_base_from_surface_key(key string) string {
	if !key.contains('.') {
		return ''
	}
	return key.all_after_last('.').trim_space()
}

fn skip_balanced_call_args(src string, open_idx int) int {
	mut i := open_idx
	mut depth := 0
	mut quote := u8(0)
	for i < src.len {
		ch := src[i]
		if quote != 0 {
			if ch == `\\` && i + 1 < src.len {
				i += 2
				continue
			}
			if ch == quote {
				quote = 0
			}
			i++
			continue
		}
		if ch == `'` || ch == `"` {
			quote = ch
			i++
			continue
		}
		if ch == `(` {
			depth++
		} else if ch == `)` {
			depth--
			if depth == 0 {
				return i + 1
			}
		}
		i++
	}
	return open_idx + 1
}

fn strip_args_for_fallback_method_names(src string, method_names map[string]bool) string {
	if src == '' || method_names.len == 0 {
		return src
	}
	mut out := strings.new_builder(src.len)
	mut i := 0
	for i < src.len {
		ch := src[i]
		if ch == `'` || ch == `"` {
			quote := ch
			start := i
			i++
			for i < src.len {
				if src[i] == `\\` && i + 1 < src.len {
					i += 2
					continue
				}
				if src[i] == quote {
					i++
					break
				}
				i++
			}
			out.write_string(src[start..i])
			continue
		}
		if ch == `.` && i + 1 < src.len && is_identifier_char(src[i + 1]) {
			name_start := i + 1
			mut name_end := name_start
			for name_end < src.len && is_identifier_char(src[name_end]) {
				name_end++
			}
			name := src[name_start..name_end]
			if name in method_names && name_end < src.len && src[name_end] == `(` {
				out.write_string(src[i..name_end])
				out.write_string('()')
				i = skip_balanced_call_args(src, name_end)
				continue
			}
		}
		out.write_u8(ch)
		i++
	}
	return out.str()
}

fn (mut c2v C2V) rewrite_fallback_method_call_args() {
	if !c2v.is_dir || c2v.project_output_root == '' || !os.exists(c2v.project_output_root)
		|| c2v.project_method_surfaces.len == 0 {
		return
	}
	_, local_methods_by_dir := c2v.collect_output_callable_names_by_dir()
	files := os.walk_ext(c2v.project_output_root, '.v')
	mut dirs := map[string]bool{}
	for file in files {
		if !is_c2v_globals_file(file) {
			dirs[os.dir(file)] = true
		}
	}
	mut method_keys := c2v.project_method_surfaces.keys()
	method_keys.sort()
	for dir in dirs.keys() {
		local_methods := local_methods_by_dir[dir] or { []string{} }
		mut local_method_set := map[string]bool{}
		mut local_method_names := map[string]bool{}
		for key in local_methods {
			local_method_set[key] = true
			name := method_base_from_surface_key(key)
			if name != '' {
				local_method_names[name] = true
			}
		}
		mut fallback_method_names := map[string]bool{}
		for key in method_keys {
			if key in local_method_set {
				continue
			}
			name := method_base_from_surface_key(key)
			if name == '' || name in local_method_names {
				continue
			}
			fallback_method_names[name] = true
		}
		if fallback_method_names.len == 0 {
			continue
		}
		for file in files {
			if os.dir(file) != dir || is_c2v_globals_file(file) {
				continue
			}
			src := os.read_file(file) or { continue }
			rewritten := strip_args_for_fallback_method_names(src, fallback_method_names)
			if rewritten != src {
				os.write_file(file, rewritten) or { panic(err) }
			}
		}
	}
}

fn (c &C2V) verror(msg string) {
	$if linux {
		eprintln('\x1b[31merror: ${msg}\x1b[0m')
	} $else {
		eprintln('error: ${msg}')
	}
	exit(1)
}

fn strict_global_declared_name(declaration string) string {
	for marker in ['__global ', 'const '] {
		marker_i := declaration.index(marker) or { continue }
		start := marker_i + marker.len
		mut end := start
		for end < declaration.len
			&& (is_identifier_char(declaration[end]) || declaration[end] == `.`) {
			end++
		}
		if end > start {
			return declaration[start..end]
		}
	}
	return ''
}

fn strict_global_reference_tokens(declaration string) map[string]bool {
	mut tokens := map[string]bool{}
	mut start := -1
	for i := 0; i <= declaration.len; i++ {
		is_identifier := i < declaration.len && is_identifier_char(declaration[i])
		if is_identifier && start < 0 {
			start = i
		} else if !is_identifier && start >= 0 {
			tokens[declaration[start..i]] = true
			start = -1
		}
	}
	return tokens
}

fn (c2v &C2V) ordered_strict_global_declarations(replacements map[string]string) []string {
	mut ordered_names := []string{}
	mut seen_names := map[string]bool{}
	for name in c2v.defined_global_order {
		if name in c2v.globals_out && name !in seen_names {
			ordered_names << name
			seen_names[name] = true
		}
	}
	mut remaining_names := c2v.globals_out.keys()
	remaining_names.sort()
	for name in remaining_names {
		if name !in seen_names {
			ordered_names << name
			seen_names[name] = true
		}
	}

	mut declarations := map[string]string{}
	mut owner_by_declared_name := map[string]string{}
	for name in ordered_names {
		mut local_replacements := replacements.clone()
		local_replacements.delete(c_global_decl_v_name(name, true))
		declaration := replace_defined_global_refs_in_text(c2v.globals_out[name], local_replacements)
		declarations[name] = declaration
		declared_name := strict_global_declared_name(declaration)
		if declared_name != '' {
			owner_by_declared_name[declared_name] = name
		}
	}

	mut dependencies := map[string]map[string]bool{}
	for name in ordered_names {
		tokens := strict_global_reference_tokens(declarations[name])
		mut name_dependencies := map[string]bool{}
		for token in tokens.keys() {
			if dependency_name := owner_by_declared_name[token] {
				if dependency_name != name {
					name_dependencies[dependency_name] = true
				}
			}
		}
		dependencies[name] = name_dependencies.clone()
	}

	mut result := []string{cap: ordered_names.len}
	mut emitted := map[string]bool{}
	for result.len < ordered_names.len {
		mut made_progress := false
		for name in ordered_names {
			if name in emitted {
				continue
			}
			if dependencies[name].keys().all(it in emitted) {
				result << declarations[name]
				emitted[name] = true
				made_progress = true
			}
		}
		if made_progress {
			continue
		}
		// Preserve deterministic output for an actual dependency cycle; V will
		// report the cyclic initializer separately.
		for name in ordered_names {
			if name !in emitted {
				result << declarations[name]
				emitted[name] = true
				break
			}
		}
	}
	return result
}

fn (mut c2v C2V) save_globals() {
	globals_path := c2v.get_globals_path()
	// Full globals aggregation across a large directory tree produces many
	// unresolved cross-file type/value dependencies in V. Emit a minimal globals
	// unit for dir-mode output so `v .` can type-check translated files directly.
	if c2v.skeleton_mode || (c2v.is_dir && c2v.project_generate_stubs) {
		mut shared_stub_types := []string{}
		mut declared_by_dir := map[string][]string{}
		mut alias_targets := map[string]string{}
		mut struct_defs := map[string]string{}
		mut local_functions_by_dir := map[string][]string{}
		mut local_methods_by_dir := map[string][]string{}
		if c2v.is_dir {
			declared_types := c2v.collect_output_declared_types()
			alias_targets = c2v.collect_output_alias_targets()
			struct_defs = c2v.collect_output_struct_definitions()
			declared_by_dir = c2v.collect_output_declared_types_by_dir()
			if c2v.project_has_cpp {
				shared_stub_types = c2v.collect_shared_stub_type_names(declared_types)
				struct_referenced_types := c2v.collect_struct_referenced_stub_types(struct_defs)
				if struct_referenced_types.len > 0 {
					mut merged_stub_types := map[string]bool{}
					for type_name in shared_stub_types {
						if is_valid_stub_type_name(type_name) {
							merged_stub_types[type_name] = true
						}
					}
					for type_name in struct_referenced_types {
						if is_valid_stub_type_name(type_name) {
							merged_stub_types[type_name] = true
						}
					}
					shared_stub_types = merged_stub_types.keys()
					shared_stub_types.sort()
				}
				local_functions_by_dir, local_methods_by_dir =
					c2v.collect_output_callable_names_by_dir()
			}
			// Remove stale per-directory globals from previous runs.
			files := os.walk_ext(c2v.project_output_root, '.v')
			for file in files {
				if is_c2v_globals_file(file) && file != globals_path {
					os.rm(file) or {}
				}
			}
		}
		root_dir := os.dir(globals_path)
		root_declared := declared_by_dir[root_dir] or { []string{} }
		root_functions := local_functions_by_dir[root_dir] or { []string{} }
		root_methods := local_methods_by_dir[root_dir] or { []string{} }
		c2v.write_globals_stub_file(globals_path, root_declared, shared_stub_types, alias_targets, struct_defs, root_functions, root_methods)
		if c2v.is_dir && c2v.project_has_cpp {
			for dir, local_declared in declared_by_dir {
				local_globals := os.join_path(dir, '0_globals.v')
				if local_globals == globals_path {
					continue
				}
				local_functions := local_functions_by_dir[dir] or { []string{} }
				local_methods := local_methods_by_dir[dir] or { []string{} }
				c2v.write_globals_stub_file(local_globals, local_declared, shared_stub_types, alias_targets, struct_defs, local_functions, local_methods)
			}
		}
		return
	}
	mut out := strings.new_builder(1024)
	out.writeln('@[translated]\n@[has_globals]\nmodule main\n')
	for include_dir in configured_include_dirs(c2v.project_folder, c2v.project_additional_flags) {
		out.writeln('#flag -I' + include_dir)
	}
	for native_source in c2v.native_manifest_files() {
		out.writeln('#flag ' + os.quoted_path(native_source))
	}
	if c2v.project_has_cpp {
		// Large translated programs initialize C++ global objects in V's `_vinit`.
		// On macOS that generated function can exceed the default 8 MiB main-thread
		// stack before user main starts; match the program's actual startup needs.
		out.writeln('#flag darwin -Wl,-stack_size,0x2000000')
	}
	if c2v.project_native_manifest != '' {
		out.writeln('')
	}
	// V resolves global identifiers most reliably when declarations precede
	// ordinary helper/function bodies in the module's first source unit. This is
	// especially important for inferred fixed arrays shared across C++ headers.
	replacements := c2v.defined_global_ref_replacements()
	// C++ constant initialization precedes dynamic object construction even when
	// the definitions live in separate translation units. Make sentinel storage
	// available before constructor calls enter V's `_vinit`.
	global_declarations := c2v.ordered_strict_global_declarations(replacements)
	for global_decl in global_declarations {
		out.writeln(global_decl)
	}
	out.write_string(c2v.global_constructors_source(replacements))
	if c2v.project_has_cpp {
		// External declarations depend on what the whole translated program uses.
		mut program_source := strings.new_builder(1 << 20)
		for file in os.walk_ext(c2v.project_output_root, '.v') {
			if !is_c2v_globals_file(file) {
				program_source.write_string(os.read_file(file) or { '' })
			}
		}
		for global_decl in global_declarations {
			program_source.writeln(global_decl)
		}
		program_text := program_source.str()
		write_strict_c_math_declarations(mut out)
		write_strict_cpp_compat_declarations(mut out, used_c_symbols(program_text))
		c2v.write_strict_external_c_function_declarations(mut out)
		c2v.write_strict_semantic_compat_helpers(mut out)
		// V's C backend only relies on the system header for C records declared
		// in a `.c.v` file, so the external surface lives in its own file.
		mut external := strings.new_builder(4096)
		external.writeln('@[translated]\nmodule main\n')
		c2v.write_strict_external_abi_declarations(mut external, program_text + out.after(0))
		os.write_file(os.join_path(os.dir(globals_path), c2v_external_decls_file_name), external.str()) or { panic(err) }
	}
	mut out_s := out.str()
	// Global fallback for malformed inferred empty array literals from recovery AST.
	out_s = out_s.replace('= []!', '= 0')
	out_s = replace_strict_global_array_result_suffixes(out_s, c2v.static_global_arrays)
	os.write_file(globals_path, out_s) or { panic(err) }
	// if os.exists(globals_path) {
	//	os.system('v fmt -translated -w ${globals_path} > /dev/null')
	// }
}

fn write_strict_c_math_declarations(mut out strings.Builder) {
	out.writeln('// Native C math declarations used by translated inline headers')
	for declaration in [
		'fn C.acos(f64) f64',
		'fn C.acosf(f32) f32',
		'fn C.asin(f64) f64',
		'fn C.asinf(f32) f32',
		'fn C.atan(f64) f64',
		'fn C.atan2(f64, f64) f64',
		'fn C.atan2f(f32, f32) f32',
		'fn C.atanf(f32) f32',
		'fn C.ceil(f64) f64',
		'fn C.ceilf(f32) f32',
		'fn C.cos(f64) f64',
		'fn C.cosf(f32) f32',
		'fn C.exp(f64) f64',
		'fn C.expf(f32) f32',
		'fn C.floor(f64) f64',
		'fn C.floorf(f32) f32',
		'fn C.log(f64) f64',
		'fn C.logf(f32) f32',
		'fn C.pow(f64, f64) f64',
		'fn C.powf(f32, f32) f32',
		'fn C.sin(f64) f64',
		'fn C.sinf(f32) f32',
		'fn C.sqrt(f64) f64',
		'fn C.sqrtf(f32) f32',
		'fn C.tan(f64) f64',
		'fn C.tanf(f32) f32',
	] {
		out.writeln(declaration)
	}
	out.writeln('')
}

// libc functions the translator itself lowers C++ constructs to. Each
// prototype is written only when the translated program references it.
const strict_libc_compat_declarations = {
	'malloc':      'fn C.malloc(usize) voidptr'
	'realloc':     'fn C.realloc(voidptr, usize) voidptr'
	'strlen':      'fn C.strlen(&i8) usize'
	'strcpy':      'fn C.strcpy(&i8, &i8) &i8'
	'snprintf':    'fn C.snprintf(&i8, usize, &i8, ...) int'
	'strstr':      'fn C.strstr(&i8, &i8) &i8'
	'isalpha':     'fn C.isalpha(int) int'
	'localtime_r': 'fn C.localtime_r(&i64, &C.tm) &C.tm'
	'strftime':    'fn C.strftime(&i8, usize, &i8, &C.tm) usize'
	'time':        'fn C.time(voidptr) i64'
	'vfprintf':    'fn C.vfprintf(&C.FILE, &i8, C.va_list) int'
	'vprintf':     'fn C.vprintf(&i8, C.va_list) int'
	'vsnprintf':   'fn C.vsnprintf(&i8, int, &i8, C.va_list) int'
	'vsprintf':    'fn C.vsprintf(&i8, &i8, C.va_list) int'
}

fn write_strict_cpp_compat_declarations(mut out strings.Builder, used_c_names map[string]bool) {
	out.writeln('// C++ compiler-builtin compatibility declarations')
	out.writeln('#include <ctype.h>')
	out.writeln('#include <stdio.h>')
	out.writeln('#include <stdlib.h>')
	out.writeln('#include <time.h>')
	for name, declaration in strict_libc_compat_declarations {
		// `builtin_alloca` below always allocates through malloc.
		if name in used_c_names || name == 'malloc' {
			out.writeln(declaration)
		}
	}
	out.writeln('fn C.va_arg(voidptr, voidptr) voidptr')
	out.writeln('fn builtin_alloca(size usize) voidptr {')
	out.writeln('\treturn C.malloc(size)')
	out.writeln('}')
	out.writeln('fn builtin_va_start(arg0 &C.va_list, arg1 voidptr) {}')
	out.writeln('fn builtin_va_end(arg0 &C.va_list) {}')
	out.writeln('fn builtin_va_copy(arg0 &C.va_list, arg1 &C.va_list) {}')
	out.writeln('fn c2v_ref_value[T](value T) &T {')
	out.writeln('\treturn &value')
	out.writeln('}')
	write_c2v_bswap_helpers(mut out)
	out.writeln("fn c2v_builtin_trap() { panic('C __builtin_trap') }")
	out.writeln('')
	write_c2v_pointer_update_helpers(mut out)
}

fn (c2v &C2V) write_strict_semantic_compat_helpers(mut out strings.Builder) {
	if c2v.cpp_abstract_types.len > 0 {
		out.write_string(cpp_interface_runtime_helpers_source())
	}
	out.writeln(c2v_variadic_compat_source())
}

fn write_c2v_bswap_helpers(mut out strings.Builder) {
	out.writeln('fn c2v_builtin_bswap16(value u16) u16 {')
	out.writeln('\treturn (value >> 8) | (value << 8)')
	out.writeln('}')
	out.writeln('fn c2v_builtin_bswap32(value u32) u32 {')
	out.writeln('\treturn (value >> 24) | ((value >> 8) & u32(0x0000ff00)) | ((value << 8) & u32(0x00ff0000)) | (value << 24)')
	out.writeln('}')
}

fn write_c2v_pointer_update_helpers(mut out strings.Builder) {
	out.writeln('fn c2v_pointer_postfix[T](storage voidptr, pointer &T, delta isize) &T {')
	out.writeln('\tunsafe { *(&&T(storage)) = pointer + delta }')
	out.writeln('\told := pointer')
	out.writeln('\treturn old')
	out.writeln('}')
	out.writeln('')
	out.writeln('fn c2v_pointer_prefix[T](storage voidptr, pointer &T, delta isize) &T {')
	out.writeln('\tupdated := unsafe { pointer + delta }')
	out.writeln('\tunsafe { *(&&T(storage)) = updated }')
	out.writeln('\treturn updated')
	out.writeln('}')
	out.writeln('')
}

// write_strict_external_abi_declarations links the configured native libraries
// and declares every system-header type the translated program references.
fn (c2v &C2V) write_strict_external_abi_declarations(mut out strings.Builder, program_source string) {
	for pkg in c2v.project_pkg_config {
		out.writeln('#pkgconfig ' + pkg)
	}
	if c2v.project_link_flags != '' {
		out.writeln('#flag ' + c2v.project_link_flags)
	}
	// Globals declared by system headers (e.g. Darwin's `mach_task_self_`).
	mut global_names := c2v.globals.keys().filter(c2v.globals[it].is_extern
		&& it in c2v.system.declaring_headers)
	global_names.sort()
	mut emitted := map[string]bool{}
	for name in global_names {
		emit_c_extern_global_decl(mut out, name, c2v.globals[name].typ, mut emitted)
	}
	out.write_string(c2v.external_surface_declarations(program_source, c2v.project_additional_flags))
}

fn (c2v &C2V) write_strict_external_c_function_declarations(mut out strings.Builder) {
	if c2v.external_c_fn_declarations.len == 0 {
		return
	}
	out.writeln('// C-linkage functions referenced from external headers')
	mut names := c2v.external_c_fn_declarations.keys()
	names.sort()
	for name in names {
		if name !in c2v.system.declaring_headers {
			// Declared by a project header for natively compiled sources. That
			// header is translated rather than included, so V emits the prototype.
			out.writeln('@[c_extern]')
		}
		out.writeln(c2v.external_c_fn_declaration(name))
	}
	out.writeln('')
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
