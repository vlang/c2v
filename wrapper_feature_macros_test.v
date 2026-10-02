module main

import os

fn test_wrapper_directory_shares_feature_macros_and_keeps_cpp_headers_out_of_c() {
	if os.user_os() == 'windows' {
		return
	}
	os.chdir(@VMODROOT)!
	root := os.join_path(os.temp_dir(), 'c2v_wrapper_feature_macros_${os.getpid()}')
	sdk := os.join_path(root, 'sdk')
	shim_dir := os.join_path(root, 'clang-bin')
	os.mkdir_all(os.join_path(sdk, 'bin')) or { panic(err) }
	os.mkdir_all(os.join_path(sdk, 'include')) or { panic(err) }
	os.mkdir_all(shim_dir) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	// Advertise a private SDK root, while delegating all AST and syntax checks
	// to real Clang. This makes the feature-gated system record portable.
	real_clang := os.find_abs_path_of_executable(clang_exe) or { panic(err) }
	shim := '#!/bin/sh\nif [ "$1" = "-print-search-dirs" ]; then\n  printf "programs: =%s\\n" ${os.quoted_path(os.join_path(sdk, 'bin'))}\n  exit 0\nfi\nexec ${os.quoted_path(real_clang)} "$@"\n'
	for name in ['clang', 'clang-18', 'clang-19', 'clang-17', 'clang-14', 'clang-13', 'clang-12',
		'clang-11', 'clang-10'] {
		path := os.join_path(shim_dir, name)
		os.write_file(path, shim) or { panic(err) }
		os.chmod(path, 0o755) or { panic(err) }
	}
	feature_header := os.join_path(sdk, 'include', 'c2v_feature_record.h')
	cpp_header := os.join_path(sdk, 'include', 'c2v_cpp_only.hpp')
	os.write_file(feature_header, '#ifndef C2V_FEATURE_RECORD_H\n#define C2V_FEATURE_RECORD_H\n#if defined(_C2V_REVIEW_FEATURE) && _C2V_REVIEW_FEATURE == 1\n#ifdef _C2V_NEGATED_FEATURE\n#error The final configured undefine must win\n#endif\n#if defined(REVIEW_GENERIC_FEATURE) && REVIEW_GENERIC_FEATURE != 1\n#error The leading source override must win\n#endif\n#ifdef _C2V_REVIEW_TEXT\ntypedef char c2v_feature_text_check[sizeof(_C2V_REVIEW_TEXT) == 10 ? 1 : -1];\n#endif\n#ifdef _C2V_REVIEW_CHAR\ntypedef char c2v_feature_char_check[_C2V_REVIEW_CHAR == 120 ? 1 : -1];\n#endif\nstruct review_feature_record { long long value; int marker; };\n#endif\n#endif\n') or {
		panic(err)
	}
	os.write_file(cpp_header, '#ifndef C2V_CPP_ONLY_HPP\n#define C2V_CPP_ONLY_HPP\nnamespace C2vOnlyCpp { struct Marker { int value; }; }\n#endif\n') or {
		panic(err)
	}
	exe := os.join_path(root, 'c2v')
	build := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(exe)} .')
	assert build.exit_code == 0, build.output
	fixtures := {
		'c':        ['h', '', '', '#define _C2V_REVIEW_FEATURE 1\n']
		'cpp':      ['hpp', '-std=c++23', '', '#define _C2V_REVIEW_FEATURE 1\n']
		'project':  ['h', '-D_C2V_REVIEW_FEATURE=1', '', '']
		'per_file': ['h', '', '-D_C2V_REVIEW_FEATURE=1', '']
		'paired':   ['h', '-D _C2V_REVIEW_FEATURE=1 -D_C2V_NEGATED_FEATURE=1', '-U _C2V_NEGATED_FEATURE',
			'']
		'quoted':   ['h', "-D'_C2V_REVIEW_FEATURE=(1 + 0)'", '', '']
		'literals': ['h',
			'-D_C2V_REVIEW_FEATURE=1 -D_C2V_REVIEW_TEXT=\'"two words"\' -D_C2V_REVIEW_CHAR="\'x\'"',
			'', '']
		'override': ['hpp', '-std=c++23 -D_C2V_REVIEW_FEATURE=0 -D_C2V_NEGATED_FEATURE=1',
			'-U_C2V_REVIEW_FEATURE -U_C2V_NEGATED_FEATURE', '#define _C2V_REVIEW_FEATURE 1\n']
		'generic':  ['hpp', '-std=c++23 -DREVIEW_GENERIC_FEATURE=0', '',
			'#define _C2V_REVIEW_FEATURE 1\n#define REVIEW_GENERIC_FEATURE 1\n']
	}
	for mode, fixture in fixtures {
		input := os.join_path(root, mode)
		output := os.join_path(input, 'api')
		os.mkdir_all(input) or { panic(err) }
		ext := fixture[0]
		project_flags := fixture[1]
		file_flags := fixture[2]
		header := os.join_path(input, 'a.${ext}')
		prefix := fixture[3] + '#if 0\n#define _C2V_CONDITIONAL_FEATURE 1\n#endif\n#include "${feature_header}"\n#ifdef __cplusplus\n#include "${cpp_header}"\n#endif\n#define _C2V_TOO_LATE 1\n'
		os.write_file(header, prefix + '#ifdef __cplusplus\nextern "C" {\n#endif\nlong long inspect_feature(struct review_feature_record *entry);\n#ifdef __cplusplus\n}\n#endif\n') or {
			panic(err)
		}
		os.write_file(os.join_path(input, 'b.${ext}'), prefix) or { panic(err) }
		os.write_file(os.join_path(input, 'z_invalid.h'), '#define _C2V_REJECTED_FEATURE 1\n#include "${feature_header}"\nUnknown invalid;\n') or {
			panic(err)
		}
		config_project_flags := project_flags.replace('\\', '\\\\').replace('"', '\\"')
		config_file_flags := file_flags.replace('\\', '\\\\').replace('"', '\\"')
		os.write_file(os.join_path(input, 'c2v.toml'), '[project]\nwrapper_module_name = "api"\noutput_dirname = "api"\nadditional_flags = "${config_project_flags}"\n[\'a.${ext}\']\nadditional_flags = "${config_file_flags}"\n[\'b.${ext}\']\nadditional_flags = "${config_file_flags}"\n') or {
			panic(err)
		}
		translator_path := shim_dir + os.path_delimiter + os.getenv('PATH')
		translate := os.execute('PATH=${os.quoted_path(translator_path)} ${os.quoted_path(exe)} wrapper ${os.quoted_path(input)}')
		assert translate.exit_code == 0, translate.output
		assert translate.output.contains('skipping wrapper header ./z_invalid.h'), translate.output
		assert !translate.output.contains('skipping wrapper header ./a.'), translate.output
		shared := os.read_file(os.join_path(output, '0_external.c.v')) or { panic(err) }
		assert shared.count("#flag '-D_C2V_REVIEW_FEATURE=") == 1, shared
		assert !shared.contains('-D__builtin_offsetof'), shared
		assert !shared.contains('-D_FORTIFY_SOURCE'), shared
		if file_flags.contains('_C2V_NEGATED_FEATURE') {
			assert shared.contains("#flag '-U_C2V_NEGATED_FEATURE'"), shared
			assert !shared.contains('-D_C2V_NEGATED_FEATURE'), shared
		}
		flag_index := shared.index('#flag ') or { panic(shared) }
		include_index := shared.index('#include ') or { panic(shared) }
		assert flag_index < include_index, shared
		assert shared.contains('value  i64'), shared
		assert shared.contains('marker i32'), shared
		assert !shared.contains('c2v_cpp_only.hpp'), shared
		assert !shared.contains('_C2V_REJECTED_FEATURE'), shared
		assert !shared.contains('_C2V_CONDITIONAL_FEATURE'), shared
		assert !shared.contains('_C2V_TOO_LATE'), shared
		object := os.join_path(input, 'native.o')
		native_ext := if ext == 'hpp' { 'cpp' } else { 'c' }
		native_source := os.join_path(root, 'native_${mode}.${native_ext}')
		os.write_file(native_source, '#include "${header}"\nlong long inspect_feature(struct review_feature_record *entry) { return entry->value + entry->marker; }\n') or {
			panic(err)
		}
		native_build := os.execute('cc ${project_flags} ${file_flags} -c ${os.quoted_path(native_source)} -o ${os.quoted_path(object)}')
		assert native_build.exit_code == 0, native_build.output
		bridge := os.join_path(input, 'native.h')
		os.write_file(bridge, 'long long inspect_feature(void *entry);\n') or { panic(err) }
		os.write_file(os.join_path(output, 'native_check.v'), 'module api\npub fn verify_native() {\nmut entry := C.review_feature_record{value: 4294967297, marker: 7}\nassert inspect_feature(&entry) == 4294967304\n}\n') or {
			panic(err)
		}
		consumer := os.join_path(input, 'consumer.v')
		os.write_file(consumer, 'module main\nimport api\n#flag ${os.quoted_path(object)}\n#include "${bridge}"\nfn main() { api.verify_native()\nprintln("feature macro native passed") }\n') or {
			panic(err)
		}
		runtime := os.execute('${os.quoted_path(@VEXE)} run ${os.quoted_path(consumer)}')
		assert runtime.exit_code == 0, runtime.output
		assert runtime.output.trim_space() == 'feature macro native passed', runtime.output
	}
}
