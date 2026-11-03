module main

import os

fn test_pointer_difference_uses_the_immediate_pointee_size() {
	cc := os.find_abs_path_of_executable('clang')!
	root := os.dir(@FILE)
	tmp := os.join_path(os.vtmp_dir(), 'c2v_pointer_difference_${os.getpid()}')
	os.mkdir_all(tmp)!
	defer { os.rmdir_all(tmp) or {} }
	build := os.exec([@VEXE, '-o', 'c2v', '-w', '.'])
	assert build.exit_code == 0, build.output
	for extension in ['c', 'cpp'] {
		source := os.join_path(tmp, 'pointer_difference.${extension}')
		os.cp(os.join_path(root, 'tests', 'pointer_difference.c'), source)!
		native := os.join_path(tmp, 'native_${extension}')
		compile_c := os.exec([cc, source, '-o', native])
		assert compile_c.exit_code == 0, compile_c.output
		native_run := os.exec([native])
		assert native_run.exit_code == 0, native_run.output
		assert native_run.output == 'charpp 3 -3\nintpp 4 -4\nchar 5 -5\nint 4 -4\nalias 4 -4\nrows 2 -2\nrow_alias 2 -2\n'
		translated := os.exec([os.join_path(root, 'c2v'), source])
		assert translated.exit_code == 0, translated.output
		program := os.join_path(tmp, 'translated_${extension}')
		compile_v := os.exec([@VEXE, '-gc', 'none', '-cc', cc, '-o', program,
			os.join_path(tmp, 'pointer_difference.v')])
		assert compile_v.exit_code == 0, compile_v.output
		translated_run := os.exec([program])
		assert translated_run.exit_code == 0, translated_run.output
		assert translated_run.output == native_run.output, '${extension}:\n${translated_run.output}\nexpected:\n${native_run.output}'
	}
}
