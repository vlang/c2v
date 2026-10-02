module main

import os

fn test_wrapper_directory_and_manifest_keep_explicit_cpp_standard() {
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_input_language_${os.getpid()}')
	input := os.join_path(root, 'input')
	output := os.join_path(input, 'api')
	os.mkdir_all(input) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	exe := os.join_path(root, 'c2v')
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	// The standard is global; each final language selection determines whether
	// it applies to a .c input. C-only identifiers also prove the C overrides.
	files := {
		'cpp20.c':    ['cpp20_value', '-x c++', 'cpp', '4294967297']
		'last_cpp.c': ['last_cpp_value', '-x c -x c++', 'cpp', '4294967297']
		'default.c':  ['default_value', '', 'c', '13']
		'last_c.c':   ['last_c_value', '-x c++ -x c', 'c', '17']
		'reset.c':    ['reset_value', '-x c++ -x none', 'c', '19']
	}
	mut config := '[project]\nwrapper_module_name = "api"\noutput_dirname = "api"\nadditional_flags = "-std=c++20"\n'
	mut manifest := ''
	mut bridge := ''
	mut native_calls := ''
	mut link_flags := ''
	for filename, fixture in files {
		name := fixture[0]
		is_cpp := fixture[2] == 'cpp'
		source := os.join_path(input, filename)
		contents := if is_cpp {
			// This compile-time assertion uses C++20's templated lambdas. The
			// wrapper translates the ordinary C ABI function, not the assertion.
			'#if __cplusplus < 202002L\n#error This API requires C++20\n#endif\nstatic_assert([]<typename T>(T value) { return value > 0; }(1LL));\nextern "C" long long ${name}(long long value) { return value + 4294967296LL; }\n'
		} else {
			'int ${name}(void) { int class = ${fixture[3]}; return class; }\n'
		}
		os.write_file(source, contents) or { panic(err) }
		config += '[\'${filename}\']\nadditional_flags = "${fixture[1]}"\n'
		manifest += filename + '\n'
		object := os.join_path(root, filename + '.o')
		compiler := if is_cpp { 'c++ -x c++ -std=c++20' } else { 'cc' }
		native := os.execute('${compiler} -c ${os.quoted_path(source)} -o ${os.quoted_path(object)}')
		assert native.exit_code == 0, native.output
		link_flags += '#flag ${os.quoted_path(object)}\n'
		bridge += if is_cpp {
			'long long ${name}(long long value);\n'
		} else {
			'int ${name}(void);\n'
		}
		native_calls += 'assert ${name}(${if is_cpp { '1' } else { '' }}) == ${fixture[3]}\n'
	}
	manifest_path := os.join_path(input, 'sources.txt')
	os.write_file(manifest_path, manifest) or { panic(err) }
	bridge_path := os.join_path(root, 'native.h').replace('\\', '/')
	os.write_file(bridge_path, bridge) or { panic(err) }
	for mode in ['directory', 'manifest'] {
		mode_config := if mode == 'manifest' {
			config.replace('output_dirname = "api"', 'output_dirname = "api"\nsource_manifest = "sources.txt"')
		} else {
			config
		}
		os.write_file(os.join_path(input, 'c2v.toml'), mode_config) or { panic(err) }
		translate := os.execute('${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
		assert translate.exit_code == 0, translate.output
		assert !translate.output.contains('skipping wrapper source'), translate.output
		generated := os.walk_ext(output, '.v')
		assert generated.len == files.len, translate.output
		mut declarations := ''
		for path in generated {
			declarations += os.read_file(path) or { panic(err) }
		}
		for _, fixture in files {
			assert declarations.count('pub fn ${fixture[0]}(') == 1, declarations
		}
		os.write_file(os.join_path(output, 'native_check.v'), 'module api\npub fn verify_native() {\n${native_calls}}\n') or { panic(err) }
		consumer := os.join_path(input, 'consumer.v')
		os.write_file(consumer, 'module main\nimport api\n${link_flags}#include "${bridge_path}"\nfn main() { api.verify_native()\nprintln("configured languages native passed") }\n') or { panic(err) }
		runtime := os.execute('${os.quoted_path(@VEXE)} run ${os.quoted_path(consumer)}')
		assert runtime.exit_code == 0, runtime.output
		assert runtime.output.trim_space() == 'configured languages native passed', runtime.output
	}
}
