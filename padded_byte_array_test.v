module main

import os

fn test_padded_byte_array_discovery_requires_adjacent_byte_fields() {
	for spelling, underlying in {
		'unsigned char': 'unsigned char'
		'signed char':   'signed char'
		'byte':          'unsigned char'
	} {
		before := Node{
			kind:     .field_decl
			id:       'before'
			ast_type: AstJsonType{ qualified: spelling, desugared_qualified: underlying }
		}
		array := Node{
			kind:     .field_decl
			id:       'values'
			ast_type: AstJsonType{ qualified: '${spelling}[4]' }
		}
		after := Node{
			...before
			id: 'after'
		}
		mut fields := map[string]bool{}
		collect_variable_size_fields([Node{
			kind:  .record_decl
			tags:  'struct'
			inner: [before, array, after]
		}], mut fields)
		assert fields['values'], spelling
		for invalid_array_type in ['${spelling}[4][2]', '${spelling} (*)[4]', 'int[4]', 'Row[4]',
			'${spelling} *'] {
			assert !is_padded_byte_array(before, Node{
				...array
				ast_type: AstJsonType{ qualified: invalid_array_type }
			}, after), invalid_array_type
		}
		for invalid_neighbors in [[array, after], [Node{
			...before
			ast_type: AstJsonType{ qualified: 'int' }
		}, array, after], [before, array, Node{
			...after
			ast_type: AstJsonType{ qualified: 'int' }
		}], [Node{
			...before
			inner: [Node{ kind_str: 'ConstantExpr' }]
		}, array, after], [before, Node{
			...array
			inner: [Node{ kind_str: 'AlignedAttr' }]
		}, after]] {
			mut rejected := map[string]bool{}
			collect_variable_size_fields([Node{
				kind:  .record_decl
				tags:  'struct'
				inner: invalid_neighbors
			}], mut rejected)
			assert !rejected['values'], invalid_neighbors.str()
		}
		mut union_fields := map[string]bool{}
		collect_variable_size_fields([Node{
			kind:  .record_decl
			tags:  'union'
			inner: [before, array, after]
		}], mut union_fields)
		assert !union_fields['values']
	}
}

fn test_padded_byte_arrays_preserve_native_sentinels_and_layout() {
	cc := os.find_abs_path_of_executable('clang') or { return }
	root := os.dir(@FILE)
	tmp := os.join_path(os.vtmp_dir(), 'c2v_padded_bytes_${os.getpid()}')
	os.mkdir_all(tmp)!
	defer { os.rmdir_all(tmp) or {} }
	build := os.exec([@VEXE, '-o', 'c2v', '-w', '.'])
	assert build.exit_code == 0, build.output
	for extension in ['c', 'cpp'] {
		source := os.join_path(tmp, 'padded.${extension}')
		os.cp(os.join_path(root, 'tests', 'padded_byte_array.c'), source)!
		native := os.join_path(tmp, 'native_${extension}')
		compile_c := os.exec([cc, '-o', native, source])
		assert compile_c.exit_code == 0, compile_c.output
		native_run := os.exec([native])
		assert native_run.exit_code == 0, native_run.output
		assert native_run.output == '12 4 1 7 14 18 23 30 29 14 1\n', native_run.output
		translated := os.exec([os.join_path(root, 'c2v'), source])
		assert translated.exit_code == 0, translated.output
		program := os.join_path(tmp, 'translated_${extension}')
		compile_v := os.exec([@VEXE, '-gc', 'none', '-cc', cc, '-o', program,
			os.join_path(tmp, 'padded.v')])
		assert compile_v.exit_code == 0, compile_v.output
		translated_run := os.exec([program])
		assert translated_run.exit_code == 0, translated_run.output
		assert translated_run.output == native_run.output, '${extension}: ${translated_run.output}'
		// An ordinary array with a following field has no leading sentinel byte.
		ordinary_member := os.exec([program, 'bounds'])
		assert ordinary_member.exit_code != 0, ordinary_member.output
		assert ordinary_member.output.contains('fixed array index out of range'), ordinary_member.output
	}
}
