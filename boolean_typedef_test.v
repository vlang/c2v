module main

import os

fn test_boolean_typedef_preserves_enum_storage_and_builtin_bool() {
	cc := os.find_abs_path_of_executable('clang')!
	root := os.dir(@FILE)
	tmp := os.join_path(os.vtmp_dir(), 'c2v_boolean_typedef_${os.getpid()}')
	os.mkdir_all(tmp)!
	defer { os.rmdir_all(tmp) or {} }
	build := os.exec([@VEXE, '-o', 'c2v', '-w', '.'])
	assert build.exit_code == 0, build.output
	for case_name in ['enum', 'builtin', 'cpp_builtin'] {
		ext := if case_name == 'cpp_builtin' { 'cpp' } else { 'c' }
		fixture := if case_name == 'enum' { 'boolean_enum.c' } else { 'boolean_builtin.c' }
		source := os.join_path(tmp, '${case_name}.${ext}')
		os.cp(os.join_path(root, 'tests', fixture), source)!
		mut objects := []string{}
		if case_name == 'enum' {
			// The same C declaration is compiled independently to verify pointer/array ABI.
			helper := os.join_path(tmp, 'native_helper.o')
			compile_helper := os.exec([cc, '-DC2V_BOOLEAN_NATIVE_HELPER', '-c', source, '-o', helper])
			assert compile_helper.exit_code == 0, compile_helper.output
			objects << helper
		}
		native := os.join_path(tmp, '${case_name}_native')
		mut native_args := [cc, '-o', native, source]
		native_args << objects
		compile_c := os.exec(native_args)
		assert compile_c.exit_code == 0, compile_c.output
		native_run := os.exec([native])
		assert native_run.exit_code == 0, native_run.output
		if case_name == 'enum' {
			assert native_run.output.contains('sentinel -1 0 0 9 1\n'), native_run.output
		} else {
			assert native_run.output.contains('builtin 0 1 1 110 1\n'), native_run.output
		}
		translated := os.exec([os.join_path(root, 'c2v'), source])
		assert translated.exit_code == 0, translated.output
		program := os.join_path(tmp, '${case_name}_translated')
		mut v_args := [@VEXE, '-gc', 'none', '-cc', cc, '-o', program]
		if case_name == 'enum' {
			// Include the helper's own declarations when compiling the generated C.
			v_args << ['-cflags', '-DC2V_BOOLEAN_NATIVE_HEADER -include ${os.quoted_path(source)}']
		}
		for object in objects {
			v_args << ['-ldflags', os.quoted_path(object)]
		}
		v_args << os.join_path(tmp, '${case_name}.v')
		compile_v := os.exec(v_args)
		assert compile_v.exit_code == 0, compile_v.output
		translated_run := os.exec([program])
		assert translated_run.exit_code == 0, translated_run.output
		assert translated_run.output == native_run.output, '${case_name}:\n${translated_run.output}\nexpected:\n${native_run.output}'
	}
}
