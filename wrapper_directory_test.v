module main

import os

fn test_wrapper_directory_keeps_shared_declarations_and_paired_inputs() {
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_directory_${os.getpid()}')
	input := os.join_path(root, 'input')
	output := os.join_path(input, 'c2v_output')
	os.mkdir_all(os.join_path(input, 'nested')) or { panic(err) }
	os.mkdir_all(os.join_path(input, 'a')) or { panic(err) }
	defer {
		os.rmdir_all(root) or {}
	}
	exe := os.join_path(root, 'c2v' + $if windows { '.exe' } $else { '' })
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	files := {
		'c2v.toml':     'keep_ast = true\n[project]\nwrapper_module_name = "api"\n'
		'common.h':     '#ifndef COMMON_H\n#define COMMON_H\ntypedef struct Shared { int value; } Shared;\nint shared_value(Shared *value);\n#endif\n'
		'nested/api.h': '#include "../common.h"\nint nested_value(Shared *value);\n'
		'foo.h':        'int header_only(void);\n'
		'foo.c':        '#include "foo.h"\nint source_only(void) { return 7; }\n'
		'a/b.h':        'int path_nested(void);\n'
		'a_b.h':        'int path_underscore(void);\n'
		'a__b.h':       'int path_double_underscore(void);\n'
		'public.hpp':   'struct HppValue { int value; };\nextern "C" int hpp_value(HppValue *value);\n'
		'public.hh':    'struct HhValue { int value; };\nextern "C" int hh_value(HhValue *value);\n'
		'public.hxx':   'struct HxxValue { int value; };\nextern "C" int hxx_value(HxxValue *value);\n'
	}
	for path, contents in files {
		os.write_file(os.join_path(input, path), contents) or { panic(err) }
	}
	translate := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
	assert translate.exit_code == 0, translate.output
	generated := os.walk_ext(output, '.v')
	assert generated.len == 10, translate.output
	mut declarations := ''
	for path in generated {
		assert os.dir(path) == output
		source := os.read_file(path) or { panic(err) }
		assert source.contains('module api\n'), source
		declarations += source
	}
	assert declarations.count('struct Shared {') == 1
	for name in ['shared_value', 'nested_value', 'source_only', 'header_only', 'path_nested',
		'path_underscore', 'path_double_underscore', 'hpp_value', 'hh_value', 'hxx_value'] {
		assert declarations.count('pub fn ${name}(') == 1, declarations
	}
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
	os.write_file(native_header, '#include "${os.join_path(input, 'common.h').replace('\\', '/')}"\nint nested_value(Shared *value);\nint source_only(void);\nint header_only(void);\nint path_nested(void);\nint path_underscore(void);\nint path_double_underscore(void);\nint hpp_value(void *value);\nint hh_value(void *value);\nint hxx_value(void *value);\n') or { panic(err) }
	os.write_file(native_source, '#include "${native_header}"\nint shared_value(Shared *value) { return value->value; }\nint nested_value(Shared *value) { return shared_value(value) + 1; }\nint source_only(void) { return 7; }\nint header_only(void) { return 8; }\nint path_nested(void) { return 1; }\nint path_underscore(void) { return 2; }\nint path_double_underscore(void) { return 3; }\nint hpp_value(void *value) { return *(int *)value; }\nint hh_value(void *value) { return *(int *)value; }\nint hxx_value(void *value) { return *(int *)value; }\n') or { panic(err) }
	native := os.execute('cc -c ${os.quoted_path(native_source)} -o ${os.quoted_path(native_object)}')
	assert native.exit_code == 0, native.output
	os.write_file(os.join_path(output, 'runtime_test.v'), 'module api\n#flag ${os.quoted_path(native_object)}\n#include "${native_header}"\nfn test_runtime() {\nmut shared := Shared{value: 4}\nassert shared_value(&shared) == 4\nassert nested_value(&shared) == 5\nassert source_only() == 7\nassert header_only() == 8\nassert path_nested() == 1\nassert path_underscore() == 2\nassert path_double_underscore() == 3\nmut hpp := HppValue{value: 9}\nmut hh := HhValue{value: 10}\nmut hxx := HxxValue{value: 11}\nassert hpp_value(&hpp) == 9\nassert hh_value(&hh) == 10\nassert hxx_value(&hxx) == 11\n}\n') or { panic(err) }
	runtime := os.execute('${os.quoted_path(@VEXE)} test ${os.quoted_path(output)}')
	assert runtime.exit_code == 0, runtime.output
	// Header manifests use a separate discovery path, including C++ headers.
	os.write_file(os.join_path(input, 'headers.txt'), 'common.h\nnested/api.h\nfoo.c\nfoo.h\npublic.hpp\npublic.hh\npublic.hxx\n') or { panic(err) }
	os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = "api"\nsource_manifest = "headers.txt"\n') or { panic(err) }
	manifest := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
	assert manifest.exit_code == 0, manifest.output
	assert os.walk_ext(output, '.v').len == 7, manifest.output
	for extension in ['hpp', 'hh', 'hxx'] {
		assert os.exists(os.join_path(output, 'public.${extension}.v'))
	}
	manifest_check := os.execute('${os.quoted_path(@VEXE)} -check ${os.quoted_path(output)}')
	assert manifest_check.exit_code == 0, manifest_check.output
	// Single-file wrappers keep their conventional output path.
	single := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(os.join_path(input, 'foo.h'))}')
	assert single.exit_code == 0, single.output
	assert os.exists(os.join_path(input, 'foo.v'))
}
