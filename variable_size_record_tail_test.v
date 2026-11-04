module main

import os

fn test_larger_record_tail_discovery_keeps_array_dimensions() {
	for typ in [AstJsonType{ qualified: 'int [8]' }, AstJsonType{ qualified: 'int [1]' },
		AstJsonType{ qualified: 'int [0]' }, AstJsonType{ qualified: 'int []' }] {
		mut fields := map[string]bool{}
		collect_variable_size_fields([Node{
			kind:  .record_decl
			inner: [Node{ kind: .field_decl, id: 'tail', ast_type: typ }]
		}], mut fields)
		assert fields['tail'], typ.qualified
	}
	for typ in [AstJsonType{ qualified: 'int [8][2]' }, AstJsonType{ qualified: 'Row[8]' },
		AstJsonType{ qualified: 'Rows', desugared_qualified: 'Row[8]' },
		AstJsonType{ qualified: 'RowPtr', desugared_qualified: 'int (*)[1]' },
		AstJsonType{ qualified: 'Rows', desugared_qualified: 'int [8][1]' },
		AstJsonType{ qualified: 'int (*)[8]' }, AstJsonType{ qualified: 'int *' }] {
		mut fields := map[string]bool{}
		collect_variable_size_fields([Node{
			kind:  .record_decl
			inner: [Node{ kind: .field_decl, id: 'tail', ast_type: typ }]
		}], mut fields)
		assert !fields['tail'], typ.qualified
	}
}

fn test_multi_element_record_tail_preserves_native_extent_and_layout() {
	cc := os.find_abs_path_of_executable('clang') or { return }
	root := os.dir(@FILE)
	tmp := os.join_path(os.vtmp_dir(), 'c2v_record_tail_${os.getpid()}')
	os.mkdir_all(tmp)!
	defer { os.rmdir_all(tmp) or {} }
	build := os.exec([@VEXE, '-o', 'c2v', '-w', '.'])
	assert build.exit_code == 0, build.output
	source := os.join_path(tmp, 'tail.c')
	os.cp(os.join_path(root, 'tests', 'variable_size_record_tail.c'), source)!
	native := os.join_path(tmp, 'native')
	compile_c := os.exec([cc, '-o', native, source])
	assert compile_c.exit_code == 0, compile_c.output
	native_run := os.exec([native])
	assert native_run.exit_code == 0, native_run.output
	assert native_run.output == '40 32 369 30 28 31\n', native_run.output
	translated := os.exec([os.join_path(root, 'c2v'), source])
	assert translated.exit_code == 0, translated.output
	program := os.join_path(tmp, 'translated')
	compile_v := os.exec([@VEXE, '-gc', 'none', '-cc', cc, '-o', program, os.join_path(tmp, 'tail.v')])
	assert compile_v.exit_code == 0, compile_v.output
	translated_run := os.exec([program])
	assert translated_run.exit_code == 0, translated_run.output
	assert translated_run.output == native_run.output, translated_run.output
	// Tail-pointer indexing must keep the ordinary C index conversions. These
	// accesses are all within the declared extent and also compile as C++.
	for extension in ['c', 'cpp'] {
		index_source := os.join_path(tmp, 'indices.${extension}')
		os.cp(os.join_path(root, 'tests', 'variable_size_record_tail_indices.c'), index_source)!
		index_native := os.join_path(tmp, 'indices_native_${extension}')
		index_c_build := os.exec([cc, '-o', index_native, index_source])
		assert index_c_build.exit_code == 0, index_c_build.output
		index_c_run := os.exec([index_native])
		assert index_c_run.exit_code == 0, index_c_run.output
		assert index_c_run.output == '17 17 11 17 17 23 18 17 18 1\n', index_c_run.output
		index_translation := os.exec([os.join_path(root, 'c2v'), index_source])
		assert index_translation.exit_code == 0, index_translation.output
		index_program := os.join_path(tmp, 'indices_translated_${extension}')
		index_v_build := os.exec([@VEXE, '-gc', 'none', '-cc', cc, '-o', index_program,
			os.join_path(tmp, 'indices.v')])
		assert index_v_build.exit_code == 0, index_v_build.output
		index_v_run := os.exec([index_program])
		assert index_v_run.exit_code == 0, index_v_run.output
		assert index_v_run.output == index_c_run.output, index_v_run.output
	}
	// The same-sized array followed by another field is not a variable record tail.
	non_tail := os.exec([program, 'bounds'])
	assert non_tail.exit_code != 0, non_tail.output
	assert non_tail.output.contains('fixed array index out of range'), non_tail.output
	// Ordinary V fixed arrays retain their bounds checks too.
	ordinary := os.join_path(tmp, 'ordinary.v')
	os.write_file(ordinary, 'import os\nfn main() {\n values := [7, 9]!\n println(values[os.args.len])\n}\n')!
	ordinary_program := os.join_path(tmp, 'ordinary')
	compile_ordinary := os.exec([@VEXE, '-gc', 'none', '-cc', cc, '-o', ordinary_program, ordinary])
	assert compile_ordinary.exit_code == 0, compile_ordinary.output
	ordinary_run := os.exec([ordinary_program, 'bounds'])
	assert ordinary_run.exit_code != 0, ordinary_run.output
	assert ordinary_run.output.contains('fixed array index out of range'), ordinary_run.output
}
