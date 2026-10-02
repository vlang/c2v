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
const v_keywords = ['__global', '__offsetof', 'as', 'asm', 'assert', 'atomic', 'bool', 'byte',
	'chan', 'defer', 'dump', 'false', 'fn', 'go', 'implements', 'import', 'in', 'interface', 'is',
	'isize', 'isreftype', 'lock', 'map', 'match', 'module', 'mut', 'nil', 'none', 'or', 'pub',
	'rlock', 'rune', 'select', 'shared', 'spawn', 'sql', 'string', 'struct', 'thread', 'true',
	'type', 'typeof', 'unsafe', 'usize', 'voidptr', '_likely_', '_unlikely_']

// V type names. A local spelled like one (`i64`) would be parsed as a type.
const v_local_reserved_type_names = ['i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'f32',
	'f64', 'int', 'byteptr', 'charptr']

// V's reserved words. C names spelled like them are written as `@name` in V.
const v_reserved_words = ['__global', '__offsetof', 'as', 'asm', 'assert', 'atomic', 'break', 'const',
	'continue', 'defer', 'dump', 'else', 'enum', 'false', 'fn', 'for', 'go', 'goto', 'if', 'implements',
	'import', 'in', 'interface', 'is', 'isreftype', 'lock', 'match', 'module', 'mut', 'nil', 'none',
	'or', 'pub', 'return', 'rlock', 'select', 'shared', 'sizeof', 'spawn', 'static', 'struct',
	'true', 'type', 'typeof', 'union', 'unsafe', 'volatile']

// libc fn definitions that have to be skipped (V already knows about them):
const builtin_fn_names = ['fopen', 'puts', 'fflush', 'getline', 'printf', 'memset', 'atoi', 'memcpy',
	'remove', 'strlen', 'rename', 'stdout', 'stderr', 'stdin', 'ftell', 'fclose', 'fread', 'read',
	'perror', 'ftruncate', 'FILE', 'strcmp', 'toupper', 'strchr', 'strdup', 'strncasecmp', 'strcasecmp',
	'isspace', 'strncmp', 'malloc', 'close', 'open', 'lseek', 'fseek', 'fgets', 'rewind', 'write',
	'calloc', 'setenv', 'gets', 'abs', 'sqrt', 'erfl', 'fprintf', 'snprintf', 'exit', '__stderrp',
	'fwrite', 'scanf', 'sscanf', 'strrchr', 'strchr', 'div', 'free', 'memcmp', 'memmove', 'vsnprintf',
	'rintf', 'rint', 'bsearch', 'qsort', '__stdinp', '__stdoutp', '__stderrp', 'getenv', 'strtoul',
	'strtol', 'strtod', 'strtof', '__error', 'errno', 'atol', 'atof', 'atoll', 'fputs', 'fputc',
	'putchar', 'getchar', 'putc', 'getc', 'feof', 'ferror', 'clearerr', 'fileno', 'isalnum', 'isalpha',
	'isdigit', 'islower', 'isupper', 'isxdigit', 'iscntrl', 'isgraph', 'isprint', 'ispunct', 'tolower',
	'strcat', 'strncat', 'strpbrk', 'strspn', 'strcspn', 'strstr', 'strerror', 'sprintf', 'vsprintf',
	'vfprintf', 'vprintf', 'strcpy', '__assert_rtn', '__builtin_expect', '__builtin_va_start',
	'__builtin_va_end', 'setvbuf', 'stat', 'tmpfile', 'rand', 'strncpy', 'getuid', 'ioctl', 'realpath',
	'sigaction', 'sysconf']

// C functions of `builtin_fn_names` that only V's `os` module declares:
// translated programs do not import it, so c2v declares them.
const v_os_module_c_fn_names = ['ioctl', 'sigaction']

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
const v_integer_type_names = ['i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
	'usize']

const v_primitive_type_names = ['bool', 'i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64',
	'isize', 'usize', 'f32', 'f64', 'byte', 'rune', 'char', 'string', 'voidptr', 'none']

// V reserved function names that conflict with V builtins or cause module prefix issues:
// - 'error' is V's built-in error function
// - functions starting with 'builtin_' get interpreted as 'builtin__' module prefix
// - V's builtin `free`, `exit`, `malloc` and `isnil` cannot be redefined
const v_reserved_fn_names = ['error', 'print', 'println', 'eprintln', 'panic', 'assert', 'init',
	'cleanup', 'free', 'exit', 'malloc', 'isnil']

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
	out                         strings.Builder   // os.File
	globals_out                 map[string]string // `globals_out["myglobal"] == "extern int myglobal = 0;"` // strings.Builder
	out_file                    os.File
	out_line_empty              bool
	types                       map[string]string               // to avoid dups
	type_aliases                map[string]string               // V type name -> underlying type (for resolving alias chains)
	file_declared_aliases       map[string]bool                 // aliases emitted in the current output file
	file_type_alias_names       map[string]string               // colliding project alias -> translation-unit-local V alias
	enums                       map[string]string               // to avoid dups
	enum_vals                   map[string][]string             // enum_vals['Color'] = ['green', 'blue'], for converting C globals  to enum values
	enum_int_vals               map[string]i64                  // maps enum constant names to their integer values
	structs                     map[string]Struct               // for correct `Foo{field:..., field2:...}` (implicit value init expr is 0, so un-initied fields are just skipped with 0s)
	fns                         map[string]string               // to avoid dups
	fn_name_files               map[string]string               // C function name -> file that first registered it
	static_fn_owners            map[string]string               // C function name -> the file whose static function holds its V name
	file_static_fn_names        map[string]bool                 // the functions of the current C file declared `static`
	extern_fns                  map[string]string               // extern C fns
	external_c_fn_declarations  map[string]string               // C-linkage header function -> typed V ABI declaration
	external_c_fn_signatures    map[string]ExternalCFnSignature // the V types of external_c_fn_declarations
	outv                        string
	cur_file                    string
	consts                      map[string]string
	globals                     map[string]Global
	defined_globals             map[string]bool
	defined_global_order        []string
	inside_switch               int             // used to be a bool, a counter to handle switches inside switches
	switch_end_labels           []string        // labels after the enclosing matches, targets of nested `break`s
	switch_trailing_breaks      map[string]bool // ids of the `break`s that end a case arm
	used_switch_end_labels      map[string]bool
	switch_label_count          int
	inside_switch_enum          bool
	switch_cases_as_int         bool   // the cases of the current switch are constants of several enums
	enum_values_as_int          bool   // emit enum constants as `int(Enum.value)`
	inside_for                  bool   // to handle `;;++i`
	inside_comma_expr           bool   // to handle prefix ++/-- in comma expressions
	inside_for_post             bool   // to keep comma operators inline in `for` post expressions
	inside_for_init             bool   // while emitting the init section of a C-style `for` loop
	for_clause_root_id          string // AST id of the active C-style `for` init/post clause root
	inside_cpp_reference_lvalue bool   // preserve &T returned by an overloaded operator in lvalue/reference contexts
	inside_array_index          bool   // for enums used as int array index: `if player.weaponowned[.wp_chaingun]`
	inside_sizeof               bool   // to skip unsafe blocks for pointer dereferences in sizeof
	inside_unsafe               bool   // to prevent nested unsafe blocks
	array_init_depth            int = -1 // innermost ArrayInitLoopExpr index an ArrayInitIndexExpr refers to
	pre_cond_stmts              []string // statements to output before conditions (for assignment-in-expr patterns)
	collecting_pre_cond         bool
	conditional_eval_depth      int               // > 0 while emitting an operand C evaluates only conditionally (`a && b`, `c ? x : y`)
	value_context_depth         int               // > 0 while emitting an operand whose value is used (not a statement)
	pending_case_label          string            // label to put at the start of the next match arm (a fallthrough target)
	compiler_builtin_decls      map[string]Node   // Clang's implicit declarations of compiler builtins (`__builtin_clzll`)
	conditional_result_type     string            // V type of the `?:` whose branches are being emitted
	emitting_callee             bool              // emitting the function expression of a call
	defined_function_names      map[string]bool   // functions the current translation unit defines
	tree_global_v_names         map[string]bool   // V names the current translation unit's globals can take
	record_owner_stack          []string          // V names of the records enclosing the anonymous member record being declared
	voidptr_array_fields        map[string]string // FieldDecl id of a pointer array stored as `[N]voidptr` -> its element pointer type
	record_layouts              map[string]string // V record name -> signature of its C layout (see record_layout_signature)
	local_v_names_seen          map[string]bool   // V names of the locals and parameters of all translated functions
	mutated_variable_ids        map[string]bool   // variables the translation unit writes or takes the address of
	global_struct_init          string
	inside_global_init          bool
	cur_out_line                string
	inside_main                 bool
	indent                      int
	empty_line                  bool // for indents
	is_wrapper                  bool
	is_cpp                      bool   // translating a C++ (.cpp) file
	single_fn_def               bool   // v translate fndef [fn_name]
	fn_def_name                 string // for translating just one fn definition (used by V on #include "header.h")
	wrapper_module_name         string // name of the wrapper module
	nm_lines                    []string
	is_verbose                  bool
	skip_parens                 bool              // for skipping unnecessary params like in `enum Foo { bar = (1+2) }`
	labels                      map[string]string // for goto stmts: `label_stmts[label_id] == 'labelname'`
	//
	project_folder   string // the folder where c2v.toml was discovered (or the CLI target folder by default)
	target_root      string // the final folder passed on the CLI, or the folder of the final file passed on the CLI
	source_scan_root string // directory root used for recursive source discovery in dir mode
	invocation_cwd   string // working directory where c2v was invoked
	conf             toml.Doc = empty_toml_doc() // conf will be set by parsing the TOML configuration file
	//
	project_output_dirname   string   // by default, 'c2v_out.dir'; override with `[project] output_dirname = "another"`
	project_additional_flags string   // what to pass to clang, so that it could parse all the input files; mainly -I directives to find additional headers; override with `[project] additional_flags = "-I/some/folder"`
	project_uses_sdl         bool     // if a project uses sdl, then the additional flags will include the result of `sdl2-config --cflags` too; override with `[project] uses_sdl = true`
	project_single_module    bool     // flatten directory output so every translated unit is compiled in one V module
	project_generate_stubs   bool     // generate cross-directory fallback types/methods and an empty main
	project_require_no_stubs bool     // reject recovered ASTs and generated placeholder bodies
	project_require_main     bool     // require a translated executable entrypoint in directory output
	project_source_manifest  string   // optional newline-delimited source list, relative to project_folder
	project_native_manifest  string   // optional newline-delimited C sources compiled unchanged into the V target
	project_pkg_config       []string // pkg-config packages of external C libraries used by the project
	project_link_flags       string   // extra C linker flags for external libraries (`[project] link_flags`)
	file_additional_flags    string   // can be added per file, appended to project_additional_flags ; override with `['info.c'] additional_flags = -I/xyz`
	skeleton_mode            bool     // generate stub function bodies instead of full statements
	//
	project_output_root  string // absolute output root for translated files and globals
	project_globals_path string // where to store the leading 0_globals.v file containing project globals/consts
	source_text          string // current source file contents, used for conservative recovery fallbacks
	//
	translations                       int // how many translations were done so far
	translation_start_ticks            i64 // initialised before the loop calling .translate_file()
	has_cfile                          bool
	project_has_cpp                    bool
	returning_bool                     bool
	cur_fn_ret_type                    string // current function's return type
	uses_cpp_interface_runtime         bool   // a directory translation calls the helpers of cpp_interface_runtime_helpers_source
	expr_operation_start               int = -1 // output line length when the binary operation being emitted started
	expr_parent_operation_start        int = -1 // ... the one whose operand is being emitted
	cur_fn_variant_return              bool   // the function returns a record of this file's layout as the project's type (see project_variant_type)
	cur_class                          string // current C++ class/struct being processed
	keep_ast                           bool   // do not delete ast.json after running
	split_files                        bool   // write one V file per original source file (see split.v)
	skip_comments                      bool   // output no comments (see comments.v)
	project_module_name                string = 'main' // the V module of the translation (see modules.v)
	record_tag_v_names                 map[string]string // record tag (capitalized) -> V name of the typedef naming the record
	split_main_file                    string
	split_current_file                 string
	line_directives                    []LineDirective   // the `#line` directives of the main file
	top_level_node_files               map[string]string // top level node id -> the file clang read it from
	last_declared_type_name            string
	forced_record_name                 string            // the V name for the next record_decl() (a named anonymous member record)
	anonymous_record_names             map[string]string // declaration location of an anonymous member record -> its V name
	expression_temp_id                 int
	declared_local_vars                datatypes.Set[string] // track declared local vars in current function
	declared_local_var_types           map[string]string     // V local name -> V type name in current function/scope
	local_decl_v_names                 map[string]string     // clang declaration id -> collision-free V local name
	for_init_vars                      datatypes.Set[string] // track variables declared in for-init (separate scope)
	current_fn_v_name                  string
	synthesizing_cpp_derived_method    bool // inherited concrete implementation is being cloned onto a derived V receiver
	synthesizing_cpp_default_method    bool // qualified base implementation is being cloned under c2v_default_ on a derived receiver
	static_local_vars                  map[string]string
	address_taken_locals               map[string]bool
	copied_pointer_params              map[string]bool               // parameter ids whose address the body takes
	param_local_copies                 []string                      // statements opening the body that copy such parameters
	copied_params_fn_id                string                        // the function copied_pointer_params belongs to
	conditional_mutable_locals         map[string]bool               // locals assigned inside value-producing ternaries need V `mut`
	declared_methods                   map[string]int                // track declared methods per class to handle overloads
	cpp_function_decl_names            map[string]string             // clang function declaration id -> exact overloaded V function name
	cpp_function_signature_v_names     map[string]string             // stable free C++ function signature -> overloaded V function name
	cpp_method_decl_names              map[string]string             // clang method declaration id -> exact overloaded V method name
	cpp_assignment_operator_records    map[string]CppDeclaringRecord // clang `operator=` declaration id -> its record
	cpp_anonymous_record_typedef_names map[string]string             // anonymous record id -> the typedef naming it
	source_comment_cache               map[string][]SourceComment    // path -> comments of the source file
	real_path_cache                    map[string]string             // source path -> real path
	gc_thread_entry_fns                map[string]bool               // declarations of functions whose address the file takes
	gc_thread_entry_body               bool                        // the function body being emitted registers its thread
	uses_gc_thread_registration        bool                        // some function registers foreign threads with the GC
	cpp_method_redeclarations          map[string][]string         // clang method declaration id -> ids of its later (out-of-line) redeclarations
	cpp_registering_records            map[string]bool             // records whose method names are being registered on demand
	cpp_class_virtual_sigs             map[string]map[string]bool  // class -> signatures of its virtual methods, own and inherited
	cpp_virtual_method_decls           map[string]CppVirtualMethod // clang virtual method declaration id -> declaring class and signature
	cpp_first_embedded_base            map[string]string           // class -> its first embedded base, which shares its address
	cpp_static_member_qualified_names  map[string]string           // `Class::member` -> the V global of a static data member
	cpp_interface_slot_count           int                         // temporaries holding interface values written through `Base *&`
	cpp_helper_names                   map[string]string           // helper prefix and types -> generated helper name
	cpp_destroy_types                  map[string]bool             // records with a complete destructor `c2v_destroy()`
	project_const_v_names              map[string]bool             // V names of the project's enumerators and macros, which locals must not take
	cpp_nested_enums                   map[string]string           // `Class::name` of a class-nested enum -> its distinct C name
	cpp_nested_enum_short_names        map[string]string           // unqualified name -> the only class-nested enum spelled so ('' if several)
	nested_enum_method_scope           string                      // the class of the method being translated, for its nested types
	nested_enum_owner                  string                      // the class whose nested enums are being declared
	cpp_destructor_body_names          map[string]string           // record -> the V method holding its destructor body
	cpp_helper_name_keys               map[string]string           // generated helper name -> its prefix and types
	cpp_dynamic_casts                  map[string]CppVirtualMethod // dynamic cast helper -> source interface and target record
	cpp_record_to_interface_casts      map[string]CppVirtualMethod // conversion helper -> source record and target interface
	cpp_address_to_interface_casts     map[string]string           // conversion helper -> target interface of an erased object address
	cpp_classes_with_destructor_body   map[string]bool             // classes declaring a user-provided destructor
	cpp_interface_deletes              map[string]string           // delete helper -> abstract class (V interface) it deletes
	unused_value_expr_id               string                      // id of the expression statement being emitted (its value is unused)
	variable_size_fields               map[string]bool             // Clang ids of trailing array fields sized for more elements than declared
	cpp_implicit_constructor_keys      map[string]bool             // signature keys of compiler-defined constructors
	cpp_virtual_impls                  map[string]CppVirtualImpl   // `Class|signature` -> the V method implementing it
	cpp_virtual_declarations           map[string]CppVirtualImpl   // `Class|signature` -> the V signature a virtual method is declared with
	cpp_virtual_dispatchers            map[string]CppVirtualMethod // `Class|signature` -> a dispatcher that calls sites use
	cpp_constructor_signature_names    map[string]string           // concrete class/ctor type -> emitted init method
	cpp_constructor_signature_params   map[string][]string         // concrete class/ctor type -> emitted V params
	cpp_nonconst_method_decls          map[string]bool             // clang method declaration ids whose receiver may be mutated
	cpp_primitive_reference_decls      map[string]bool             // C++ primitive reference parameter declaration ids
	cpp_value_reference_params         map[string]bool             // `const T &` parameters of primitive T, passed by value
	enum_value_aliases                 map[string]string           // enum constant => the earlier constant of its enum with the same value
	cpp_nrvo_vars                      map[string]bool             // locals C++ constructs in the return slot (named return value optimization)
	inside_return_stmt                 bool
	cur_receiver_is_ref                bool              // the current method's `this` is a V pointer (`this &T`)
	static_global_arrays               map[string]bool   // V globals holding a constant-initialized fixed array
	namespace_var_ids                  map[string]bool   // namespace-scope variable declarations of the current translation unit
	global_constructor_calls           map[string]string // global C name => the call constructing it (run by the generated `fn init()`)
	global_constructor_order           []string
	deref_reference_call_values        bool     // read the values of reference-returning calls (C variadic arguments)
	continue_labels                    []string // innermost loop last: the label `continue` jumps to, or '' for V's `continue`
	used_continue_labels               map[string]bool
	continue_label_count               int
	cpp_method_signature_v_names       map[string]string     // stable class/signature -> overloaded V method name across project ASTs
	cpp_mut_method_names               map[string]bool       // emitted V method names that require a mutable receiver
	cpp_abstract_types                 map[string]bool       // pure-virtual C++ bases lowered to V interfaces
	cpp_pure_method_bases              map[string]bool       // pure interface methods keyed as "Type.method"
	cpp_method_body_bases              map[string]bool       // C++ methods with an available body, keyed as "Type.method"
	cpp_opaque_record_files            map[string]string     // opaque V record name -> earlier output file containing its empty declaration
	class_method_bases                 map[string]bool       // known method bases from C++ class declarations: "Class.method"
	cpp_class_bases                    map[string][]string   // concrete C++ base classes by translated receiver name
	project_function_surfaces          map[string]string     // cross-file callable surfaces: "fn_name" -> "fn fn_name(args ...voidptr) Ret"
	project_method_surfaces            map[string]string     // cross-file callable surfaces: "Type.method" -> "fn (this Type) method(args ...voidptr) Ret"
	project_dir_method_defs            map[string]bool       // "output_dir|Type.method" definitions found in project sources
	project_emitted_method_defs        map[string]bool       // typed header/interface methods emitted into an output directory
	cpp_field_v_names                  map[string]string     // "Type.c_field" -> collision-free V field name
	c_field_v_names                    map[string]string     // FieldDecl id -> V name of a C field renamed to avoid a collision
	cpp_template_values                map[string]string     // active concrete values for C++ non-type template parameters
	cpp_template_type_aliases          map[string]string     // active nested-type aliases for a concrete C++ template specialization
	local_type_declarations            []string              // function-local record declarations hoisted to V module scope
	cpp_static_member_v_names          map[string]string     // unambiguous C++ static member name -> translated project global
	cpp_ambiguous_static_members       map[string]bool       // static member names owned by more than one class
	cpp_static_member_decl_names       map[string]string     // clang static-member declaration id -> exact translated global
	file_static_global_decl_v_names    map[string]string     // clang file-static declaration id -> translation-unit-qualified global
	current_static_init_owner          string                // class whose static member initializer is being emitted
	cpp_static_method_symbols          map[string]bool       // mangled methods declared static inside C++ class records
	can_output_comment                 map[int]bool          // to avoid duplicate output comment
	seen_comments                      map[string]bool       // to avoid repeated comments across AST segments
	cnt                                int                   // global unique id counter
	files                              []string              // all files' names used in current file, include header files' names
	file_indexes                       map[string]int        // index of each path in `files`
	used_fn                            datatypes.Set[string] // used fn in current .c file
	used_global                        datatypes.Set[string] // used global in current .c file
	seen_ids                           map[string]&Node
	callback_seen_ids                  map[string]&Node             // recursive declaration index used only for member callbacks
	typedef_names_by_tag_id            map[string]string            // first named typedef owning each tag declaration (see index_seen_declarations)
	pointer_typedef_tag_ids            map[string]bool              // tag declarations owned by pointer typedefs
	record_decls_by_name               map[string][]string          // record declaration ids by name
	arithmetic_typedef_c_types         map[string]string            // V alias name -> C spelling of an arithmetic typedef's type
	cpp_record_static_methods          map[string]bool              // mangled names of static methods of the file's top-level classes
	generated_declarations             map[string]bool              // prevent duplicate generations
	emitted_cpp_members                map[string]bool              // cross-file dedup for emitted C++ member definitions
	emitted_top_level_fns              map[string]bool              // cross-file dedup for top-level C/C++ function emissions
	emitted_top_level_name_counts      map[string]int               // overload suffixes for top-level function names in dir mode
	external_types                     map[string]bool              // external C types that need declarations
	system                             SystemSurface                // declarations read from system headers
	function_type_aliases              map[string]bool              // aliases of C function types (not function pointers)
	cpp_template_param_names           map[string]bool              // names of template type parameters in the project
	cpp_receiver_cast_id               string                       // explicit cast node that is the current method call receiver
	cpp_record_nested_type_aliases     map[string]map[string]string // specialization => nested typedef V name => its concrete V name
	known_types                        map[string]bool              // all type names that will be defined in this translation unit (pre-scanned)
	project_known_types                map[string]bool              // all type names discovered across the whole dir translation
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
	// Skip trailing whitespace/newlines to find the closing delimiter. The
	// output is only inspected from its end: copying it for every `else` made
	// translating large files quadratic.
	mut end := c.out.len
	for end > 0 && c.out[end - 1] in [` `, `\t`, `\n`, `\r`] {
		end--
	}
	if end > 0 && (c.out[end - 1] in [`}`, `]`] || (end > 1 && c.out[end - 2] == `]`
		&& c.out[end - 1] == `!`)) {
		c.out.go_back(c.out.len - end)
		c.out.write_string(' ')
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
	return v_name in c.tree_global_v_names
}

// collect_tree_global_v_names records the V names the variables declared at
// file scope in the current translation unit can take.
fn (mut c C2V) collect_tree_global_v_names() {
	c.tree_global_v_names = map[string]bool{}
	for node in c.tree.inner {
		if node.kind_str != 'VarDecl' && !node.kindof(.var_decl) {
			continue
		}
		mut global_name := node.name
		class_name := extract_class_from_mangled(node.mangled_name)
		if class_name != '' {
			global_name = class_name + '_' + global_name
		}
		c.tree_global_v_names[c_identifier_to_v_name(global_name)] = true
		c.tree_global_v_names[filter_name(global_name.uncapitalize(), true)] = true
		c.tree_global_v_names[filter_name(c_identifier_to_v_name(global_name), true)] = true
	}
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
	first_registration := c_name !in c.fns
	mut v_name := c.add_var_func_name(mut c.fns, c_name)
	if first_registration {
		c.fn_name_files[c_name] = c.cur_file
	}
	if first_registration && !c.is_cpp && c.is_dir && v_name in c.local_v_names_seen {
		// A local of an earlier translation unit has this name: in a flattened
		// module, calling that local (a function pointer) would be ambiguous.
		mut candidate := v_name + '_fn'
		mut i := 2
		for map_has_value(c.fns, candidate) || (candidate in c.local_v_names_seen) {
			candidate = v_name + '_fn${i}'
			i++
		}
		c.fns[c_name] = candidate
		v_name = candidate
	}
	// (In a C project the global yields instead: its name is chosen once all
	// translation units are known, see defined_global_ref_replacements.)
	if (c.is_cpp || !c.is_dir) && c.global_uses_v_name(v_name) {
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
	// Check for conflict with V built-in type names (e.g., Option, Result).
	// V reserves single capital letters for generic type parameters.
	if v_string in v_builtin_type_names || v_string.len == 1 {
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
		close_paren := matching_paren_index(type_name, 'fn '.len)
		if close_paren < 0 {
			return type_name
		}
		args_part := type_name['fn ('.len..close_paren]
		ret_part := type_name[close_paren + 1..].trim_space()

		// Process each argument type (nested function types have commas too)
		mut new_args := []string{}
		mut arg_start := 0
		mut depth := 0
		for i := 0; i <= args_part.len; i++ {
			if i < args_part.len && args_part[i] == `(` {
				depth++
			} else if i < args_part.len && args_part[i] == `)` {
				depth--
			} else if i == args_part.len || (args_part[i] == `,` && depth == 0) {
				arg := args_part[arg_start..i].trim_space()
				if arg != '' {
					new_args << c.prefix_external_type(arg)
				}
				arg_start = i + 1
			}
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
	// If it starts with 'C.' already, or is one of c2v's own types, return unchanged
	if base.starts_with('C.') || base == 'C2vVaList' || base.starts_with('C2vFn_')
		|| base == 'C2vU128' {
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
		return prefix + 'i32'
	}
	return type_name
}

fn (mut c C2V) save() {
	vprintln('\n\n')
	if !c.is_dir {
		// Directory translation writes global constructors to 0_globals.v.
		c.out.write_string(c.global_constructors_source(map[string]string{}))
		c.out.write_string(c.cpp_virtual_dispatchers_source())
		c.out.write_string(c.cpp_dynamic_cast_helpers_source())
	}
	mut s := c.out.str()
	if !c.is_cpp && s.contains('C2vU128') {
		// (A declaration can mention the type without any 128-bit operation.)
		c.ensure_int128_helpers()
	}
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
	// Declare the common C functions that the code calls without a prototype
	// (a prototype from a header is translated where it appears: in this file,
	// or in the globals file of a project).
	mut c_fn_decls := strings.new_builder(100)
	used_c_names := used_c_symbols(s)
	mut undeclared_c_fns := []string{}
	for name, decl in c_fallback_fn_decls {
		if name in used_c_names && !s.contains('fn C.${name}(') && name !in c.extern_fns {
			undeclared_c_fns << decl
		}
	}
	if undeclared_c_fns.len > 0 {
		c_fn_decls.write_string('\n// Common C function declarations\n')
		for decl in undeclared_c_fns {
			c_fn_decls.write_string(decl + '\n')
		}
		c_fn_decls.write_string('\n')
	}
	mut preamble_insert := ''
	preamble_insert += c_fn_decls.str()
	if !c.is_dir && c.external_c_fn_declarations.len > 0 {
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
	if !c.is_dir {
		// The function declarations above can be the only users of a record.
		preamble_insert += c.external_surface_declarations(preamble_insert + s, c.project_additional_flags)
	}
	if !c.is_dir && s.contains('c2v_builtin_trap()') {
		preamble_insert += "fn c2v_builtin_trap() { panic('C __builtin_trap') }\n\n"
	}
	if !c.is_dir && (s.contains('c2v_builtin_bswap16(') || s.contains('c2v_builtin_bswap32(')) {
		mut bswap_helpers := strings.new_builder(320)
		write_c2v_bswap_helpers(mut bswap_helpers)
		preamble_insert += bswap_helpers.str()
	}
	threads_key := 'gc_threads:${os.dir(c.outv)}'
	if s.contains('c2v_gc_register_thread()') && !c.threads_support_in_globals()
		&& threads_key !in c.generated_declarations {
		c.generated_declarations[threads_key] = true
		preamble_insert += c2v_threads_source() + '\n'
	}
	alloca_helpers_key := 'alloca_helpers:${os.dir(c.outv)}'
	if s.contains('c2v_alloca(') && !c.va_list_helpers_in_globals()
		&& alloca_helpers_key !in c.generated_declarations {
		c.generated_declarations[alloca_helpers_key] = true
		preamble_insert += c2v_alloca_source() + '\n'
	}
	va_list_helpers_key := 'cpp_va_list_helpers:${os.dir(c.outv)}'
	if c.is_cpp && (s.contains('C2vVaList') || s.contains('c2v_va_'))
		&& !c.va_list_helpers_in_globals() && va_list_helpers_key !in c.generated_declarations {
		c.generated_declarations[va_list_helpers_key] = true
		preamble_insert += c2v_va_list_source() + '\n'
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
	// Aliases can name other aliases (`fn (voidptr) C2vFn_...`): repeat until
	// every alias is declared.
	mut alias_scan := preamble_insert + s
	for {
		mut added := ''
		for alias in returned_fn_type_aliases(alias_scan) {
			alias_key := 'returned_fn_alias:${alias}:' + (if c.is_dir {
				c.project_output_root
			} else {
				os.dir(c.outv)
			})
			if alias_key !in c.generated_declarations {
				c.generated_declarations[alias_key] = true
				added += alias + '\n\n'
			}
		}
		if added == '' {
			break
		}
		preamble_insert += added
		alias_scan = added
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
		s = add_alloca_scopes(s)
		s = parenthesize_c_global_call_addresses(s)
		s = parenthesize_c_global_loop_operands(s)
		s = wrap_returned_receivers(s)
	}
	if s.contains('FILE') {
		c.has_cfile = true
	}
	if c.split_files {
		c.out_file.close()
		os.rm(c.outv) or {}
		c.write_split_files(s)
		return
	}
	if c.skip_comments && !c.is_dir {
		// (Project outputs are rewritten once all files are translated.)
		s = strip_v_comments(s)
	}
	if c.project_module_name != 'main' && !c.is_dir && !c.is_wrapper {
		s = make_declarations_public(alias_c_functions({
			'': s
		})[''])
	}
	c.out_file.write_string(s) or { panic('failed to write to the .v file: ${err}') }
	c.out_file.close()
	if !c.is_wrapper && !c.outv.contains('st_lib.v') && !c.skeleton_mode {
		c.format_output_file(c.outv)
	}
}

fn (mut c C2V) format_output_file(path string) {
	mut fmt_result := -1
	max_attempts := if c.project_require_no_stubs { 5 } else { 1 }
	for attempt in 0 .. max_attempts {
		fmt_result = os.system('v fmt -translated -w ${os.quoted_path(path)} > /dev/null')
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
		c.verror('v fmt rejected strict translation output ${path}')
	}
}

fn (mut c2v C2V) record_top_level_node_files(group Node) {
	if !c2v.split_files {
		return
	}
	for node in group.inner {
		if node.id != '' {
			c2v.top_level_node_files[node.id] = group.location.file
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
		idx := out.index_after('().', start_search) or { break }
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

// c_fallback_fn_decls declares C library functions that translated code can
// call without a prototype in the translated source.
const c_fallback_fn_decls = {
	'getenv':           'fn C.getenv(&char) &char'
	'strtoul':          'fn C.strtoul(&i8, &&i8, i32) u64'
	'strtol':           'fn C.strtol(&i8, &&i8, i32) i64'
	'strcpy':           'fn C.strcpy(&i8, &i8) &i8'
	'strcat':           'fn C.strcat(&i8, &i8) &i8'
	'tmpfile':          'fn C.tmpfile() &C.FILE'
	'fgets':            'fn C.fgets(&i8, i32, &C.FILE) &i8'
	'strncpy':          'fn C.strncpy(&i8, &i8, usize) &i8'
	'__error':          'fn C.__error() &i32'
	'qsort':            'fn C.qsort(voidptr, usize, usize, fn (voidptr, voidptr) i32)'
	'__builtin_expect': 'fn C.__builtin_expect(i64, i64) i64'
	'__assert_rtn':     'fn C.__assert_rtn(&i8, &i8, i32, &i8)'
	'fabs':             'fn C.fabs(f64) f64'
	'fabsf':            'fn C.fabsf(f32) f32'
	'strlen':           'fn C.strlen(&i8) usize'
	'strstr':           'fn C.strstr(&i8, &i8) &i8'
	'__ctype_b_loc':    'fn C.__ctype_b_loc() &&u16'
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
		start := out.index_after(marker, search_from) or { break }
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
		start := out.index_after(marker, search_from) or { break }
		expr_start := start + marker.len
		// (The block may contain blocks of its own.)
		close_idx := find_matching_unsafe_block_close(out, start + 2)
		if close_idx < 0 {
			break
		}
		out = out[..start] + '= *' + out[expr_start..close_idx].trim_right(' ') +
			out[close_idx + 1..]
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
		start := out.index_after(marker, search_from) or { break }
		expr_start := start + marker.len
		close_idx := find_matching_unsafe_block_close(out, start)
		if close_idx < 0 {
			break
		}
		out = out[..start] + '*' + out[expr_start..close_idx].trim_right(' ') + out[close_idx + 1..]
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
			outer_start := out.index_after(marker, outer_search_from) or { break }
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
		if ch == `'` || ch == `"` || ch == `\`` {
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
			if source_has_text_at(condition, i, ' && ') {
				op = '&&'
			} else if source_has_text_at(condition, i, ' || ') {
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
		method_idx := expr.index_after(method_prefix, search_from) or { break }
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
	// (`*(x).f()` dereferences `(x).f()`, like `*x.f()`; `*(...)` as a whole is
	// handled below.)
	if trimmed.starts_with('*') && trimmed.ends_with(')') && (!trimmed.starts_with('*(')
		|| find_matching_paren_index(trimmed, 1) != trimmed.len - 1) {
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
		if marker_idx > best_marker_idx && should_sanitize_mut_receiver_expr(receiver)
			&& !is_conditionally_evaluated(trimmed[..marker_idx - receiver.len]) {
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
		if marker_idx > best_marker_idx && should_sanitize_mut_receiver_expr(receiver)
			&& !is_conditionally_evaluated(condition[..marker_idx - receiver.len]) {
			best_marker_idx = marker_idx
			best_receiver = receiver
			best_tail = condition[marker_idx..]
		}
	}
	return best_receiver, best_tail, best_marker_idx >= 0
}

// wrap_conditional_mut_receiver_calls rewrites a call of a mutating method on a
// receiver V cannot mutate in place (such as a call result) when the call only
// runs conditionally (after `&&` or `||`). V needs that receiver in a variable;
// it is bound inside an `if` expression, so the call keeps its place in the
// evaluation order. (The unreachable `else` branch repeats the call to give the
// expression its type.)
fn wrap_conditional_mut_receiver_calls(text string, method_names []string, mut next_id &int) string {
	mut result := text
	// Each rewrite shifts the text: rescan from the start until nothing changes.
	for _ in 0 .. 64 {
		rewritten := wrap_first_conditional_mut_receiver_call(result, method_names, mut next_id)
		if rewritten == result {
			break
		}
		result = rewritten
	}
	return result
}

fn wrap_first_conditional_mut_receiver_call(text string, method_names []string, mut next_id &int) string {
	for method_name in method_names {
		marker := '.' + method_name + '('
		mut search_from := 0
		for {
			marker_idx := text.index_after(marker, search_from) or { break }
			search_from = marker_idx + marker.len
			// (Bindings inserted by earlier rewrites end in a newline.)
			line_start := (text[..marker_idx].last_index('\n') or { -1 }) + 1
			receiver := trailing_mut_receiver_expr(text[line_start..marker_idx])
			if receiver == '' || !text[..marker_idx].ends_with(receiver)
				|| !should_sanitize_mut_receiver_expr(receiver)
				|| !is_conditionally_evaluated(text[..marker_idx - receiver.len]) {
				continue
			}
			close_idx := find_matching_paren_index(text, marker_idx + marker.len - 1)
			if close_idx < 0 {
				continue
			}
			call := text[marker_idx..close_idx + 1]
			tmp := '__c2v_mut_recv_cond_${next_id}'
			next_id++
			start_idx := marker_idx - receiver.len
			bound_receiver := strip_balanced_outer_parentheses(receiver)
			branch_open := enclosing_if_expression_branch(text[..start_idx])
			if branch_open >= 0 {
				// Inside a branch of an `if` expression (a C `?:`), which V cannot
				// nest another statement-carrying `if` expression in: bind the
				// receiver at the start of that branch, which runs only when taken.
				return text[..branch_open + 1] + '\nmut ' + tmp + ' := ' + mut_receiver_binding(bound_receiver) + '\n' + text[branch_open + 1..start_idx] + tmp + text[marker_idx..]
			}
			bound := 'mut ' + tmp + ' := ' + mut_receiver_binding(bound_receiver) + '\n' + tmp + call
			return text[..start_idx] + '(if true {\n' + bound + '\n} else {\n' + bound + '\n})' + text[close_idx + 1..]
		}
	}
	return text
}

// mut_receiver_binding is the initializer of the variable binding a hoisted
// receiver of a mutating call. A field or an element is a value: the variable
// holds its address (V calls methods through it like on the object itself),
// or the call would change a copy. A call result is bound as it is.
fn mut_receiver_binding(receiver string) string {
	trimmed := receiver.trim_space()
	if trimmed == '' {
		return receiver
	}
	last := trimmed[trimmed.len - 1]
	if last == `]` || last.is_alnum() || last == `_` {
		return collapse_nested_unsafe_blocks('unsafe { &' + trimmed + ' }')
	}
	return receiver
}

// materialize_receiver_chain binds, in variables written before the statement,
// the receivers of mutating calls inside a receiver being bound itself
// (`a.b().c()` where both `b` and `c` change their object), innermost first.
fn materialize_receiver_chain(receiver string, method_names []string, indent string, mut out strings.Builder, mut next_id &int) string {
	mut text := receiver
	for {
		inner_receiver, inner_tail, found := split_mut_receiver_call_expr(text, method_names)
		if !found {
			break
		}
		inner_tmp := '__c2v_mut_recv_chain_${next_id}'
		next_id++
		bound := materialize_receiver_chain(strip_balanced_outer_parentheses(inner_receiver), method_names, indent, mut out, mut next_id)
		out.writeln(indent + 'mut ' + inner_tmp + ' := ' + mut_receiver_binding(bound))
		text = text.replace(inner_receiver + inner_tail, inner_tmp + inner_tail)
	}
	return text
}

// enclosing_if_expression_branch returns the index of the `{` opening the branch
// of an inline `if` expression that the end of `prefix` lies in, when nothing in
// that branch before it is itself conditional; -1 otherwise.
fn enclosing_if_expression_branch(prefix string) int {
	mut depth := 0
	mut i := prefix.len - 1
	for i >= 0 {
		ch := prefix[i]
		if ch in [`)`, `]`, `}`] {
			depth++
		} else if ch in [`(`, `[`, `{`] {
			if depth == 0 && ch != `{` {
				// The call is an argument or operand inside the branch.
				i--
				continue
			}
			if depth == 0 {
				if i == 0 || prefix[i - 1] != ` ` {
					return -1
				}
				before := prefix[..i].trim_right(' ')
				branch := prefix[i + 1..]
				is_branch := !before.ends_with('unsafe')
					&& (before.ends_with('else') || before.contains('if '))
				if !is_branch || branch.contains('&&') || branch.contains('||') || branch.contains('if ') {
					return -1
				}
				return i
			}
			depth--
		}
		i--
	}
	return -1
}

// is_conditionally_evaluated reports whether the code following `prefix` in an
// expression only runs depending on a condition: after `&&` or `||`, or inside
// an `if` expression. Hoisting it into a statement before the expression would
// evaluate it unconditionally (e.g. dereference the pointer the condition
// checks for nil).
fn is_conditionally_evaluated(prefix string) bool {
	// Scan back from the end of `prefix`, skipping closed groups: an `&&`/`||`
	// at this nesting level or an enclosing one, or an enclosing branch block
	// of an inline `if` expression, makes the code after `prefix` conditional.
	mut depth := 0
	mut i := prefix.len - 1
	for i >= 0 {
		ch := prefix[i]
		if ch in [`)`, `]`, `}`] {
			depth++
		} else if ch in [`(`, `[`, `{`] {
			if depth > 0 {
				depth--
			} else if ch == `{` {
				before := prefix[..i].trim_right(' ')
				return i > 0 && prefix[i - 1] == ` ` && !before.ends_with('unsafe')
					&& (before.ends_with('else') || before.contains('if '))
			}
		} else if depth == 0 && i > 0 && ((ch == `&` && prefix[i - 1] == `&`)
			|| (ch == `|` && prefix[i - 1] == `|`)) {
			return true
		}
		i--
	}
	return false
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
		start := out.index_after(marker, search_from) or { break }
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
	mut source_lines := s.split_into_lines()
	mut conditional_receiver_id := 0
	for i, source_line in source_lines {
		source_lines[i] = wrap_conditional_mut_receiver_calls(source_line, mutable_method_names, mut conditional_receiver_id)
	}
	mut source_line_idx := 0
	for source_line_idx < source_lines.len {
		mut raw_line := source_lines[source_line_idx]
		source_line_idx++
		if raw_line.starts_with('#') {
			// `#flag`/`#include` directives are C text.
			out.writeln(raw_line)
			continue
		}
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
			// Evaluate the terms in variables, in order and only as far as C's
			// short-circuit evaluation does: V's `&&` binds tighter than `||`, so
			// each `&&` group runs only while no earlier group was true, and each of
			// its terms only while the group can still be true.
			indent := leading_whitespace(line)
			result_name := '__c2v_condition_${sanitized_condition_id}'
			sanitized_condition_id++
			out.writeln(indent + 'mut ' + result_name + ' := false')
			mut group_start := 0
			for group_start < condition_terms.len {
				mut group_end := group_start
				for group_end < condition_operators.len && condition_operators[group_end] == '&&' {
					group_end++
				}
				group_indent := if group_start == 0 { indent } else { indent + '\t' }
				if group_start > 0 {
					out.writeln(indent + 'if !' + result_name + ' {')
				}
				group_name := '__c2v_condition_${sanitized_condition_id}'
				sanitized_condition_id++
				out.writeln(group_indent + 'mut ' + group_name + ' := false')
				for term_i in group_start .. group_end + 1 {
					term_indent := if term_i > group_start {
						group_indent + '\t'
					} else {
						group_indent
					}
					if term_i > group_start {
						out.writeln(group_indent + 'if ' + group_name + ' {')
					}
					mut rewritten_term := condition_terms[term_i]
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
						out.writeln(term_indent + 'mut ' + tmp_name + ' := ' + if has_base_receiver
							&& !materialize_full_receiver {
							materialized_receiver
						} else {
							mut_receiver_binding(materialized_receiver)
						})
						rewritten_term = rewritten_term.replace(receiver_expr + call_tail, replacement_receiver + call_tail)
						sanitized_lhs_assign_id++
					}
					out.writeln(term_indent + group_name + ' = ' + rewritten_term)
					if term_i > group_start {
						out.writeln(group_indent + '}')
					}
				}
				out.writeln(group_indent + result_name + ' = ' + group_name)
				if group_start > 0 {
					out.writeln(indent + '}')
				}
				group_start = group_end + 1
			}
			out.writeln(indent + 'if ' + result_name + ' {')
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
			bound_receiver := materialize_receiver_chain(materialized_receiver, mutable_method_names, indent, mut out, mut sanitized_lhs_assign_id)
			out.writeln(indent + 'mut ' + tmp_name + ' := ' + if has_base_receiver
				&& !materialize_full_receiver {
				// (The base of a dereference or of an index call is an address.)
				bound_receiver
			} else {
				mut_receiver_binding(bound_receiver)
			})
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
			bound_receiver := materialize_receiver_chain(materialized_receiver, mutable_method_names, indent, mut out, mut sanitized_lhs_assign_id)
			out.writeln(indent + 'mut ' + tmp_name + ' := ' + if has_base_receiver
				&& !materialize_full_receiver {
				// (The base of a dereference or of an index call is an address.)
				bound_receiver
			} else {
				mut_receiver_binding(bound_receiver)
			})
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
		if trimmed.contains(':=') && !trimmed.ends_with('++') && !trimmed.ends_with('--')
			&& (trimmed.ends_with('+') || trimmed.ends_with('-')
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
		is_wrapper:     args.len > 1 && args[1] == 'wrapper'
		single_fn_def:  args.len > 1 && args[1] == 'fndef'
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

	// Decoding a large AST (hundreds of MB of JSON for an amalgamated C file) only
	// allocates: collecting in between cannot free anything and makes Boehm
	// abort once its heap sections are fragmented. Grow the heap instead.
	gc_disable()
	ast_txt := os.read_file(ast_path) or {
		gc_enable()
		vprintln('failed to read ast file "${ast_path}": ${err}')
		return err
	}
	mut all_nodes := json2.decode[Node](ast_txt) or {
		gc_enable()
		vprintln('failed to decode ast file "${ast_path}": ${err}')
		return err
	}
	gc_enable()
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
	if c2v.split_files {
		c2v.split_main_file = main_file_for_grouping
		c2v.line_directives = scan_line_directives(c2v.source_text, main_file_for_grouping)
	}
	mut header_node := Node{}
	mut curr_file := ''
	mut keep_file := false
	for mut node in all_nodes.inner {
		if node.kind_str == 'FunctionDecl' && node.is_implicit && node.name.starts_with('__') {
			c2v.compiler_builtin_decls[node.name] = node
		}
		mut node_file := if c2v.is_cpp { resolve_node_file_path(&node) } else { node.location.file }
		if c2v.is_cpp && node_file == '' && (is_cpp_body_decl_node_by_kind_str(node)
			|| is_cpp_body_container_node_by_kind_str(node)) {
			node_file = main_file_for_grouping
			node.location.file = node_file
		}
		if node_file != '' {
			if is_synthetic_source_path(node_file) {
				curr_file = node_file
			} else {
				curr_file = c2v.cached_real_path(node_file)
			}
			vprintln('==> node_id = ${node.id} curr_file=${curr_file}')
			keep_file = !line_is_builtin_header(curr_file)
		}
		if node_file != '' && keep_file {
			if header_node.inner.len > 0 && header_node.location.file != '' {
				vprintln('=====>processing header file ${header_node.location.file} node number=${header_node.inner.len}')
				c2v.parse_comment(mut header_node, header_node.location.file)
				c2v.record_top_level_node_files(header_node)
				c2v.tree.inner << header_node.inner
			}
			header_node = Node{
				location: NodeLocation{
					file: curr_file
					// source_file : SourceFile {
					//	path : c_file
					// }
				}
				range:    Range{
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
		c2v.record_top_level_node_files(header_node)
		c2v.tree.inner << header_node.inner
	}

	mut main_c_file := os.real_path(c_file)
	if main_c_file == '' {
		main_c_file = c_file
	}
	if !c2v.is_dir {
		c2v.append_trailing_comments(main_c_file)
	}
	c2v.cnt = 0
	c2v.files.clear()
	c2v.files << main_c_file
	c2v.file_indexes = {}
	c2v.cur_file = main_c_file
	// Declarations from system headers are used through V's C interop, with the
	// types, record layouts and signatures Clang parsed (see external.v).
	c2v.collect_system_surface(&all_nodes)
	if c2v.is_cpp {
		c2v.prune_nested_system_decls(mut c2v.tree.inner)
	}
	c2v.set_file_index(mut c2v.tree)
	c2v.variable_size_fields.clear()
	collect_variable_size_fields(c2v.tree.inner, mut c2v.variable_size_fields)
	c2v.gc_thread_entry_fns = map[string]bool{}
	for top in c2v.tree.inner {
		collect_address_taken_functions(&top, mut c2v.gc_thread_entry_fns)
	}
	c2v.collect_defined_function_names()
	c2v.collect_tree_global_v_names()
	if !c2v.is_cpp && !c2v.is_wrapper {
		// Give every function its V name in declaration order, before any call
		// refers to it: C names that snake_case alike (`sqlite3Close` and
		// `sqlite3_close`) get distinct V names.
		mut file_static_fns := map[string]bool{}
		for node in c2v.tree.inner {
			if node.kind_str == 'FunctionDecl' && node.class_modifier == 'static' {
				file_static_fns[node.name] = true
			}
		}
		c2v.file_static_fn_names = file_static_fns.clone()
		for node in c2v.tree.inner {
			if node.kind_str != 'FunctionDecl' || node.name == '' || node.is_implicit
				|| node.name.starts_with('__builtin_') {
				continue
			}
			if node.name !in c2v.fns {
				c2v.add_fn_name(node.name)
				if node.name in file_static_fns {
					c2v.static_fn_owners[node.name] = main_c_file
				}
			} else if c2v.is_dir && node.name !in file_static_fns {
				owner := c2v.static_fn_owners[node.name] or { '' }
				if owner != '' && owner != main_c_file {
					// An external function named like a static function of an
					// earlier file: that file keeps the V name for its own function.
					static_v_name := c2v.fns[node.name]
					c2v.fns['static:${owner}:${node.name}'] = static_v_name
					c2v.fns.delete(node.name)
					c2v.static_fn_owners.delete(node.name)
					c2v.add_fn_name(node.name)
				}
			}
		}
	}
	c2v.mutated_variable_ids = map[string]bool{}
	for top in c2v.tree.inner {
		collect_mutated_variables(&top, mut c2v.mutated_variable_ids)
	}
	c2v.namespace_var_ids = map[string]bool{}
	collect_namespace_var_ids(c2v.tree.inner, mut c2v.namespace_var_ids)
	c2v.used_fn.clear()
	c2v.cur_file = main_c_file
	c2v.get_used_fn(c2v.tree)
	if c2v.is_dir && c2v.is_cpp && c2v.project_require_no_stubs {
		c2v.collect_cpp_class_hierarchy_from_node(&all_nodes)
		c2v.collect_cpp_abstract_types_from_node(&all_nodes)
	}
	if (c2v.is_cpp || !c2v.is_wrapper) && (!c2v.is_dir || c2v.project_require_no_stubs) {
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
	c2v.cpp_assignment_operator_records.clear()
	c2v.cpp_method_redeclarations.clear()
	c2v.cpp_virtual_method_decls.clear()
	c2v.cpp_nonconst_method_decls.clear()
	c2v.cpp_primitive_reference_decls.clear()
	c2v.cpp_value_reference_params.clear()
	c2v.cpp_nrvo_vars.clear()
	c2v.file_static_global_decl_v_names.clear()
	if c2v.is_dir && !c2v.is_cpp && !c2v.is_wrapper {
		c2v.name_file_static_functions(main_c_file)
	}
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
			c2v.genln('module ${c2v.project_module_name}\n')
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
	c2v.typedef_names_by_tag_id = {}
	c2v.pointer_typedef_tag_ids = {}
	c2v.record_decls_by_name = {}
	c2v.cpp_record_static_methods = {}
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
		'__builtin_expect', '__builtin_expect_with_probability' {
			// A branch prediction hint: the value is the first argument.
			if args.len < 1 {
				return false
			}
			c.gen('(')
			c.expr(args[0])
			c.gen(')')
			return true
		}
		'__builtin_add_overflow', '__builtin_sub_overflow', '__builtin_mul_overflow' {
			if args.len != 3 {
				return false
			}
			result_type := c.convert_type(node_effective_type_name(args[2])).name
			if !result_type.starts_with('&') {
				return false
			}
			typ := c.resolve_type_alias(result_type[1..])
			if typ !in v_integer_type_names {
				return false
			}
			for operand in args[..2] {
				operand_type := c.convert_type(node_effective_type_name(operand)).name
				// (An integer literal keeps its value in the result type.)
				if c.resolve_type_alias(operand_type) != typ && !is_integer_literal_value(operand) {
					c.verror('${name} with operands of another type (${c.resolve_type_alias(operand_type)}) than the result (${typ}) is not supported: ${c.cur_file}')
				}
			}
			op := name['__builtin_'.len..].all_before('_')
			c.ensure_overflow_helper(op, typ)
			c.gen('c2v_${op}_overflow_${typ}(${typ}(')
			c.expr(args[0])
			c.gen('), ${typ}(')
			c.expr(args[1])
			c.gen('), &${typ}(voidptr(')
			c.expr(args[2])
			c.gen(')))')
			return true
		}
		'__builtin_isinf', '__builtin_isnan', '__builtin_isfinite' {
			if args.len != 1 {
				return false
			}
			c.ensure_float_class_helpers()
			c.gen('c2v_${name['__builtin_'.len..]}(f64(')
			c.expr(args[0])
			c.gen('))')
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

fn is_integer_literal_value(node Node) bool {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr)
		|| (current.kindof(.unary_operator) && current.opcode in ['-', '+'])) {
		current = current.inner[0]
	}
	return current.kindof(.integer_literal)
}

// overflow_helper_source returns `c2v_<op>_overflow_<t>`: integer arithmetic
// with overflow detection (`__builtin_add_overflow`, ...) for the V integer
// type `t`. The result wraps (V builds C with -fwrapv), and the helper reports
// whether the exact result did not fit. (One function per type: in a generic
// one, V divides with the operation of another instantiation's type.)
fn overflow_helper_source(op string, t string) string {
	signed := t.starts_with('i') // i8 .. i64, int, isize
	mut body := ''
	match op {
		'add' {
			body = if signed {
				'return (a >= 0) == (b >= 0) && (r >= 0) != (a >= 0)'
			} else {
				'return r < a'
			}
		}
		'sub' {
			body = if signed {
				'return (a >= 0) != (b >= 0) && (r >= 0) != (a >= 0)'
			} else {
				'return b > a'
			}
		}
		else {
			body = 'if a == 0 || b == 0 {\n\t\treturn false\n\t}\n\t'
			if signed {
				body += 'if a == -1 {\n\t\treturn b == -b\n\t}\n\tif b == -1 {\n\t\treturn a == -a\n\t}\n\t'
			}
			body += 'return r / b != a'
		}
	}
	operator := match op {
		'add' { '+' }
		'sub' { '-' }
		else { '*' }
	}
	return 'fn c2v_${op}_overflow_${t}(a ${t}, b ${t}, res &${t}) bool {\n\tr := a ${operator} b\n\tunsafe {\n\t\t*res = r\n\t}\n\t${body}\n}\n\n'
}

const float_class_helpers_source = 'fn c2v_isinf(x f64) int {
	return if x != 0 && x * 2 == x { 1 } else { 0 }
}

fn c2v_isnan(x f64) int {
	return if x != x { 1 } else { 0 }
}

fn c2v_isfinite(x f64) int {
	return if x - x == 0 { 1 } else { 0 }
}

'

fn (mut c C2V) ensure_overflow_helper(op string, t string) {
	key := 'overflow_helper:${op}:${t}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << overflow_helper_source(op, t)
	}
}

fn (mut c C2V) ensure_float_class_helpers() {
	key := 'float_class_helpers:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << float_class_helpers_source
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
				&& op_token in ['=', '+=', '-=', '*=', '/=', '%=', '==', '!=', '<', '>', '<=',
					'>=', '+', '-', '*', '/', '%', '&', '|', '^', '&&', '||', '<<', '>>', '<<=',
					'>>=', ','] {
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
	if !c.is_cpp && c.gen_variadic_pointer_call(expr, node) {
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
	if !c.is_cpp && !emitted_recovery_callee {
		if loaded := loaded_function_pointer_callee(expr) {
			// `(*slot)(args)` with `slot` a pointer to a function pointer: c2v
			// carries such a pointer as `&voidptr`, so the loaded value is cast back
			// to the function type before the call.
			fn_type := c.resolve_type_alias(c.convert_type(loaded.ast_type.qualified).name)
			if fn_type.starts_with('fn ') {
				helper_name := c.function_pointer_cast_helper_name(fn_type)
				c.gen('${c.fn_pointer_call_helper(helper_name)}(voidptr(')
				c.expr(loaded)
				c.gen('))')
				emitted_callee = true
			}
		}
	}
	if !emitted_callee && callee_was_wrapped && (unwrapped.kindof(.decl_ref_expr)
		|| unwrapped.kindof(.member_expr) || unwrapped.kindof(.array_subscript_expr)) {
		c.expr(unwrapped)
		emitted_callee = true
	}
	if !emitted_callee && !emitted_recovery_callee {
		c.emitting_callee = true
		c.expr(expr) // this is `fn_name(`
		c.emitting_callee = false
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
		c.cur_out_line = c.cur_out_line.replace('memset(', 'C.memset(').replace('C.C.memset(', 'C.memset(')
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
	mut callee_text := c.cur_out_line[callee_start..].trim_space()
	for callee_text.starts_with('(') && matching_paren_index(callee_text, 0) == callee_text.len - 1 {
		callee_text = callee_text[1..callee_text.len - 1].trim_space()
	}
	if !c.is_cpp && callee_text.starts_with('C2vFn_') {
		// A cast cannot be called directly (V's C output loses the grouping of
		// `(T(p))(args)`): convert the pointer in a function call instead.
		alias := callee_text.all_before('(')
		c.cur_out_line = c.cur_out_line[..callee_start] + c.fn_pointer_call_helper(alias) + callee_text[alias.len..]
	}
	mut emitted_callee_text := c.cur_out_line[callee_start..].trim_space()
	if emitted_callee_text == 'builtin_alloca' {
		// The calling function releases the storage when it returns (see
		// add_alloca_scopes).
		c.cur_out_line = c.cur_out_line[..callee_start] + 'c2v_alloca'
		emitted_callee_text = 'c2v_alloca'
	}
	if c.is_cpp && emitted_callee_text in ['builtin_va_start', 'builtin_va_end', 'builtin_va_copy']
		&& node.inner.len > 1 {
		// See c2v_va_list_source.
		list := c.render_expr_to_string(c.unwrap_expr_for_deref_check(node.inner[1]))
		c.cur_out_line = c.cur_out_line[..callee_start]
		if emitted_callee_text == 'builtin_va_start' {
			args := if c.declared_local_vars.exists('c2v_variadic_args') {
				'c2v_variadic_args'
			} else {
				'[]voidptr{}'
			}
			c.gen('${list} = c2v_va_start(${args})')
		} else if emitted_callee_text == 'builtin_va_copy' && node.inner.len > 2 {
			source := c.render_expr_to_string(c.unwrap_expr_for_deref_check(node.inner[2]))
			c.gen('${list} = c2v_va_copy(${source})')
		} else {
			c.gen('c2v_va_end(${list})')
		}
		return
	}
	if !c.is_cpp && emitted_callee_text in ['builtin_va_start', 'builtin_va_end', 'builtin_va_copy']
		&& node.inner.len >= 2 {
		// A translated C variadic function is a C variadic function in V's C
		// output, so C's own va_start/va_end/va_copy macros apply.
		c.ensure_c_va_macro_declarations()
		list := c.render_expr_to_string(unwrap_va_list_operand(node.inner[1]))
		c.cur_out_line = c.cur_out_line[..callee_start]
		if emitted_callee_text == 'builtin_va_start' && node.inner.len >= 3 {
			c.gen('C.va_start(${list}, ${c.render_expr_to_string(node.inner[2])})')
		} else if emitted_callee_text == 'builtin_va_copy' && node.inner.len >= 3 {
			source := c.render_expr_to_string(unwrap_va_list_operand(node.inner[2]))
			c.gen('C.va_copy(${list}, ${source})')
		} else {
			c.gen('C.va_end(${list})')
		}
		return
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
	cast_variadic_args_to_voidptr := !is_c_foreign_call
	fixed_param_count := callee_params.filter(it != '...').len
	mut invoked_through_helper := false
	if !c.is_cpp && c.conditional_eval_depth > 0 && emitted_callee_text.starts_with('c2v_fnptr_')
		&& !is_m {
		// V's C backend stores a called function value in a temporary, which
		// it cannot do inside a conditional expression: call a helper instead.
		open := emitted_callee_text.index_u8(`(`)
		if open > 0 && matching_paren_index(emitted_callee_text, open) == emitted_callee_text.len - 1 {
			if helper := c.fn_pointer_invoke_helper(emitted_callee_text['c2v_fnptr_'.len..open]) {
				c.cur_out_line = c.cur_out_line[..callee_start] + helper + emitted_callee_text[open..emitted_callee_text.len - 1]
				invoked_through_helper = true
			}
		}
	}
	if invoked_through_helper {
		if node.inner.len > 1 {
			c.gen(', ')
		}
	} else {
		c.gen('(')
	}
	if emitted_callee_text == 'c2v_alloca' {
		c.gen('mut c2v_alloca_blocks, ')
	}
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
	if c.is_cpp && cast_variadic_args_to_voidptr && is_variadic
		&& node.inner.len - 1 == fixed_param_count {
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
	if !c.is_cpp {
		// In C, a conversion to a function pointer type is a cast to a named
		// alias of the V function type (`C2vFn_<hex>(voidptr(f))`), which also
		// stays a constant expression in static initializers. The alias is
		// declared by returned_fn_type_aliases.
		return returned_fn_type_alias(fn_type)
	}
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

	v_method_name := c.cpp_method_decl_names[target.ref_declaration.id] or {
		method_base_name_from_cpp_name(method_name)
	}
	// One named function per method: C++ compares pointers to the same member
	// function as equal (e.g. idClass::CallSpawnFunc skips an inherited Spawn),
	// which separate anonymous V closures would not be.
	name := c.cpp_helper_name('c2v_member_fn_', '${receiver_type}_${v_method_name}')
	key := 'cpp_member_fn:${name}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		mut f := strings.new_builder(128)
		f.write_string('fn ${name}(mut c2v_this ${receiver_type}')
		for i, param in params {
			param_type := c.prefix_external_type(c.convert_type(param).name)
			f.write_string(', c2v_arg_${i} ${param_type}')
		}
		returns_value := return_type != '' && return_type != 'void'
		f.write_string(if returns_value { ') ${return_type} {\n' } else { ') {\n' })
		// Included headers are intentionally not emitted wholesale. When a callback
		// targets an inline no-op method from one of those headers, preserve its
		// exact semantics instead of calling a method that cannot exist in the
		// generated source.
		if returns_value || !has_referenced_method
			|| !cpp_method_has_empty_body(referenced_method) {
			f.write_string('\t' + (if returns_value { 'return ' } else { '' }) + 'c2v_this.' + v_method_name + '(')
			for i in 0 .. params.len {
				if i > 0 {
					f.write_string(', ')
				}
				f.write_string('c2v_arg_${i}')
			}
			f.write_string(')\n')
		}
		f.write_string('}\n\n')
		c.local_type_declarations << f.str()
	}
	// Member function pointers are stored as `voidptr`.
	c.gen('voidptr(${name})')
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
		// A copy from a V pointer variable (a C++ reference), or from a call
		// returning a reference, is dereferenced by the copy itself.
		if c.is_cpp && cpp_call_expr_returns_reference_value(current.inner[0])
			&& !is_cpp_pointer_slot_call(current.inner[0]) {
			return false
		}
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

// atomic_expr emits a GNU/C11 atomic builtin (`__atomic_load_n(p, order)`) as a
// call to that builtin through a V declaration typed for this use: the builtins
// are type-generic, a V function declaration is not.
fn (mut c C2V) atomic_expr(node &Node) {
	// Clang stores the operands as Ptr, Order, Val1, OrderFail, Val2, Weak; the
	// builtin takes them as Ptr, Val1, Val2, Weak, Order, OrderFail.
	sub := node.inner
	args := match sub.len {
		2 { [sub[0], sub[1]] }
		3 { [sub[0], sub[2], sub[1]] }
		4 { [sub[0], sub[2], sub[3], sub[1]] }
		6 { [sub[0], sub[2], sub[4], sub[5], sub[1], sub[3]] }
		else { []Node{} }
	}
	if node.name == '' || args.len == 0 {
		c.verror('unsupported atomic builtin `${node.name}` with ${sub.len} operands in ${c.cur_file}:${node.location.line}')
		return
	}
	arg_types := args.map(c.convert_type(it.ast_type.qualified).name)
	ret_type := if node.ast_type.qualified == 'void' {
		''
	} else {
		c.convert_type(node.ast_type.qualified).name
	}
	mut signature := node.name.trim_left('_') + '_' + arg_types.join('_') + '_' + ret_type
	signature = signature.bytes().map(if it.is_letter() || it.is_digit() {
		it
	} else {
		`_`
	}).bytestr()
	alias := 'c2v_${signature}'
	helper_key := 'atomic:${alias}:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		ret := if ret_type == '' { '' } else { ' ${ret_type}' }
		c.local_type_declarations << "@[c: '${node.name}']\nfn C.${alias}(${arg_types.join(', ')})${ret}\n\n"
	}
	c.gen('C.${alias}(')
	for i, arg in args {
		if i > 0 {
			c.gen(', ')
		}
		c.expr(arg)
	}
	c.gen(')')
}

// variable_size_element returns [field, index] when `node` indexes a trailing
// variable sized array field (`p->tail[i]`) beyond its declared length.
fn (c &C2V) variable_size_element(node Node) []Node {
	mut current := node
	for (current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr))
		&& current.inner.len == 1 {
		current = current.inner[0]
	}
	if !current.kindof(.array_subscript_expr) || current.inner.len != 2 {
		return []
	}
	mut array := current.inner[0]
	for (array.kindof(.paren_expr) || array.kindof(.implicit_cast_expr)) && array.inner.len == 1 {
		array = array.inner[0]
	}
	if !array.kindof(.member_expr) || array.referenced_member_decl !in c.variable_size_fields || is_constant_index_within(current.inner[1], cpp_fixed_array_length(c.convert_type(array.ast_type.qualified).name)) {
		return []
	}
	return [array, current.inner[1]]
}

fn (mut c C2V) ensure_c2v_at_helper() {
	helper_key := 'c2v_at:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << '@[inline]\nfn c2v_at[T](base &T, index isize) &T {\n\treturn unsafe { base + index }\n}\n\n'
	}
}

// gen_logical_operand emits an operand of `&&`/`||`: C tests a pointer
// operand against null, V needs the explicit test.
fn (mut c C2V) gen_logical_operand(operand Node) {
	if !c.is_cpp {
		operand_type := c.resolve_type_alias(c.convert_type(node_effective_type_name(operand)).name)
		if operand_type.starts_with('&') || operand_type == 'voidptr'
			|| operand_type.starts_with('fn ') {
			c.gen('!isnil(')
			c.expr(operand)
			c.gen(')')
			return
		}
	}
	c.expr(operand)
}

// c_int_operand_needs_cast reports whether an arithmetic operand has C type int
// but a V type other than a number: a comparison (bool), or a character
// literal (rune) next to an `int` operand.
fn (c &C2V) c_int_operand_needs_cast(operand Node, other Node) bool {
	if is_c_truth_value(operand) {
		return true
	}
	if !unwrap_condition_atom(operand).kindof(.character_literal) {
		return false
	}
	return c.resolve_type_alias(c.convert_type(node_effective_type_name(other)).name) in [
		'int',
		'i32',
	]
}

// is_c_truth_value reports whether `node` is a C comparison, logical operator
// or `!`: an `int` in C, but a `bool` in V.
fn is_c_truth_value(node Node) bool {
	current := unwrap_condition_atom(node)
	return (current.kindof(.binary_operator)
		&& current.opcode in ['==', '!=', '<', '>', '<=', '>=', '&&', '||'])
		|| (current.kindof(.unary_operator) && current.opcode == '!')
}

// is_lowered_compiler_builtin reports whether c2v translates calls to a compiler
// builtin itself rather than calling it through C.
fn is_lowered_compiler_builtin(name string) bool {
	return name.starts_with('__builtin___') || name in ['__builtin_alloca', '__builtin_va_start',
		'__builtin_va_end', '__builtin_va_copy', '__builtin_va_arg', '__builtin_expect',
		'__builtin_bswap16', '__builtin_bswap32', '__builtin_trap', '__builtin_constant_p',
		'__builtin_bzero', '__builtin_memcpy', '__builtin_object_size']
}

fn (mut c C2V) declare_compiler_builtin(decl Node) {
	key := 'compiler_builtin:${decl.name}:${os.dir(c.outv)}'
	if key in c.generated_declarations {
		return
	}
	c.generated_declarations[key] = true
	mut params := []string{}
	for child in decl.inner {
		if child.kind_str == 'ParmVarDecl' {
			params << c.convert_type(child.ast_type.qualified).name
		}
	}
	if decl.ast_type.qualified.contains('...') {
		params << '...'
	}
	raw_return := decl.ast_type.qualified.before('(').trim_space()
	ret := if raw_return in ['', 'void'] { '' } else { ' ' + c.convert_type(raw_return).name }
	c.local_type_declarations << 'fn C.${decl.name}(${params.join(', ')})${ret}\n\n'
}

// shift_count_primitive returns the integer type behind a shift count whose V
// type is an alias (`Pgno`), or ''.
fn (c &C2V) shift_count_primitive(count Node) string {
	// The V expression has the typedef'd type as spelled, not the desugared one.
	count_type := c.convert_type(count.ast_type.qualified).name
	resolved := c.resolve_type_alias(count_type)
	return if resolved != count_type && resolved in v_integer_type_names { resolved } else { '' }
}

// c_function_return_type is the return type of the C function type `fn_type`:
// `int (char *)` returns `int`, `void (*(sqlite3_vfs *, char *))(void)` returns
// the function pointer `void (*)(void)`.
fn c_function_return_type(fn_type string) string {
	t := fn_type.trim_space()
	open := t.index_u8(`(`)
	if open < 0 {
		return t
	}
	close := matching_paren_index(t, open)
	if close > open && t[open + 1..close].starts_with('*') && close + 1 < t.len {
		// `R (*(args))(ret_args)`: the declarator group wraps the parameter list.
		inner := t[open + 1..close]
		args_open := inner.index_u8(`(`)
		if args_open > 0 && inner[..args_open].trim_space() == '*'
			&& matching_paren_index(inner, args_open) == inner.len - 1 {
			return t[..open].trim_space() + ' (*)' + t[close + 1..].trim_space()
		}
	}
	return t[..open].trim_space()
}

// c_type_is_top_level_const reports whether a C object of type `t` is itself
// const: `const int`, `const char [4]`, `char *const`, but not `const char *`.
fn c_type_is_top_level_const(t string) bool {
	typ := t.trim_space()
	if typ.ends_with(' const') || typ.ends_with('*const') {
		return true
	}
	return typ.starts_with('const ') && !typ.contains('*') && !typ.contains('(')
}

// external_fn_value_wrapper returns a V function that calls the external C
// function `name`, for use as a function value.
fn (mut c C2V) external_fn_value_wrapper(name string) string {
	wrapper := 'c2v_fn_${name}'
	key := 'fn_value_wrapper:${name}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		signature := c.external_c_fn_signatures[name] or { ExternalCFnSignature{} }
		mut params := []string{}
		mut args := []string{}
		for i, param in signature.params {
			params << 'a${i} ${param}'
			args << 'a${i}'
		}
		ret := if signature.return_type == '' { '' } else { ' ${signature.return_type}' }
		body := if signature.return_type == '' { '' } else { 'return ' }
		c.local_type_declarations << 'fn ${wrapper}(${params.join(', ')})${ret} {\n\t${body}C.${name}(${args.join(', ')})\n}\n\n'
	}
	return wrapper
}

// voidptr_array_element returns the pointer type of an element of a pointer
// array stored as `[N]voidptr` (see pointer_array_to_owner) that `node` indexes.
fn (c &C2V) voidptr_array_element(node Node) ?string {
	if c.voidptr_array_fields.len == 0 || !node.kindof(.array_subscript_expr) || node.inner.len != 2 {
		return none
	}
	mut base := node.inner[0]
	for base.inner.len == 1 && (base.kindof(.implicit_cast_expr) || base.kindof(.paren_expr)) {
		base = base.inner[0]
	}
	if base.kindof(.member_expr) {
		return c.voidptr_array_fields[base.referenced_member_decl] or { return none }
	}
	return none
}

// gen_variadic_pointer_call emits a call through a pointer to a C variadic
// function (`((int (*)(int, int, ...))p)(fd, cmd, arg)`). V drops the `...` of
// such function types, and a variadic callee needs its arguments passed as
// variadic ones (on the stack on Apple arm64), so the call goes through a C
// macro that casts the pointer to the variadic prototype.
fn (mut c C2V) gen_variadic_pointer_call(callee Node, call Node) bool {
	mut direct := callee
	for direct.inner.len == 1 && (direct.kindof(.implicit_cast_expr) || direct.kindof(.paren_expr)) {
		direct = direct.inner[0]
	}
	if direct.kindof(.decl_ref_expr) && direct.ref_declaration.kind == .function_decl {
		return false
	}
	callee_type := fn_call_callee_type(callee)
	params := function_type_params(callee_type)
	if params.len == 0 || params.last() != '...' {
		return false
	}
	fn_type := if callee_type.contains('(*)') {
		callee_type
	} else {
		function_type_as_pointer(callee_type) or { return false }
	}
	mut c_params := []string{}
	for param in params[..params.len - 1] {
		spelling := c_abi_type_spelling(c.resolve_type_alias(c.convert_type(param).name))
		if spelling == '' {
			return false
		}
		c_params << spelling
	}
	ret_v := c.convert_type(c_function_return_type(fn_type)).name
	ret_c := if ret_v == 'void' { 'void' } else { c_abi_type_spelling(c.resolve_type_alias(ret_v)) }
	if ret_c == '' {
		return false
	}
	c_params << '...'
	prototype := '${ret_c}(*)(${c_params.join(',')})'
	macro := 'C2V_VCALL_' + function_pointer_cast_type_token(prototype)
	key := 'variadic_pointer_call:${macro}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		ret := if ret_v == 'void' { '' } else { ' ${ret_v}' }
		// (Quoted: C types such as `unsigned long` contain spaces.)
		c.local_type_declarations << "#flag '-D${macro}(p,...)=((${prototype})(p))(__VA_ARGS__)'\nfn C.${macro}(voidptr, ...)${ret}\n\n"
	}
	c.gen('C.${macro}(voidptr(')
	c.emitting_callee = true
	c.expr(callee)
	c.emitting_callee = false
	c.gen(')')
	for i := 1; i < call.inner.len; i++ {
		c.gen(', ')
		c.gen_call_arg(call.inner[i], '', true)
	}
	c.gen(')')
	return true
}

// c_abi_type_spelling spells a scalar V type as C, for casts of function
// pointers. Pointers are `void*`: only the calling convention matters.
fn c_abi_type_spelling(v_type string) string {
	if v_type.starts_with('&') || v_type == 'voidptr' || v_type.starts_with('fn ') {
		return 'void*'
	}
	return match v_type {
		'i8' { 'signed char' }
		'u8' { 'unsigned char' }
		'i16' { 'short' }
		'u16' { 'unsigned short' }
		'int', 'i32' { 'int' }
		'u32' { 'unsigned int' }
		'i64' { 'long long' }
		'u64' { 'unsigned long long' }
		'isize' { 'long' }
		'usize' { 'unsigned long' }
		'f32' { 'float' }
		'f64' { 'double' }
		'bool' { '_Bool' }
		else { '' }
	}
}

// add_function_static_global declares the module global that holds a function's
// `static` local (V's own static locals of struct types are never allocated).
fn (mut c C2V) add_function_static_global(name string, typ string, declaration string) {
	if !c.is_dir {
		c.local_type_declarations << declaration
		return
	}
	c.globals_out[name] = declaration
	if name !in c.defined_globals {
		c.defined_global_order << name
	}
	c.defined_globals[name] = true
	c.register_global_symbol(name, typ, false)
}

// fn_pointer_call_helper returns a function converting a pointer to the
// function type `alias` (a `C2vFn_` alias), for calls through the result.
fn (mut c C2V) fn_pointer_call_helper(alias string) string {
	if !alias.starts_with('C2vFn_') {
		return alias
	}
	helper := 'c2v_fnptr_' + alias['C2vFn_'.len..]
	key := 'fn_pointer_call_helper:${helper}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << 'fn ${helper}(p voidptr) ${alias} {\n\treturn ${alias}(p)\n}\n\n'
	}
	return helper
}

fn float_literal_value(node Node) ?f64 {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr)
		|| current.kindof(.c_style_cast_expr)) {
		current = current.inner[0]
	}
	if current.kindof(.floating_literal) {
		return current.value.to_str().f64()
	}
	if current.kindof(.binary_operator) && current.inner.len == 2 {
		a := float_literal_value(current.inner[0])?
		b := float_literal_value(current.inner[1])?
		return match current.opcode {
			'*' { a * b }
			'/' { a / b }
			'+' { a + b }
			'-' { a - b }
			else { none }
		}
	}
	return none
}

// folds_to_non_finite_float reports whether the binary operation of floating
// literals `node` computes an infinity or NaN.
fn folds_to_non_finite_float(node Node) bool {
	if node.opcode !in ['*', '/', '+', '-'] {
		return false
	}
	value := float_literal_value(node) or { return false }
	return value != value || value > 1.7976931348623157e308 || value < -1.7976931348623157e308
}

// fn_pointer_invoke_helper declares `c2v_fncall_<hex>(p voidptr, args...)`,
// which calls the function pointer `p` of the function type `C2vFn_<hex>`.
fn (mut c C2V) fn_pointer_invoke_helper(hex string) ?string {
	signature := returned_fn_type_signature('C2vFn_' + hex)?
	if !signature.starts_with('fn (') {
		return none
	}
	close := matching_paren_index(signature, 3)
	if close < 0 {
		return none
	}
	params := split_top_level_commas(signature[4..close])
	if params.any(it == '...' || it.starts_with('...')) {
		return none
	}
	ret := signature[close + 1..].trim_space()
	helper := 'c2v_fncall_' + hex
	key := 'fn_pointer_invoke_helper:${helper}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		mut decl_params := ['p voidptr']
		mut args := []string{}
		for i, param in params {
			decl_params << 'a${i} ${param}'
			args << 'a${i}'
		}
		ret_part := if ret == '' { '' } else { ' ${ret}' }
		call := 'f(${args.join(', ')})'
		body := if ret == '' { '\t${call}\n' } else { '\treturn ${call}\n' }
		c.local_type_declarations << 'fn ${helper}(${decl_params.join(', ')})${ret_part} {\n\tf := C2vFn_${hex}(p)\n${body}}\n\n'
	}
	return helper
}

fn split_top_level_commas(text string) []string {
	mut parts := []string{}
	mut depth := 0
	mut start := 0
	for i, ch in text {
		if ch in [`(`, `[`] {
			depth++
		} else if ch in [`)`, `]`] {
			depth--
		} else if ch == `,` && depth == 0 {
			parts << text[start..i].trim_space()
			start = i + 1
		}
	}
	last := text[start..].trim_space()
	if last != '' {
		parts << last
	}
	return parts
}

// is_c_function_type reports whether the C type `t` is a function type (as
// opposed to a function pointer): `int (char *)`, `void (*(int))(void)`.
fn is_c_function_type(t string) bool {
	typ := t.trim_space()
	open := typ.index_u8(`(`)
	if open <= 0 {
		return false
	}
	close := matching_paren_index(typ, open)
	if close < 0 {
		return false
	}
	content := typ[open + 1..close].trim_space()
	if !content.starts_with('*') {
		// `R (params)`
		return true
	}
	rest := content[1..].trim_space()
	if rest == '' || rest.trim('*') == '' {
		// `R (*)(params)`: a function pointer.
		return false
	}
	if rest.starts_with('(') {
		// The declarator group nests: `R (*(params))(ret_params)`.
		return is_c_function_type('R ' + rest)
	}
	return false
}

// loaded_function_pointer_callee returns the load `*slot` of a function pointer
// that a call expression calls, as in `(**(fn_t *)p)(args)` or `(*slot)(args)`
// where `slot` points to a function pointer.
fn loaded_function_pointer_callee(callee Node) ?Node {
	mut current := callee
	for current.inner.len == 1 && (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
		current = current.inner[0]
	}
	// `*fp` designates the function itself: calling it calls `fp`.
	if current.kindof(.unary_operator) && current.opcode == '*' && current.inner.len == 1
		&& is_c_function_type(current.ast_type.qualified) {
		current = current.inner[0]
		for current.inner.len == 1
			&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
			current = current.inner[0]
		}
	}
	if current.kindof(.unary_operator) && current.opcode == '*' && current.inner.len == 1 {
		return current
	}
	return none
}

// v_statement_safe_value makes an expression that starts its own line safe from
// being parsed as call arguments of the previous line (`f\n(x)` is `f(x)` in V).
fn v_statement_safe_value(value string) string {
	mut v := value.trim_space()
	for v.starts_with('(') && matching_paren_index(v, 0) == v.len - 1 {
		v = v[1..v.len - 1].trim_space()
	}
	return if v.starts_with('(') { 'unsafe { ${v} }' } else { v }
}

// matching_paren_index returns the index of the `)` closing the `(` at `open`.
fn matching_paren_index(s string, open int) int {
	mut depth := 0
	for i := open; i < s.len; i++ {
		if s[i] == `(` {
			depth++
		} else if s[i] == `)` {
			depth--
			if depth == 0 {
				return i
			}
		}
	}
	return -1
}

// unwrap_va_list_operand finds the `va_list` object a va_* builtin operates on.
fn unwrap_va_list_operand(node Node) Node {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.implicit_cast_expr)
		|| current.kindof(.paren_expr)
		|| (current.kindof(.unary_operator) && current.opcode == '&')) {
		current = current.inner[0]
	}
	return current
}

fn (mut c C2V) ensure_c_va_macro_declarations() {
	key := 'c_va_macros:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << 'fn C.va_start(C.va_list, ...)\nfn C.va_end(C.va_list)\nfn C.va_copy(C.va_list, C.va_list)\n\n'
	}
}

// gen_assignment_value emits the C assignment expression `lhs = rhs` (or
// `lhs op= rhs`) where its value is used, as `c2v_assign[T](&lhs, value)`.
fn (mut c C2V) gen_assignment_value(assign Node) {
	helper_key := 'c2v_assign:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << 'fn c2v_assign[T](target &T, value T) T {\n\tunsafe {\n\t\t*target = value\n\t}\n\treturn value\n}\n\n'
	}
	lhs := assign.inner[0]
	rhs := assign.inner[1]
	// (Generating a node consumes its children: a compound assignment reads a
	// copy of the target.)
	lhs_value := clone_cpp_operator_node(&lhs)
	value_type := c.convert_type(node_effective_type_name(lhs)).name
	mut target := lhs
	for target.kindof(.paren_expr) && target.inner.len == 1 {
		target = target.inner[0]
	}
	resolved_value_type := c.resolve_type_alias(value_type)
	if resolved_value_type.starts_with('fn ') && assign.kindof(.binary_operator) {
		// V's C output for the generic helper breaks with a function type T.
		voidptr_key := 'c2v_assign_voidptr:${os.dir(c.outv)}'
		if voidptr_key !in c.generated_declarations {
			c.generated_declarations[voidptr_key] = true
			c.local_type_declarations << 'fn c2v_assign_voidptr(target &voidptr, value voidptr) voidptr {\n\tunsafe {\n\t\t*target = value\n\t}\n\treturn value\n}\n\n'
		}
		helper_name := c.function_pointer_cast_helper_name(resolved_value_type)
		c.gen('${helper_name}(c2v_assign_voidptr(unsafe { &voidptr(&')
		c.expr(target)
		c.gen(') }, voidptr(')
		c.expr(rhs)
		c.gen(')))')
		return
	}
	old_inside_unsafe := c.inside_unsafe
	c.gen('c2v_assign[${value_type}](')
	if target.kindof(.unary_operator) && target.opcode == '*' && target.inner.len == 1 {
		c.expr(target.inner[0])
	} else {
		c.gen('unsafe { &')
		c.inside_unsafe = true
		c.expr(target)
		c.inside_unsafe = old_inside_unsafe
		c.gen(' }')
	}
	// Numeric values are converted to the target type as C does; V only infers
	// `T` from both arguments when they agree.
	cast_value := c.resolve_type_alias(value_type) in v_primitive_type_names
		&& value_type != 'bool'
	c.gen(if cast_value { ', ${value_type}(' } else { ', ' })
	if assign.kindof(.compound_assign_operator) {
		c.expr(lhs_value)
		c.gen(' ${assign.opcode.trim_right('=')} (')
		c.expr(rhs)
		c.gen(')')
	} else {
		c.expr(rhs)
	}
	c.gen(if cast_value { '))' } else { ')' })
}

// null_member_offset translates the address of a member reached from a null
// pointer, `&((T *)0)->a.b[i]`, to the member's byte offset in V.
fn (mut c C2V) null_member_offset(node &Node) ?string {
	mut current := unsafe { node }
	for current.kindof(.paren_expr) && current.inner.len == 1 {
		current = unsafe { &current.inner[0] }
	}
	if !current.kindof(.unary_operator) || current.opcode != '&' || current.inner.len != 1 {
		return none
	}
	mut terms := []string{}
	if !c.null_member_offset_terms(current.inner[0], mut terms) || terms.len == 0 {
		return none
	}
	return terms.join(' + ')
}

fn (mut c C2V) null_member_offset_terms(node Node, mut terms []string) bool {
	if node.kindof(.paren_expr) && node.inner.len == 1 {
		return c.null_member_offset_terms(node.inner[0], mut terms)
	}
	if node.kindof(.implicit_cast_expr) && node.inner.len == 1
		&& node.cast_kind in ['ArrayToPointerDecay', 'NoOp'] {
		return c.null_member_offset_terms(node.inner[0], mut terms)
	}
	if node.kindof(.member_expr) && node.inner.len == 1 {
		base := node.inner[0]
		if !c.null_member_offset_terms(base, mut terms) {
			return false
		}
		record := c.convert_type(base.ast_type.qualified).name.trim_left('&')
		raw_field := node.name
		if record == '' || raw_field == '' {
			return false
		}
		field := if record.starts_with('C.') {
			if raw_field in v_reserved_words { '@' + raw_field } else { raw_field }
		} else if is_all_upper_identifier(raw_field) {
			filter_name(raw_field.to_lower(), false).all_after_last('.')
		} else if !c.is_cpp {
			c_record_field_v_name(raw_field)
		} else {
			filter_name(raw_field, false).all_after_last('.')
		}
		terms << 'usize(__offsetof(${record}, ${field}))'
		return true
	}
	if node.kindof(.array_subscript_expr) && node.inner.len == 2 {
		if !c.null_member_offset_terms(node.inner[0], mut terms) {
			return false
		}
		index := c.render_expr_to_string(node.inner[1])
		elem := c.convert_type(node.ast_type.qualified).name
		terms << 'usize(${index}) * usize(sizeof(${elem}))'
		return true
	}
	// The root: a null pointer constant cast to the record pointer type.
	if (node.kindof(.c_style_cast_expr) || node.kindof(.implicit_cast_expr))
		&& node.cast_kind in ['NullToPointer', 'IntegralToPointer'] && node.inner.len == 1 {
		mut value := node.inner[0]
		for value.kindof(.paren_expr) && value.inner.len == 1 {
			value = value.inner[0]
		}
		return value.kindof(.integer_literal) && value.value.to_str() == '0'
	}
	return false
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

// gen_cpp_prefix_update emits a prefix `++`/`--` whose value is used: the
// variable is updated first, then its new value is the result.
fn (mut c C2V) gen_cpp_prefix_update(target Node, delta string) {
	helper_key := 'c2v_prefix_add:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << 'fn c2v_prefix_add[T](target &T, delta T) T {\n\tunsafe {\n\t\t*target += delta\n\t\treturn *target\n\t}\n}\n\n'
	}
	value_type := c.convert_type(node_effective_type_name(target)).name
	typed_delta := if c.resolve_type_alias(value_type) == 'int' {
		delta
	} else {
		'${value_type}(${delta})'
	}
	c.gen('c2v_prefix_add(')
	if reference_name := c.cpp_primitive_reference_v_name(&target) {
		c.gen(reference_name)
	} else {
		mut deref := target
		for deref.kindof(.paren_expr) && deref.inner.len == 1 {
			deref = deref.inner[0]
		}
		was_inside_unsafe := c.inside_unsafe
		if deref.kindof(.unary_operator) && deref.opcode == '*' && deref.inner.len == 1 {
			c.expr(deref.inner[0])
		} else {
			c.gen(if was_inside_unsafe { '&' } else { 'unsafe { &' })
			c.inside_unsafe = true
			c.expr(target)
			c.inside_unsafe = was_inside_unsafe
			if !was_inside_unsafe {
				c.gen(' }')
			}
		}
	}
	c.gen(', ${typed_delta})')
}

// gen_address_in_cast emits `&target` as the operand of a pointer cast. V's old
// backend moves a variable whose address is taken to the heap, then casts the
// address of that heap pointer instead of the variable's. Passing the address
// through a function call is lowered correctly.
fn (mut c C2V) gen_address_in_cast(target Node) {
	if c.is_heap_promotable_local(target) {
		helper_key := 'c2v_address_of:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_address_of(address voidptr) voidptr {\n\treturn address\n}\n\n'
		}
		c.gen('c2v_address_of(&')
		c.expr(target)
		c.gen(')')
		return
	}
	c.gen('&')
	c.expr(target)
}

// unwrap_address_of_operand returns x for an `&x` expression (under parentheses
// and no-op casts).
fn unwrap_address_of_operand(expr Node) ?Node {
	mut current := expr
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind in ['NoOp', 'BitCast'])) {
		current = current.inner[0]
	}
	if current.kindof(.unary_operator) && current.opcode == '&' && current.inner.len == 1 {
		return current.inner[0]
	}
	return none
}

// is_heap_promotable_local reports whether an expression names a local variable
// or parameter held by value, which V may move to the heap when its address is
// taken.
fn (c &C2V) is_heap_promotable_local(target Node) bool {
	mut current := target
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind == 'NoOp')) {
		current = current.inner[0]
	}
	return current.kindof(.decl_ref_expr)
		&& current.ref_declaration.kind in [.var_decl, .parm_var_decl]
		&& current.ref_declaration.id in c.local_decl_v_names
		&& current.ref_declaration.id !in c.cpp_primitive_reference_decls && !current.ref_declaration.ast_type.qualified.trim_space().ends_with('&')
}

fn (mut c C2V) ensure_cpp_abstract_pointer_cast_helpers() {
	helper_key := 'cpp_abstract_pointer_cast_helper:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << 'union C2vAbstractPointerCastStorage[T] {\nmut:\n\traw [2]voidptr\n\tvalue T\n}\n\nfn c2v_abstract_pointer_cast[T](value voidptr) T {\n\tmut storage := C2vAbstractPointerCastStorage[T]{}\n\tunsafe {\n\t\tstorage.raw[0] = value\n\t\treturn storage.value\n\t}\n}\n\nfn c2v_abstract_pointer_value[T](value T) voidptr {\n\tstorage := C2vAbstractPointerCastStorage[T]{\n\t\tvalue: value\n\t}\n\treturn unsafe { storage.raw[0] }\n}\n\n'
	}
}

// gen_cpp_abstract_pointer_erasure converts a C++ abstract class pointer, a V
// interface value, to `void *`: the object's address. (V's own `iface as
// voidptr` panics in the old compiler backend.)
fn (mut c C2V) gen_cpp_abstract_pointer_erasure(expr Node, iface string) {
	c.ensure_cpp_abstract_pointer_cast_helpers()
	c.gen('c2v_abstract_pointer_value[${iface}](')
	c.expr(expr)
	c.gen(')')
}

// gen_variadic_array_decay passes the C array `rendered` through `...`: it
// decays to a pointer to its first element. (V requires `unsafe` for a pointer
// into a fixed array that is not itself a call argument.)
fn (mut c C2V) gen_variadic_array_decay(rendered string) {
	if c.inside_unsafe {
		c.gen('voidptr(&${rendered}[0])')
	} else {
		c.gen('unsafe { voidptr(&${rendered}[0]) }')
	}
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
	if c.is_cpp && c.is_v_abstract_interface_type(source_type) {
		// A translated C++ abstract pointer is a V interface value, whose runtime
		// representation cannot be converted with the ordinary `voidptr(value)` cast.
		c.gen_cpp_abstract_pointer_erasure(source_arg, source_type)
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
				c.gen_variadic_array_decay(inner_rendered)
				return
			}
		}
	}
	if rendered_arg_is_addressable_lvalue(rendered)
		&& cpp_raw_fixed_array_length(node_effective_type_name(arg)) > 0 {
		c.gen_variadic_array_decay(rendered)
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
	is_integer_literal := base_arg.kindof(.integer_literal)
	if is_integer_literal && base_arg.value.to_str().u64() < 1048576 {
		// An immediate (see c2v_va_is_immediate).
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
		// V cannot infer the type argument from an `if` or `match` expression,
		// and would store an untyped literal as an `int`.
		trimmed_rendered := rendered.trim_space()
		type_arg := if v_arg_type != '' && !v_arg_type.contains(' ') && (is_integer_literal
			|| trimmed_rendered.starts_with('if ') || trimmed_rendered.starts_with('match ')) {
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
	spelled := c.convert_type(expr.ast_type.qualified).name
	v_type := c.resolve_type_alias(spelled).trim_left('&')
	// (Nor of a pointer type spelled by an alias: `PQExpBuffer`.)
	through_voidptr := v_type.starts_with('fn ')
		|| (!c.is_cpp && !spelled.starts_with('&') && spelled != 'voidptr' && spelled != v_type)
	c.gen(if through_voidptr { 'usize(voidptr(' } else { 'usize(' })
	c.gen_cxx_pointer_cast_source(expr)
	c.gen(if through_voidptr { '))' } else { ')' })
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

// is_cpp_const_pointer_reference_type reports whether `typ` is a reference to a
// const pointer (`T *const &`), which V passes as the pointer value.
fn is_cpp_const_pointer_reference_type(typ string) bool {
	trimmed := typ.trim_space()
	last_pointer_index := trimmed.last_index('*') or { return false }
	return trimmed.ends_with('&') && trimmed[last_pointer_index + 1..].contains('const')
}

// cpp_lvalue_is_rooted_at_call reports whether an lvalue is a member or an
// element reached from a call result (`list[i].count`, `Get()->value`).
fn cpp_lvalue_is_rooted_at_call(node Node) bool {
	mut current := unwrap_cpp_noop_casts(node)
	if !current.kindof(.member_expr) && !current.kindof(.array_subscript_expr) {
		return false
	}
	for current.inner.len > 0 {
		if current.kindof(.member_expr) || current.kindof(.array_subscript_expr) {
			current = current.inner[0]
		} else if (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr))
			&& current.inner.len == 1 {
			current = current.inner[0]
		} else {
			break
		}
	}
	return current.kindof(.call_expr) || current.kindof(.cxx_member_call_expr)
		|| current.kindof(.cxx_operator_call_expr)
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
	if c.is_cpp && param_type.replace(' ', '').ends_with('*&') {
		if slot := cpp_reinterpreted_pointer_slot(arg) {
			// `reinterpret_cast<Base *&>(pointer)` binds the pointer's own storage
			// as a `Base *` slot, without adjusting the pointer.
			slot_type := '&' + c.convert_type(arg.ast_type.qualified).name
			c.gen('unsafe { ${slot_type}(voidptr(')
			old_inside_unsafe := c.inside_unsafe
			c.inside_unsafe = true
			c.gen_address_in_cast(slot)
			c.inside_unsafe = old_inside_unsafe
			c.gen(')) }')
			return
		}
	}
	if converted_param_type.is_const && param_type.trim_space().ends_with('&')
		&& v_param_type.starts_with('&')
		&& normalize_v_ptr_type(v_param_type) in v_primitive_type_names {
		v_param_type = v_param_type[1..]
	}
	resolved_v_param_type := c.resolve_type_alias(v_param_type)
	if !is_variadic_arg && c.file_variant_pointer_type(param_type) != ''
		&& !is_cpp_null_pointer_expression(arg) {
		// The callee may be declared with the project's layout of the record.
		c.gen('voidptr(')
		c.expr(arg)
		c.gen(')')
		return
	}
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
	if !is_variadic_arg && c.is_cpp && is_cpp_const_pointer_reference_type(param_type) {
		// The parameter takes the pointer value, but a call returning a mutable
		// `T *&`, like a `T *&` variable, is a V pointer to the pointer.
		mut source := arg
		for source.inner.len == 1 && ((source.kindof(.implicit_cast_expr)
			&& source.cast_kind == 'NoOp') || source.kindof(.paren_expr)) {
			source = source.inner[0]
		}
		returns_pointer_slot := source.value_category == 'lvalue' && (source.kindof(.call_expr)
			|| source.kindof(.cxx_member_call_expr) || source.kindof(.cxx_operator_call_expr))
			&& !source.ast_type.qualified.trim_space().ends_with('const')
			&& c.cpp_primitive_reference_operator_source(&source) == none
		names_pointer_slot := source.kindof(.decl_ref_expr)
			&& source.ref_declaration.kind in [.var_decl, .parm_var_decl]
			&& is_cpp_mutable_pointer_reference_type(source.ref_declaration.ast_type.qualified)
		if returns_pointer_slot || names_pointer_slot {
			old_inside_unsafe := c.inside_unsafe
			c.gen(if old_inside_unsafe { '(*' } else { '(unsafe { *' })
			c.inside_unsafe = true
			c.expr(source)
			c.inside_unsafe = old_inside_unsafe
			c.gen(if old_inside_unsafe { ')' } else { ' })' })
			return
		}
	}
	if !is_variadic_arg && c.is_cpp && !converted_param_type.is_const
		&& param_type.trim_space().ends_with('&') && !param_type.trim_space().ends_with('&&')
		&& normalize_v_ptr_type(resolved_v_param_type) in v_primitive_type_names
		&& v_param_type.starts_with('&') && arg.value_category == 'lvalue'
		&& cpp_lvalue_is_rooted_at_call(arg) {
		// V would pass the address of a copy of a member of a call result.
		c.gen('&')
		c.expr(arg)
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
		if !c.is_cpp && resolved_v_param_type.trim_left('&') == 'voidptr' {
			// The old V backend types an `if` of `&voidptr` values as a `voidptr`
			// (and passes its address): convert byte pointers as a whole instead.
			old_inside_unsafe := c.inside_unsafe
			c.gen('voidptr(unsafe { if ')
			c.inside_unsafe = true
			mut pointer_condition := clone_cpp_operator_node(&conditional_arg.inner[0])
			c.gen_bool(&pointer_condition)
			c.gen(' { ')
			for i in 1 .. 3 {
				if i == 2 {
					c.gen(' } else { ')
				}
				if is_c_null_pointer_constant(conditional_arg.inner[i]) {
					c.gen('&u8(nil)')
				} else {
					c.gen('&u8(')
					c.expr(conditional_arg.inner[i])
					c.gen(')')
				}
			}
			c.inside_unsafe = old_inside_unsafe
			c.gen(' } })')
			return
		}
		was_inside_unsafe := c.inside_unsafe
		if !was_inside_unsafe {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
		mut condition := clone_cpp_operator_node(&conditional_arg.inner[0])
		c.gen('if ')
		c.gen_bool(&condition)
		c.gen(' { ')
		for i in 1 .. 3 {
			if i == 2 {
				c.gen(' } else { ')
			}
			if !c.is_cpp && is_c_null_pointer_constant(conditional_arg.inner[i]) {
				// V types an `if` expression by its branches: a bare `nil` would
				// make it a `voidptr`.
				c.gen('${v_param_type}(nil)')
			} else {
				c.gen_call_arg(conditional_arg.inner[i], param_type, false)
			}
		}
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
	if is_variadic_arg && !c.is_cpp {
		// V passes the variadic arguments of a C variadic function to C, which
		// promotes them; V's checker only rejects pointers there.
		arg_type := c.resolve_type_alias(c.convert_type(node_effective_type_name(arg)).name)
		if arg_type.starts_with('&') || arg_type.starts_with('fn ') || arg_type == 'voidptr' {
			c.write_voidptr_arg_expr(arg)
		} else {
			c.expr(arg)
		}
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
			// A translated C++ reference parameter is already a V pointer. Passing
			// its address would incorrectly produce `&&T`; reading a primitive
			// one would pass a copy.
			if param_type.trim_space().ends_with('&') {
				if reference_name := c.cpp_primitive_reference_v_name(&base_arg) {
					c.gen(reference_name)
					return
				}
			}
			c.expr(arg)
			return
		}
	}
	if !is_variadic_arg && is_enum_ref_expr(base_arg)
		&& (v_param_type in v_integer_type_names || resolved_v_param_type in v_integer_type_names
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
	// (A `va_list` desugars to a platform type such as `char *`.)
	arg_type_name := if arg.ast_type.qualified in ['va_list', '__builtin_va_list', '__gnuc_va_list'] {
		arg.ast_type.qualified
	} else {
		node_effective_type_name(arg)
	}
	v_arg_type := c.prefix_external_type(c.convert_type(arg_type_name).name)
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
					// V binds a record value to a `&T` parameter itself, in storage
					// that lasts for the call, like the C++ temporary.
					c.expr(arg)
					return
				}
				arg_id := c.expression_temp_id
				c.expression_temp_id++
				c.gen('__c2v_ref_arg_${arg_id}(')
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
					// temporary before their initializer: V binds the value to the
					// `&T` parameter itself, for global and ordinary temporaries alike.
					c.gen(rendered)
				} else {
					arg_id := c.expression_temp_id
					c.expression_temp_id++
					c.gen('__c2v_ref_arg_${arg_id}(')
					c.gen(rendered)
					c.gen(')')
				}
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
		// Keep the parameter's pointer depth (`T **` out-parameters): V would pass
		// a shallower pointer as the address of a temporary copy of it.
		target_type := v_param_type.trim_space()[1..].trim_space()
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

fn (mut c C2V) gen_conditional_branch(branch Node, float_type string) {
	if !c.is_cpp && c.conditional_result_type != '' && is_c_null_pointer_constant(branch) {
		// `cond ? 0 : ptr`: V types an `if` expression by its first branch.
		resolved := c.resolve_type_alias(c.conditional_result_type)
		if resolved.starts_with('fn ') {
			c.gen(c.typed_null_function_pointer(c.conditional_result_type))
			return
		}
		if resolved.starts_with('&') {
			c.gen(if c.inside_unsafe {
				'${c.conditional_result_type}(nil)'
			} else {
				'unsafe { ${c.conditional_result_type}(nil) }'
			})
			return
		}
		if resolved == 'voidptr' {
			c.gen('voidptr(0)')
			return
		}
	}
	mut literal := branch
	for literal.inner.len == 1 && (literal.kindof(.implicit_cast_expr) || literal.kindof(.paren_expr)) {
		literal = literal.inner[0]
	}
	if float_type != '' && literal.kindof(.floating_literal) {
		c.gen(float_type + '(')
		c.expr(branch)
		c.gen(')')
		return
	}
	c.expr(branch)
}

// is_null_pointer_constant reports a C `NULL` (`(void *)0`) or C++ null pointer.
fn is_null_pointer_constant(node Node) bool {
	mut current := node
	for current.inner.len == 1 && current.kindof(.paren_expr) {
		current = current.inner[0]
	}
	if current.kindof(.c_style_cast_expr) && current.cast_kind == 'NullToPointer' {
		return true
	}
	return is_cpp_null_pointer_expression(current)
}

// cpp_reinterpreted_pointer_slot returns the pointer lvalue whose storage a
// `reinterpret_cast<T *&>(pointer)` rebinds as a pointer of another type.
fn cpp_reinterpreted_pointer_slot(arg Node) ?Node {
	mut current := arg
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind == 'NoOp')) {
		current = current.inner[0]
	}
	if !current.kindof(.cxx_reinterpret_cast_expr) || current.value_category != 'lvalue'
		|| current.cast_kind != 'LValueBitCast' || current.inner.len != 1
		|| !current.ast_type.qualified.trim_space().ends_with('*') {
		return none
	}
	return current.inner[0]
}

// file_variant_pointer_type returns the V type of the C pointer or function
// type `c_type` when it refers to a record that this file declares under a
// file-qualified name (C lets translation units give a tag different layouts,
// see record_decl). Declarations shared with other files use the project's
// layout, so such values cross into them as `voidptr`.
fn (mut c C2V) file_variant_pointer_type(c_type string) string {
	if c.is_cpp || !c.is_dir || c.file_type_alias_names.len == 0 || c_type == '' {
		return ''
	}
	v_type := c.convert_type(c_type).name
	resolved := c.resolve_type_alias(v_type)
	if !resolved.starts_with('&') && !resolved.starts_with('fn ') && !v_type.starts_with('C2vFn_') {
		return ''
	}
	mut spelled := resolved
	if v_type.starts_with('C2vFn_') {
		spelled = returned_fn_type_signature(v_type) or { resolved }
	}
	for _, local_name in c.file_type_alias_names {
		if contains_identifier_token(spelled, local_name) {
			return v_type
		}
	}
	return ''
}

// is_shared_variant_fn reports whether the function `node` is defined in this
// file, may be called from other files, and this file declares a record under a
// file-qualified name. Its signature then uses the project's name of such a
// record (see project_variant_type), and its body this file's layout.
fn (c &C2V) is_shared_variant_fn(node &Node, no_stmts bool) bool {
	return !c.is_cpp && c.is_dir && !c.is_wrapper && !no_stmts && c.file_type_alias_names.len > 0
		&& node.class_modifier != 'static' && node.name != 'main'
}

// project_variant_type spells the records of V type `typ` that this file
// declares under file-qualified names by their project names.
fn (c &C2V) project_variant_type(typ string) string {
	mut out := typ
	for source_alias, local_alias in c.file_type_alias_names {
		out = replace_c_ref_token(out, local_alias, source_alias)
	}
	return out
}

fn contains_identifier_token(text string, name string) bool {
	mut from := 0
	for {
		start := text.index_after(name, from) or { return false }
		end := start + name.len
		before_ok := start == 0 || !is_simple_identifier_char(text[start - 1])
		after_ok := end >= text.len || !is_simple_identifier_char(text[end])
		if before_ok && after_ok {
			return true
		}
		from = start + 1
	}
	return false
}

// is_function_value reports whether `node` evaluates to a function's address.
fn is_function_value(node Node) bool {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| current.kindof(.implicit_cast_expr) || current.kindof(.c_style_cast_expr)) {
		if current.cast_kind == 'FunctionToPointerDecay' {
			return true
		}
		current = current.inner[0]
	}
	return current.kindof(.decl_ref_expr) && current.ref_declaration.kind == .function_decl
}

// gen_function_as_fn_type emits a function stored in a slot of V function type
// `target` whose parameters are spelled differently (a typedef such as
// `sqlite3_filename` instead of `const char *`). The C types are the same, but
// V function types only match exactly. Returns false for other values.
fn (mut c C2V) gen_function_as_fn_type(value Node, target string) bool {
	target_fn := c.resolve_type_alias(target)
	if !target_fn.starts_with('fn ') {
		return false
	}
	mut function := value
	for function.inner.len == 1 && (function.kindof(.paren_expr)
		|| (function.kindof(.implicit_cast_expr) && function.cast_kind == 'FunctionToPointerDecay')) {
		function = function.inner[0]
	}
	if !function.kindof(.decl_ref_expr) || function.ref_declaration.kind != .function_decl {
		return false
	}
	pointer_type := function_type_as_pointer(function.ref_declaration.ast_type.qualified) or {
		return false
	}
	if c.resolve_type_alias(c.convert_type(pointer_type).name) == target_fn {
		return false
	}
	helper_name := c.function_pointer_cast_helper_name(target_fn)
	c.gen('${helper_name}(voidptr(')
	c.expr(function)
	c.gen('))')
	return true
}

// typed_null_function_pointer is a null value of a V function type (a raw
// `fn (T)(nil)` would parse as an anonymous function).
fn (mut c C2V) typed_null_function_pointer(v_type string) string {
	if v_type.starts_with('fn ') {
		return '${c.function_pointer_cast_helper_name(v_type)}(voidptr(0))'
	}
	return 'unsafe { ${v_type}(nil) }'
}

// is_c_null_pointer_constant reports whether `node` is C's null pointer
// constant: `0` or `(void *)0`, possibly parenthesized and cast.
fn is_c_null_pointer_constant(node Node) bool {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| ((current.kindof(.implicit_cast_expr) || current.kindof(.c_style_cast_expr))
			&& current.cast_kind in ['NullToPointer', 'BitCast', 'NoOp'])) {
		current = current.inner[0]
	}
	return (current.kindof(.integer_literal) && current.value.to_str() == '0')
		|| current.kindof(.gnu_null_expr)
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

// sizeof_reference_operand_type returns the type of a C++ `sizeof` operand
// that names a reference (`sizeof(vec)` for `idVec3 &vec`): the translated
// reference is a V pointer, whose size `sizeof` would give instead.
fn (c &C2V) sizeof_reference_operand_type(expr Node) ?string {
	if !c.is_cpp {
		return none
	}
	mut current := expr
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| current.kindof(.implicit_cast_expr)) {
		current = current.inner[0]
	}
	declared_type := if current.kindof(.decl_ref_expr) {
		current.ref_declaration.ast_type.qualified
	} else if current.kindof(.member_expr) {
		field := c.callback_seen_ids[current.referenced_member_decl] or { return none }
		field.ast_type.qualified
	} else {
		''
	}
	if !declared_type.trim_space().ends_with('&') || current.ast_type.qualified == '' {
		return none
	}
	return current.ast_type.qualified
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
	if is_assignment && node.inner.len > 0 && lvalue_reached_through_pointer(node.inner[0]) {
		// `a[i]->n = v`: V only writes through the elements of a `mut` pointer.
		if root := subscripted_pointer_local(node.inner[0]) {
			refs[root.id] = true
			refs['name:${root.name}'] = true
		}
	}
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

// subscripted_pointer_local returns the local pointer variable that the member
// lvalue `node` subscripts (`a` in `a[i]->n`).
fn subscripted_pointer_local(node Node) ?Node {
	mut current := node
	for current.inner.len > 0 {
		if current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr)
			|| current.kindof(.member_expr) {
			current = current.inner[0]
		} else if current.kindof(.array_subscript_expr) {
			base := unwrap_address_target(current.inner[0])
			if base.kindof(.decl_ref_expr) && base.ref_declaration.kind == .var_decl
				&& base.ref_declaration.id != '' {
				return Node{
					id:   base.ref_declaration.id
					name: if base.ref_declaration.name != '' {
						base.ref_declaration.name
					} else {
						base.name
					}
				}
			}
			return none
		} else {
			break
		}
	}
	return none
}

// lvalue_reached_through_pointer reports whether the C lvalue `node` is a
// member of an object reached by dereferencing or subscripting a pointer.
fn lvalue_reached_through_pointer(node Node) bool {
	mut current := node
	mut through_member := false
	for current.inner.len > 0 {
		if current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr) {
			current = current.inner[0]
		} else if current.kindof(.member_expr) {
			through_member = true
			current = current.inner[0]
		} else if current.kindof(.unary_operator) && current.opcode == '*' {
			return through_member
		} else if current.kindof(.array_subscript_expr) {
			base := current.inner[0]
			return through_member && !(base.kindof(.implicit_cast_expr)
				&& base.cast_kind == 'ArrayToPointerDecay')
		} else {
			break
		}
	}
	return false
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

// v_zero_value is the V literal of a zero-initialized C/C++ value of a V type.
fn (mut c C2V) v_zero_value(v_type string) string {
	t := v_type.trim_space()
	mut resolved := c.resolve_type_alias(t)
	if t.starts_with('C2vFn_') {
		resolved = returned_fn_type_aliases(t)[0] or { '' }.all_after(' = ')
	}
	if t.starts_with('&') || resolved == 'voidptr' {
		return 'unsafe { nil }'
	}
	if resolved.starts_with('fn ') {
		return c.typed_null_function_pointer(resolved)
	}
	if t in c.enum_vals || resolved in c.enum_vals {
		return 'unsafe { ${t}(0) }'
	}
	if resolved in ['i8', 'i16', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize', 'f32', 'f64'] {
		return '${t}(0)'
	}
	return c.skeleton_default_value(t)
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
		'i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize' {
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
	return c_name in c.defined_function_names
}

// collect_defined_function_names records the functions the translation unit
// defines (with a body).
fn (mut c C2V) collect_defined_function_names() {
	c.defined_function_names = map[string]bool{}
	for node in c.tree.inner {
		if node.kind_str == 'FunctionDecl' && node.name != ''
			&& node.inner.any(it.kind_str == 'CompoundStmt') {
			c.defined_function_names[node.name] = true
		}
	}
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
	// Translated C declares every system function it calls, from the prototype
	// Clang parsed: V's builtin module declares only part of libc (a repeated
	// declaration of a C function is accepted).
	declared_by_v := (name in c_known_fn_names || name in builtin_fn_names)
		&& name !in v_os_module_c_fn_names && (c.is_cpp || name !in c.system.declaring_headers)
	if name == '' || declared_by_v || name in c.external_c_fn_declarations || node.is_implicit
		|| name.starts_with('__builtin_') {
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
	raw_return_type := c_function_return_type(node.ast_type.qualified)
	mut return_type := ''
	if raw_return_type != '' && raw_return_type != 'void' {
		converted := c.prefix_external_type(c.convert_type(raw_return_type).name)
		return_type = ' ' + c.external_decl_abi_type(converted)
	}
	c.external_c_fn_declarations[name] = 'fn C.${name}(${params.join(', ')})${return_type}'
	c.external_c_fn_signatures[name] = ExternalCFnSignature{
		params:      params
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
	// In C, a project prototype without a body is defined by another translation
	// unit of the project, not by an external library.
	is_system_function := node.name in c.system.declaring_headers
	if node.kind_str == 'FunctionDecl' && c.used_fn.exists(node.name)
		&& (is_system_function || (c.is_cpp && is_c_linkage_function_decl(node)
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
	if !c.is_cpp && !c.is_wrapper && !c.is_dir && !node.has_child_of_kind(.compound_stmt)
		&& (c.has_function_definition(c_name) || node.previous_declaration != '') {
		// A C prototype of a function this file defines, or a repeated prototype:
		// V needs no (further) declaration.
		return
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
	if node.ast_type.qualified.contains('...)') && !c.is_cpp {
		// Attach the attribute only after deciding to emit this declaration.
		c.genln('@[c2v_variadic]')
	}
	preassigned_cpp_name := c.cpp_function_decl_names[node.id] or { '' }
	registered_v_name := if preassigned_cpp_name != '' {
		preassigned_cpp_name
	} else {
		c.add_fn_name(c_name)
	}
	// A function declared through a function typedef (`static Tcl_ObjCmdProc f;`)
	// spells its type by that name.
	fn_type_spelling := if !node.ast_type.qualified.contains('(')
		&& node.ast_type.desugared_qualified.contains('(') {
		node.ast_type.desugared_qualified
	} else {
		node.ast_type.qualified
	}
	mut typ := c_function_return_type(fn_type_spelling)
	enum_abi_for_decl := no_stmts && !c.is_dir && !c.is_wrapper
		&& !c.has_function_definition(c_name)
	if typ == 'void' {
		typ = ''
	} else {
		typ = c.cpp_return_v_type(typ)
		if enum_abi_for_decl {
			typ = c.external_decl_abi_type(typ)
		}
		if !c.is_cpp {
			// The same alias as in function pointer types (see convert_type): V
			// compares function types exactly.
			typ = returned_fn_type_alias(typ)
		}
	}
	c.cur_fn_variant_return = false
	if typ != '' && c.is_shared_variant_fn(node, no_stmts)
		&& c.file_variant_pointer_type(c_function_return_type(fn_type_spelling)) != '' {
		typ = c.project_variant_type(typ)
		c.cur_fn_variant_return = true
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
			if !c.is_cpp && node.ast_type.qualified.contains('...') {
				// V's `@[export]` wrapper calls the function without its variadic
				// arguments: a C variadic function takes the C name itself.
				c.genln("@[c: '${c_name}']")
			} else {
				c.genln("@[export: '${c_name}']")
			}
			c.generated_declarations[export_key] = true
		} else if !is_dir_exported_fn && v_name != c_name && !c.is_wrapper
			&& !is_template_specialization && !(c.is_dir && c.is_cpp)
			&& !(c.is_dir && !c.is_cpp && c_name in c.file_static_fn_names)
			&& is_c_linkage_function_decl(&node) {
			// (A static function of a project keeps its V name: other files may
			// define a function of the same C name.)
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
				// (builtin's `arguments()`: importing `os` would bring its own
				// declarations of C functions into the translated program.)
				c.genln('\tc2v_main_arguments := arguments()')
				c.genln('\tmut c2v_main_argv_storage := []&i8{cap: c2v_main_arguments.len + 1}')
				c.genln('\tfor arg in c2v_main_arguments {')
				c.genln('\t\tc2v_main_argv_storage << arg.str')
				c.genln('\t}')
				// C guarantees `argv[argc] == NULL`.
				c.genln('\tc2v_main_argv_storage << unsafe { &i8(nil) }')
				c.genln('\t${argc_name} := c2v_main_argv_storage.len - 1')
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
			c.gc_thread_entry_body = !c.inside_main && c.is_gc_thread_entry(&node)
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
	if base in v_local_reserved_type_names || base in v_reserved_fn_names {
		// (V resolves `error = x` to its builtin function `error`.)
		base += '_'
	}
	mut candidate := base
	mut suffix := 2
	for c.declared_local_vars.exists(candidate) || c.for_init_vars.exists(candidate)
		|| map_has_value(c.fns, candidate) || map_has_value(c.extern_fns, candidate)
		|| map_has_value(c.cpp_function_signature_v_names, candidate)
		|| map_has_value(c.cpp_method_signature_v_names, candidate)
		|| candidate in c.project_function_surfaces || map_has_value(c.consts, candidate)
		|| candidate in c.project_const_v_names {
		// V resolves a local named like a module constant to the constant.
		candidate = '${base}_${suffix}'
		suffix++
	}
	if decl_id != '' {
		c.local_decl_v_names[decl_id] = candidate
	}
	c.local_v_names_seen[candidate] = true
	return candidate
}

fn (mut c C2V) fn_params(mut node Node, enum_abi_for_decl bool) []string {
	mut str_args := []string{cap: 5}
	mut used_param_names := map[string]int{}
	shared_variant_fn := c.is_shared_variant_fn(node, !node.has_child_of_kind(.compound_stmt))
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
			&& (is_pointer_reference || c.is_primitive_reference_v_type(v_arg_typ_name)) {
			c.cpp_primitive_reference_decls[param.id] = true
		}
		if shared_variant_fn && c.file_variant_pointer_type(param.ast_type.qualified) != '' {
			// Other files pass the record with the project's layout.
			str_args << '${v_param_name}_param ${c.project_variant_type(v_arg_typ_name)}'
			c.param_local_copies << 'mut ${v_param_name} := unsafe { ${v_arg_typ_name}(voidptr(${v_param_name}_param)) }'
		} else if param.id in c.copied_pointer_params && node.id == c.copied_params_fn_id {
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
// strip_cpp_type_qualifier removes every `qualifier` from a type. It reports
// whether one qualifies the type itself or its pointee chain: one inside
// parentheses belongs to a function type's parameters.
fn strip_cpp_type_qualifier(type_name string, qualifier string) (string, bool) {
	mut out := strings.new_builder(type_name.len)
	mut found := false
	mut depth := 0
	mut i := 0
	for i < type_name.len {
		if type_name[i] == `(` {
			depth++
		} else if type_name[i] == `)` {
			depth--
		}
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
				if depth == 0 {
					found = true
				}
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
	for qualifier in ['_Nonnull', '_Nullable', '_Null_unspecified', 'restrict', '__restrict',
		'__restrict__'] {
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
	const_pointer_reference := is_cpp_const_pointer_reference_type(typ)
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
			name: 'i32'
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
				name:     strings.repeat(`&`, outer_ptr_depth) + converted_template.name
				is_const: is_const
			}
		}
		if outer_array_suffix != '' {
			converted_template := convert_type(typ)
			return Type{
				name:     outer_array_suffix + converted_template.name
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
				name:     '&' + enum_part[..enum_part.len - 2].capitalize()
				is_const: is_const
			}
		}
		return Type{
			name:     enum_part.capitalize()
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
				name:     '&' + array_suffix + converted_base.name
				is_const: is_const
			}
		}
	}

	// A declarator nested in a function pointer: `R (*(*)(args))(ret_args)` is a
	// pointer to a function taking `args` that returns `R (*)(ret_args)`.
	if typ.contains('(*(') {
		open := typ.index_u8(`(`)
		close := matching_paren_index(typ, open)
		if open > 0 && close > open && close + 1 < typ.len && typ[close + 1..].trim_space().starts_with('(')
			&& typ[open + 1..close].starts_with('*(') {
			returned := convert_type(typ[..open].trim_space() + ' (*)' + typ[close + 1..].trim_space())
			declarator := typ[open + 2..close].trim_space()
			outer := convert_type('C2vReturnedFnPlaceholder ' + declarator)
			// V cannot parse a function type returning a function type inline;
			// the returned type is named by an alias (see returned_fn_type_aliases).
			return Type{
				name:     outer.name.replace('C2vReturnedFnPlaceholder', returned_fn_type_alias(returned.name))
				is_const: is_const
			}
		}
	}
	// `R (*[N])(args)`: an array of function pointers.
	if open := typ.index('(*[') {
		close := typ.index_after_('])', open)
		if close > open && open == typ.index_u8(`(`) {
			dims := typ[open + 2..close + 1].replace(' ', '')
			converted := convert_type(typ[..open] + '(*)' + typ[close + 2..])
			return Type{
				name:     dims + converted.name
				is_const: is_const
			}
		}
	}
	// `R (**)(args)`: a pointer to a function pointer.
	if open := typ.index('(**') {
		close := typ.index_after_(')', open)
		if close > open && open == typ.index_u8(`(`) {
			group := typ[open + 1..close]
			if group.trim('*') == '' {
				converted := convert_type(typ[..open] + '(*)' + typ[close + 1..])
				return Type{
					name:     strings.repeat(`&`, group.len - 1) + converted.name
					is_const: is_const
				}
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
			if c_long_size == 8 { 'i64' } else { 'i32' }
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
			'i32'
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
		'int8_t', '__int8_t' {
			'i8'
		}
		'__int16_t' {
			'i16'
		}
		'__int64_t' {
			'i64'
		}
		'__int32_t' {
			'i32'
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

		// C's `int` is 32 bits wide; V's `int` has the width of a pointer.
		'int' {
			'i32'
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
		'__int128', '__int128_t', 'unsigned __int128', '__uint128_t' {
			// See int128.v.
			'C2vU128'
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
		'off_t' {
			'i64'
		}
		'uid_t', 'gid_t' {
			'u32'
		}
		'pid_t' {
			'i32'
		}
		'mode_t' {
			'u32'
		}
		'dev_t' {
			'u64'
		}
		else {
			mut capitalized := trim_underscores(base).capitalize()
			// Check for conflict with V built-in type names (e.g., Option, Result).
			// V reserves single capital letters for generic type parameters.
			if capitalized in v_builtin_type_names || capitalized.len == 1 {
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
		name:     name
		is_const: is_const
	}
}

// qualify_nested_enum_type spells an enum nested in a class by its distinct
// name: a qualified reference anywhere, an unqualified one inside the class.
fn (c &C2V) qualify_nested_enum_type(typ string) string {
	if c.cpp_nested_enums.len == 0 {
		return typ
	}
	mut result := typ
	if result.contains('::') {
		for qualified, flattened in c.cpp_nested_enums {
			result = replace_cpp_identifier(result, qualified, flattened)
		}
	}
	for word in result.split(' ') {
		bare := word.trim('*&')
		if bare == '' || bare.contains('::') {
			continue
		}
		scope := if c.cur_class != '' { c.cur_class } else { c.nested_enum_method_scope }
		if scope != '' {
			if flattened := c.cpp_nested_enums['${scope}::${bare}'] {
				result = replace_cpp_identifier(result, bare, flattened)
				continue
			}
		}
		// Elsewhere a bare name denotes the only nested enum spelled so, unless an
		// enum outside any class has that name.
		if flattened := c.cpp_nested_enum_short_names[bare] {
			if flattened != '' && bare !in c.enums {
				result = replace_cpp_identifier(result, bare, flattened)
			}
		}
	}
	return result
}

// replace_cpp_identifier replaces whole occurrences of a (qualified) name.
fn replace_cpp_identifier(text string, name string, replacement string) string {
	if !text.contains(name) {
		return text
	}
	mut out := strings.new_builder(text.len)
	mut i := 0
	for i < text.len {
		if source_has_text_at(text, i, name) && (i == 0 || !is_identifier_char(text[i - 1]))
			&& (i + name.len >= text.len || !is_identifier_char(text[i + name.len]))
			&& !source_has_text_at(text, i - 2, '::') {
			out.write_string(replacement)
			i += name.len
			continue
		}
		out.write_u8(text[i])
		i++
	}
	return out.str()
}

fn (c &C2V) convert_type(raw_typ string) Type {
	mut typ := c.qualify_nested_enum_type(raw_typ)
	if c.anonymous_record_names.len > 0 {
		key := anonymous_record_key(typ)
		if name := c.anonymous_record_names[key] {
			// `union (unnamed union at f.c:12:3) *` -> `FuncDef_u *`
			open := typ.index('(') or { 0 }
			close := typ.index_after_(')', open)
			// Keep qualifiers; drop the tag keyword and an enclosing `Outer::`.
			qualifiers := typ[..open].split(' ').filter(it != '' && it !in ['struct', 'union'] && !it.ends_with('::'))
			typ = (qualifiers.join(' ') + ' ' + name + typ[close + 1..]).trim_space()
		}
	}
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
	if c.is_cpp && converted.name.ends_with('C.va_list') {
		// Translated C++ variadic functions receive their arguments as a V slice;
		// a `va_list` reads through one (see c2v_va_list_source).
		converted.name = converted.name.all_before_last('C.va_list') + '&C2vVaList'
	}
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
	if c.is_cpp {
		// A typedef of a record, or of a pointer to one, is spelled as that
		// type. An alias is a type of its own in V: a method taking `&View_t`
		// does not implement an interface method taking `&View_s`, and the
		// methods of a record are not called through an alias of its pointer.
		// (Another file of the project may define a typedef of the same name.)
		alias := c.file_type_alias_names[abstract_base] or { abstract_base }
		if target := c.type_aliases[alias] {
			if target != abstract_base && target.trim_left('&') in c.structs {
				converted.name = '&'.repeat(pointer_depth) + target
				abstract_base = target.trim_left('&')
				pointer_depth += target.len - abstract_base.len
			}
		}
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
	if !c.is_cpp {
		for tag, v_name in c.record_tag_v_names {
			converted.name = replace_c_ref_token(converted.name, tag, v_name)
		}
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
			if c_type := c.arithmetic_typedef_c_types[converted_token] {
				// Template specializations are named after Clang's spelling of
				// their arguments (`idList<unsigned int>`), not after V types.
				out.write_string(c_type)
			} else if resolved_token != converted_token {
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
	return 'union C2vNilInterfaceStorage[T] {\nmut:\n\traw [2]voidptr\n\tvalue T\n}\n\nstruct C2vInterfaceHeader {\n\tobject voidptr\n}\n\nfn c2v_nil_interface[T]() T {\n\tstorage := C2vNilInterfaceStorage[T]{}\n\treturn unsafe { storage.value }\n}\n\nfn c2v_interface_object[T](value T) voidptr {\n\treturn unsafe { (&C2vInterfaceHeader(&value)).object }\n}\n\nfn c2v_interface_is_nil[T](value T) bool {\n\treturn c2v_interface_object(value) == unsafe { nil }\n}\n\nfn c2v_interface_ref_object(value voidptr) voidptr {\n\treturn unsafe { (&C2vInterfaceHeader(value)).object }\n}\n\n' + '// Reinterprets an address as `&T`. Casting a raw pointer to `&Interface`\n' + '// would instead box the pointer into a new interface value.\n' + 'union C2vPointerStorage[T] {\nmut:\n\traw   voidptr\n\tvalue &T\n}\n\n' + 'fn c2v_pointer_as[T](raw voidptr) &T {\n\tmut storage := C2vPointerStorage[T]{\n\t\traw: raw\n\t}\n\treturn unsafe { storage.value }\n}\n\n' + 'fn c2v_pointer_at[T](base &T, index isize) &T {\n\treturn c2v_pointer_as[T](unsafe { voidptr(usize(voidptr(base)) + usize(index) * usize(sizeof(T))) })\n}\n\n'
}

fn (mut c C2V) ensure_cpp_interface_runtime_helpers() {
	if c.is_dir {
		// Directory translation writes them to 0_globals.v.
		c.uses_cpp_interface_runtime = true
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

// typedef_names_tag reports whether `typedef` (the declaration after `tag` in the
// AST) is `typedef struct tag {...} name;`, which names the record or enum. A
// typedef that merely follows a definition, such as a function pointer typedef
// after `struct A {...};`, does not.
fn typedef_names_tag(typedef &Node, tag &Node) bool {
	if node_contains_owned_tag_id(typedef, tag.id) {
		return true
	}
	// Without an owned tag (older Clang JSON), accept an anonymous tag or a
	// typedef whose type spells the tag.
	if tag.name == '' {
		return true
	}
	underlying := typedef.ast_type.qualified.trim_space()
	return underlying == tag.name || underlying.all_after_last(' ') == tag.name
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

// float_conversion_intermediate_type is the integer type through which a
// conversion of a floating value to the narrower integer type `to_type` is
// translated. C leaves converting a value outside `to_type`'s range undefined,
// and optimized C relies on it (`b = (byte)(d * 255)` then drops a following
// `if (b > 255)` clamp); converting to a wider type and truncating the integer
// is what unoptimized code and common hardware do.
fn float_conversion_intermediate_type(to_type string) string {
	return match to_type {
		'i8', 'u8', 'i16', 'u16' { 'i32' }
		'u32' { 'i64' }
		else { '' }
	}
}

// map_has_value reports whether `value` is one of the values of `m`, without
// copying them into an array like `m.values()`.
fn map_has_value(m map[string]string, value string) bool {
	for _, v in m {
		if v == value {
			return true
		}
	}
	return false
}

// is_c_arithmetic_type_spelling reports whether a C type is spelled with
// arithmetic type keywords only (`unsigned int`, `double`).
fn is_c_arithmetic_type_spelling(typ string) bool {
	words := typ.trim_space().split(' ').filter(it != '')
	return words.len > 0 && words.all(it in ['unsigned', 'signed', 'char', 'short', 'int', 'long',
		'float', 'double', 'bool', '_Bool'])
}

fn collect_owned_tag_ids(node &Node, mut ids []string) {
	if node.owned_tag_decl.id != '' {
		ids << node.owned_tag_decl.id
	}
	for i in 0 .. node.inner.len {
		collect_owned_tag_ids(&node.inner[i], mut ids)
	}
}

// index_seen_declarations indexes the declarations of the translated file
// that lookups by tag or record name need, which would otherwise scan every
// declaration of the file for each record and enum.
fn (mut c C2V) index_seen_declarations() {
	c.typedef_names_by_tag_id = {}
	c.pointer_typedef_tag_ids = {}
	c.record_decls_by_name = {}
	c.cpp_record_static_methods = {}
	for i in 0 .. c.tree.inner.len {
		record := &c.tree.inner[i]
		if !record.kindof(.cxx_record_decl) {
			continue
		}
		for j in 0 .. record.inner.len {
			declaration := &record.inner[j]
			if declaration.kindof(.cxx_method_decl) && declaration.class_modifier == 'static'
				&& declaration.mangled_name != '' {
				c.cpp_record_static_methods[declaration.mangled_name] = true
			}
		}
	}
	for id, declaration in c.callback_seen_ids {
		if declaration.kindof(.typedef_decl) {
			mut tag_ids := []string{}
			collect_owned_tag_ids(declaration, mut tag_ids)
			is_pointer := declaration.ast_type.qualified.trim_space().ends_with(' *')
			for tag_id in tag_ids {
				if declaration.name != '' && tag_id !in c.typedef_names_by_tag_id {
					c.typedef_names_by_tag_id[tag_id] = declaration.name
				}
				if is_pointer {
					c.pointer_typedef_tag_ids[tag_id] = true
				}
			}
		} else if (declaration.kindof(.record_decl) || declaration.kindof(.cxx_record_decl))
			&& declaration.name != '' {
			c.record_decls_by_name[declaration.name] << id
		}
	}
}

fn (c &C2V) typedef_name_for_tag_id(tag_id string) string {
	if tag_id == '' {
		return ''
	}
	return c.typedef_names_by_tag_id[tag_id] or { '' }
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
				qualified := child.ast_type.qualified.trim_space()
				candidate := qualified.all_after_last('::').trim_space()
				if candidate != '' && !candidate.contains_any_substr(['(', ')', ' ', '<', '>']) {
					c_enum_name = candidate
					if c.is_cpp && c.nested_enum_owner != ''
						&& qualified == '${c.nested_enum_owner}::${candidate}' {
						// An enum nested in a class is distinct from an equally named one
						// elsewhere (`idMultiplayerGame::gameState_t`).
						c_enum_name = qualified.replace('::', '_')
						c.cpp_nested_enums[qualified] = c_enum_name
						// An empty entry marks a short name nested in several classes.
						c.cpp_nested_enum_short_names[candidate] = if existing := c.cpp_nested_enum_short_names[candidate] {
							if existing == c_enum_name { existing } else { '' }
						} else {
							c_enum_name
						}
					}
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
		mut shadowed_v_enum_name := ''
		if c_enum_name in c.enums {
			mut known_vals := c.enum_vals[c_enum_name]
			constants := node.inner.filter(it.kind == .enum_constant_decl && it.name != '').map(it.name)
			if !c.is_cpp && constants.any(it !in known_vals) {
				// Another enum with this tag (C scopes tags to a block and a
				// translation unit): later references in this file mean it.
				shadowed_v_enum_name = c.enums[c_enum_name]
				file_token :=
					sanitize_type_token(c.cur_file.all_after_last('/').all_before_last('.'))
				mut local_name := '${c_enum_name}_${file_token}'
				mut n := 2
				for (local_name in c.enums) {
					local_name = '${c_enum_name}_${file_token}${n}'
					n++
				}
				c_enum_name = local_name
			} else {
				for name in constants {
					if name !in known_vals {
						known_vals << name
					}
				}
				c.enum_vals[c_enum_name] = known_vals
				return
			}
		}
		v_enum_name =
			c.add_struct_name(mut c.enums, c_enum_name) // .capitalize().replace('Enum ', '')
		if shadowed_v_enum_name != '' {
			c.file_type_alias_names[shadowed_v_enum_name] = v_enum_name
		}
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
			mut const_expr := child.inner[0]
			// Clang evaluates C++ enumerator values (`ConstantExpr`), even from
			// `const` variables (`(1 << NUM_BITS) - 1`).
			for const_expr.kindof(.implicit_cast_expr) && const_expr.inner.len == 1 {
				const_expr = const_expr.inner[0]
			}
			ok, value := c.eval_const_numeric_expr(const_expr)
			if const_expr.kind == .constant_expr && const_expr.value.to_str() != '' {
				current_val = const_expr.value.to_str().i64()
				got_explicit_val = true
			} else if ok {
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
		i:        i64(f)
		f:        f
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
	return type_name in ['int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
		'usize']
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
	if is_function_body && c.gc_thread_entry_body {
		// Foreign code can call this function on a thread it created.
		c.gc_thread_entry_body = false
		c.uses_gc_thread_registration = true
		c.genln('c2v_gc_register_thread()')
	}
	// Each CompoundStmt's child is a statement
	c.block_statements(mut compound_stmt)
	last_statement := last_c_statement(compound_stmt)
	if is_function_body && c.cur_fn_ret_type != '' && compound_stmt.inner.len > 0 {
		if is_unconditional_c_for(last_statement) || c.is_unconditional_c_while(last_statement) {
			c.genln("panic('unreachable after C for (;;)')")
		} else if !c.is_cpp && !c.inside_main && !c_statement_returns(last_statement) {
			// C lets a non-void function end without `return` (and V cannot see
			// that a switch whose arms jump to each other always returns).
			c.genln('return ${c.v_zero_value(c.cur_fn_ret_type)}')
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
	c.block_statements(mut compound_stmt)
	c.declared_local_vars = outer_declared
	c.declared_local_var_types = outer_declared_types.clone()
}

// V does not support a standalone lexical block as a statement. Flatten C/C++
// blocks that are not attached to control flow and keep their declarations in
// the translated V scope. reserve_local_decl_v_name() will rename a later C
// declaration when two source blocks reuse the same identifier.
fn (mut c C2V) statements_flattened(mut compound_stmt Node) {
	c.gen_comment(compound_stmt)
	c.block_statements(mut compound_stmt)
}

// block_statements translates the statements of a C block. A statement after
// an unconditional jump is dead code (`return x; return 0;`), which V rejects
// as unreachable: it is left out, unless a label makes it reachable (or it
// declares a variable, which code after a label can use).
fn (mut c C2V) block_statements(mut compound_stmt Node) {
	mut unreachable := false
	for i, _ in compound_stmt.inner {
		statement := compound_stmt.inner[i]
		if unreachable && !statement.kindof(.text_comment) && !statement.kindof(.decl_stmt)
			&& !node_contains_jump_target(statement) {
			continue
		}
		c.statement(mut compound_stmt.inner[i])
		c.blank_line_after_switch(compound_stmt, i)
		if !statement.kindof(.text_comment) {
			unreachable = c_statement_jumps(statement)
		}
	}
}

// last_c_statement returns the last statement of a block that is not a
// comment (comments are nodes of the block, see insert_comment_node) or an
// empty statement (`return rc;;` from a macro ending with `return rc;`), or
// an empty node.
fn last_c_statement(block Node) Node {
	for i := block.inner.len - 1; i >= 0; i-- {
		if !block.inner[i].kindof(.text_comment) && !block.inner[i].kindof(.null_stmt) {
			return block.inner[i]
		}
	}
	return Node{
		kind: .text_comment
	}
}

// c_statement_jumps reports whether control never continues after `node`.
fn c_statement_jumps(node Node) bool {
	if node.kindof(.return_stmt) || node.kindof(.break_stmt) || node.kindof(.continue_stmt)
		|| node.kindof(.goto_stmt) {
		return true
	}
	if node.kindof(.compound_stmt) {
		last := last_c_statement(node)
		return !last.kindof(.text_comment) && c_statement_jumps(last)
	}
	return false
}

// node_contains_jump_target reports whether `node` contains a label or a
// switch case, which make it reachable after a jump.
fn node_contains_jump_target(node Node) bool {
	if node.kindof(.label_stmt) || node.kindof(.case_stmt) || node.kindof(.default_stmt) {
		return true
	}
	return node.inner.any(node_contains_jump_target(it))
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
	old_value_context_depth := c.value_context_depth
	// An initializer is a value: `T *a = b = c;` assigns `b` as an expression.
	c.value_context_depth = if child.kindof(.decl_stmt) { 1 } else { 0 }
	defer {
		c.value_context_depth = old_value_context_depth
	}
	if child.kindof(.null_stmt) {
		// An empty statement (`;`, or a macro such as `testcase(X)` that expands
		// to nothing) does nothing.
	} else if child.kindof(.decl_stmt) {
		c.var_decl(mut child)
		c.genln('')
	} else if child.kindof(.return_stmt) {
		c.return_st(mut child)
		c.genln('')
	} else if child.kindof(.if_stmt) {
		c.if_statement(mut child)
	} else if child.kindof(.while_stmt) {
		// A `break` in the loop leaves the loop, not an enclosing switch.
		old_inside_switch := c.inside_switch
		c.inside_switch = 0
		c.while_st(mut child)
		c.inside_switch = old_inside_switch
	} else if child.kindof(.for_stmt) {
		// A `break` in the loop leaves the loop, not an enclosing switch.
		old_inside_switch := c.inside_switch
		c.inside_switch = 0
		c.for_st(mut child)
		c.inside_switch = old_inside_switch
	} else if child.kindof(.do_stmt) {
		// A `break` in the loop leaves the loop, not an enclosing switch.
		old_inside_switch := c.inside_switch
		c.inside_switch = 0
		c.do_st(mut child)
		c.inside_switch = old_inside_switch
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
		label := v_label_name(child.name)
		c.labels[child.declaration_id] = label
		// c.genln('// RRRREG ${child.name} id=${child.declaration_id}')
		c.genln('${label}: ')
		c.statements_no_rcbr(mut child)
	} else if child.kindof(.cxx_for_range_stmt) {
		// C++
		old_inside_switch := c.inside_switch
		c.inside_switch = 0
		c.for_range(child)
		c.inside_switch = old_inside_switch
	} else {
		if is_noop_zero_expression(child) {
			return
		}
		if !c.is_cpp && c.gen_void_conditional_stmt(unwrap_unused_value_expr(child)) {
			return
		}
		// The value of an expression statement is unused (`++i;` is `i++`).
		old_unused_value_expr_id := c.unused_value_expr_id
		c.unused_value_expr_id = unwrap_unused_value_expr(child).id
		c.expr(child)
		c.unused_value_expr_id = old_unused_value_expr_id
		c.genln('')
	}
}

// is_constant_index_within reports whether an array index is an integer literal
// below `length`.
fn is_constant_index_within(index Node, length int) bool {
	mut current := index
	for current.inner.len == 1 && (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
		current = current.inner[0]
	}
	return current.kindof(.integer_literal) && current.value.to_str().int() < length
}

// collect_variable_size_fields records the trailing array fields of zero or one
// element (or no size): C's variable sized record tail (`int edges[1];`), which
// is allocated with room for more elements.
fn collect_variable_size_fields(nodes []Node, mut fields map[string]bool) {
	for node in nodes {
		if node.kindof(.record_decl) || node.kindof(.cxx_record_decl)
			|| node.kind_str in ['RecordDecl', 'CXXRecordDecl', 'ClassTemplateSpecializationDecl'] {
			mut last := -1
			for i, child in node.inner {
				if child.kindof(.field_decl) || child.kind_str == 'FieldDecl' {
					last = i
				}
			}
			if last >= 0 {
				t := node.inner[last].ast_type.qualified.trim_space()
				if node.inner[last].id != '' && (t.ends_with('[1]') || t.ends_with('[0]')
					|| t.ends_with('[]')) {
					fields[node.inner[last].id] = true
				}
			}
		}
		if node.inner.len > 0 {
			collect_variable_size_fields(node.inner, mut fields)
		}
	}
}

// gen_void_conditional_stmt emits the statement `c ? (void)f() : (void)0;` as
// an `if` statement. Returns false for other expressions.
fn (mut c C2V) gen_void_conditional_stmt(node Node) bool {
	if !node.kindof(.conditional_operator) || node.inner.len != 3
		|| node.ast_type.qualified != 'void' {
		return false
	}
	mut condition := clone_cpp_operator_node(&node.inner[0])
	c.gen('if ')
	c.gen_bool(&condition)
	c.genln(' {')
	for i in 1 .. 3 {
		if i == 2 {
			c.genln('} else {')
		}
		branch := unwrap_unused_value_expr(node.inner[i])
		if c.gen_void_conditional_stmt(branch) || is_noop_zero_expression(branch)
			|| !has_side_effects(branch) {
			continue
		}
		old_unused_value_expr_id := c.unused_value_expr_id
		c.unused_value_expr_id = branch.id
		mut statement := clone_cpp_operator_node(&branch)
		c.expr(statement)
		c.unused_value_expr_id = old_unused_value_expr_id
		c.genln('')
	}
	c.genln('}')
	return true
}

// has_side_effects reports whether evaluating the C expression `node` calls a
// function or modifies an object.
fn has_side_effects(node Node) bool {
	if node.kindof(.call_expr) || node.kindof(.compound_assign_operator)
		|| (node.kindof(.binary_operator) && node.opcode == '=')
		|| (node.kindof(.unary_operator) && node.opcode in ['++', '--']) {
		return true
	}
	return node.inner.any(has_side_effects(it))
}

// unwrap_unused_value_expr returns the expression an expression statement
// evaluates for its effect alone.
fn unwrap_unused_value_expr(node Node) Node {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| current.kindof(.expr_with_cleanups)
		|| ((current.kindof(.c_style_cast_expr) || current.kindof(.cxx_static_cast_expr))
			&& current.cast_kind == 'ToVoid')) {
		current = current.inner[0]
	}
	return current
}

// C library functions that a failed `assert()` calls.
const c_assert_failure_functions = ['__assert_rtn', '__assert_fail', '__assert', '_assert', '__assert2',
	'_wassert']

// is_c_assert_expansion reports whether `node` is the expansion of C's
// `assert(e)`: `(cond ? __assert_fail(...) : (void)0)` (or the reverse).
fn is_c_assert_expansion(node Node) bool {
	mut current := node
	for current.inner.len == 1 && (current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr)
		|| current.kindof(.c_style_cast_expr)) {
		current = current.inner[0]
	}
	if !current.kindof(.conditional_operator) || current.inner.len != 3 {
		return false
	}
	for branch in current.inner[1..] {
		mut call := branch
		for call.inner.len == 1 && (call.kindof(.paren_expr) || call.kindof(.implicit_cast_expr)
			|| call.kindof(.c_style_cast_expr)) {
			call = call.inner[0]
		}
		if call.kindof(.call_expr) && call.inner.len > 0 {
			mut callee := call.inner[0]
			for callee.inner.len == 1 && callee.kindof(.implicit_cast_expr) {
				callee = callee.inner[0]
			}
			if callee.kindof(.decl_ref_expr)
				&& callee.ref_declaration.name in c_assert_failure_functions {
				return true
			}
		}
	}
	return false
}

fn is_noop_zero_expression(node Node) bool {
	if is_c_assert_expansion(node) {
		// c2v leaves `assert()` out.
		return true
	}
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

// is_char_literal_vs_i8 reports whether `literal` is a character literal and
// `other` a C `char` value (V `i8`), which V cannot compare with a rune.
fn (c &C2V) is_char_literal_vs_i8(literal Node, other Node) bool {
	if !unwrap_condition_atom(literal).kindof(.character_literal) {
		return false
	}
	mut value := other
	for value.inner.len == 1 && (value.kindof(.paren_expr)
		|| (value.kindof(.implicit_cast_expr) && value.cast_kind == 'IntegralCast')) {
		value = value.inner[0]
	}
	return c.resolve_type_alias(c.convert_type(node_effective_type_name(value)).name) == 'i8'
}

// sizeof_type_operand spells a V type for `sizeof`: V cannot parse a function
// type there, and a function pointer has the size of any pointer.
fn sizeof_type_operand(v_type string) string {
	mut dims := ''
	mut elem := v_type
	for elem.starts_with('[') {
		close := elem.index(']') or { break }
		dims += elem[..close + 1]
		elem = elem[close + 1..]
	}
	return if elem.starts_with('fn ') || elem.starts_with('fn(') {
		dims + 'voidptr'
	} else {
		v_type
	}
}

// v_label_name keeps a C label that is spelled like a V keyword (`shared`)
// from being parsed as one.
fn v_label_name(name string) string {
	return if name in v_keywords || name in v_reserved_words { name + '_' } else { name }
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

// starts_with_c_call reports whether V code starts with a call `C.name(`.
fn starts_with_c_call(code string) bool {
	if !code.starts_with('C.') {
		return false
	}
	mut i := 2
	for i < code.len && (code[i].is_letter() || code[i].is_digit() || code[i] == `_`) {
		i++
	}
	return i > 2 && i < code.len && code[i] == `(`
}

fn is_zero_int_literal(node Node) bool {
	mut current := node
	for (current.kindof(.paren_expr) || current.kindof(.implicit_cast_expr))
		&& current.inner.len == 1 {
		current = current.inner[0]
	}
	return current.kindof(.integer_literal) && current.value.to_str() == '0'
}

fn (mut c C2V) return_st(mut node Node) {
	old_inside_return_stmt := c.inside_return_stmt
	c.inside_return_stmt = true
	defer {
		c.inside_return_stmt = old_inside_return_stmt
	}
	// V's `main` returns nothing: the exit status of C's `return status;` has to
	// be passed to `exit`. A plain `return 0` keeps V's `return`.
	if c.inside_main && node.inner.len > 0 && (c.is_dir || !is_zero_int_literal(node.inner[0])) {
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
		if c.is_cpp && c.cur_fn_ret_type == '' && expr.ast_type.qualified == 'void' {
			// C++ can return a void expression from a void function; V evaluates
			// it as a statement first.
			c.expr(expr)
			c.genln('')
			c.gen('return')
			return
		}
		assignment := unwrap_condition_atom(expr)
		if assignment.kindof(.binary_operator) && assignment.opcode == '='
			&& assignment.inner.len >= 2 {
			mut lhs := assignment.inner[0]
			mut rhs := assignment.inner[1]
			// (Generating a node consumes its children: the returned value is a
			// copy of the target.)
			returned := clone_cpp_operator_node(&lhs)
			c.gen_simple_assign(mut lhs, mut rhs)
			c.genln('')
			c.gen('return ')
			c.expr(returned)
			return
		}
		if c.cur_fn_variant_return && !is_c_null_pointer_constant(expr) {
			c.gen('return unsafe { ${c.cur_fn_ret_type}(voidptr(')
			c.expr(expr)
			c.gen(')) }')
			return
		}
		if !c.is_cpp && is_c_null_pointer_constant(expr) {
			resolved_ret := c.resolve_type_alias(c.cur_fn_ret_type)
			if resolved_ret.starts_with('fn ') {
				c.gen('return ${c.typed_null_function_pointer(c.cur_fn_ret_type)}')
				return
			}
			if resolved_ret.starts_with('&') || resolved_ret == 'voidptr' {
				c.gen('return unsafe { nil }')
				return
			}
		}
		if !c.is_cpp && (is_c_truth_value(expr) || c.is_v_enum_value(expr))
			&& c.resolve_type_alias(c.cur_fn_ret_type) in v_integer_type_names {
			// C's comparison result, like an enum constant, is an int.
			c.gen('return ${c.cur_fn_ret_type}(')
			c.expr(expr)
			c.gen(')')
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
		needs_int_cast := c.cur_fn_ret_type in ['int', 'i32']
			&& (c.is_comparison_expr(expr) || node_references_function(expr, 'ftell'))
		numeric_types := ['i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
			'usize', 'f32', 'f64']
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
			c.cur_fn_ret_type
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
		} else if c.is_cpp && c.cur_fn_ret_type.starts_with('&')
			&& cpp_reinterpreted_object(&expr) != none {
			// A reference to the object reinterpret_cast views at another address.
			operand := cpp_reinterpreted_object(&expr) or { bad_node }
			c.gen('unsafe { ${c.cur_fn_ret_type}(voidptr(')
			old_inside_unsafe := c.inside_unsafe
			c.inside_unsafe = true
			c.gen_address_in_cast(operand)
			c.inside_unsafe = old_inside_unsafe
			c.gen(')) }')
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
			} else if c.is_cpp && target.kindof(.decl_ref_expr)
				&& target.ref_declaration.ast_type.qualified.trim_space().ends_with('&') {
				// A reference variable or parameter already holds the address it
				// refers to.
				if reference_name := c.cpp_primitive_reference_v_name(&target) {
					c.gen(reference_name)
				} else {
					c.expr(target)
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
			} else if c.is_cpp && c.cpp_primitive_reference_operator_source(&expr) != none {
				// Returning the reference itself; the pointer is not read here.
				old_inside_reference_lvalue := c.inside_cpp_reference_lvalue
				c.inside_cpp_reference_lvalue = true
				c.expr(expr)
				c.inside_cpp_reference_lvalue = old_inside_reference_lvalue
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

fn is_assignment_expr(node Node) bool {
	return (node.kindof(.binary_operator) && node.opcode == '=')
		|| node.kindof(.compound_assign_operator)
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
		} else if !c.is_cpp && expr.kindof(.compound_assign_operator) {
			// V's loop header only declares or assigns: run `i += 2` first.
			c.expr(expr)
			c.genln('')
			c.gen('for ')
			use_while_style = true
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
			if condition_pre.len == 0 {
				// Nothing had to move out of the condition (an assignment after `&&`
				// stays inline): it is the loop condition itself.
				c.gen(condition_output)
				condition_output = ''
			} else {
				c.gen('true')
			}
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
			// Collect all comma-separated expressions. The rest move to the
			// body end, which runs before V's post clause, so the first one may
			// only stay there when the order cannot matter; otherwise all move
			// (`p = &n->next, n = *p` must read the new `p`).
			for comma.kindof(.binary_operator) && comma.opcode == ',' && comma.inner.len >= 2 {
				extra_post_exprs << unsafe { &comma.inner[1] }
				comma = unsafe { &comma.inner[0] }
			}
			if for_post_exprs_are_independent(comma, extra_post_exprs) {
				c.for_clause_root_id = comma.id
				c.inside_for_post = true
				c.expr(comma)
				c.inside_for_post = false
			} else {
				extra_post_exprs << comma
			}
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

// cpp_reference_binding_is_returned_reference reports whether a C++ reference
// is bound to the reference a call or overloaded operator returns.
fn cpp_reference_binding_is_returned_reference(init Node) bool {
	bound := unwrap_cpp_reference_binding(init)
	return bound.value_category == 'lvalue' && (bound.kindof(.call_expr)
		|| bound.kindof(.cxx_member_call_expr) || bound.kindof(.cxx_operator_call_expr))
}

// cpp_reference_binding_is_reference_variable reports whether a C++ reference is
// bound to another reference variable or parameter, which holds the address.
fn cpp_reference_binding_is_reference_variable(init Node) bool {
	bound := unwrap_cpp_reference_binding(init)
	return bound.kindof(.decl_ref_expr) && bound.ref_declaration.kind in [.var_decl, .parm_var_decl]
		&& bound.ref_declaration.ast_type.qualified.trim_space().ends_with('&')
}

// is_primitive_reference_v_type reports whether a V pointer type represents a
// C++ reference to a primitive value, including through a typedef.
fn (c &C2V) is_primitive_reference_v_type(v_type string) bool {
	t := v_type.trim_space()
	if !t.starts_with('&') {
		return false
	}
	base := normalize_v_ptr_type(t)
	return base in v_primitive_type_names || c.resolve_type_alias(base) in v_primitive_type_names
		|| base in c.enum_vals || c.is_known_enum_v_type(base)
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
	if c.global_constructor_order.len == 0 && !c.uses_gc_thread_registration {
		return ''
	}
	mut out := strings.new_builder(1024)
	out.writeln('fn init() {')
	if c.uses_gc_thread_registration {
		// Before any foreign thread can call back into translated code.
		out.writeln('\tc2v_gc_allow_threads()')
	}
	for name in c.global_constructor_order {
		call := c.global_constructor_calls[name] or { continue }
		// (Concatenation: the pinned V miscompiles interpolation in this call.)
		out.writeln('\t' + replace_defined_global_refs_in_text(call, replacements))
	}
	out.writeln('}')
	out.writeln('')
	return out.str()
}

// for_post_exprs_are_independent reports whether the first expression of a
// comma-separated for-loop post clause may run after the others: they refer to
// disjoint variables and none of them reaches memory through pointers, members
// or calls.
fn for_post_exprs_are_independent(first &Node, rest []&Node) bool {
	mut first_refs := map[string]bool{}
	if !collect_plain_decl_refs(first, mut first_refs) {
		return false
	}
	for expr in rest {
		mut refs := map[string]bool{}
		if !collect_plain_decl_refs(expr, mut refs) {
			return false
		}
		for name, _ in refs {
			if name in first_refs {
				return false
			}
		}
	}
	return true
}

// collect_plain_decl_refs gathers the variables `node` refers to. It returns
// false when `node` may also touch other memory.
fn collect_plain_decl_refs(node &Node, mut refs map[string]bool) bool {
	if node.kindof(.decl_ref_expr) {
		refs[if node.ref_declaration.id != '' { node.ref_declaration.id } else { node.name }] = true
		return true
	}
	if node.kindof(.unary_operator) && node.opcode in ['*', '&'] {
		return false
	}
	if !(node.kindof(.unary_operator) || node.kindof(.binary_operator)
		|| node.kindof(.compound_assign_operator) || node.kindof(.implicit_cast_expr)
		|| node.kindof(.c_style_cast_expr) || node.kindof(.paren_expr)
		|| node.kindof(.integer_literal) || node.kindof(.floating_literal)
		|| node.kindof(.character_literal) || node.kindof(.cxx_bool_literal_expr)) {
		return false
	}
	for child in node.inner {
		if !collect_plain_decl_refs(&child, mut refs) {
			return false
		}
	}
	return true
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

// leading_feature_test_macros returns the macros (`NAME=VALUE`) with a name
// that starts with `_` that C source `src` defines unconditionally before its
// first `#include`: feature test macros such as `_GNU_SOURCE` or
// `__STDC_WANT_LIB_EXT1__`.
fn leading_feature_test_macros(src string) []string {
	mut defines := []string{}
	mut depth := 0
	mut in_comment := false
	for raw_line in src.split_into_lines() {
		mut line := raw_line.trim_space()
		if in_comment {
			if !line.contains('*/') {
				continue
			}
			in_comment = false
			line = line.all_after('*/').trim_space()
		}
		if line.starts_with('/*') && !line.contains('*/') {
			in_comment = true
			continue
		}
		if !line.starts_with('#') {
			continue
		}
		directive := line[1..].trim_space()
		if directive.starts_with('include') {
			break
		}
		if directive.starts_with('if') {
			depth++
		} else if directive.starts_with('endif') {
			depth--
		} else if depth == 0 && directive.starts_with('define') {
			rest := directive['define'.len..].trim_space()
			name := rest.all_before(' ').all_before('\t')
			if !name.starts_with('_') || name.contains('(') {
				continue
			}
			mut value := rest[name.len..].trim_space()
			if value.contains('/*') {
				value = value.all_before('/*').trim_space()
			}
			if value.contains('//') {
				value = value.all_before('//').trim_space()
			}
			defines << if value == '' { name } else { '${name}=${value}' }
		}
	}
	return defines
}

// c_record_field_v_name is the V name of the field `raw` of a translated C
// record, as record_decl declares it: a field spelled like a C library
// function (`free`) gets a `_` suffix, so that `p->free(x)` does not call V's
// `free()` method.
fn c_record_field_v_name(raw string) string {
	filtered := filter_name(raw, false)
	return if filtered.starts_with('C.') { filtered[2..] + '_' } else { filtered }
}

// is_v_enum_value reports whether `node` names a constant of a C enum that is
// a V enum (the constants of an anonymous C enum are V constants of type int).
fn (c &C2V) is_v_enum_value(node Node) bool {
	if !is_enum_ref_expr(node) {
		return false
	}
	mut current := node
	for current.inner.len > 0 && !current.kindof(.decl_ref_expr) {
		current = current.inner[0]
	}
	return c.enum_val_to_enum_name(current.ref_declaration.name) != ''
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

// is_untyped_v_integer_expr reports whether the translation of `node` is an
// expression of integer (or character) literals only, whose type V infers as
// `int` (which has the width of a pointer, unlike C's `int`).
fn is_untyped_v_integer_expr(node Node) bool {
	if node.kindof(.integer_literal) || node.kindof(.character_literal) {
		return true
	}
	if node.inner.len == 0 {
		return false
	}
	if node.kindof(.paren_expr) || node.kindof(.constant_expr)
		|| (node.kindof(.implicit_cast_expr) && node.cast_kind in ['IntegralCast', 'NoOp']) {
		return is_untyped_v_integer_expr(node.inner[0])
	}
	if node.kindof(.unary_operator) && node.opcode in ['-', '+', '~'] {
		return is_untyped_v_integer_expr(node.inner[0])
	}
	if node.kindof(.binary_operator) && node.inner.len == 2
		&& node.opcode in ['+', '-', '*', '/', '%', '&', '|', '^', '<<', '>>'] {
		return is_untyped_v_integer_expr(node.inner[0]) && is_untyped_v_integer_expr(node.inner[1])
	}
	if node.kindof(.conditional_operator) && node.inner.len == 3 {
		return is_untyped_v_integer_expr(node.inner[1]) && is_untyped_v_integer_expr(node.inner[2])
	}
	return false
}

fn is_v_small_integer_type(type_name string) bool {
	return type_name in ['i8', 'u8', 'i16', 'u16', 'bool']
}

fn (c &C2V) shift_lhs_needs_int_cast(node Node) bool {
	promoted_type := c.convert_type(node.ast_type.qualified).name
	unwrapped := c.unwrap_expr_for_deref_check(node)
	source_type := c.convert_type(unwrapped.ast_type.qualified).name
	return promoted_type in ['int', 'i32'] && is_v_small_integer_type(source_type)
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
			&& last.inner[0].kindof(.decl_ref_expr)
			&& !is_assignment_expr(unwrap_condition_atom(last.inner[1])) {
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
		if is_cpp_object_this_expr(&cur) {
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
	if c.is_cpp && is_cpp_object_this_expr(&cur) {
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
				// (A name C code cannot use: `*__error() = e` is `errno = e`.)
				c.gen('c2v_target := ')
				c.expr(ptr_expr)
				c.genln('')
				c.gen('unsafe { *c2v_target')
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
	resolved_lhs_type := c.resolve_type_alias(lhs_v_type)
	if c.is_v_abstract_interface_type(lhs_v_type) && is_cpp_null_pointer_expression(second_expr) {
		c.gen(c.v_abstract_interface_nil_literal(lhs_v_type))
	} else if !c.is_cpp && is_c_null_pointer_constant(second_expr)
		&& resolved_lhs_type.starts_with('fn ') {
		// `x_busy = 0;` for a function pointer.
		c.gen(c.typed_null_function_pointer(lhs_v_type))
	} else if !c.is_cpp && is_c_null_pointer_constant(second_expr)
		&& (resolved_lhs_type.starts_with('&') || resolved_lhs_type == 'voidptr') {
		// `*pp = 0;`: V assigns no integer to a pointer.
		c.gen(if c.inside_unsafe { 'nil' } else { 'unsafe { nil }' })
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
	// C's `continue` in a do-while body jumps to the condition, which the V loop
	// evaluates at the end of its body.
	c.continue_label_count++
	continue_label := 'c2v_do_next_${c.continue_label_count}'
	c.continue_labels << continue_label
	defer {
		c.continue_labels.delete_last()
	}
	c.genln('for {')
	mut child := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	last_stmt := if child.kindof(.compound_stmt) { last_c_statement(child) } else { child }
	if child.kindof(.compound_stmt) {
		c.statements_no_rcbr(mut child)
	} else {
		// `do x = f(); while (...);`: a single statement body.
		c.statement(mut child)
	}
	expr := node.try_get_next_child() or {
		println(add_place_data_to_error(err))
		bad_node
	}
	if (last_stmt.kindof(.return_stmt) || last_stmt.kindof(.break_stmt))
		&& continue_label !in c.used_continue_labels {
		// The body never reaches the condition (`do { ...; return x; } while (0)`),
		// and V rejects unreachable code.
		c.genln('}')
		return
	}
	c.gen_continue_label(continue_label)
	c.genln('// while()')
	is_constant, constant_value := c.eval_const_numeric_expr(expr)
	if is_constant {
		if constant_value.as_i64() == 0 {
			c.genln('break')
		}
	} else if expr_needs_pre_cond(expr) {
		cond_output, pre_cond := c.render_condition_with_pre_cond(expr)
		for stmt in pre_cond {
			c.genln(stmt)
		}
		c.genln('if !(${cond_output}) {')
		c.genln('\tbreak')
		c.genln('}')
	} else {
		c.gen('if !(')
		c.gen_bool(expr)
		c.genln(') {')
		c.genln('\tbreak')
		c.genln('}')
	}
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

// c_statement_returns reports whether V sees that `node` always leaves the
// function: a `return`, or an if/else whose branches all do.
fn c_statement_returns(node Node) bool {
	if node.kindof(.return_stmt) {
		return true
	}
	if (node.kindof(.compound_stmt) || node.kindof(.label_stmt)) && node.inner.len > 0 {
		return c_statement_returns(last_c_statement(node))
	}
	if node.kindof(.if_stmt) && node.inner.len >= 3 {
		return c_statement_returns(node.inner[node.inner.len - 2])
			&& c_statement_returns(node.inner.last())
	}
	return false
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
	if node.kindof(.label_stmt) && node.inner.len > 0 {
		return switch_statement_falls_through(node.inner.last())
	}
	// `if (a) break; else goto out;` leaves the arm on both paths.
	if node.kindof(.if_stmt) && node.inner.len >= 3 {
		return switch_statement_falls_through(node.inner[node.inner.len - 2])
			|| switch_statement_falls_through(node.inner.last())
	}
	return true
}

// switch_fallthrough_targets returns the indexes of the case and default labels
// in a switch body that the statements before them fall through to.
fn switch_fallthrough_targets(comp_stmt &Node) []int {
	mut targets := []int{}
	mut arm_last := Node{}
	mut in_arm := false
	for i, child in comp_stmt.inner {
		if child.kindof(.case_stmt) || child.kindof(.default_stmt) {
			if in_arm && switch_statement_falls_through(arm_last) {
				targets << i
			}
			arm_last = switch_labeled_statement(child) or { Node{} }
			in_arm = true
		} else if in_arm {
			arm_last = child
		}
	}
	return targets
}

// switch_arm_trailing_break_ids returns the `break`s that end the arms of a
// switch body (possibly inside the arm's last block): V's match arms end there.
fn switch_arm_trailing_break_ids(comp_stmt &Node) []string {
	mut ids := []string{}
	mut arm_last := Node{}
	mut in_arm := false
	for child in comp_stmt.inner {
		if child.kindof(.case_stmt) || child.kindof(.default_stmt) {
			if in_arm {
				ids << switch_trailing_break_id(arm_last)
			}
			arm_last = switch_labeled_statement(child) or { Node{} }
			in_arm = true
		} else if in_arm {
			arm_last = child
		}
	}
	if in_arm {
		ids << switch_trailing_break_id(arm_last)
	}
	return ids.filter(it != '')
}

fn switch_trailing_break_id(node Node) string {
	mut current := node
	for current.kindof(.compound_stmt) && current.inner.len > 0 {
		current = current.inner.last()
	}
	return if current.kindof(.break_stmt) { current.id } else { '' }
}

// emit_switch_fallthrough continues a case arm whose statements fall through
// into the following labels. V's match arms do not fall through, so the arm
// repeats the statements C runs next, up to one that leaves the switch.
fn (mut c C2V) emit_switch_fallthrough(comp_stmt &Node, start int) {
	// The copies declare their locals in this arm's scope; the labels they come
	// from declare them again in their own arms.
	saved_vars := c.declared_local_vars.copy()
	saved_var_types := c.declared_local_var_types.clone()
	defer {
		c.declared_local_vars = saved_vars
		c.declared_local_var_types = saved_var_types.clone()
	}
	for j := start; j < comp_stmt.inner.len; j++ {
		child := comp_stmt.inner[j]
		statement := if child.kindof(.case_stmt) || child.kindof(.default_stmt) {
			switch_labeled_statement(child) or { continue }
		} else {
			child
		}
		if statement.kindof(.break_stmt) {
			return
		}
		mut copy := clone_cpp_operator_node(&statement)
		c.statement(mut copy)
		if !switch_statement_falls_through(statement) {
			return
		}
	}
}

fn (mut c C2V) gen_switch_case_expr(case_expr Node, is_enum bool) {
	if is_enum {
		enum_case_expr := switch_enum_expr_source(case_expr)
		c.expr(enum_case_expr)
	} else if node_contains_kind(case_expr, .character_literal) {
		// C/C++ applies integral promotion to a switch operand. V character
		// literals are runes, so explicitly match their promoted integer value.
		c.gen('i32(')
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
		old_enum_values_as_int := c.enum_values_as_int
		c.enum_values_as_int = c.switch_cases_as_int
		c.gen_switch_case_expr(case_expr, is_enum)
		c.enum_values_as_int = old_enum_values_as_int
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
			c.emit_pending_case_label()
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
				old_grouped_as_int := c.enum_values_as_int
				c.enum_values_as_int = c.switch_cases_as_int
				c.gen_switch_case_expr(e, is_enum)
				c.enum_values_as_int = old_grouped_as_int
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
			c.emit_pending_case_label()
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
			c.emit_pending_case_label()
			c.inside_switch_enum = false
		} else {
			// case body
			c.inside_switch_enum = false
			c.genln(' { // case comp body kind=${a.kind} is_enum=${is_enum}')
			c.emit_pending_case_label()
			c.statement(mut a)
			if a.kindof(.return_stmt) {
			} else if a.kindof(.break_stmt) {
				return true
			}
		}
	}
	return false
}

fn (mut c C2V) emit_pending_case_label() {
	if c.pending_case_label != '' {
		c.genln('${c.pending_case_label}:')
		c.pending_case_label = ''
	}
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

// switch_case_enum_constant_names returns the enum constants that the case
// labels of a switch body name.
fn switch_case_enum_constant_names(node Node) []string {
	mut names := []string{}
	if node.kindof(.case_stmt) && node.inner.len > 0 {
		mut expr := node.inner[0]
		for expr.inner.len > 0 && (expr.kindof(.constant_expr) || expr.kindof(.implicit_cast_expr)
			|| expr.kindof(.paren_expr)) {
			expr = expr.inner[0]
		}
		if expr.kindof(.decl_ref_expr) && expr.ref_declaration.kind == .enum_constant_decl {
			names << expr.ref_declaration.name
		}
	}
	for child in node.inner {
		if child.kindof(.switch_stmt) {
			continue
		}
		names << switch_case_enum_constant_names(child)
	}
	return names
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

// flatten_nested_switch_labels moves case labels nested in a case's block
// (`case A: { int x; ... case B: ... }`) up to the switch body. The block's
// declarations are shared by those arms in C: they are returned, without their
// initializers, to be declared before the V match, and the initializers become
// assignments where the declarations were.
fn flatten_nested_switch_labels(mut compound Node) []Node {
	mut hoisted := []Node{}
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
		mut prefix := body.inner[..nested_label_idx].clone()
		mut trailing := body.inner[nested_label_idx..].clone()
		prefix = hoist_switch_block_decls(prefix, mut hoisted)
		trailing = hoist_switch_block_decls(trailing, mut hoisted)
		body.inner = prefix
		expanded << compound.inner[child_idx]
		expanded << trailing
	}
	compound.inner = expanded
	return hoisted
}

// hoist_switch_block_decls replaces the local declarations among `statements`
// with assignments of their initializers, collecting the declarations.
fn hoist_switch_block_decls(statements []Node, mut hoisted []Node) []Node {
	mut result := []Node{cap: statements.len}
	for statement in statements {
		if !statement.kindof(.decl_stmt) {
			result << statement
			continue
		}
		mut declaration := statement
		declaration.inner = []Node{}
		for var_decl in statement.inner {
			if !var_decl.kindof(.var_decl) || var_decl.class_modifier == 'static'
				|| var_decl.initialization_type == '' || var_decl.inner.len == 0 {
				declaration.inner << var_decl
				continue
			}
			mut bare := var_decl
			bare.initialization_type = ''
			bare.inner = []Node{}
			declaration.inner << bare
			result << Node{
				kind:     .binary_operator
				kind_str: 'BinaryOperator'
				opcode:   '='
				ast_type: var_decl.ast_type
				location: var_decl.location
				range:    var_decl.range
				inner:    [
					Node{
						kind:            .decl_ref_expr
						kind_str:        'DeclRefExpr'
						ast_type:        var_decl.ast_type
						value_category:  'lvalue'
						location:        var_decl.location
						range:           var_decl.range
						ref_declaration: RefDeclarationNode{
							id:       var_decl.id
							kind_str: 'VarDecl'
							kind:     .var_decl
							name:     var_decl.name
							ast_type: var_decl.ast_type
						}
					},
					var_decl.inner.last(),
				]
			}
		}
		hoisted << declaration
	}
	return result
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
	end_label := 'c2v_switch_end_${c.switch_label_count}'
	c.switch_label_count++
	c.switch_end_labels << end_label
	defer {
		c.switch_end_labels.pop()
		if end_label in c.used_switch_end_labels {
			c.genln('${end_label}:')
		}
	}
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
	hoisted_decls := flatten_nested_switch_labels(mut comp_stmt)
	for mut child in comp_stmt.inner {
		if default_label := switch_case_chain_default(child) {
			child = default_label
		}
	}
	for decl in hoisted_decls {
		mut declaration := decl
		c.statement(mut declaration)
	}
	// Labels of the arms that the previous arm falls through to. V's match arms
	// do not fall through: the previous arm jumps to the label instead.
	switch_id := c.switch_label_count - 1
	fallthrough_targets := if c.is_cpp { []int{} } else { switch_fallthrough_targets(comp_stmt) }
	for id in switch_arm_trailing_break_ids(comp_stmt) {
		c.switch_trailing_breaks[id] = true
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
	old_switch_cases_as_int := c.switch_cases_as_int
	defer {
		c.switch_cases_as_int = old_switch_cases_as_int
	}
	c.switch_cases_as_int = false
	mut case_enums := map[string]bool{}
	for name in switch_case_enum_constant_names(comp_stmt) {
		case_enums[c.enum_val_to_enum_name(name)] = true
	}
	mut switch_value_node := expr
	for switch_value_node.inner.len > 0 && (switch_value_node.kindof(.implicit_cast_expr)
		|| switch_value_node.kindof(.paren_expr) || switch_value_node.kindof(.constant_expr)) {
		switch_value_node = switch_value_node.inner[0]
	}
	if !c.is_cpp && case_enums.len > 1
		&& is_cpp_operator_primitive_type(c.convert_type(switch_value_node.ast_type.qualified).name) {
		// The cases are constants of several enums (`switch (top)` of a `char`
		// holding either): match the integer value.
		c.switch_cases_as_int = true
		c.gen('i32(')
		second_par = true
	} else if switch_enum_constant != '' {
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
				c.gen('i32')
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
		c.gen('i32(')
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
	mut default_fallthrough_index := -1
	mut default_entry_label := ''
	// The last statement of the case arm being emitted.
	mut arm_last := Node{}
	for i, mut child in comp_stmt.inner {
		if i < first_case_idx {
			continue // already emitted pre-case statements
		}
		c.gen_comment(child)
		if child.kindof(.case_stmt) {
			if got_else && default_fallthrough_case == bad_node {
				default_fallthrough_case = clone_cpp_operator_node(&child)
				default_fallthrough_index = i
			}
			after_default := in_default_body
			in_default_body = false // stop collecting default body siblings
			if has_case {
				if !after_default && i in fallthrough_targets {
					c.genln('unsafe { goto c2v_case_${switch_id}_${i} }')
				} else if c.is_cpp && !after_default && switch_statement_falls_through(arm_last) {
					c.emit_switch_fallthrough(&comp_stmt, i)
				}
				c.genln('}')
			}
			if i in fallthrough_targets {
				c.pending_case_label = 'c2v_case_${switch_id}_${i}'
			}
			arm_last = switch_labeled_statement(child) or { Node{} }
			c.case_st(mut child, is_enum)
			has_case = true
		} else if child.kindof(.default_stmt) {
			if has_case && !in_default_body && i in fallthrough_targets {
				c.genln('unsafe { goto c2v_case_${switch_id}_${i} }')
				default_entry_label = 'c2v_case_${switch_id}_${i}'
			} else if c.is_cpp && has_case && !in_default_body
				&& switch_statement_falls_through(arm_last) {
				c.emit_switch_fallthrough(&comp_stmt, i)
			}
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
				arm_last = child
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
		if default_entry_label != '' {
			c.genln('${default_entry_label}:')
		}
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
		if default_can_fall_through && default_fallthrough_index in fallthrough_targets {
			c.genln('unsafe { goto c2v_case_${switch_id}_${default_fallthrough_index} }')
		} else if c.is_cpp && default_can_fall_through && default_fallthrough_case != bad_node {
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
	// File and directory names may contain characters such as `-`.
	mut prefix_bytes := '${parent}_${stem}'.bytes()
	for i, ch in prefix_bytes {
		if !ch.is_alnum() {
			prefix_bytes[i] = `_`
		}
	}
	prefix := prefix_bytes.bytestr()
	return filter_name(c_identifier_to_v_name('${prefix}_${c_name}'), true)
}

// name_file_static_functions gives the `static` functions that this C file
// defines a file-qualified V name when an earlier file of the project already
// uses their name: static functions have translation-unit linkage, and the
// project is flattened into one V module.
fn (mut c2v C2V) name_file_static_functions(main_c_file string) {
	main_path := os.real_path(main_c_file)
	mut static_names := map[string]bool{}
	mut defined_here := map[string]bool{}
	for node in c2v.tree.inner {
		if node.kind_str != 'FunctionDecl' || node.name == '' {
			continue
		}
		if node.class_modifier == 'static' {
			static_names[node.name] = true
		}
		if node.inner.any(it.kind_str == 'CompoundStmt') && node.location.file_index >= 0
			&& node.location.file_index < c2v.files.len
			&& c2v.files[node.location.file_index] == main_path {
			defined_here[node.name] = true
		}
	}
	for node in c2v.tree.inner {
		if node.kind_str != 'FunctionDecl' || node.id == '' || node.name !in static_names || node.name !in defined_here {
			continue
		}
		owner := c2v.fn_name_files[node.name] or { '' }
		if owner == '' || owner == main_c_file {
			continue
		}
		c2v.cpp_function_decl_names[node.id] = c2v.file_static_global_v_name(node.name)
	}
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

// cpp_static_member_v_name names the global of a static data member. Keep
// declarations, definitions, and cross-file references identical: a mutable
// static member can be defined in a later translation unit, while a
// header-only reference only sees its class declaration. Different members
// can share a spelling (`idForceField::Type`, `idForce_Field::Type`) and so can
// a member and a static method (`currentThread`, `CurrentThread()`), so a name
// is reserved once per member.
fn (mut c C2V) cpp_static_member_v_name(owner string, member string) string {
	qualified := '${owner.capitalize()}::${member}'
	if name := c.cpp_static_member_qualified_names[qualified] {
		return name
	}
	base := filter_name(c_identifier_to_v_name('${owner}_${member}'), true)
	mut name := base
	if n := c.emitted_top_level_name_counts[base] {
		c.emitted_top_level_name_counts[base] = n + 1
		name = '${base}${n + 1}'
	} else {
		c.emitted_top_level_name_counts[base] = 1
	}
	c.cpp_static_member_qualified_names[qualified] = name
	return name
}

fn (mut c C2V) register_cpp_static_member_v_name(owner string, member string, decl_id string) {
	if owner == '' || member == '' {
		return
	}
	v_static_name := c.cpp_static_member_v_name(owner, member)
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
		if !c.is_cpp && var_decl.kindof(.function_decl) {
			// A block scope function declaration (`extern void f(int);` in a body)
			// only declares the file scope function.
			continue
		}
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
					mut anon_name := 'AnonStruct_${var_decl.location.line}_${var_decl.location.offset}'
					// `typedef struct { ... } name;` names the record for linkage.
					next_index := decl_stmt.current_child_id
					if next_index < decl_stmt.inner.len
						&& decl_stmt.inner[next_index].kind == .typedef_decl
						&& decl_stmt.inner[next_index].name != ''
						&& node_contains_owned_tag_id(&decl_stmt.inner[next_index], var_decl.id) {
						anon_name = decl_stmt.inner[next_index].name
					}
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
			// Keep array dimensions: `struct {...} a[3]` is `[3]AnonStruct_N`.
			anon_type := c.convert_type(c.last_declared_type_name)
			dims := local_cpp_type.all_after_last(')').replace(' ', '')
			if dims.starts_with('[') && dims.ends_with(']') {
				Type{
					...anon_type
					name: dims + anon_type.name
				}
			} else {
				anon_type
			}
		} else {
			c.convert_type(local_cpp_type)
		}
		declared_typ_name := c.prefix_external_type(typ_.name)
		if (c.is_dir || !c.is_cpp) && var_decl.class_modifier == 'static' && c.current_fn_v_name != ''
			&& (c.address_taken_locals[var_decl.name] || c.cpp_static_local_is_constructed(var_decl)
				|| c.is_v_object_type(declared_typ_name) || cpp_fixed_array_length(declared_typ_name) > 0) {
			// (V's own `static` locals of a struct type are never allocated, and
			// its static arrays are immutable.)
			mut static_name := '${c.current_fn_v_name}_${v_name}'
			// Blocks of one function may declare statics of the same name.
			mut n := 2
			for (static_name in c.static_local_vars.values()) {
				static_name = '${c.current_fn_v_name}_${v_name}${n}'
				n++
			}
			if var_decl.id != '' {
				c.local_decl_v_names[var_decl.id] = static_name
			}
			c.static_local_vars[var_decl.name] = static_name
			mut typ := declared_typ_name
			if typ == '' {
				typ = 'i32'
			}
			start := c.out.len
			c.genln('@[weak] __global ${static_name} ${typ}\n')
			c.add_function_static_global(static_name, typ, c.out.cut_to(start))
			if cinit {
				expr := var_decl.try_get_next_child() or {
					println(add_place_data_to_error(err))
					bad_node
				}
				init_name := '${static_name}_inited'
				init_start := c.out.len
				c.genln('@[weak] __global ${init_name} bool\n')
				c.add_function_static_global(init_name, 'bool', c.out.cut_to(init_start))
				c.genln('if !${init_name} {')
				c.indent++
				construction := unwrap_cpp_reference_binding(expr)
				if c.is_cpp && cpp_fixed_array_length(typ) > 0
					&& c.gen_cpp_array_element_constructors(static_name, &construction) {
					// The elements are constructed in place, once.
				} else if c.is_cpp && cpp_fixed_array_length(typ) == 0
					&& c.resolve_type_alias(c.convert_type(node_effective_type_name(construction)).name) == c.resolve_type_alias(typ)
					&& c.cpp_user_constructor_init_name(&construction) != none {
					// C++ constructs the object in place, once, so its constructor sees
					// the object's own address.
					ctor_init_name := c.cpp_user_constructor_init_name(&construction) or { '' }
					c.gen_cpp_constructor_call_on(static_name, ctor_init_name, &construction)
					c.genln('')
				} else if cpp_fixed_array_length(typ) > 0
					&& unwrap_condition_atom(construction).kindof(.string_literal)
					&& cpp_fixed_array_element_type(typ) in ['i8', 'u8'] {
					// `static const char z[] = "abc";` holds the bytes. (C cannot assign
					// the array: copy the elements.)
					c.genln('c2v_static_init := ' + c_string_fixed_array_literal(unwrap_condition_atom(construction).value.to_str(), typ))
					c.genln('for c2v_i_0, c2v_element_0 in c2v_static_init {')
					c.genln('\t${static_name}[c2v_i_0] = c2v_element_0')
					c.genln('}')
				} else if cpp_fixed_array_length(typ) > 0 && construction.kindof(.init_list_expr) {
					// C cannot assign an array literal to the array: copy its elements.
					old_inside_global_init := c.inside_global_init
					old_global_struct_init := c.global_struct_init
					c.inside_global_init = true
					c.global_struct_init = typ
					literal := c.render_expr_to_string(expr).trim_space()
					c.inside_global_init = old_inside_global_init
					c.global_struct_init = old_global_struct_init
					// One loop per dimension: C cannot assign the rows either.
					mut depth := 0
					mut element_type := typ
					for cpp_fixed_array_length(element_type) > 0 {
						element_type = cpp_fixed_array_element_type(element_type)
						depth++
					}
					// (V cannot parse a record literal in a `for ... in` header.)
					c.genln('c2v_static_init := ${literal}')
					mut source := 'c2v_static_init'
					mut target := static_name
					for level in 0 .. depth {
						c.genln('\t'.repeat(level) + 'for c2v_i_${level}, c2v_element_${level} in ${source} {')
						source = 'c2v_element_${level}'
						target += '[c2v_i_${level}]'
					}
					c.genln('\t'.repeat(depth) + '${target} = ${source}')
					for level := depth - 1; level >= 0; level-- {
						c.genln('\t'.repeat(level) + '}')
					}
				} else {
					c.gen('${static_name} = ')
					old_inside_global_init := c.inside_global_init
					old_global_struct_init := c.global_struct_init
					c.inside_global_init = true
					c.global_struct_init = typ
					c.expr(expr)
					c.inside_global_init = old_inside_global_init
					c.global_struct_init = old_global_struct_init
					c.genln('')
				}
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
				&& initializer_base.kindof(.string_literal)
				&& cpp_fixed_array_element_type(declared_typ_name) in ['i8', 'u8'] {
				// A character array initialized from a string literal is a mutable
				// copy of its bytes, zero padded, not a pointer to the literal.
				c.gen(c_string_fixed_array_literal(initializer_base.value.to_str(), declared_typ_name))
			} else if cpp_fixed_array_length(declared_typ_name) > 0
				&& (initializer_base.kindof(.cxx_construct_expr)
					|| is_zero_initializer_expr(expr)) {
				// Clang models default construction of a C++ object array as one
				// element CXXConstructExpr, while `T values[N] = {}` is an empty
				// InitListExpr. Preserve the declared array shape in both cases rather
				// than inferring a single object or letting the sanitizer reduce `[]!`
				// to scalar zero.
				c.gen('${declared_typ_name}{}')
				if !c.inside_for && initializer_base.kindof(.cxx_construct_expr)
					&& c.cpp_array_element_constructor(&initializer_base) != none {
					c.genln('')
					c.gen_cpp_array_element_constructors(v_name, &initializer_base)
				}
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
			} else if !c.is_cpp && (is_c_truth_value(expr) || c.is_v_enum_value(expr))
				&& c.resolve_type_alias(declared_typ_name) in v_integer_type_names {
				// `int adj = x != 0;` is an int in C; V would infer a bool (or the
				// enum of `int e = CONSTANT;`).
				c.gen('${declared_typ_name}(')
				c.expr(expr)
				c.gen(')')
			} else if is_untyped_v_integer_expr(initializer_base)
				&& c.resolve_type_alias(declared_typ_name) in v_integer_type_names
				&& c.resolve_type_alias(declared_typ_name) != 'int' {
				// V infers an expression of integer literals as `int`: keep the
				// declared type (its width and wraparound, and literals above INT_MAX).
				rendered := c.render_expr_to_string(expr)
				if rendered.trim_space().starts_with('${declared_typ_name}(') {
					c.gen(rendered)
				} else {
					c.gen('${declared_typ_name}(${rendered})')
				}
			} else if c.resolve_type_alias(declared_typ_name).starts_with('fn (')
				&& is_cpp_null_pointer_expression(expr) {
				// A bare nil initializer would lose the function pointer type.
				if declared_typ_name.starts_with('fn (') {
					// V parses `fn (T)(nil)` as an anonymous function.
					helper_name := c.function_pointer_cast_helper_name(declared_typ_name)
					c.gen('${helper_name}(voidptr(0))')
				} else {
					c.gen('unsafe { ${declared_typ_name}(nil) }')
				}
			} else if c.is_v_abstract_interface_type(declared_typ_name)
				&& is_cpp_null_pointer_expression(expr) {
				// A C++ abstract pointer is represented by the V interface descriptor
				// itself. Keep a null initializer typed as that interface so later
				// address-taking produces `&Interface`, not `&voidptr`.
				c.gen(c.v_abstract_interface_nil_literal(declared_typ_name))
			} else if declared_typ_name.starts_with('&') && c.is_cpp && var_decl.id != ''
				&& is_cpp_lvalue_reference_decl(var_decl)
				&& c.is_primitive_reference_v_type(declared_typ_name)
				&& (cpp_reference_binding_is_returned_reference(expr)
					|| cpp_reference_binding_is_reference_variable(expr)) {
				// A primitive reference bound to a reference returned by a call, or to
				// another reference, keeps that pointer; reads and writes go through it.
				c.cpp_primitive_reference_decls[var_decl.id] = true
				bound := unwrap_cpp_reference_binding(expr)
				if reference_name := c.cpp_primitive_reference_v_name(&bound) {
					c.gen(reference_name)
				} else {
					old_reference_lvalue := c.inside_cpp_reference_lvalue
					c.inside_cpp_reference_lvalue = true
					c.expr(bound)
					c.inside_cpp_reference_lvalue = old_reference_lvalue
				}
			} else if declared_typ_name.starts_with('&') && c.is_cpp
				&& is_cpp_lvalue_reference_decl(var_decl)
				&& cpp_reference_binding_needs_address(expr) {
				// A C++ reference is the V address of the object it is bound to.
				if var_decl.id != '' && c.is_primitive_reference_v_type(declared_typ_name) {
					// Reads and writes of a primitive reference go through the pointer.
					c.cpp_primitive_reference_decls[var_decl.id] = true
				}
				bound := unwrap_cpp_reference_binding(expr)
				// A reference to a base bound to a derived object keeps the base type.
				upcast := cpp_derived_to_base_source(&expr) != none
					&& !c.is_v_abstract_interface_type(declared_typ_name[1..])
				if bound.kindof(.unary_operator) && bound.opcode == '*' && bound.inner.len == 1 {
					if upcast {
						c.gen('unsafe { ${declared_typ_name}(')
						c.expr(bound.inner[0])
						c.gen(') }')
					} else {
						c.expr(bound.inner[0])
					}
				} else {
					c.gen(if upcast { 'unsafe { ${declared_typ_name}(&' } else { 'unsafe { &' })
					old_inside_unsafe := c.inside_unsafe
					c.inside_unsafe = true
					c.expr(bound)
					c.inside_unsafe = old_inside_unsafe
					c.gen(if upcast { ') }' } else { ' }' })
				}
			} else if !c.is_cpp && c.resolve_type_alias(declared_typ_name) == 'voidptr'
				&& is_c_null_pointer_constant(expr) {
				// `void *p = 0;`: V would infer an int.
				c.gen('voidptr(0)')
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
					if rendered.trim_space() in ['nil', 'unsafe { nil }']
						|| (!c.is_cpp && is_c_null_pointer_constant(expr)) {
						// Preserve the declared pointer type. A bare nil initializer is
						// inferred as `nil`, which loses both record methods and abstract
						// interface conformance on later assignments/calls.
						c.gen('unsafe { ${declared_typ_name}(nil) }')
					} else if !c.is_cpp && expr.kindof(.implicit_cast_expr) && expr.cast_kind == 'BitCast'
						&& expr.inner.len == 1
						&& c.convert_type(expr.inner[0].ast_type.qualified).name == 'voidptr'
						&& !rendered.trim_space().starts_with('${declared_typ_name}(') {
						// C converts `void *` to the declared pointer type implicitly
						// (`T *p = malloc(n)`); V would infer `voidptr`.
						c.gen('${declared_typ_name}(${rendered})')
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
			if var_decl.ast_type.desugared_qualified.starts_with('struct ')
				&& !var_decl.ast_type.desugared_qualified.contains('*') {
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
			} else if typ == 'i32' {
				def = 'i32(0)'
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
				// C code tests function pointers against null: a C local of function
				// pointer type is zero-initialized as a null function pointer.
				def = if c.is_cpp {
					c.skeleton_default_value(typ)
				} else {
					c.typed_null_function_pointer(typ)
				}
			} else if !c.is_cpp && typ.starts_with('C2vFn_') {
				def = c.v_zero_value(typ)
			} else if typ == 'voidptr' {
				// `void *p;` (`&voidptr(0)` would be a pointer to a pointer).
				def = 'voidptr(0)'
			} else if oldtyp.ends_with('*') {
				// *sqlite3_mutex ==>
				// &sqlite3_mutex{!}
				// println2('!!! $oldtyp $typ')
				// def = '&${typ.right(1)}{!}'
				tt := if typ.starts_with('&') { typ[1..] } else { typ }
				def = if c.cpp_abstract_types[tt] {
					// Abstract C++ classes are V interfaces. Casting integer zero to a
					// V interface triggers one diagnostic per method. The interface value
					// itself represents the first C++ pointer layer. A deeper pointer
					// keeps its type: generic element access depends on it.
					if typ.starts_with('&') {
						'unsafe { ${typ}(nil) }'
					} else {
						c.v_abstract_interface_nil_literal(tt)
					}
				} else {
					'&${tt}(0)'
				}
			} else if typ.starts_with('[') {
				// Empty array init
				def = '${typ}{}'
			} else if typ.starts_with('&') {
				// A pointer spelled without `*`, such as a translated C++ `va_list`.
				def = '&${typ[1..]}(0)'
			} else {
				// We assume that everything else is a struct, because C AST doesn't
				// give us any info that typedef'ed structs are structs

				if c.resolve_type_alias(typ) in ['u8', 'u16', 'u32', 'u64', 'i8', 'i16', 'int',
					'i32', 'i64', 'f32', 'f64', 'usize', 'isize', 'bool', 'voidptr'] {
					def = '${typ}(0)'
				} else if !c.is_cpp && c.resolve_type_alias(typ).starts_with('&') {
					// A pointer typedef (`typedef T *TP;`).
					def = '${typ}(unsafe { nil })'
				} else {
					// Check if this is a type alias to a primitive type
					// V doesn't allow TypeAlias{} for primitive type aliases, use TypeAlias(0) instead
					underlying := c.resolve_type_alias(typ)
					if underlying in ['u8', 'u16', 'u32', 'u64', 'i8', 'i16', 'int', 'i32', 'i64',
						'f32', 'f64', 'usize', 'isize', 'bool', 'voidptr'] {
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
		c.register_cpp_static_member_v_name(class_name, original_c_name, var_decl.id)
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
	// In C, `const char *p` is a variable (pointing to const data); only a
	// top-level qualifier (`char *const p`, `const int n`) makes the object const.
	is_const_object := if c.is_cpp {
		typ.is_const
	} else {
		c_type_is_top_level_const(var_decl.ast_type.qualified)
	}
	is_external_const_array := has_external_linkage && is_fixed_array && is_const_object
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
	// A variable the program writes, or whose address it takes, needs storage.
	is_mutated := var_decl.id in c.mutated_variable_ids
		|| (var_decl.previous_declaration != '' && var_decl.previous_declaration in c.mutated_variable_ids)
	// A C++ object built by a user constructor is constructed in place, even when
	// it is `const`: the constructor can keep its address (see the global
	// constructors below). A V `const` would hold a copy of a temporary object.
	mut constructed_in_place := false
	if c.is_cpp && is_inited && !is_fixed_array {
		for child in var_decl.inner {
			if child.kindof(.visibility_attr) || child.kindof(.full_comment)
				|| child.kindof(.record_decl) || child.kindof(.cxx_record_decl)
				|| child.kindof(.enum_decl) || child.kindof(.typedef_decl) {
				continue
			}
			construction := unwrap_cpp_reference_binding(child)
			constructed_in_place = c.resolve_type_alias(c.convert_type(node_effective_type_name(construction)).name) == c.resolve_type_alias(global_v_type)
				&& c.cpp_user_constructor_init_name(&construction) != none
			break
		}
	}
	is_const := is_inited && !should_emit_dir_external_global && !should_define_static_init_global
		&& !is_external_const_array && !is_pointer_element_fixed_array && (c.is_cpp || !is_mutated)
		&& !constructed_in_place && (is_const_object || (is_fixed_array
		&& (!c.is_dir || var_decl.class_modifier != 'static') && !is_mutable_fixed_array))
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
			c.cpp_static_member_v_name(class_name, original_c_name)
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
		if is_fixed_array && emitted_global_name != ''
			&& (!c.is_cpp || c.is_constant_scalar_initializer(child)) {
			// C++ initializes it statically, before any dynamic initialization.
			// (A C initializer of static storage is always a constant expression.)
			c.static_global_arrays[emitted_global_name] = true
		}
		construction := unwrap_cpp_reference_binding(child)
		if c.is_cpp && emitted_global_name != '' && is_fixed_array
			&& c.cpp_array_element_constructor(&construction) != none {
			// C++ constructs every element of a global array of objects in place,
			// in the global initialization sequence.
			c.genln('= ${global_v_type}{}')
			c.genln('\n')
			construct_start := c.out.len
			old_line := c.cur_out_line
			old_out_line_empty := c.out_line_empty
			old_indent := c.indent
			c.cur_out_line = ''
			c.out_line_empty = true
			c.indent = 0
			old_inside_global_init := c.inside_global_init
			c.inside_global_init = true
			c.gen_cpp_array_element_constructors(emitted_global_name, &construction)
			c.inside_global_init = old_inside_global_init
			call := c.out.cut_to(construct_start) + c.cur_out_line
			c.cur_out_line = old_line
			c.out_line_empty = old_out_line_empty
			c.indent = old_indent
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
		if c.resolve_type_alias(global_v_type).starts_with('fn ') && is_null_pointer_constant(child) {
			// A null function pointer is the zero value of its type, which V cannot
			// spell as a cast of `nil`; an untyped `nil` would not be callable.
			c.genln(global_v_type)
			c.genln('\n')
			if c.is_dir {
				s := c.out.cut_to(start)
				if should_emit_dir_external_global || should_define_static_init_global {
					if c_name !in c.defined_globals {
						c.defined_global_order << c_name
					}
					c.defined_globals[c_name] = true
				}
				c.globals_out[c_name] = s
			}
			c.global_struct_init = ''
			c.register_global_symbol(c_name, typ.name, is_extern)
			return
		}
		c.gen('= ')
		if !c.is_cpp && c.resolve_type_alias(global_v_type).starts_with('fn ')
			&& !is_null_pointer_constant(child) {
			// V would type a global initialized with a function by that function's
			// name: spell the function pointer type.
			fn_type_name := if global_v_type.starts_with('fn ') {
				c.function_pointer_cast_helper_name(global_v_type)
			} else {
				global_v_type
			}
			c.gen('${fn_type_name}(voidptr(')
			c.expr(child)
			c.genln('))')
			c.genln('\n')
			if c.is_dir {
				s := c.out.cut_to(start)
				if should_emit_dir_external_global || should_define_static_init_global {
					if c_name !in c.defined_globals {
						c.defined_global_order << c_name
					}
					c.defined_globals[c_name] = true
				}
				c.globals_out[c_name] = s
			}
			c.global_struct_init = ''
			c.register_global_symbol(c_name, typ.name, is_extern)
			return
		}
		string_array_init := unwrap_condition_atom(child)
		if !c.is_cpp && is_fixed_array && string_array_init.kindof(.string_literal)
			&& cpp_fixed_array_element_type(typ.name) in ['i8', 'u8'] {
			// `char label[16] = "READY";` is an array holding the bytes.
			c.genln(c_string_fixed_array_literal(string_array_init.value.to_str(), typ.name))
			c.genln('\n')
			if c.is_dir {
				s := c.out.cut_to(start)
				if should_emit_dir_external_global || should_define_static_init_global {
					if c_name !in c.defined_globals {
						c.defined_global_order << c_name
					}
					c.defined_globals[c_name] = true
				}
				c.globals_out[c_name] = s
			}
			c.global_struct_init = ''
			c.register_global_symbol(c_name, typ.name, is_extern)
			return
		}
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
		// A pointer to an abstract class holds the concrete object as the V
		// interface value, not as the object's own pointer type.
		upcast_source := c.cpp_derived_cast_root_type(child)
		interface_upcast := c.is_cpp && c.is_v_abstract_interface_type(global_v_type)
			&& upcast_source != '' && upcast_source != global_v_type
			&& !c.is_v_abstract_interface_type(upcast_source)
		needs_cast := interface_upcast || ((!is_const || (c.is_dir && is_numeric_literal))
			&& !is_struct && !is_fn_ptr && !is_fixed_array
			&& (!is_default_record_init || is_typed_pointer_literal)
			&& (!is_same_record_type || is_typed_pointer_literal)
			&& !c.is_v_abstract_interface_type(global_v_type)) // Don't cast function pointers, struct inits, fixed arrays, or interface descriptors.
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
		name:      c_name
		is_extern: is_extern
		typ:       clean_typ
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
fn (mut c C2V) expr(node &Node) string {
	// A conversion emitted right before a binary operation converts the whole
	// operation, not its leftmost operand (see the implicit numeric casts in
	// expr_node).
	old_operation_start := c.expr_operation_start
	old_parent_operation_start := c.expr_parent_operation_start
	c.expr_parent_operation_start = c.expr_operation_start
	c.expr_operation_start = if node.kindof(.binary_operator)
		|| node.kindof(.compound_assign_operator) {
		c.cur_out_line.len
	} else {
		-1
	}
	defer {
		c.expr_operation_start = old_operation_start
		c.expr_parent_operation_start = old_parent_operation_start
	}
	if c.is_cpp {
		return c.expr_node(node)
	}
	is_assignment := (node.kindof(.binary_operator) && node.opcode == '=')
		|| node.kindof(.compound_assign_operator)
	if is_assignment && c.value_context_depth > 0 && node.inner.len == 2 {
		// An assignment whose value is an operand: `a[i = next]`, `f(x = y)`.
		c.gen_comment(node)
		c.gen_assignment_value(node)
		return ''
	}
	// The operands of these expressions are values, even when they are
	// assignments (which are statements in V).
	is_value_parent := (node.kindof(.binary_operator) && node.opcode !in ['=', ','])
		|| is_assignment || node.kindof(.unary_operator) || node.kindof(.array_subscript_expr)
		|| node.kindof(.conditional_operator) || node.kindof(.call_expr)
		|| node.kindof(.member_expr)
		|| (node.kindof(.c_style_cast_expr) && node.cast_kind != 'ToVoid')
	if is_value_parent {
		c.value_context_depth++
	}
	result := c.expr_node(node)
	if is_value_parent {
		c.value_context_depth--
	}
	return result
}

fn (mut c C2V) expr_node(_node &Node) string {
	mut node := unsafe { _node }
	c.gen_comment(node)
	if !c.is_cpp && (mentions_int128(node.ast_type)
		|| (node.inner.len > 0 && mentions_int128(node.inner[0].ast_type))) && c.int128_expr(node) {
		return ''
	}
	// Just gen a number
	if node.kindof(.null) || node.kindof(.visibility_attr) {
		return ''
	}
	if !c.is_cpp && !c.inside_global_init && node.kindof(.binary_operator) && node.inner.len == 2
		&& folds_to_non_finite_float(node) {
		// V folds `1e308 * 1e308` into an `inf` token that C does not know
		// (C computes infinity at run time): pass one operand through a function.
		key := 'c2v_float_value:${os.dir(c.outv)}'
		if key !in c.generated_declarations {
			c.generated_declarations[key] = true
			c.local_type_declarations << 'fn c2v_float_value(x f64) f64 {\n\treturn x\n}\n\n'
		}
		c.gen('c2v_float_value(')
		c.expr(node.inner[0])
		c.gen(') ${node.opcode} ')
		c.expr(node.inner[1])
		return ''
	}
	if node.cast_kind == 'PointerToIntegral' && node.inner.len == 1 {
		// `(size_t)&((T *)0)->m`: the offset of `m` (how `offsetof` is spelled).
		if offset := c.null_member_offset(node.inner[0]) {
			c.gen('${c.convert_type(node.ast_type.qualified).name}(${offset})')
			return ''
		}
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
		// Clang spells an integral value without a decimal point (`2.0f` is `2`);
		// V would read that as an integer (and `2 / 640` divides integers).
		mut literal := node.value.to_str()
		if literal != '' && literal.bytes().all(it.is_digit() || it == `-`) {
			literal += '.0'
		}
		c.gen(literal)
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
		} else if op == ',' && !c.is_cpp && !c.inside_for_post
			&& (c.value_context_depth > 0 || c.collecting_pre_cond) {
			// A comma expression whose value is used: evaluate the left operand as a
			// statement, then yield the right one, in an always-taken `if` block.
			mut second_expr := node.try_get_next_child() or {
				println(add_place_data_to_error(err))
				bad_node
			}
			value_type := c.convert_type(node.ast_type.qualified).name
			old_value_context_depth := c.value_context_depth
			old_collecting_pre_cond := c.collecting_pre_cond
			c.genln('(if true {')
			c.value_context_depth = 0
			c.collecting_pre_cond = false
			c.expr(first_expr)
			c.genln('')
			c.value_context_depth = old_value_context_depth + 1
			c.gen(v_statement_safe_value(c.render_expr_to_string(second_expr)))
			c.value_context_depth = old_value_context_depth
			c.collecting_pre_cond = old_collecting_pre_cond
			if value_type == 'void' {
				c.genln('')
				c.gen('})')
			} else {
				c.genln('')
				c.gen('} else { ${c.v_zero_value(value_type)} })')
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
			fn_null_operand := if !c.is_cpp && op in ['==', '!='] && first_is_null != second_is_null {
				if first_is_null { second_expr } else { first_expr }
			} else {
				bad_node
			}
			if fn_null_operand != bad_node && c.resolve_type_alias(c.convert_type(node_effective_type_name(fn_null_operand)).name).starts_with('fn ') {
				// A function pointer compared with null.
				c.gen(if op == '==' { 'isnil(' } else { '!isnil(' })
				c.expr(fn_null_operand)
				c.gen(')')
			} else if abstract_comparison_type != '' {
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
			} else if !c.is_cpp && op == '+'
				&& c.is_pointer_ast_type(node_effective_type_name(second_expr))
				&& !c.is_pointer_ast_type(node_effective_type_name(first_expr)) {
				// `n + ptr`: V's pointer arithmetic takes the pointer first.
				old_inside_unsafe := c.inside_unsafe
				if !old_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.expr(second_expr)
				c.gen(' + (')
				c.expr(first_expr)
				c.gen(')')
				if !old_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
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
			} else if !c.is_cpp && op in ['<<', '>>'] && c.shift_count_primitive(second_expr) != '' {
				// V takes a shift count of a primitive integer type, not an alias.
				if is_bool_expr(first_expr) || c.shift_lhs_needs_int_cast(first_expr) {
					c.gen('i32(')
					c.expr(first_expr)
					c.gen(')')
				} else {
					c.expr(first_expr)
				}
				c.gen(' ${op} ${c.shift_count_primitive(second_expr)}(')
				c.expr(second_expr)
				c.gen(')')
			} else if op in ['<<', '>>']
				&& (is_bool_expr(first_expr) || c.shift_lhs_needs_int_cast(first_expr)) {
				c.gen('i32(')
				c.expr(first_expr)
				c.gen(')')
				c.gen(' ${op} ')
				c.expr(second_expr)
			} else if op == '-' && c.expr_renders_with_leading_unary_minus(second_expr) {
				c.expr(first_expr)
				c.gen(' - (')
				c.expr(second_expr)
				c.gen(')')
			} else if op in ['&&', '||'] {
				c.gen_logical_operand(first_expr)
				c.gen(' ${op} ')
				c.conditional_eval_depth++
				c.gen_logical_operand(second_expr)
				c.conditional_eval_depth--
			} else if !c.is_cpp && op in ['==', '!=', '<', '>', '<=', '>=']
				&& (c.is_char_literal_vs_i8(first_expr, second_expr)
					|| c.is_char_literal_vs_i8(second_expr, first_expr)) {
				// C character literals are ints; V compares a rune with no `i8`.
				for i, operand in [first_expr, second_expr] {
					if i > 0 {
						c.gen(' ${op} ')
					}
					if unwrap_condition_atom(operand).kindof(.character_literal) {
						c.gen('i8(')
						c.expr(operand)
						c.gen(')')
					} else {
						c.expr(operand)
					}
				}
			} else if !c.is_cpp && op in ['+', '-', '*', '/', '%', '&', '|', '^']
				&& (c.c_int_operand_needs_cast(first_expr, second_expr)
					|| c.c_int_operand_needs_cast(second_expr, first_expr)) {
				// C computes with ints where V has a bool (`(a < b) * 4`) or a rune
				// (`c - '0'`).
				for i, operand in [first_expr, second_expr] {
					other := if i == 0 { second_expr } else { first_expr }
					if i > 0 {
						c.gen(' ${op} ')
					}
					if c.c_int_operand_needs_cast(operand, other) {
						c.gen('i32(')
						c.expr(operand)
						c.gen(')')
					} else {
						c.expr(operand)
					}
				}
			} else {
				c.expr(first_expr)
				c.gen(' ${op} ')
				rhs_start := c.cur_out_line.len
				c.expr(second_expr)
				if op == '&' && starts_with_c_call(c.cur_out_line[rhs_start..]) {
					// V parses `a & C.f(x, y)` as the pointer cast `&C.f(x)`.
					c.cur_out_line = c.cur_out_line[..rhs_start] + '(' + c.cur_out_line[rhs_start..] + ')'
				}
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
					if value_type in ['i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64',
						'isize', 'usize', 'f32', 'f64'] {
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
			// (Not an update that C evaluates only conditionally, as in the right
			// operand of `&&`, nor one of a target with side effects.)
			if c.collecting_pre_cond && !node.is_postfix && c.conditional_eval_depth == 0
				&& !has_side_effects(expr) {
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
			mut deref := expr
			for deref.kindof(.paren_expr) && deref.inner.len == 1 {
				deref = deref.inner[0]
			}
			if deref.kindof(.unary_operator) && deref.opcode == '*' && deref.inner.len == 1
				&& !c.inside_for && !c.inside_comma_expr {
				// V increments a dereferenced pointer as `(*p)++`, within `unsafe`.
				was_inside_unsafe := c.inside_unsafe
				c.gen(if was_inside_unsafe { '(*' } else { 'unsafe { (*' })
				c.inside_unsafe = true
				c.expr(deref.inner[0])
				c.inside_unsafe = was_inside_unsafe
				c.gen(')${op}')
				if !was_inside_unsafe {
					c.gen(' }')
				}
				return ''
			}
			value_unused := node.id == c.unused_value_expr_id
				|| (c.inside_for && node.id == c.for_clause_root_id) || c.inside_comma_expr
			if !c.is_cpp && !c.inside_unsafe && !c.inside_for && !c.inside_comma_expr
				&& node.id == c.unused_value_expr_id && lvalue_reached_through_pointer(expr) {
				// `++(*pp)->n` and `a[i]->n++` update memory reached through a
				// pointer: V wants the whole statement in `unsafe`.
				c.gen('unsafe { ')
				c.inside_unsafe = true
				c.expr(expr)
				c.inside_unsafe = false
				c.gen('${op} }')
				return ''
			}
			if !node.is_postfix && !value_unused {
				// V has only postfix `x++`: a prefix increment whose value is used
				// updates the variable first, then yields it.
				c.gen_cpp_prefix_update(expr, if op == '++' { '1' } else { '-1' })
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
		} else if op == '!' && !c.is_cpp && (c.is_pointer_ast_type(node_effective_type_name(expr))
			|| c.resolve_type_alias(c.convert_type(node_effective_type_name(expr)).name).starts_with('fn ')) {
			// `!ptr` tests for a null pointer; V has no `!` for pointers.
			c.gen('isnil(')
			c.expr(expr)
			c.gen(')')
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
			} else if addr_target.kindof(.array_subscript_expr) && addr_target.inner.len >= 2
				&& c.is_v_abstract_interface_type(c.convert_type(addr_target.ast_type.qualified).name) {
				// V's pointer arithmetic does not apply to pointers to interface values.
				c.ensure_cpp_interface_runtime_helpers()
				c.gen('c2v_pointer_at(')
				c.expr(addr_target.inner[0])
				c.gen(', isize(')
				c.expr(addr_target.inner[1])
				c.gen('))')
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
			} else if !c.is_cpp && c.is_heap_promotable_local(addr_target)
				&& c.convert_type(addr_target.ast_type.qualified).name.starts_with('&') {
				// V's old backend moves a local whose address is taken to the heap and
				// then mistranslates field accesses of a pointer local (`p.f` becomes
				// `(*p).f` in C). Taking the address inside a call avoids that.
				pointer_type := '&' + c.convert_type(addr_target.ast_type.qualified).name
				c.gen('${pointer_type}(c2v_address_of(&')
				c.expr(addr_target)
				c.gen('))')
				helper_key := 'c2v_address_of:${os.dir(c.outv)}'
				if helper_key !in c.generated_declarations {
					c.generated_declarations[helper_key] = true
					c.local_type_declarations << 'fn c2v_address_of(address voidptr) voidptr {\n\treturn address\n}\n\n'
				}
			} else if !c.is_cpp && !c.inside_unsafe
				&& addr_target.ast_type.qualified.trim_space().ends_with(']') {
				// `&array`: V requires `unsafe` for the address of a fixed array
				// that is not itself a call argument.
				c.gen('unsafe { &')
				c.inside_unsafe = true
				c.expr(expr)
				c.inside_unsafe = false
				c.gen(' }')
			} else {
				c.gen('&')
				c.expr(expr)
			}
		} else if op == '*' {
			if c.is_cpp && is_cpp_object_this_expr(node) {
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
		// Parentheses around a primary expression are redundant, and V continues
		// the previous statement with a line that starts with `(`: `(g).f = 1`.
		is_primary := !c.is_cpp && (child.kindof(.decl_ref_expr) || child.kindof(.member_expr)
			|| child.kindof(.array_subscript_expr) || child.kindof(.call_expr)
			|| child.kindof(.integer_literal) || child.kindof(.string_literal)
			|| child.kindof(.character_literal) || child.kindof(.floating_literal)
			|| child.kindof(.paren_expr))
		skip := c.skip_parens || is_comma_expr || is_compound_assign || is_simple_assign
			|| is_primary
		// An assignment that C evaluates only conditionally, such as the right
		// operand of `&&`, cannot move in front of the condition.
		// Neither can one whose target has side effects (`*(p++) = v`): the
		// condition would evaluate the target again.
		if c.collecting_pre_cond && (is_simple_assign || is_compound_assign) && child.inner.len > 1
			&& (c.conditional_eval_depth > 0 || has_side_effects(child.inner[0])) {
			c.gen_assignment_value(child)
			return ''
		}
		// Handle assignment in condition: `(x = expr)` / `(x += expr)` -> collect assignment, output `x`
		if c.collecting_pre_cond && (is_simple_assign || is_compound_assign) && child.inner.len > 0 {
			var_node := child.inner[0]
			// Temporarily capture the assignment output
			old_cur_out := c.cur_out_line
			old_value_context_depth := c.value_context_depth
			c.cur_out_line = ''
			c.value_context_depth = 0
			c.expr(child) // generates the assignment
			c.value_context_depth = old_value_context_depth
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
		// A call returning a reference to a primitive value returns a V pointer.
		reads_primitive_reference_call := c.is_cpp && expr.value_category == 'lvalue'
			&& (expr.kindof(.call_expr) || expr.kindof(.cxx_member_call_expr))
			&& c.convert_type(node_effective_type_name(expr)).name in v_primitive_type_names
		if node.cast_kind == 'LValueToRValue' && (is_cpp_pointer_slot_call(expr)
			|| ((c.deref_reference_call_values || reads_primitive_reference_call)
				&& cpp_call_expr_returns_reference_value(expr)
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
		if c.is_cpp && node.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase'] {
			target := c.convert_type(node.ast_type.qualified).name
			source := c.convert_type(node_effective_type_name(expr)).name
			if target != source && c.is_v_abstract_interface_type(target)
				&& c.is_v_abstract_interface_type(source) {
				c.gen(c.cpp_interface_conversion_helper(source, target) + '(')
				c.expr(expr)
				c.gen(')')
				return ''
			}
		}
		if !c.is_cpp && node.cast_kind == 'LValueToRValue' {
			if element_type := c.voidptr_array_element(expr) {
				// Read from a pointer array stored as `[N]voidptr`.
				c.gen('${element_type}(')
				c.expr(expr)
				c.gen(')')
				return ''
			}
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
			if c.is_cpp && to_type == 'voidptr' && c.is_v_abstract_interface_type(from_type) {
				c.gen_cpp_abstract_pointer_erasure(expr, from_type)
				handled = true
			} else if from_type == 'voidptr' && to_type == '&u8' {
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
		} else if ((c.is_dir || !c.is_cpp)
			&& node.cast_kind in ['IntegralCast', 'IntegralToFloating', 'FloatingToIntegral'])
			|| (node.cast_kind == 'FloatingCast' && !expr.kindof(.floating_literal)) {
			to_type := c.prefix_external_type(c.convert_type(node.ast_type.qualified).name)
			from_type := c.prefix_external_type(c.convert_type(expr.ast_type.qualified).name)
			resolved_to_type := c.resolve_type_alias(to_type)
			// An enclosing explicit conversion to the same type already converts.
			// (Unless the conversion precedes the binary operation whose first
			// operand this is: it converts the whole operation.)
			already_converted := c.cur_out_line.ends_with('${to_type}(')
				&& c.expr_parent_operation_start != c.cur_out_line.len
			if to_type != from_type && resolved_to_type in v_primitive_type_names {
				float_via := if node.cast_kind == 'FloatingToIntegral' {
					float_conversion_intermediate_type(resolved_to_type)
				} else {
					''
				}
				if !already_converted {
					c.gen('${to_type}(')
				}
				if float_via != '' {
					c.gen('${float_via}(')
				}
				c.expr(expr)
				if float_via != '' {
					c.gen(')')
				}
				if !already_converted {
					c.gen(')')
				}
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
		variant_result := if c.value_context_depth > 0 {
			c.file_variant_pointer_type(node.ast_type.qualified)
		} else {
			''
		}
		if variant_result != '' {
			// The callee may be declared with the project's layout of the record.
			c.gen('${variant_result}(voidptr(')
		}
		c.fn_call(mut node)
		if variant_result != '' {
			c.gen('))')
		}
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
		flex_element := c.variable_size_element(expr)
		// Optimize (*ptr).field -> ptr.field
		// In V, '.' works on pointers directly, so dereferencing is unnecessary
		mut address_base := expr
		for address_base.inner.len == 1
			&& (address_base.kindof(.paren_expr) || address_base.kindof(.implicit_cast_expr)) {
			address_base = address_base.inner[0]
		}
		if !c.is_cpp && node.is_arrow && address_base.kindof(.unary_operator)
			&& address_base.opcode == '&' && address_base.inner.len == 1 {
			// `(&x)->f` is `x.f`.
			c.expr(address_base.inner[0])
		} else if flex_element.len == 2 {
			// `p->tail[i].f`: address the element through a helper call. The usual
			// `(&p.tail[0])[i].f` form cannot start a V statement, since V
			// continues the previous line with `(`.
			c.ensure_c2v_at_helper()
			c.gen('c2v_at(&')
			c.expr(flex_element[0])
			c.gen('[0], isize(')
			c.expr(flex_element[1])
			c.gen('))')
		} else if operator_reference_base {
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
		anonymous_member := if c.is_cpp && raw_field == '' {
			cpp_anonymous_member_name(node.ast_type.qualified) or { '' }
		} else {
			''
		}
		if anonymous_member != '' {
			field = anonymous_member
		} else if renamed := c.c_field_v_names[node.referenced_member_decl] {
			field = renamed
		} else if receiver_v_type.starts_with('C.')
			|| expr.ast_type.qualified in c.system.anonymous_types {
			// (A system record's field of anonymous record type is declared with
			// the C member names too, see write_system_record_fields.)
			field = if raw_field in v_reserved_words { '@' + raw_field } else { raw_field }
		} else if raw_is_all_upper {
			field = filter_name(raw_field.to_lower(), false).all_after_last('.')
		} else if !c.is_cpp {
			field = c_record_field_v_name(raw_field)
		} else {
			field = filter_name(raw_field, false).all_after_last('.')
		}
		if c.is_cpp && !receiver_v_type.starts_with('C.') && anonymous_member == '' {
			field = field.camel_to_snake().trim_left('_')
			// Derived-to-base conversions of the object are implicit in V.
			receiver_class := c.cpp_derived_cast_root_type(expr)
			current_class := if c.cur_class != '' {
				c.types[c.cur_class] or { c.cur_class }
			} else {
				''
			}
			mut seen := map[string]bool{}
			mut owner := c.cpp_field_owner(receiver_class, field, mut seen)
			if owner == '' {
				seen = map[string]bool{}
				owner = c.cpp_field_owner(current_class, field, mut seen)
			}
			if owner != '' {
				v_field := c.cpp_field_v_names['${owner}.${field}'] or { field }
				field = if owner != receiver_class && c.is_v_abstract_interface_type(receiver_class)
					&& !c.is_v_abstract_interface_type(owner)
					&& owner in c.cpp_concrete_bases_through_abstract(receiver_class) {
					// An abstract class is a V interface: it reaches the fields of a
					// concrete base through that base's accessor.
					cpp_abstract_base_accessor_name(owner) + '().' + v_field
				} else {
					v_field
				}
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
				c.gen('(${sizeof_type_operand(typ.name)})')
				return ''
			}
			if referenced_type := c.sizeof_reference_operand_type(expr) {
				typ := c.convert_type(referenced_type)
				c.gen('(${sizeof_type_operand(typ.name)})')
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
					c.gen('(${sizeof_type_operand(typ.name)})')
				} else {
					// Fallback: output expression
					c.gen('(${sizeof_expr})')
				}
			} else {
				mut cleaned_sizeof := sizeof_expr
				if c.convert_type(expr.ast_type.qualified).name.starts_with('fn ') {
					// A function pointer value: V cannot take `sizeof` of its type.
					cleaned_sizeof = 'voidptr'
				}
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
		if actual_expr.kindof(.member_expr) && actual_expr.referenced_member_decl in c.variable_size_fields
			&& !is_constant_index_within(second_expr, cpp_fixed_array_length(c.convert_type(actual_expr.ast_type.qualified).name)) {
			// A variable sized record tail holds more elements than its declared
			// one: index it through a pointer, without V's fixed array bounds check.
			c.gen('(&')
			c.expr(actual_expr)
			c.gen('[0])[')
			c.expr(second_expr)
			c.gen(']')
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
			c.gen('i32(')
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
	} else if node.kindof(.c_style_cast_expr) && c.is_cpp && cpp_reinterpreted_object(node) != none {
		// `(int &)value` is the object stored at `value`, like a reinterpret_cast.
		c.cxx_cast_expr(node)
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
			// ... but `(void)f(x);` still calls `f`.
			mut operand := expr
			for operand.inner.len == 1 && (operand.kindof(.paren_expr)
				|| (operand.kindof(.c_style_cast_expr) && operand.cast_kind == 'ToVoid')) {
				operand = operand.inner[0]
			}
			if !c.is_cpp && operand.id != '' && operand.id == c.unused_value_expr_id
				&& has_side_effects(operand) {
				if operand.kindof(.call_expr) || operand.kindof(.compound_assign_operator)
					|| (operand.kindof(.binary_operator) && operand.opcode in ['=', ','])
					|| (operand.kindof(.unary_operator) && operand.opcode in ['++', '--']) {
					c.expr(operand)
				} else {
					c.gen('_ = ')
					c.expr(operand)
				}
			}
			return ''
		}
		if !c.is_cpp && node.cast_kind in ['BitCast', 'PointerToIntegral']
			&& (cast.starts_with('&') || c.resolve_type_alias(cast) in v_integer_type_names) {
			mut source := expr
			for source.inner.len == 1
				&& (source.kindof(.paren_expr) || (source.kindof(.implicit_cast_expr)
					&& source.cast_kind in ['LValueToRValue', 'NoOp'])) {
				source = source.inner[0]
			}
			source_v_type := c.convert_type(node_effective_type_name(source)).name
			if source_v_type != cast && source_v_type != 'voidptr'
				&& (source_v_type.starts_with('&') || source_v_type.starts_with('fn '))
				&& !source.kindof(.conditional_operator) && !source.kindof(.string_literal) {
				// V rejects most casts between unrelated pointer types and from
				// pointers to integer aliases; C reinterprets the address.
				c.gen('${cast}(')
				address_operand := unwrap_address_of_operand(source) or { bad_node }
				if c.is_heap_promotable_local(address_operand) {
					c.gen_address_in_cast(address_operand)
				} else {
					c.gen('voidptr(')
					c.expr(expr)
					c.gen(')')
				}
				c.gen(')')
				return ''
			}
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
		source_type := c.cpp_cast_source_type(source_expr)
		if cast == 'voidptr' && c.is_v_abstract_interface_type(source_type) {
			c.gen_cpp_abstract_pointer_erasure(expr, source_type)
			return ''
		}
		abstract_to_integer := is_v_integer_const_type(cast)
			&& c.is_v_abstract_interface_type(source_type)
		integer_to_abstract := c.is_v_abstract_interface_type(cast) && source_type != cast
			&& !c.is_v_abstract_interface_type(source_type)
		if abstract_to_integer || integer_to_abstract {
			c.ensure_cpp_abstract_pointer_cast_helpers()
			if abstract_to_integer {
				c.gen('${cast}(usize(c2v_abstract_pointer_value[${source_type}](')
				c.expr(expr)
				c.gen(')))')
				return ''
			}
			if integer_to_abstract {
				// An integer/void pointer sometimes carries a previously erased C++
				// abstract-base pointer: the object's address. Its class id selects
				// the concrete V type of the interface value.
				c.gen('${c.cpp_address_to_interface_helper(cast)}(voidptr(')
				c.expr(expr)
				c.gen('))')
				return ''
			}
		}
		interface_downcast := source_type != cast && c.is_v_abstract_interface_type(source_type)
			&& (c.is_v_abstract_interface_type(cast) || cast.starts_with('&'))
		if interface_downcast {
			if cast.starts_with('&') && !c.is_v_abstract_interface_type(cast) {
				c.gen_cpp_interface_object_cast(expr, cast)
				return ''
			}
			// A C++ cast between abstract classes is a V type assertion. A
			// constructor-style cast instead asks the source interface itself to
			// implement the target interface.
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
			c.gen('unsafe { *(&${cast}(')
			c.gen_address_in_cast(expr)
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
		float_via := if node.cast_kind == 'FloatingToIntegral' {
			float_conversion_intermediate_type(c.resolve_type_alias(cast))
		} else {
			''
		}
		if float_via != '' {
			c.gen('${float_via}(')
		}
		old_inside_switch := c.inside_switch
		if is_enum_ref_expr(expr) {
			c.inside_switch = 0
		}
		address_operand := unwrap_address_of_operand(expr) or { bad_node }
		if (cast.starts_with('&') || cast == 'voidptr') && c.is_heap_promotable_local(address_operand) {
			c.gen_address_in_cast(address_operand)
		} else {
			c.expr(expr)
		}
		c.inside_switch = old_inside_switch
		if float_via != '' {
			c.gen(')')
		}
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
		mut is_assert := is_c_assert_expansion(node)
		if expr.kindof(.implicit_cast_expr) && expr.inner.len > 0
			&& expr.inner[0].kindof(.call_expr) && expr.inner[0].inner.len > 0
			&& expr.inner[0].inner[0].kindof(.implicit_cast_expr)
			&& expr.inner[0].inner[0].inner.len > 0
			&& expr.inner[0].inner[0].inner[0].ref_declaration.name == '__builtin_expect' {
			is_assert = true
		}
		conditional_type := if c.is_cpp {
			''
		} else {
			c.resolve_type_alias(c.convert_type(node.ast_type.qualified).name)
		}
		if is_assert {
			// Skip assert macros — they're debug-only and produce invalid V syntax
			c.gen('0')
		} else if conditional_type == 'voidptr' {
			// The old V backend cannot type an `if` expression of type voidptr: its
			// branches are byte pointers, converted as a whole.
			old_inside_unsafe := c.inside_unsafe
			c.gen('voidptr(unsafe { if ')
			c.inside_unsafe = true
			c.expr(expr)
			c.gen(' { ')
			c.conditional_eval_depth++
			for i, branch in [case1, case2] {
				if i > 0 {
					c.gen(' } else { ')
				}
				if is_c_null_pointer_constant(branch) {
					c.gen('&u8(nil)')
				} else {
					c.gen('&u8(')
					c.expr(branch)
					c.gen(')')
				}
			}
			c.conditional_eval_depth--
			c.inside_unsafe = old_inside_unsafe
			c.gen(' } })')
		} else {
			// `v fmt` drops an `unsafe` block that forms a whole single-line `if`
			// branch, which leaves a bare `nil`: make the whole expression unsafe.
			wrap_unsafe := !c.inside_unsafe
				&& (is_null_pointer_constant(case1) || is_null_pointer_constant(case2)
					|| (!c.is_cpp && conditional_type.starts_with('&')
						&& (is_c_null_pointer_constant(case1) || is_c_null_pointer_constant(case2))))
			if wrap_unsafe {
				c.inside_unsafe = true
				c.gen('unsafe { ')
			}
			// V gives an `if` of float literals the type f64.
			typed_float := if c.convert_type(node.ast_type.qualified).name == 'f32' {
				'f32'
			} else {
				''
			}
			c.gen('if ')
			c.expr(expr)
			c.gen(' { ')
			c.conditional_eval_depth++
			old_conditional_result_type := c.conditional_result_type
			c.conditional_result_type = c.convert_type(node.ast_type.qualified).name
			c.gen_conditional_branch(case1, typed_float)
			c.gen(' } else {')
			c.gen_conditional_branch(case2, typed_float)
			c.conditional_result_type = old_conditional_result_type
			c.conditional_eval_depth--
			c.gen('}')
			if wrap_unsafe {
				c.gen(' }')
				c.inside_unsafe = false
			}
		}
	} else if node.kindof(.break_stmt) {
		if c.inside_switch == 0 {
			c.genln('break')
		} else if node.id !in c.switch_trailing_breaks && c.switch_end_labels.len > 0 {
			// V's match arms end without `break`; a `break` before the end of an arm
			// leaves the match through the label after it.
			label := c.switch_end_labels.last()
			c.used_switch_end_labels[label] = true
			c.genln('unsafe { goto ${label} }')
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
			c.array_init_depth--
			c.expr(node.inner[0])
			c.array_init_depth++
		}
	} else if node.kindof(.paren_list_expr) {
	} else if node.kindof(.va_arg_expr) {
		typ := c.prefix_external_type(c.convert_type(node.ast_type.qualified).name)
		if c.is_cpp {
			c.gen_cpp_va_arg(node, typ)
			return ''
		}
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
	} else if node.kindof(.compound_stmt) {
	} else if node.kindof(.atomic_expr) {
		c.atomic_expr(node)
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
			c.gen(c.cpp_static_member_v_name(owner, node.ref_declaration.name))
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
		if !c.emitting_callee && !c.is_cpp && c.is_system_record_name(c_name) {
			// `stat` is both a function and `struct stat`; V's `C.stat` is the
			// record, so the function is passed through a wrapper.
			c.gen(c.external_fn_value_wrapper(c_name))
			return
		}
		c.gen('C.${c_name}')
		return
	}
	if is_func_call && !c.is_cpp && c_name in c.compiler_builtin_decls
		&& !is_lowered_compiler_builtin(c_name) {
		// A compiler builtin (`__builtin_clzll`, `__sync_synchronize`) is called
		// through C, declared with the signature Clang gives it.
		c.declare_compiler_builtin(c.compiler_builtin_decls[c_name])
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
		if c.inside_array_index || c.enum_values_as_int {
			need_full_enum = true
		}
		enum_name := c.enum_val_to_enum_name(c_enum_val)
		if c.inside_array_index || c.enum_values_as_int {
			// `foo[ENUM_VAL]` => `foo(i32(ENUM_NAME.ENUM_VAL))`
			c.gen('i32(')
		}
		if need_full_enum {
			c.gen(enum_name)
		}
		if enum_name == '' && c.is_system_enum_constant(c_enum_val) {
			if c.inside_switch_enum {
				c.gen('i32(C.${c_enum_val})')
			} else {
				c.gen('C.${c_enum_val}')
			}
			if c.inside_array_index || c.enum_values_as_int {
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
	if is_enum_val && (c.inside_array_index || c.enum_values_as_int) {
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

// struct_init_cast_type returns the type to cast the initializer `child` of a
// field or array element of type `expected_type` to, or ''. V infers the type
// of an array literal from its first element (`first_in_array`).
fn (c &C2V) struct_init_cast_type(expected_type string, child Node, first_in_array bool) string {
	expected := expected_type.trim_space()
	if expected == '' {
		return ''
	}
	resolved_expected := c.resolve_type_alias(expected)
	child_type := c.resolve_type_alias(c.convert_type(node_effective_type_name(child)).name)
	if child_type == resolved_expected && c.implicit_numeric_cast_will_render(child) {
		return ''
	}
	if c.is_cpp && child.kindof(.implicit_cast_expr)
		&& child.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase']
		&& ((resolved_expected.starts_with('&')
			&& !c.is_v_abstract_interface_type(resolved_expected[1..]))
			|| c.is_v_abstract_interface_type(resolved_expected)) {
		// A pointer to a derived object converts to a pointer to its base (or to
		// the interface of an abstract base), which V does not do implicitly in
		// an array literal, whose type comes from its first element.
		return expected
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
		&& resolved_expected in v_integer_type_names {
		return expected
	}
	// (A signed literal such as `-1` is typed like the literal.)
	literal := if base.kindof(.unary_operator) && base.opcode in ['-', '+'] && base.inner.len == 1
		&& resolved_expected !in ['u8', 'u16', 'u32', 'u64', 'usize'] {
		unwrap_struct_init_expr(base.inner[0])
	} else {
		base
	}
	if literal.kindof(.integer_literal)
		&& (resolved_expected in ['i8', 'i16', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize',
			'f32', 'f64']
			|| (first_in_array && resolved_expected == 'i32')) {
		return expected
	}
	if literal.kindof(.floating_literal) && resolved_expected in ['f32', 'f64'] {
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
	anonymous_record_name := c.anonymous_record_names[anonymous_record_key(t)] or { '' }
	if !is_arr {
		// Struct init
		if anonymous_record_name != '' {
			c_struct_name = anonymous_record_name
		} else if (t.contains('unnamed struct') || t.contains('unnamed union')
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
		converted_struct_literal := if anonymous_record_name != '' {
			anonymous_record_name
		} else if c_struct_name != ''
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
		// elements (with value-initialized holes left by designators). The
		// filler zero-initializes the remaining elements up to the declared
		// length, which the V literal has to spell out.
		if node.array_filler.len > 1 && is_zero_initializer_expr(node.array_filler[0]) {
			for i := 1; i < node.array_filler.len; i++ {
				child_indices << i
			}
		} else {
			for i, _ in node.array_filler {
				child_indices << i
			}
		}
		declared_len := cpp_fixed_array_length(c.convert_type(t).name)
		zero_element := c.v_zero_value(array_element_type)
		for output_i, child_idx in child_indices {
			mut child := node.array_filler[child_idx]
			if child.kindof(.implicit_value_init_expr) {
				c.gen(zero_element)
				if output_i < child_indices.len - 1 {
					c.gen(', ')
				}
				continue
			}
			c.gen_comment(child)
			cast_type := c.struct_init_cast_type(array_element_type, child, output_i == 0)
			if !c.is_cpp && is_c_null_pointer_constant(child)
				&& c.resolve_type_alias(array_element_type).starts_with('fn ') {
				c.gen(c.typed_null_function_pointer(array_element_type))
			} else if !c.is_cpp && is_c_null_pointer_constant(child)
				&& array_element_type.starts_with('&') {
				// V types an array literal by its first element.
				c.gen('unsafe { ${array_element_type}(nil) }')
			} else {
				if cast_type != '' {
					c.gen(cast_type + '(')
				}
				c.expr(child)
				if cast_type != '' {
					c.gen(')')
				}
			}
			if output_i < child_indices.len - 1 {
				if child.kindof(.init_list_expr) {
					c.put_on_same_line_as_close_brace(',', true)
				} else {
					c.gen(', ')
				}
			}
		}
		if child_indices.len < declared_len {
			last_is_record := child_indices.len > 0
				&& node.array_filler[child_indices.last()].kindof(.init_list_expr)
			if last_is_record {
				c.put_on_same_line_as_close_brace(',', true)
			} else if child_indices.len > 0 {
				c.gen(', ')
			}
			c.gen([]string{len: declared_len - child_indices.len, init: zero_element}.join(', '))
		}
	} else {
		mut struct_ := Struct{}
		// A record renamed in this file (its tag names another layout elsewhere).
		if local_name := c.file_type_alias_names[c_struct_name.capitalize()] {
			c_struct_name = local_name
		}
		// A typedef name (`Mem` for `struct sqlite3_value`) names the record by
		// its desugared type.
		desugared_struct_name := parse_c_struct_name(node.ast_type.desugared_qualified)
		if c_struct_name != '' && !is_empty_record_init && c_struct_name !in c.structs && c_struct_name.capitalize() !in c.structs && desugared_struct_name != '' {
			if desugared_struct_name in c.structs {
				c_struct_name = desugared_struct_name
			} else if desugared_struct_name.capitalize() in c.structs {
				c_struct_name = desugared_struct_name.capitalize()
			}
		}
		if c_struct_name != '' && !is_empty_record_init && c_struct_name !in c.structs && c_struct_name.capitalize() !in c.structs {
			// A record from a system header (`pthread_mutex_t m =
			// PTHREAD_MUTEX_INITIALIZER`): its fields come from Clang's AST.
			if system_struct := c.system_record_struct(c_struct_name) {
				c.structs[c_struct_name] = system_struct
			} else if system_struct := c.system_record_struct(desugared_struct_name) {
				c.structs[c_struct_name] = system_struct
			}
		}
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
				c.struct_init_cast_type(array_element_type, child, i == 0)
			} else {
				''
			}
			if !is_arr && i < struct_.field_types.len {
				expected_field_type = struct_.field_types[i]
				cast_type = c.struct_init_cast_type(expected_field_type, child, false)
			}
			slot_type := if is_arr { array_element_type } else { expected_field_type }
			if !c.is_cpp && is_c_null_pointer_constant(child)
				&& c.resolve_type_alias(slot_type).starts_with('fn ') {
				c.gen(c.typed_null_function_pointer(slot_type))
			} else if !c.is_cpp && is_arr && is_c_null_pointer_constant(child)
				&& slot_type.starts_with('&') {
				// V types an array literal by its first element.
				c.gen('unsafe { ${slot_type}(nil) }')
			} else if !c.is_cpp && ((c.resolve_type_alias(slot_type) == 'voidptr'
				&& is_function_value(child))
				|| c.file_variant_pointer_type(child.ast_type.qualified) != '') {
				// A function stored in a `void *` (`pUserData: ceil`).
				c.gen('voidptr(')
				c.expr(child)
				c.gen(')')
			} else if !c.is_cpp && c.gen_function_as_fn_type(child, slot_type) {
				// Converted above.
			} else if cpp_fixed_array_length(expected_field_type) > 0 && child.kindof(.string_literal) {
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
	// (`path.trim_space()` without allocating.)
	mut i := 0
	for i < path.len && path[i] in [` `, `\n`, `\t`, `\v`, `\f`, `\r`] {
		i++
	}
	return i == path.len || path[i] == `<`
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

// Clang options for parsing C sources for translation:
// - Clang's JSON AST drops the member designator of `__builtin_offsetof`, so it
//   is spelled as the equivalent null-pointer member address.
// - Fortified libc headers turn calls such as `memcpy` into compiler checking
//   builtins (`__builtin___memcpy_chk`); translate the plain libc calls.
// - V has no 128-bit integers: translate for a target without `__int128`.
const c_translation_clang_flags = "'-D__builtin_offsetof(T,M)=((__SIZE_TYPE__)&(((T *)0)->M))' -U_FORTIFY_SOURCE -D_FORTIFY_SOURCE=0 -U__SIZEOF_INT128__"

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

// source_has_text_at reports whether `text` occurs in `source` at `index`.
fn source_has_text_at(source string, index int, text string) bool {
	if index < 0 || index + text.len > source.len {
		return false
	}
	for j in 0 .. text.len {
		if source[index + j] != text[j] {
			return false
		}
	}
	return true
}

fn scan_cpp_abstract_type_names(source string) []string {
	clean := sanitize_cpp_metadata_source(source)
	mut names := map[string]bool{}
	mut i := 0
	for i < clean.len {
		// (Slicing the tail would copy it at every position.)
		is_class := source_has_text_at(clean, i, 'class')
		if !((is_class || source_has_text_at(clean, i, 'struct'))
			&& (i == 0 || !is_identifier_char(clean[i - 1]))) {
			i++
			continue
		}
		keyword_len := if is_class { 5 } else { 6 }
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

// scan_c_constant_names returns the enumerators and object-like macro names a
// source declares.
fn scan_c_constant_names(source string) []string {
	clean := sanitize_cpp_metadata_source(source)
	mut names := []string{}
	for line in clean.split_into_lines() {
		trimmed := line.trim_space()
		if trimmed.starts_with('#') {
			directive := trimmed[1..].trim_space()
			if directive.starts_with('define ') {
				name := directive['define '.len..].trim_space()
				mut end := 0
				for end < name.len && is_identifier_char(name[end]) {
					end++
				}
				// Function-like macros are not constants.
				if end > 0 && (end == name.len || name[end] != `(`) {
					names << name[..end]
				}
			}
		}
	}
	// File-scope constants: `const float EPSILON = 1e-6f;`.
	mut depth := 0
	mut statement := strings.new_builder(128)
	mut line_start := true
	mut in_directive := false
	for ch in clean {
		// Preprocessor lines (`#include`, `#pragma`) are not part of a declaration.
		if ch == `\n` {
			line_start = true
			in_directive = false
			if depth == 0 {
				statement.write_u8(` `)
			}
			continue
		}
		if line_start && ch != ` ` && ch != `\t` && ch != `\r` {
			line_start = false
			in_directive = ch == `#`
		}
		if in_directive {
			continue
		}
		if ch == `{` {
			depth++
			statement = strings.new_builder(128)
		} else if ch == `}` {
			depth--
			statement = strings.new_builder(128)
		} else if depth == 0 && ch == `;` {
			text := statement.str().trim_space()
			statement = strings.new_builder(128)
			if (text.starts_with('const ') || text.starts_with('static const ')
				|| text.starts_with('constexpr ')) && text.contains('=') && !text.contains('(') {
				declarator := text.all_before('=').trim_space()
				mut start := declarator.len
				for start > 0 && is_identifier_char(declarator[start - 1]) {
					start--
				}
				if start < declarator.len {
					names << declarator[start..]
				}
			}
		} else if depth == 0 {
			statement.write_u8(ch)
		}
	}
	mut i := 0
	for {
		start := clean.index_after('enum', i) or { break }
		i = start + 4
		if (start > 0 && is_identifier_char(clean[start - 1]))
			|| (i < clean.len && is_identifier_char(clean[i])) {
			continue
		}
		open := clean.index_after('{', i) or { break }
		semicolon := clean.index_after(';', i) or { clean.len }
		if semicolon < open {
			continue
		}
		close := clean.index_after('}', open) or { break }
		for item in clean[open + 1..close].split(',') {
			name := item.all_before('=').trim_space()
			if name != '' && name.bytes().all(is_identifier_char(it)) {
				names << name
			}
		}
		i = close
	}
	return names
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
		// Enumerators and macros can become module constants in any translation
		// unit; a local variable spelled like one would resolve to the constant.
		for const_name in scan_c_constant_names(source) {
			c2v.project_const_v_names[filter_name(c_identifier_to_v_name(const_name), false)] = true
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
		eprintln('  -split_files\t\twrite one V file per original source file (#line directives, headers)')
		eprintln('  -skip_comments\toutput no comments')
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
				c2v.dedupe_c_function_prototypes()
				c2v.rewrite_project_defined_function_decls()
				c2v.rewrite_project_defined_global_refs()
				c2v.save_globals()
				c2v.sanitize_strict_cpp_backend_outputs()
				c2v.verify_no_generated_stubs()
				if c2v.skip_comments {
					c2v.strip_output_comments()
				}
				if c2v.project_module_name != 'main' {
					c2v.make_output_declarations_public()
				}
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
	return strip_redundant_multiline_value_dereferences(src)
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
	for i, mut node in root_node.inner {
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
			c.insert_comment_node(mut node, comment_node)
			return false
		} else if begin_offset > comment_node.location.offset {
			if c.split_files && root_node.kind_str == ''
				&& c.split_file_at(root_node.location.file, comment_node.location.offset) != c.split_file_at(root_node.location.file, begin_offset) {
				// The comment is in another file than the declaration (see split.v).
				root_node.inner.insert(i, comment_node)
				c.can_output_comment[comment_node.unique_id] = true
				return true
			}
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
		// Keep old behavior in single-file mode for test compatibility, but only
		// for statement lists: a comment appended to an expression, such as after
		// the last element of an initializer list, would become an operand.
		// (Node kinds are not resolved yet: test the Clang spelling.)
		if root_node.kind_str !in ['', 'CompoundStmt', 'TranslationUnitDecl', 'EnumDecl', 'RecordDecl'] {
			return false
		}
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

// cached_real_path resolves a source path once per run.
fn (mut c2v C2V) cached_real_path(path string) string {
	if resolved := c2v.real_path_cache[path] {
		return resolved
	}
	mut resolved := os.real_path(path)
	if resolved == '' {
		resolved = path
	}
	c2v.real_path_cache[path] = resolved
	return resolved
}

struct SourceComment {
	offset int
	text   string
}

// source_comments returns the comments of a source file, scanned once: a
// translation unit visits the same header in many AST segments.
fn (mut c2v C2V) source_comments(path string) ?[]SourceComment {
	if comments := c2v.source_comment_cache[path] {
		return comments
	}
	if !source_path_exists(path) {
		return none
	}
	str := os.read_file(path) or { return none }
	comments := scan_source_comments(str)
	c2v.source_comment_cache[path] = comments
	return comments
}

// scan_source_comments uses a DFA to recognize the C comments // and /**/;
// a multi-line comment is converted to single-line comments.
fn scan_source_comments(str string) []SourceComment {
	mut curr_state := CommentState.s0
	mut comments := []SourceComment{}
	mut comment := strings.new_builder(1024)
	mut comment_str := ''

	mut offset := 0
	mut comment_offset := 0

	// scan c file for comments
	for c in str {
		match curr_state {
			.s0 {
				if c == `/` {
					comment_offset = offset
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
					comments << SourceComment{
						offset: comment_offset
						text:   comment_str
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
					comments << SourceComment{
						offset: comment_offset
						text:   comment_str
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
	return comments
}

// parse_comment adds the comments of a source file to an AST segment, based
// on the comment nodes' offsets.
fn (mut c2v C2V) parse_comment(mut root_node Node, path string) {
	if c2v.skip_comments {
		return
	}
	comments := c2v.source_comments(path) or { return }
	// A file contributes one AST segment per run of declarations between
	// `#include`s of other files. Only collect comments inside this segment to
	// avoid repeated comment blocks from the same file across disjoint segments.
	// Outside dir mode, comments before the segment that no earlier segment took
	// belong to its first declaration, and comments after the file's last
	// segment are appended by `append_trailing_comments`.
	mut seg_begin := 0
	mut seg_end := int(max_i32)
	if c2v.is_dir || root_node.inner.len > 0 {
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
		if !c2v.is_dir {
			seg_begin = 0
		}
	}
	mut comment_id := 0
	mut comment_nodes := []Node{}
	for comment in comments {
		if comment.offset < seg_begin || comment.offset > seg_end {
			continue
		}
		comment_key := '${path}:${comment.offset}:${comment.text}'
		if c2v.seen_comments[comment_key] {
			continue
		}
		c2v.seen_comments[comment_key] = true
		comment_nodes << Node{
			unique_id: c2v.cnt
			id:        'text_comment_${c2v.cnt}'
			comment:   comment.text
			location:  NodeLocation{
				offset: comment.offset
			}
			kind:      .text_comment
			kind_str:  'TextComment'
		}
		c2v.cnt++
		comment_id++
	}
	for node in comment_nodes {
		c2v.insert_comment_node(mut root_node, node)
	}
}

// collect_nested_record_types registers the named records defined inside `node`
// (file scope types in C).
fn (mut c2v C2V) collect_nested_record_types(node Node) {
	for field in node.inner {
		if field.kindof(.record_decl) && field.inner.len > 0 {
			if field.name != '' && field.name !in builtin_type_names {
				c2v.known_types[field.name.trim_left('_').capitalize()] = true
			}
			c2v.collect_nested_record_types(field)
		}
	}
}

// append_trailing_comments keeps the comments after the last declaration of the
// translated file, which no AST segment of the file covers.
fn (mut c2v C2V) append_trailing_comments(path string) {
	if c2v.skip_comments {
		return
	}
	comments := c2v.source_comments(path) or { return }
	for comment in comments {
		comment_key := '${path}:${comment.offset}:${comment.text}'
		if c2v.seen_comments[comment_key] {
			continue
		}
		c2v.seen_comments[comment_key] = true
		c2v.tree.inner << Node{
			unique_id: c2v.cnt
			id:        'text_comment_trailing_${comment.offset}'
			comment:   comment.text
			location:  NodeLocation{
				offset: comment.offset
			}
			kind:      .text_comment
			kind_str:  'TextComment'
		}
		c2v.can_output_comment[c2v.cnt] = true
		c2v.cnt++
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
		additional_clang_flags += ' ' + c_translation_clang_flags
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

	if !c2v.is_cpp && !c2v.is_wrapper {
		c2v.collect_direct_system_includes(path, additional_clang_flags)
		// Feature test macros (`#define _GNU_SOURCE`) select what the system
		// headers declare, so they must precede all of them, V's own included.
		for define in leading_feature_test_macros(c2v.source_text) {
			key := 'feature_test_macro:${define}'
			if key !in c2v.generated_declarations {
				c2v.generated_declarations[key] = true
				c2v.local_type_declarations << "#flag '-D${define}'\n\n"
			}
		}
	}
	// preparation pass, fill all seen_ids ...
	c2v.seen_ids = {}
	c2v.callback_seen_ids = {}
	for i, mut node in c2v.tree.inner {
		c2v.node_i = i
		c2v.seen_ids[node.id] = unsafe { node }
		c2v.collect_seen_ids_recursive(mut node)
	}
	c2v.index_seen_declarations()
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
				if next_node.kind == .typedef_decl && typedef_names_tag(&next_node, &node) {
					c_name = next_node.name
					if !c2v.is_cpp && node.name != '' && node.name.capitalize() != c_name.capitalize() {
						// `typedef struct pgNotify {...} PGnotify;`: the record is
						// named by its typedef, also where the tag names it.
						c2v.record_tag_v_names[node.name.capitalize()] = c_name.capitalize()
					}
				}
			}
			if c_name != '' && c_name !in builtin_type_names {
				c2v.known_types[c_name.trim_left('_').capitalize()] = true
			}
			if !c2v.is_cpp {
				c2v.collect_nested_record_types(node)
			}
		} else if node.kindof(.enum_decl) {
			mut c_name := node.name
			if c2v.tree.inner.len > i + 1 {
				next_node := c2v.tree.inner[i + 1]
				if next_node.kind == .typedef_decl && typedef_names_tag(&next_node, &node) {
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
	if c2v.split_files {
		c2v.split_current_file = c2v.split_main_file
	}
	for i, node in c2v.tree.inner {
		vprintln('\ndoing top node ${i} ${node.kind} name="${node.name}"')
		c2v.node_i = i
		if c2v.split_files {
			c2v.mark_split_file(c2v.split_source_file(node))
		}
		c2v.top_level(node)
	}
	if c2v.split_files {
		c2v.mark_split_file(c2v.split_main_file)
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

fn resolve_node_file_path(n &Node) string {
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
		if is_cpp_body_decl_node_by_kind_str(child) && resolve_node_file_path(&child) == '' {
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
	mut node_file := resolve_node_file_path(&n)
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
		c2v.cur_file = c2v.cached_real_path(node_file)
		if c2v.file_index(c2v.cur_file) < 0 {
			c2v.file_indexes[c2v.cur_file] = c2v.files.len
			c2v.files << c2v.cur_file
		}
	}
	n.location.file_index = c2v.file_index(c2v.cur_file)

	for mut child in n.inner {
		c2v.set_file_index(mut child)
	}

	for mut child in n.array_filler {
		c2v.set_file_index(mut child)
	}
	c2v.cur_file = parent_file
}

// file_index returns the index of `path` in `files`, or -1.
fn (mut c2v C2V) file_index(path string) int {
	if index := c2v.file_indexes[path] {
		if index < c2v.files.len && c2v.files[index] == path {
			return index
		}
	}
	index := c2v.files.index(path)
	if index >= 0 {
		c2v.file_indexes[path] = index
	}
	return index
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
// returned_fn_type_alias names a V function type that is the return type of
// another function type: `C2vFn_<hex of the signature>`.
fn returned_fn_type_alias(v_fn_type string) string {
	if !v_fn_type.starts_with('fn ') {
		return v_fn_type
	}
	return 'C2vFn_' + function_pointer_cast_type_token(v_fn_type)
}

// returned_fn_type_signature decodes the signature named by a `C2vFn_` alias.
fn returned_fn_type_signature(name string) ?string {
	if !name.starts_with('C2vFn_') {
		return none
	}
	token := name[6..]
	mut signature := []u8{}
	for i := 0; i + 1 < token.len; i += 2 {
		signature << u8(('0x' + token[i..i + 2]).u8())
	}
	return signature.bytestr()
}

// returned_fn_type_aliases declares the `C2vFn_` aliases used by `src`.
fn returned_fn_type_aliases(src string) []string {
	mut declarations := []string{}
	mut seen := map[string]bool{}
	mut from := 0
	for {
		start := src.index_after_('C2vFn_', from)
		if start < 0 {
			break
		}
		mut end := start + 6
		for end < src.len && src[end].is_hex_digit() {
			end++
		}
		from = end
		name := src[start..end]
		if name in seen || (start > 0 && is_simple_identifier_char(src[start - 1])) {
			continue
		}
		seen[name] = true
		signature := returned_fn_type_signature(name) or { continue }
		declarations << 'type ${name} = ${signature}'
	}
	return declarations
}

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
	return base in ['bool', 'i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
		'usize', 'f32', 'f64', 'byte', 'voidptr']
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
	out.writeln(c2v.v_module_header())
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
				typ_name = 'i32'
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

// c2v_va_list_source declares the translated `va_list`: the arguments of a
// translated variadic function (small integer literals as immediates, other
// values by the address of their promoted value; see write_voidptr_arg_expr)
// and the position of the next one. Passing a `va_list` on shares the
// position, as consuming a passed `va_list` leaves the caller's indeterminate.
fn c2v_va_list_source() string {
	return [
		'struct C2vVaList {',
		'\targs []voidptr',
		'mut:',
		'\tindex int',
		'}',
		'',
		'fn c2v_va_start(args []voidptr) &C2vVaList {',
		'\treturn &C2vVaList{',
		'\t\targs: args',
		'\t}',
		'}',
		'',
		'fn c2v_va_copy(ap &C2vVaList) &C2vVaList {',
		'\tif isnil(ap) {',
		'\t\treturn unsafe { nil }',
		'\t}',
		'\treturn &C2vVaList{',
		'\t\targs:  ap.args',
		'\t\tindex: ap.index',
		'\t}',
		'}',
		'',
		'fn c2v_va_end(ap &C2vVaList) {}',
		'',
		'fn c2v_va_arg(ap &C2vVaList) voidptr {',
		'\tif isnil(ap) || ap.index >= ap.args.len {',
		'\t\treturn unsafe { nil }',
		'\t}',
		'\tvalue := ap.args[ap.index]',
		'\tap.index++',
		'\treturn value',
		'}',
		'',
		'// c2v_va_rest returns the arguments that remain to be read.',
		'fn c2v_va_rest(ap &C2vVaList) []voidptr {',
		'\tif isnil(ap) || ap.index >= ap.args.len {',
		'\t\treturn []voidptr{}',
		'\t}',
		'\treturn ap.args[ap.index..]',
		'}',
		'',
		'fn c2v_va_is_immediate(raw usize) bool {',
		'\treturn raw < usize(1048576) || raw > ~usize(0) - usize(1048576)',
		'}',
		'',
		'fn c2v_va_integer(ap &C2vVaList, wide bool) i64 {',
		'\targ := c2v_va_arg(ap)',
		'\tif c2v_va_is_immediate(usize(arg)) {',
		'\t\treturn i64(isize(usize(arg)))',
		'\t}',
		'\tif wide {',
		'\t\treturn unsafe { *(&i64(arg)) }',
		'\t}',
		'\treturn i64(unsafe { *(&i32(arg)) })',
		'}',
		'',
		'fn c2v_va_float(ap &C2vVaList) f64 {',
		'\targ := c2v_va_arg(ap)',
		'\tif c2v_va_is_immediate(usize(arg)) {',
		'\t\treturn f64(isize(usize(arg)))',
		'\t}',
		'\treturn unsafe { *(&f64(arg)) }',
		'}',
		'',
	].join('\n')
}

// gen_cpp_va_arg reads the next argument of a translated `va_list` as `typ`,
// decoding it the way write_voidptr_arg_expr passed it.
fn (mut c C2V) gen_cpp_va_arg(node &Node, typ string) {
	list := if node.inner.len > 0 {
		c.render_expr_to_string(c.unwrap_expr_for_deref_check(node.inner[0]))
	} else {
		'unsafe { nil }'
	}
	c_type := if node.ast_type.desugared_qualified != '' {
		node.ast_type.desugared_qualified
	} else {
		node.ast_type.qualified
	}
	value_type := convert_type(c_type).name
	if c.is_v_abstract_interface_type(typ) {
		c.gen('${c.cpp_address_to_interface_helper(typ)}(c2v_va_arg(${list}))')
	} else if c_type.contains('*') || typ.starts_with('&') || typ == 'voidptr'
		|| typ.starts_with('fn ') {
		c.gen('unsafe { ${typ}(c2v_va_arg(${list})) }')
	} else if value_type in ['f32', 'f64'] {
		c.gen('${typ}(c2v_va_float(${list}))')
	} else if value_type == 'bool' {
		c.gen('(c2v_va_integer(${list}, false) != 0)')
	} else if value_type in ['i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize',
		'usize', 'byte', 'rune', 'char'] || c_type.starts_with('enum ') || c.is_known_enum_v_type(typ) {
		wide := value_type in ['i64', 'u64', 'isize', 'usize']
		c.gen('${typ}(c2v_va_integer(${list}, ${wide}))')
	} else {
		c.gen('unsafe { *(&${typ}(c2v_va_arg(${list}))) }')
	}
}

// c2v_alloca_source declares the storage of C `alloca`: heap blocks that the
// calling function chains together and frees when it returns (see
// add_alloca_scopes). Each block starts with the address of the block
// allocated before it; no GC memory is involved, as `alloca` is common in hot
// code and on threads that foreign libraries create.
fn c2v_alloca_source() string {
	// (The chain head is a record field: a `mut` parameter of a pointer type
	// is passed by value, so the caller would never see the new head.)
	return [
		'struct C2vAllocaBlocks {',
		'mut:',
		'\thead voidptr',
		'}',
		'',
		'fn c2v_alloca(mut blocks C2vAllocaBlocks, size usize) voidptr {',
		'\tblock := unsafe { C.malloc(size + 16) }',
		'\tunsafe {',
		'\t\t*(&voidptr(block)) = blocks.head',
		'\t}',
		'\tblocks.head = block',
		'\treturn unsafe { voidptr(usize(block) + 16) }',
		'}',
		'',
		'fn c2v_alloca_free(blocks C2vAllocaBlocks) {',
		'\tmut block := blocks.head',
		'\tfor block != unsafe { nil } {',
		'\t\tnext := unsafe { *(&voidptr(block)) }',
		'\t\tunsafe { C.free(block) }',
		'\t\tblock = next',
		'\t}',
		'}',
		'',
	].join('\n')
}

// skip_balanced_group returns the index after the `(...)` or `[...]` group
// that opens at `open_idx`, or -1 when it is not closed.
fn skip_balanced_group(src string, open_idx int) int {
	mut depth := 0
	mut quote := u8(0)
	for i := open_idx; i < src.len; i++ {
		ch := src[i]
		if quote != 0 {
			if ch == `\\` {
				i++
			} else if ch == quote {
				quote = 0
			}
			continue
		}
		if ch == `'` || ch == `"` || ch == `\`` {
			quote = ch
		} else if ch == `(` || ch == `[` {
			depth++
		} else if ch == `)` || ch == `]` {
			depth--
			if depth == 0 {
				return i + 1
			}
		}
	}
	return -1
}

// parenthesize_c_global_call_addresses wraps the operand of `&` in parentheses
// when it is a call chain rooted at a C global: V reads
// `&C.game.player().origin` as a cast to the type `&C.game.player`.
fn parenthesize_c_global_call_addresses(src string) string {
	if !src.contains('&C.') {
		return src
	}
	mut out := strings.new_builder(src.len)
	mut i := 0
	for i < src.len {
		if src[i] != `&` || !src[i..].starts_with('&C.')
			|| (i > 0 && (is_identifier_char(src[i - 1]) || src[i - 1] == `&`)) {
			out.write_u8(src[i])
			i++
			continue
		}
		// The chain: `C.name`, then members, calls and indexes.
		mut end := i + 3
		for end < src.len && is_identifier_char(src[end]) {
			end++
		}
		mut members := 0
		mut has_call := false
		for end < src.len {
			if src[end] == `.` && end + 1 < src.len && is_identifier_char(src[end + 1]) {
				end++
				for end < src.len && is_identifier_char(src[end]) {
					end++
				}
				members++
			} else if (src[end] == `(` && members > 0) || src[end] == `[` {
				group_end := skip_balanced_group(src, end)
				if group_end < 0 {
					break
				}
				has_call = has_call || src[end] == `(`
				end = group_end
			} else {
				break
			}
		}
		if has_call {
			out.write_string('&(')
			out.write_string(src[i + 1..end])
			out.write_string(')')
		} else {
			out.write_string(src[i..end])
		}
		i = end
	}
	return out.str()
}

// parenthesize_c_global_loop_operands wraps a C global that ends the header of
// a `for` loop in parentheses: V reads `for n > C.limit {` as the struct
// literal `C.limit{...}`.
fn parenthesize_c_global_loop_operands(src string) string {
	if !src.contains(' C.') {
		return src
	}
	mut lines := src.split_into_lines()
	for i, line in lines {
		if !line.trim_space().starts_with('for ') || !line.ends_with(' {') {
			continue
		}
		header := line[..line.len - 2]
		start := header.last_index(' ') or { continue }
		operand := header[start + 1..]
		if operand.starts_with('C.') && !header[..start].ends_with(' in')
			&& !operand.bytes().any(!is_identifier_char(it) && it != `.`) {
			lines[i] = header[..start + 1] + '(' + operand + ') {'
		}
	}
	return lines.join('\n') + if src.ends_with('\n') { '\n' } else { '' }
}

// wrap_returned_receivers returns the receiver of a method that returns a
// reference (`return *this;`) inside `unsafe`: V's new compiler rejects a
// plain reference to a receiver, which may be stored on the stack.
fn wrap_returned_receivers(src string) string {
	if !src.contains('return this\n') {
		return src
	}
	mut lines := src.split_into_lines()
	mut returns_reference := false
	for i, line in lines {
		if line.starts_with('fn ') {
			returns_reference = line.all_after_last(')').trim_space().starts_with('&')
		} else if returns_reference && line.trim_space() == 'return this' {
			lines[i] = line.replace('return this', 'return unsafe { this }')
		}
	}
	return lines.join('\n') + if src.ends_with('\n') { '\n' } else { '' }
}

// add_alloca_scopes gives every function that calls `c2v_alloca` the chain of
// its blocks, freed when the function returns like C `alloca` storage.
fn add_alloca_scopes(src string) string {
	if !src.contains('c2v_alloca(mut c2v_alloca_blocks') {
		return src
	}
	lines := src.split('\n')
	mut result := []string{cap: lines.len + 16}
	mut i := 0
	for i < lines.len {
		line := lines[i]
		result << line
		i++
		if !line.starts_with('fn ') || !line.ends_with('{') {
			continue
		}
		mut end := i
		for end < lines.len && lines[end] != '}' {
			end++
		}
		mut uses_alloca := false
		for j in i .. end {
			if lines[j].contains('c2v_alloca(mut c2v_alloca_blocks') {
				uses_alloca = true
				break
			}
		}
		if uses_alloca {
			result << '\tmut c2v_alloca_blocks := C2vAllocaBlocks{}'
			result << '\tdefer {'
			result << '\t\tc2v_alloca_free(c2v_alloca_blocks)'
			result << '\t}'
		}
	}
	return result.join('\n')
}

// collect_address_taken_functions records the functions and static methods
// that a translation unit uses as values rather than calling them: callbacks,
// which foreign code may call on threads it created (see c2v_threads_source).
fn collect_address_taken_functions(node &Node, mut ids map[string]bool) {
	// (Runs on the raw AST: node kinds are only known by name here.)
	if node.kind_str in ['CallExpr', 'CXXMemberCallExpr', 'CXXOperatorCallExpr'] && node.inner.len > 0 {
		mut callee := unsafe { &node.inner[0] }
		for callee.kind_str == 'ImplicitCastExpr' && callee.inner.len == 1 {
			callee = unsafe { &callee.inner[0] }
		}
		if callee.kind_str != 'DeclRefExpr' {
			collect_address_taken_functions(callee, mut ids)
		}
		for i in 1 .. node.inner.len {
			collect_address_taken_functions(unsafe { &node.inner[i] }, mut ids)
		}
		return
	}
	if node.kind_str == 'DeclRefExpr' && node.ref_declaration.id != ''
		&& node.ref_declaration.kind_str in ['FunctionDecl', 'CXXMethodDecl'] {
		ids[node.ref_declaration.id] = true
	}
	for i in 0 .. node.inner.len {
		collect_address_taken_functions(unsafe { &node.inner[i] }, mut ids)
	}
}

// collect_mutated_variables records the variables whose storage is written
// (`g = x`, `g.a[i] += 1`, `g++`) or whose address is taken (`&g`, `f(array)`),
// which therefore cannot be V constants.
// (Runs on the raw AST: node kinds are only known by name here.)
fn collect_mutated_variables(node &Node, mut ids map[string]bool) {
	match node.kind_str {
		'BinaryOperator' {
			if node.opcode == '=' && node.inner.len > 0 {
				mark_variable_storage(node.inner[0], mut ids)
			}
		}
		'CompoundAssignOperator' {
			if node.inner.len > 0 {
				mark_variable_storage(node.inner[0], mut ids)
			}
		}
		'UnaryOperator' {
			if node.opcode in ['++', '--', '&'] && node.inner.len > 0 {
				mark_variable_storage(node.inner[0], mut ids)
			}
		}
		'ImplicitCastExpr' {
			if node.cast_kind == 'ArrayToPointerDecay' && node.inner.len > 0 {
				mark_variable_storage(node.inner[0], mut ids)
			}
		}
		'ArraySubscriptExpr' {
			// Indexing an array reads it; only its decay elsewhere exposes it.
			if node.inner.len == 2 {
				base := node.inner[0]
				if base.kind_str == 'ImplicitCastExpr' && base.cast_kind == 'ArrayToPointerDecay'
					&& base.inner.len == 1 {
					collect_mutated_variables(&base.inner[0], mut ids)
				} else {
					collect_mutated_variables(&base, mut ids)
				}
				collect_mutated_variables(&node.inner[1], mut ids)
				return
			}
		}
		else {}
	}
	for i in 0 .. node.inner.len {
		collect_mutated_variables(unsafe { &node.inner[i] }, mut ids)
	}
}

// mark_variable_storage marks the variable whose own storage `lvalue` is part
// of (not storage reached through a pointer).
fn mark_variable_storage(lvalue Node, mut ids map[string]bool) {
	mut current := lvalue
	for {
		if current.kind_str in ['ParenExpr', 'ImplicitCastExpr'] && current.inner.len == 1 {
			current = current.inner[0]
		} else if current.kind_str == 'MemberExpr' && !current.is_arrow && current.inner.len == 1 {
			current = current.inner[0]
		} else if current.kind_str == 'ArraySubscriptExpr' && current.inner.len == 2
			&& current.inner[0].kind_str == 'ImplicitCastExpr'
			&& current.inner[0].cast_kind == 'ArrayToPointerDecay' {
			current = current.inner[0]
		} else {
			break
		}
	}
	if current.kind_str == 'DeclRefExpr' && current.ref_declaration.id != '' {
		ids[current.ref_declaration.id] = true
	}
}

// is_gc_thread_entry reports whether a function definition is used as a value
// in the current translation unit (see collect_address_taken_functions).
fn (c &C2V) is_gc_thread_entry(node &Node) bool {
	return (node.id != '' && node.id in c.gc_thread_entry_fns)
		|| (node.previous_declaration != '' && node.previous_declaration in c.gc_thread_entry_fns)
}

// threads_support_in_globals reports whether the globals file declares the
// foreign-thread helpers (see c2v_threads_source).
fn (c &C2V) threads_support_in_globals() bool {
	return c.is_dir && !c.project_generate_stubs && !c.skeleton_mode
}

// c2v_threads_source is the support for threads that foreign libraries create
// (a sound mixing thread, for example) and that call back into translated
// code. The Boehm GC aborts when it collects on a thread it does not know, and
// does not scan such a thread's stack: such callbacks register their thread,
// which is unregistered when it exits.
fn c2v_threads_source() string {
	return [
		'fn C.GC_thread_is_registered() i32',
		'fn C.GC_allow_register_threads()',
		'fn C.pthread_key_create(voidptr, voidptr) i32',
		'fn C.pthread_setspecific(usize, voidptr) i32',
		'',
		'__global c2v_gc_thread_key = u64(0)',
		'',
		'fn c2v_gc_thread_exit(value voidptr) {',
		'\t\$if gcboehm ? {',
		'\t\tC.GC_unregister_my_thread()',
		'\t}',
		'}',
		'',
		'fn c2v_gc_register_thread() {',
		'\t\$if gcboehm ? {',
		'\t\tif C.GC_thread_is_registered() != 0 {',
		'\t\t\treturn',
		'\t\t}',
		'\t\t// (Room for a `struct GC_stack_base`.)',
		'\t\tmut base := [4]voidptr{}',
		'\t\tif C.GC_get_stack_base(unsafe { voidptr(&base[0]) }) != 0 {',
		'\t\t\treturn',
		'\t\t}',
		'\t\tC.GC_register_my_thread(unsafe { voidptr(&base[0]) })',
		'\t\t\$if !windows {',
		'\t\t\t// Unregister the thread when it exits.',
		'\t\t\tif c2v_gc_thread_key == 0 {',
		'\t\t\t\tC.pthread_key_create(voidptr(&c2v_gc_thread_key), voidptr(c2v_gc_thread_exit))',
		'\t\t\t}',
		'\t\t\tC.pthread_setspecific(usize(c2v_gc_thread_key), voidptr(1))',
		'\t\t}',
		'\t}',
		'}',
		'',
		'fn c2v_gc_allow_threads() {',
		'\t\$if gcboehm ? {',
		'\t\tC.GC_allow_register_threads()',
		'\t}',
		'}',
		'',
	].join('\n')
}

// va_list_helpers_in_globals reports whether the globals file declares the
// translated `va_list` (with the other strict C++ helpers).
fn (c &C2V) va_list_helpers_in_globals() bool {
	return c.is_dir && c.project_has_cpp && !c.project_generate_stubs && !c.skeleton_mode
}

fn c2v_variadic_compat_source() string {
	return [
		c2v_va_list_source(),
		'// The C `v*printf` functions of translated code format the remaining',
		'// arguments of a translated `va_list`.',
		'fn c2v_vsnprintf[T](dest &i8, size T, fmt &i8, ap &C2vVaList) i32 {',
		'\treturn c2v_format_variadic(dest, int(size), fmt, c2v_va_rest(ap))',
		'}',
		'',
		'fn c2v_vsprintf(dest &i8, fmt &i8, ap &C2vVaList) i32 {',
		'\treturn c2v_format_variadic(dest, max_i32, fmt, c2v_va_rest(ap))',
		'}',
		'',
		'fn c2v_vfprintf(stream &C.FILE, fmt &i8, ap &C2vVaList) i32 {',
		'\tmut buffer := [16384]i8{}',
		'\twritten := c2v_format_variadic(unsafe { &buffer[0] }, buffer.len, fmt, c2v_va_rest(ap))',
		'\tC.fputs(unsafe { voidptr(&buffer[0]) }, stream)',
		'\treturn written',
		'}',
		'',
		'fn c2v_vprintf(fmt &i8, ap &C2vVaList) i32 {',
		'\treturn c2v_vfprintf(C.stdout, fmt, ap)',
		'}',
		'',
		'fn c2v_variadic_signed(arg voidptr, wide bool) i64 {',
		'\traw := usize(arg)',
		'\tif c2v_va_is_immediate(raw) {',
		'\t\treturn i64(isize(raw))',
		'\t}',
		'\tif wide {',
		'\t\treturn unsafe { *(&i64(arg)) }',
		'\t}',
		'\treturn i64(unsafe { *(&i32(arg)) })',
		'}',
		'',
		'fn c2v_variadic_unsigned(arg voidptr, wide bool) u64 {',
		'\traw := usize(arg)',
		'\tif c2v_va_is_immediate(raw) {',
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
		'fn c2v_format_variadic(dest &i8, size_2 int, fmt &i8, args []voidptr) i32 {',
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
		'\t\t\t\tunsafe { *(&i32(arg)) = i32(out_pos) }',
		'\t\t\t}',
		'\t\t\tcontinue',
		'\t\t}',
		'\t\tmut temp := [512]i8{}',
		'\t\tmut rendered := 0',
		'\t\tmatch conversion {',
		'\t\t\t`s` {',
		"\t\t\t\tstring_arg := if usize(arg) == 0 { c'(null)' } else { &i8(arg) }",
		'\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, voidptr(string_arg))',
		'\t\t\t}',
		'\t\t\t`c` {',
		'\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, i32(c2v_variadic_signed(arg, false)))',
		'\t\t\t}',
		'\t\t\t`d`, `i` {',
		'\t\t\t\tif wide {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, c2v_variadic_signed(arg, true))',
		'\t\t\t\t} else {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, i32(c2v_variadic_signed(arg, false)))',
		'\t\t\t\t}',
		'\t\t\t}',
		'\t\t\t`u`, `o`, `x`, `X` {',
		'\t\t\t\tif wide {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, c2v_variadic_unsigned(arg, true))',
		'\t\t\t\t} else {',
		'\t\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, u32(c2v_variadic_unsigned(arg, false)))',
		'\t\t\t\t}',
		'\t\t\t}',
		'\t\t\t`f`, `F`, `e`, `E`, `g`, `G`, `a`, `A` {',
		'\t\t\t\tfloat_arg := if usize(arg) == 0 { f64(0) } else if c2v_va_is_immediate(usize(arg)) { f64(isize(usize(arg))) } else { unsafe { *(&f64(arg)) } }',
		'\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, float_arg)',
		'\t\t\t}',
		'\t\t\t`p` {',
		'\t\t\t\trendered = C.snprintf(unsafe { voidptr(&temp[0]) }, usize(temp.len), unsafe { voidptr(&spec[0]) }, arg)',
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
		'\treturn i32(out_pos)',
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

// dedupe_c_function_prototypes removes the V declarations made for C prototypes
// in a single-module C project: a function defined by any translation unit
// needs none, and one that no unit defines keeps a single declaration.
fn (c2v &C2V) dedupe_c_function_prototypes() {
	if !c2v.is_dir || c2v.project_has_cpp || !c2v.project_single_module
		|| c2v.project_output_root == '' || !os.exists(c2v.project_output_root) {
		return
	}
	mut files := os.walk_ext(c2v.project_output_root, '.v').filter(!is_c2v_globals_file(it))
	files.sort()
	mut defined := map[string]bool{}
	for file in files {
		for line in os.read_lines(file) or { continue } {
			if name := top_level_v_fn_name(line) {
				if line.trim_space().ends_with('{') {
					defined[name] = true
				}
			}
		}
	}
	mut declared := map[string]bool{}
	for file in files {
		lines := os.read_lines(file) or { continue }
		mut out_lines := []string{cap: lines.len}
		mut changed := false
		for line in lines {
			if name := top_level_v_fn_name(line) {
				if !line.trim_space().ends_with('{') {
					if name in defined || name in declared {
						// Drop the prototype with the attributes written for it.
						for out_lines.len > 0 && out_lines.last().starts_with('@[') {
							out_lines.delete_last()
						}
						changed = true
						continue
					}
					declared[name] = true
				}
			}
			out_lines << line
		}
		if changed {
			os.write_file(file, out_lines.join('\n') + '\n') or { panic(err) }
		}
	}
}

// top_level_v_fn_name returns the name of a (non-method, non-C) V function
// declared or defined on `line`.
fn top_level_v_fn_name(line string) ?string {
	if !line.starts_with('fn ') || line.starts_with('fn (') || line.starts_with('fn C.') {
		return none
	}
	name := line[3..].all_before('(').all_before('[').trim_space()
	if name == '' {
		return none
	}
	return name
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

// global_ref_call_marker marks, in a global reference replacement map, a name
// that is also a function: its calls are not global references.
const global_ref_call_marker = '\x01call:'

fn (c2v &C2V) defined_global_ref_replacements() map[string]string {
	mut replacements := map[string]string{}
	mut function_v_names := map[string]bool{}
	for _, v_name in c2v.fns {
		function_v_names[v_name] = true
	}
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
			if !c2v.project_has_cpp && snake_ref_name in function_v_names {
				// C keeps `sqlite3Config` and `sqlite3_config()` apart; V needs two
				// names. Calls of the function keep its name (see
				// replace_defined_global_refs_in_text).
				v_name = snake_ref_name + '_var'
				replacements[global_ref_call_marker + snake_ref_name] = '1'
			}
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
		// String and rune literals (a rune literal may hold a quote).
		if s[i] == `'` || s[i] == `"` || s[i] == `\`` {
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
		if (global_ref_call_marker + token) in replacements {
			mut next := i
			for next < s.len && s[next] == ` ` {
				next++
			}
			if next < s.len && s[next] == `(` {
				// A call of the function that shares the global's name.
				out.write_string(token)
				continue
			}
		}
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
		if ch == `'` || ch == `"` || ch == `\`` {
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
		if ch == `'` || ch == `"` || ch == `\`` {
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
	out.writeln('@[translated]\n@[has_globals]\nmodule ' + c2v.project_module_name + '\n')
	for include_dir in configured_include_dirs(c2v.project_folder, c2v.project_additional_flags) {
		// Translated project headers are never included: only native sources and
		// the headers of system libraries (#include <tcl.h>) need the directory.
		if c2v.project_native_manifest == '' && !line_is_builtin_header(include_dir + '/') {
			continue
		}
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
	if c2v.uses_gc_thread_registration {
		out.write_string(c2v_threads_source())
	}
	out.write_string(c2v.global_constructors_source(replacements))
	if c2v.project_has_cpp || c2v.project_require_no_stubs {
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
		if c2v.project_has_cpp {
			write_strict_c_math_declarations(mut out)
			write_strict_cpp_compat_declarations(mut out, used_c_symbols(program_text))
		} else {
			// C: the helpers translated C code uses (system functions are declared
			// from their headers below).
			out.writeln(c2v_alloca_source())
			write_c2v_bswap_helpers(mut out)
			out.writeln("fn c2v_builtin_trap() { panic('C __builtin_trap') }")
			out.writeln('')
			write_c2v_pointer_update_helpers(mut out)
		}
		c2v.write_strict_external_c_function_declarations(mut out)
		if c2v.project_has_cpp {
			c2v.write_strict_semantic_compat_helpers(mut out)
		}
		// V's C backend only relies on the system header for C records declared
		// in a `.c.v` file, so the external surface lives in its own file.
		mut external := strings.new_builder(4096)
		external.writeln(c2v.v_module_header())
		c2v.write_strict_external_abi_declarations(mut external, program_text + out.after(0))
		os.write_file(os.join_path(os.dir(globals_path), c2v_external_decls_file_name), external.str()) or { panic(err) }
	}
	// Function type aliases used only by global declarations (see
	// returned_fn_type_aliases; the translated files declare their own).
	mut alias_scan := out.after(0)
	for {
		mut added := ''
		for alias in returned_fn_type_aliases(alias_scan) {
			alias_key := 'returned_fn_alias:${alias}:${c2v.project_output_root}'
			if alias_key !in c2v.generated_declarations {
				c2v.generated_declarations[alias_key] = true
				added += alias + '\n\n'
			}
		}
		if added == '' {
			break
		}
		out.write_string(added)
		alias_scan = added
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
	'snprintf':    'fn C.snprintf(&i8, usize, &i8, ...) i32'
	'strstr':      'fn C.strstr(&i8, &i8) &i8'
	'isalpha':     'fn C.isalpha(i32) i32'
	'localtime_r': 'fn C.localtime_r(&i64, &C.tm) &C.tm'
	'strftime':    'fn C.strftime(&i8, usize, &i8, &C.tm) usize'
	'time':        'fn C.time(voidptr) i64'
	'vfprintf':    'fn C.vfprintf(&C.FILE, &i8, C.va_list) i32'
	'vprintf':     'fn C.vprintf(&i8, C.va_list) i32'
	'vsnprintf':   'fn C.vsnprintf(&i8, usize, &i8, C.va_list) i32'
	'vsprintf':    'fn C.vsprintf(&i8, &i8, C.va_list) i32'
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
	out.writeln(c2v_alloca_source())
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

fn (mut c2v C2V) write_strict_semantic_compat_helpers(mut out strings.Builder) {
	if c2v.cpp_abstract_types.len > 0 || c2v.uses_cpp_interface_runtime {
		out.write_string(cpp_interface_runtime_helpers_source())
	}
	out.write_string(c2v.cpp_virtual_dispatchers_source())
	out.write_string(c2v.cpp_dynamic_cast_helpers_source())
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
