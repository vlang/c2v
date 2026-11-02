module main

import json2
import os
import strings

fn read_test_ast[T](text string, options AstReadOptions) !T {
	path := os.join_path(os.temp_dir(), 'c2v_ast_reader_${os.getpid()}.json')
	os.write_file(path, text)!
	defer {
		os.rm(path) or {}
	}
	return read_ast[T](path, options)
}

fn test_parallel_ast_decoding_preserves_order_and_reservation_pruning() {
	mut text := strings.new_builder(1024 * 1024)
	text.write_string('{"inner":[')
	for i in 0 .. 12000 {
		if i > 0 { text.write_u8(`,`) }
		text.write_string('{"kind":"FunctionDecl","name":"fn_${i}","loc":{"file":"unit.c"},"inner":[{"kind":"CompoundStmt","inner":[{"kind":"IntegerLiteral","value":"${i}"}]}]}')
	}
	text.write_string('],"kind":"TranslationUnitDecl"}')
	source := text.str()
	serial := read_test_ast[Node](source)!
	parallel := read_test_ast[Node](source, jobs: 4)!
	assert parallel == serial
	assert parallel.inner[11999].name == 'fn_11999'
	assert read_test_ast[TypeReservationNode](source, jobs: 4)! == read_test_ast[TypeReservationNode](source)!
}

fn test_parallel_ast_error_paths_join_workers() {
	mut text := strings.new_builder(512 * 1024)
	text.write_string('{"inner":[')
	for i in 0 .. 6000 {
		if i > 0 { text.write_u8(`,`) }
		text.write_string('{"kind":"IntegerLiteral","value":"${i}"}')
	}
	valid_prefix := text.str()
	for tail in [',{"kind":"IntegerLiteral","value":', ',{"loc":{"offset":"bad"}}]}',
		',{"inner":[{},]}]}'] {
		if _ := read_test_ast[Node](valid_prefix + tail, jobs: 4) {
			assert false, 'accepted invalid parallel AST'
		}
	}
}

fn test_ast_reader_matches_json_decoder_across_buffer_boundaries() {
	text := '{"unknown":{"escaped":"brackets [ } and quote \\"", "long":"' +
		'x'.repeat(64 * 1024) + '"},"inner":[{},' +
		'{"kind":"CharacterLiteral","value":65},' +
		'{"array_filler":[{"kind":"IntegerLiteral","value":"0"}],"value":true,' +
		'"inner":[{"kind":"StringLiteral","value":"\\u03bb\\n\\\\\\\""}]}],' +
		'"kind":"TranslationUnitDecl","loc":{"file":"main.c"},"id":"root"}'
	expected := json2.decode[Node](text)!
	actual := read_test_ast[Node](text)!
	assert actual == expected
	assert actual.inner[0].unique_id == -1
}

fn test_ast_reader_accepts_escaped_child_array_keys() {
	text := '{"padding":"' + 'x'.repeat(64 * 1024) +
		'","in\\u006eer":[{"kind":"IntegerLiteral","value":"12"}]}'
	assert read_test_ast[Node](text)! == json2.decode[Node](text)!
}

fn test_ast_reader_preserves_large_array_fillers() {
	mut text := strings.new_builder(128 * 1024)
	text.write_string('{"array_filler":[')
	for i in 0 .. 2000 {
		if i > 0 {
			text.write_u8(`,`)
		}
		text.write_string('{"kind":"IntegerLiteral","type":{"qualType":"int"},"value":"${i}"}')
	}
	text.write_string('],"kind":"InitListExpr","inner":[{}]}')
	source := text.str()
	assert read_test_ast[Node](source)! == json2.decode[Node](source)!
	assert read_test_ast[TypeReservationNode](source)!.inner.len == 1
}

fn test_ast_reservation_reader_discards_expressions_and_keeps_declarations() {
	mut text := strings.new_builder(128 * 1024)
	text.write_string('{"inner":[{"kind":"FunctionDecl","inner":[{"kind":"CompoundStmt","inner":[')
	for i in 0 .. 2000 {
		if i > 0 {
			text.write_u8(`,`)
		}
		text.write_string('{"kind":"BinaryOperator","inner":[{"kind":"IntegerLiteral","value":"1"}]}')
	}
	text.write_string(',{"kind":"DeclStmt","inner":[{"kind":"RecordDecl","name":"Local"}]}]}]},')
	text.write_string('{"kind":"FunctionDecl","loc":{"file":"other.c"}}]}')
	tree := read_test_ast[TypeReservationNode](text.str())!
	assert tree.inner.len == 2
	assert tree.inner[0].has_unattributed_cpp_body()
	assert tree.inner[0].inner[0].inner.len == 1
	assert tree.inner[1].location.file == 'other.c'
	mut names := map[string]bool{}
	collect_reserved_type_names(&tree, 'main.c', mut names)
	assert names['Local']
}

fn test_ast_reader_rejects_malformed_or_truncated_input() {
	// Exercise both the buffered fast path and the incremental path.
	for padding in ['', '"padding":"' + 'x'.repeat(64 * 1024) + '",'] {
		for text in ['', '{', '{"inner":[{}', '{"inner":[{},]}', '{"inner":{}}',
			'{"inner":[{}] "kind":"TranslationUnitDecl"}', '{"id":"x",}',
			'{"loc":{"file":"unterminated}}', '{"unknown":[}}', '{"id":invalid}', '{"id":"\\q"}',
			'{} garbage', '{}\x00'] {
			input := if text.starts_with('{') { '{' + padding + text[1..] } else { text }
			if _ := read_test_ast[Node](input) {
				assert false, 'accepted invalid AST: ${text}'
			}
		}
	}
}

fn test_comment_cursors_preserve_equal_and_out_of_order_ranges() {
	mut translator := C2V{ is_dir: true }
	mut root := Node{
		inner: [
			Node{
				unique_id: 1
				range:     Range{ begin: Begin{ offset: 10 }, end: End{ offset: 30 } }
				inner:     [
					Node{ unique_id: 2, range: Range{ begin: Begin{ offset: 20 }, end: End{ offset: 25 } } },
				]
			},
			Node{
				unique_id: 3
				range:     Range{ begin: Begin{ offset: 5 }, end: End{ offset: 40 } }
				inner:     [
					Node{ unique_id: 4, range: Range{ begin: Begin{ offset: 35 }, end: End{ offset: 36 } } },
				]
			},
			Node{ unique_id: 5, range: Range{ begin: Begin{ offset: 50 }, end: End{ offset: 60 } } },
		]
	}
	mut cursors := map[int]int{}
	for offset in [10, 15, 31, 45] {
		translator.insert_comment_node(mut root, Node{
			unique_id: 100 + offset
			comment:   '${offset},'
			location:  NodeLocation{ offset: offset }
		}, mut cursors)
	}
	// The comment at the first node's exact beginning goes to the next range;
	// later comments must still be able to enter that first node.
	assert root.inner[0].inner[0].comment == '15,'
	assert root.inner[1].inner[0].comment == '10,31,'
	assert root.inner[2].comment == '45,'
	assert cursors[root.unique_id] == 2
}
