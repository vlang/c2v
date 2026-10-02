module main

import os

fn test_wrapper_directory_keeps_shared_declarations_and_paired_inputs() {
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_directory_${os.getpid()}')
	input := os.join_path(root, 'input')
	output := os.join_path(input, 'c2v_output')
	// A manifest may name a header outside the project, preserving its drive
	// letter on Windows. Unix can also exercise the colon through a directory.
	external_dir := os.join_path(root, $if windows { 'external' } $else { 'C:' }, 'sdk')
	os.mkdir_all(external_dir) or { panic(err) }
	external_header := os.join_path(external_dir, 'api.h').replace('\\', '/')
	os.write_file(external_header, 'int external_manifest_value(void);\n') or { panic(err) }
	os.mkdir_all(os.join_path(input, 'nested')) or { panic(err) }
	os.mkdir_all(os.join_path(input, 'a')) or { panic(err) }
	deep := ['level_${'x'.repeat(75)}', 'level_${'y'.repeat(75)}', 'level_${'z'.repeat(75)}',
		'level_${'w'.repeat(75)}'].join('/')
	assert deep.len > 255
	os.mkdir_all(os.join_path(input, deep)) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	exe := os.join_path(root, 'c2v' + $if windows { '.exe' } $else { '' })
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	files := {
		'c2v.toml':         'keep_ast = true\n[project]\nwrapper_module_name = "api"\n'
		'common.h':         '#ifndef COMMON_H\n#define COMMON_H\ntypedef struct Shared { int value; } Shared;\nint shared_value(Shared *value);\n#endif\n'
		'nested/api.h':     '#include "../common.h"\nint nested_value(Shared *value);\n'
		'foo.h':            'int header_only(void);\n'
		'foo.c':            '#include "foo.h"\nint source_only(void) { return 7; }\n'
		'a/b.h':            'int path_nested(void);\n'
		'a_b.h':            'int path_underscore(void);\n'
		'a__b.h':           'int path_double_underscore(void);\n'
		'public.hpp':       'struct HppValue { int value; };\nextern "C" int hpp_value(HppValue *value);\n'
		'public.hh':        'struct HhValue { int value; };\nextern "C" int hh_value(HhValue *value);\n'
		'public.hxx':       'struct HxxValue { int value; };\nextern "C" int hxx_value(HxxValue *value);\n'
		'public.h':         'namespace Detail { template<class T> struct Token {}; }\nclass CppHValue { public: int value; };\nextern "C" int cpp_header_value(CppHValue *value);\n'
		'public.C':         'extern "C" int uppercase_value(void) { return 12; }\n'
		'zconly.h':         'typedef struct COnlyValue { int class; int new; } COnlyValue;\nint c_header_value(COnlyValue *value);\n'
		'a_nonself.h':      'MYTYPE macro_value(MYTYPE value);\nPrereq prerequisite_value(Prereq value);\n'
		'a_bad.c':          'Missing *recovered_source_value(Missing *value);\n'
		'zhealthy.h':       'typedef struct Missing { long field; } Missing;\nMissing *recovered_source_value(Missing *value);\n'
		'zself.c':          '#define MYTYPE long\ntypedef long Prereq;\n#include "a_nonself.h"\nMYTYPE macro_value(MYTYPE value) { return value + 4294967296L; }\nPrereq prerequisite_value(Prereq value) { return value + 4294967296L; }\n'
		'${deep}/first.h':  'int deep_header(void);\n'
		'${deep}/first.c':  '#include "first.h"\nint deep_source(void) { return 16; }\n'
		'${deep}/second.h': 'extern "C" int deep_cpp_header(void);\n'
	}
	for path, contents in files {
		os.write_file(os.join_path(input, path), contents) or { panic(err) }
	}
	translate := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
	assert translate.exit_code == 0, translate.output
	generated := os.walk_ext(output, '.v')
	assert generated.len == 18, translate.output
	assert translate.output.contains('skipping wrapper header ./a_nonself.h'), translate.output
	assert translate.output.contains('skipping wrapper source ./a_bad.c'), translate.output
	assert !os.exists(os.join_path(output, 'a_unonself.h.v'))
	assert !os.exists(os.join_path(output, 'a_ubad.c.v'))
	long_names := generated.filter(os.file_name(it).starts_with('_hash_'))
	assert long_names.len == 3
	for path in os.walk_ext(output, '.json') {
		assert os.dir(path) == output
		assert os.file_name(path).len <= 255
	}
	mut declarations := ''
	for path in generated {
		assert os.dir(path) == output
		source := os.read_file(path) or { panic(err) }
		assert source.contains('module api\n'), source
		declarations += source
	}
	assert declarations.count('struct Shared {') == 1
	for name in ['shared_value', 'nested_value', 'source_only', 'header_only', 'path_nested',
		'path_underscore', 'path_double_underscore', 'hpp_value', 'hh_value', 'hxx_value',
		'cpp_header_value', 'uppercase_value', 'c_header_value', 'macro_value', 'prerequisite_value',
		'deep_header', 'deep_source', 'deep_cpp_header', 'recovered_source_value'] {
		assert declarations.count('pub fn ${name}(') == 1, declarations
	}
	assert declarations.contains('pub fn macro_value(value i64) i64'), declarations
	assert declarations.contains('pub fn prerequisite_value(value Prereq) Prereq'), declarations
	assert declarations.contains('pub fn recovered_source_value(value &Missing) &Missing'), declarations
	assert os.exists(os.join_path(output, 'foo.c.v'))
	assert os.exists(os.join_path(output, 'foo.h.v'))
	assert os.exists(os.join_path(output, 'foo.c.json'))
	assert os.exists(os.join_path(output, 'foo.h.json'))
	check := os.execute('${os.quoted_path(@VEXE)} -check ${os.quoted_path(output)}')
	assert check.exit_code == 0, check.output
	// Call both halves of the source/header pair and the shared typed wrappers.
	// C definitions stay outside discovery, as a separately compiled library.
	native_source := os.join_path(root, 'native.c')
	native_object := os.join_path(root, 'native.o')
	native_header := os.join_path(root, 'native.h').replace('\\', '/')
	native_cpp_source := os.join_path(root, 'native.cpp')
	native_cpp_object := os.join_path(root, 'native_cpp.o')
	os.write_file(native_header, '#include "${os.join_path(input, 'common.h').replace('\\', '/')}"\nint nested_value(Shared *value);\nint source_only(void);\nint header_only(void);\nint path_nested(void);\nint path_underscore(void);\nint path_double_underscore(void);\nint hpp_value(void *value);\nint hh_value(void *value);\nint hxx_value(void *value);\nint cpp_header_value(void *value);\nint uppercase_value(void);\n#include "${os.join_path(input, 'zconly.h').replace('\\', '/')}"\nint deep_header(void);\nint deep_source(void);\nint deep_cpp_header(void);\n#define MYTYPE long\ntypedef long Prereq;\n#include "${os.join_path(input, 'a_nonself.h').replace('\\', '/')}"\n#include "${os.join_path(input, 'zhealthy.h').replace('\\', '/')}"\n') or { panic(err) }
	os.write_file(native_source, '#include "${native_header}"\nint shared_value(Shared *value) { return value->value; }\nint nested_value(Shared *value) { return shared_value(value) + 1; }\nint source_only(void) { return 7; }\nint header_only(void) { return 8; }\nint path_nested(void) { return 1; }\nint path_underscore(void) { return 2; }\nint path_double_underscore(void) { return 3; }\nint hpp_value(void *value) { return *(int *)value; }\nint hh_value(void *value) { return *(int *)value; }\nint hxx_value(void *value) { return *(int *)value; }\nint c_header_value(COnlyValue *value) { return value->class + value->new; }\n#include "${os.join_path(input, 'zself.c').replace('\\', '/')}"\nint deep_header(void) { return 14; }\nint deep_source(void) { return 16; }\nMissing *recovered_source_value(Missing *value) { return value; }\n') or { panic(err) }
	native := os.execute('cc -c ${os.quoted_path(native_source)} -o ${os.quoted_path(native_object)}')
	assert native.exit_code == 0, native.output
	os.write_file(native_cpp_source, '#include "${os.join_path(input, 'public.h').replace('\\', '/')}"\n#include "${os.join_path(input, 'public.C').replace('\\', '/')}"\nextern "C" int cpp_header_value(CppHValue *value) { return value->value; }\nextern "C" int deep_cpp_header(void) { return 15; }\n') or { panic(err) }
	native_cpp := os.execute('c++ -c ${os.quoted_path(native_cpp_source)} -o ${os.quoted_path(native_cpp_object)}')
	assert native_cpp.exit_code == 0, native_cpp.output
	os.write_file(os.join_path(output, 'runtime_test.v'), 'module api\n#flag ${os.quoted_path(native_object)}\n#flag ${os.quoted_path(native_cpp_object)}\n#include "${native_header}"\nfn test_runtime() {\nmut shared := Shared{value: 4}\nassert shared_value(&shared) == 4\nassert nested_value(&shared) == 5\nassert source_only() == 7\nassert header_only() == 8\nassert path_nested() == 1\nassert path_underscore() == 2\nassert path_double_underscore() == 3\nmut hpp := HppValue{value: 9}\nmut hh := HhValue{value: 10}\nmut hxx := HxxValue{value: 11}\nassert hpp_value(&hpp) == 9\nassert hh_value(&hh) == 10\nassert hxx_value(&hxx) == 11\nmut cpp_h := CppHValue{value: 13}\nassert cpp_header_value(&cpp_h) == 13\nassert uppercase_value() == 12\nmut c_only := COnlyValue{class: 2, new: 3}\nassert c_header_value(&c_only) == 5\nassert deep_header() == 14\nassert deep_cpp_header() == 15\nassert deep_source() == 16\nlarge := i64(4294967297)\nassert macro_value(large) == 8589934593\nassert i64(prerequisite_value(Prereq(large))) == 8589934593\nmut missing := Missing{field: large}\nassert recovered_source_value(&missing).field == large\n}\n') or { panic(err) }
	runtime := os.execute('${os.quoted_path(@VEXE)} test ${os.quoted_path(output)}')
	assert runtime.exit_code == 0, runtime.output
	// Header manifests use a separate discovery path, including C++ headers.
	os.write_file(os.join_path(input, 'headers.txt'), 'common.h\nnested/api.h\nfoo.c\nfoo.h\npublic.hpp\npublic.hh\npublic.hxx\npublic.h\npublic.C\nzconly.h\na_nonself.h\nzself.c\n${deep}/first.h\n${deep}/first.c\n${deep}/second.h\na_bad.c\nzhealthy.h\n${external_header}\n') or { panic(err) }
	os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = "api"\nsource_manifest = "headers.txt"\n') or { panic(err) }
	manifest := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
	assert manifest.exit_code == 0, manifest.output
	manifest_generated := os.walk_ext(output, '.v')
	assert manifest_generated.len == 16, manifest.output
	mut external_wrappers := 0
	for path in manifest_generated {
		name := os.file_name(path)
		assert !name.bytes().any(it < 32 || it in [`<`, `>`, `:`, `"`, `|`, `?`, `*`, `/`, `\\`])
		if (os.read_file(path) or { panic(err) }).contains('pub fn external_manifest_value(') {
			external_wrappers++
			assert name.starts_with('_hash_'), name
		}
	}
	assert external_wrappers == 1
	for extension in ['hpp', 'hh', 'hxx'] {
		assert os.exists(os.join_path(output, 'public.${extension}.v'))
	}
	manifest_check := os.execute('${os.quoted_path(@VEXE)} -check ${os.quoted_path(output)}')
	assert manifest_check.exit_code == 0, manifest_check.output
	// Link and call the wrapper emitted for the external absolute manifest entry.
	external_source := os.join_path(root, 'external.c')
	external_object := os.join_path(root, 'external.o')
	os.write_file(external_source, '#include "${external_header}"\nint external_manifest_value(void) { return 17; }\n') or { panic(err) }
	external_native := os.execute('cc -c ${os.quoted_path(external_source)} -o ${os.quoted_path(external_object)}')
	assert external_native.exit_code == 0, external_native.output
	os.write_file(os.join_path(output, 'external_runtime_test.v'), 'module api\n#flag ${os.quoted_path(external_object)}\n#include "${external_header}"\nfn test_external_manifest_runtime() {\nassert external_manifest_value() == 17\n}\n') or { panic(err) }
	external_runtime := os.execute('${os.quoted_path(@VEXE)} test ${os.quoted_path(output)}')
	assert external_runtime.exit_code == 0, external_runtime.output
	// Single-file wrappers keep their conventional output path.
	single := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(os.join_path(input, 'foo.h'))}')
	assert single.exit_code == 0, single.output
	assert os.exists(os.join_path(input, 'foo.v'))
	// Ambiguous .h input retries as C++, while normal C headers keep their mode.
	cpp_single := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(os.join_path(input, 'public.h'))}')
	assert cpp_single.exit_code == 0, cpp_single.output
	assert !cpp_single.output.contains('recovered AST'), cpp_single.output
	cpp_auto := os.read_file(os.join_path(input, 'public.v')) or { panic(err) }
	assert cpp_auto.contains('struct CppHValue {')
	assert cpp_auto.contains('pub fn cpp_header_value(')
	// Keep quoted -x options and macro text out of language-option detection.
	for flags in ["'-x' c++", '\'-xc++\' -DMESSAGE=\'"words -x c"\'', "-x c++ -DMESSAGE='words -x c'"] {
		encoded := flags.replace('\\', '\\\\').replace('\"', '\\\"')
		os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = \"api\"\nadditional_flags = \"${encoded}\"\n') or { panic(err) }
		explicit_cpp := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(os.join_path(input, 'public.h'))}')
		assert explicit_cpp.exit_code == 0, explicit_cpp.output
		assert !explicit_cpp.output.contains('recovered AST'), explicit_cpp.output
		assert (os.read_file(os.join_path(input, 'public.v')) or { panic(err) }) == cpp_auto
	}
	c_flags := "-x c++ -xc-header -DMESSAGE='words -x c++'"
	os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = \"api\"\nadditional_flags = \"${c_flags}\"\n') or { panic(err) }
	explicit_c := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(os.join_path(input, 'zconly.h'))}')
	assert explicit_c.exit_code == 0, explicit_c.output
	assert !explicit_c.output.contains('recovered AST'), explicit_c.output
	assert (os.read_file(os.join_path(input, 'zconly.v')) or { panic(err) }).contains('struct COnlyValue {')
}

fn test_wrapper_directory_finalizes_system_records_and_skip_comments() {
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_finalization_${os.getpid()}')
	input := os.join_path(root, 'system')
	comments_input := os.join_path(root, 'comments')
	output := os.join_path(input, 'reviewapi')
	os.mkdir_all(os.join_path(input, 'nested')) or { panic(err) }
	os.mkdir_all(comments_input) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	exe := os.join_path(root, 'c2v' + $if windows { '.exe' } $else { '' })
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	os.write_file(os.join_path(input, 'first.h'), 'struct stat;\n// Native system record surface\nlong long inspect_stat(const struct stat *entry);\n') or { panic(err) }
	os.write_file(os.join_path(input, 'nested/second.h'), '#include <sys/stat.h>\n#include "../first.h"\nint inspect_stat_mode(const struct stat *entry);\n') or { panic(err) }
	os.write_file(os.join_path(comments_input, 'api.h'), 'struct external_item;\n/* Source heading */\nstruct container { struct external_item *item; };\nint inspect_container(struct container *value);\n') or { panic(err) }
	native_source := os.join_path(root, 'native.c')
	native_object := os.join_path(root, 'native.o')
	forward_header := os.join_path(root, 'native.h').replace('\\', '/')
	os.write_file(native_source, '#include <sys/stat.h>\nlong long inspect_stat(const struct stat *entry) { return entry->st_size; }\nint inspect_stat_mode(const struct stat *entry) { return entry->st_mode; }\n') or { panic(err) }
	// The native prototypes do not supply the record definition. The generated
	// shared ABI unit must supply its header and field declarations.
	os.write_file(forward_header, 'struct stat;\nlong long inspect_stat(const struct stat *entry);\nint inspect_stat_mode(const struct stat *entry);\n') or { panic(err) }
	native := os.execute('cc -c ${os.quoted_path(native_source)} -o ${os.quoted_path(native_object)}')
	assert native.exit_code == 0, native.output
	for mode in ['default', 'cli', 'config'] {
		config := '[project]\nmodule_name = "other_project"\nwrapper_module_name = "reviewapi"\noutput_dirname = "reviewapi"\n' +
			if mode == 'config' { 'skip_comments = true\n' } else { '' }
		os.write_file(os.join_path(input, 'c2v.toml'), config) or { panic(err) }
		os.write_file(os.join_path(comments_input, 'c2v.toml'), config) or { panic(err) }
		flag := if mode == 'cli' { '-skip_comments ' } else { '' }
		for folder in [input, comments_input] {
			translate := os.execute('${os.quoted_path(exe)} wrapper ${flag}${os.quoted_path(folder)}')
			assert translate.exit_code == 0, translate.output
		}
		generated := os.walk_ext(output, '.v')
		assert generated.len == 3
		shared := os.join_path(output, '0_external.c.v')
		assert os.exists(shared)
		mut declarations := ''
		for path in generated {
			source := os.read_file(path) or { panic(err) }
			assert source.contains('module reviewapi\n'), source
			declarations += source
		}
		assert declarations.count('struct C.stat {') == 1, declarations
		assert !declarations.contains('C.Stat'), declarations
		assert declarations.contains('pub fn inspect_stat(entry &C.stat)'), declarations
		assert declarations.split('\n').any(it.fields() == ['st_size', 'i64']), declarations
		assert declarations.contains('pub fn inspect_stat_mode('), declarations
		comment_sources := os.walk_ext(os.join_path(comments_input, 'reviewapi'), '.v')
		mut all_generated := generated.clone()
		all_generated << comment_sources
		for path in all_generated {
			source := os.read_file(path) or { panic(err) }
			if mode != 'default' {
				assert strip_v_comments(source) == source, source
			}
		}
		comment_source := os.read_file(comment_sources[0]) or { panic(err) }
		assert comment_source.contains('// External C type declarations') == (mode == 'default')
		// A regular application avoids test-runner imports supplying C.stat.
		consumer := os.join_path(input, 'consumer.v')
		os.write_file(os.join_path(output, 'native_check.v'), 'module reviewapi\npub fn verify_native() {\nmut entry := C.stat{}\nentry.st_size = 4294967297\nentry.st_mode = 420\nassert inspect_stat(&entry) == 4294967297\nassert inspect_stat_mode(&entry) == 420\n}\n') or { panic(err) }
		os.write_file(consumer, 'module main\nimport reviewapi\n#flag ${os.quoted_path(native_object)}\n#include "${forward_header}"\nfn main() {\nreviewapi.verify_native()\nprintln("stat native call passed")\n}\n') or { panic(err) }
		runtime := os.execute('${os.quoted_path(@VEXE)} run ${os.quoted_path(consumer)}')
		assert runtime.exit_code == 0, runtime.output
		assert runtime.output.trim_space() == 'stat native call passed', runtime.output
		comments_check := os.execute('${os.quoted_path(@VEXE)} -check ${os.quoted_path(os.join_path(comments_input, 'reviewapi'))}')
		assert comments_check.exit_code == 0, comments_check.output
	}
	// Single-file wrappers keep their existing in-file external declarations.
	single := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(os.join_path(input, 'nested/second.h'))}')
	assert single.exit_code == 0, single.output
	single_source := os.read_file(os.join_path(input, 'nested/second.v')) or { panic(err) }
	assert single_source.contains('module reviewapi\n')
	assert single_source.contains('struct C.stat {')
}

fn test_wrapper_directory_indexes_later_definitions_before_signatures() {
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_forward_types_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	exe := os.join_path(root, 'c2v' + $if windows { '.exe' } $else { '' })
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	// Each case has an early API, a later clean definition, and an actual native
	// client. Opaque records must survive both rejected and function-local trees.
	cases := {
		'record':     [
			'struct Foo;\nlong long inspect_forward(struct Foo *entry);\n',
			'struct Foo { long long value; int marker; };\n',
			'long long inspect_forward(struct Foo *entry) { return entry->value + entry->marker; }\n',
			'pub fn inspect_forward(entry &Foo) i64',
			'mut entry := Foo{value: 4294967297, marker: 7}\nassert inspect_forward(&entry) == 4294967304\n',
		]
		'renamed':    [
			'struct Tag;\nlong long inspect_alias(struct Tag *entry);\n',
			'typedef struct Tag { long long value; int marker; } Renamed;\n',
			'long long inspect_alias(struct Tag *entry) { return entry->value + entry->marker; }\n',
			'pub fn inspect_alias(entry &Renamed) i64',
			'mut entry := Renamed{value: 4294967297, marker: 7}\nassert inspect_alias(&entry) == 4294967304\n',
		]
		'cpp':        [
			'class CppForward;\nextern "C" long long inspect_cpp(CppForward *entry);\n',
			'class CppForward { public: long long value; int marker; };\n',
			'extern "C" long long inspect_cpp(CppForward *entry) { return entry->value + entry->marker; }\n',
			'pub fn inspect_cpp(entry &CppForward) i64',
			'mut entry := CppForward{value: 4294967297, marker: 7}\nassert inspect_cpp(&entry) == 4294967304\n',
		]
		'opaque':     [
			'struct Ghost;\nlong long inspect_opaque(struct Ghost *entry);\n',
			'static inline void scope(void) { struct Ghost { long long local_field; }; }\n',
			'long long inspect_opaque(struct Ghost *entry) { return entry == 0 ? 19 : 0; }\nlong long inspect_other(struct Ghost *entry) { return entry == 0 ? 23 : 0; }\n',
			'pub fn inspect_opaque(entry &C.Ghost) i64',
			'assert inspect_opaque(unsafe { nil }) == 19\nassert inspect_other(unsafe { nil }) == 23\n',
		]
		'cpp_opaque': [
			'class Ghost;\nextern "C" long long inspect_ghost(Ghost *entry);\nextern "C" Ghost *get_ghost();\n',
			'class Ghost;\nextern "C" long long inspect_other(Ghost *entry);\n',
			'class Ghost { public: long long value; };\nstatic Ghost storage{4294967297};\nextern "C" Ghost *get_ghost() { return &storage; }\nextern "C" long long inspect_ghost(Ghost *entry) { return entry ? entry->value : 19; }\nextern "C" long long inspect_other(Ghost *entry) { return entry ? entry->value + 7 : 23; }\n',
			'pub fn inspect_ghost(entry &Ghost) i64',
			'entry := get_ghost()\nassert inspect_ghost(entry) == 4294967297\nassert inspect_other(entry) == 4294967304\nassert inspect_ghost(unsafe { nil }) == 19\n',
		]
	}
	for name, fixture in cases {
		is_cpp := name in ['cpp', 'cpp_opaque']
		first_header := if name == 'cpp_opaque' { 'a.hpp' } else { 'a.h' }
		last_header := if name == 'cpp_opaque' { 'z.hpp' } else { 'z.h' }
		input := os.join_path(root, name)
		output := os.join_path(input, 'api')
		os.mkdir_all(input) or { panic(err) }
		os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = "api"\noutput_dirname = "api"\n') or { panic(err) }
		os.write_file(os.join_path(input, first_header), fixture[0]) or { panic(err) }
		os.write_file(os.join_path(input, last_header), fixture[1]) or { panic(err) }
		if name == 'opaque' {
			os.write_file(os.join_path(input, 'y_invalid.h'), 'struct Ghost { long long recovered_field; };\nUnknown invalid;\n') or { panic(err) }
			os.write_file(os.join_path(input, 'zz.h'), 'struct Ghost;\nlong long inspect_other(struct Ghost *entry);\n') or { panic(err) }
		}
		translate := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
		assert translate.exit_code == 0, translate.output
		generated := os.walk_ext(output, '.v')
		assert generated.len == (if name == 'opaque' { 3 } else { 2 }), translate.output
		mut declarations := ''
		for path in generated {
			declarations += os.read_file(path) or { panic(err) }
		}
		assert declarations.contains(fixture[3]), declarations
		if name == 'opaque' {
			assert translate.output.contains('skipping wrapper header ./y_invalid.h'), translate.output
			assert declarations.count('struct C.Ghost {') == 1, declarations
			assert declarations.contains('pub fn inspect_other(entry &C.Ghost) i64'), declarations
			assert !declarations.contains('struct Ghost {')
			assert !declarations.contains('local_field')
			assert !declarations.contains('recovered_field')
		} else if name == 'cpp_opaque' {
			assert declarations.count('struct Ghost {') == 1, declarations
			assert !declarations.contains('struct C.Ghost {'), declarations
			assert declarations.contains('pub fn inspect_other(entry &Ghost) i64'), declarations
		} else {
			assert !declarations.contains('struct C.'), declarations
			assert declarations.split('\n').any(it.fields() == ['value', 'i64']), declarations
		}
		header := os.join_path(root, '${name}_native.h').replace('\\', '/')
		includes := '#include "${os.join_path(input, first_header).replace('\\', '/')}"\n#include "${os.join_path(input, last_header).replace('\\', '/')}"\n' +
			if name == 'opaque' {
				'#include "${os.join_path(input, 'zz.h').replace('\\', '/')}"\n'
			} else {
				''
			}
		// V's C backend links the C++ ABI without parsing class syntax.
		os.write_file(header, if name == 'cpp_opaque' {
			'void *get_ghost(void);\nlong long inspect_ghost(void *entry);\nlong long inspect_other(void *entry);\n'
		} else if is_cpp {
			'long long inspect_cpp(void *entry);\n'
		} else {
			includes
		}) or { panic(err) }
		native_source := os.join_path(root, '${name}_native.' + if is_cpp {
			'cpp'
		} else {
			'c'
		})
		native_object := os.join_path(root, '${name}_native.o')
		os.write_file(native_source, (if is_cpp {
			includes
		} else {
			'#include "${header}"\n'
		}) + fixture[2]) or { panic(err) }
		compiler := if is_cpp { 'c++' } else { 'cc' }
		native := os.execute('${compiler} -c ${os.quoted_path(native_source)} -o ${os.quoted_path(native_object)}')
		assert native.exit_code == 0, native.output
		os.write_file(os.join_path(output, 'native_check.v'), 'module api\npub fn verify_native() {\n' + fixture[4] + '}\n') or { panic(err) }
		consumer := os.join_path(input, 'consumer.v')
		os.write_file(consumer, 'module main\nimport api\n#flag ${os.quoted_path(native_object)}\n#include "${header}"\nfn main() {\napi.verify_native()\nprintln("forward native call passed")\n}\n') or { panic(err) }
		runtime := os.execute('${os.quoted_path(@VEXE)} run ${os.quoted_path(consumer)}')
		assert runtime.exit_code == 0, runtime.output
		assert runtime.output.trim_space() == 'forward native call passed', runtime.output
		if name == 'opaque' {
			// The directory guard preserves conventional single-file stubs.
			single := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(os.join_path(input, 'a.h'))}')
			assert single.exit_code == 0, single.output
			single_source := os.read_file(os.join_path(input, 'a.v')) or { panic(err) }
			assert single_source.count('struct C.Ghost {') == 1, single_source
			assert single_source.contains(fixture[3]), single_source
		}
	}
}
