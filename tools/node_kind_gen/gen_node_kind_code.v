import os

fn main() {
	lines := os.read_lines('types') or {
		println('types file not found')
		return
	}

	println('enum NodeKind {')

	for line in lines {
		node_kind_name := line.trim_space()
		println('.${string_to_snake_case(node_kind_name)}')
	}

	println('}')
	println('\n')

	println('const str_to_node_kind_map = {')
	print_map_pair('BAD', 'NodeKind.bad')

	for line in lines {
		node_kind_name := line.trim_space()
		print_map_pair(node_kind_name, '.${string_to_snake_case(node_kind_name)}')
	}

	println('}')
}

fn print_map_pair(key string, value string) {
	println('\'$key\': $value')
}

fn string_to_snake_case(value string) string {
	mut snake_cased_string := ''

	for character_index, character in value {
		if character.is_capital() && (index_on_array_edges(character_index, value.len)
			|| character_surrounded_by_capital_characters(character_index, value)) == false {
			snake_cased_string += '_'
		}

		snake_cased_string += character.ascii_str().to_lower()
	}

	return snake_cased_string
}

fn index_on_array_edges(index int, array_length int) bool {
	return index == 0 || index == array_length - 1
}

fn character_surrounded_by_capital_characters(character_index int, original_string string) bool {
	return original_string[character_index + 1].is_capital()
		&& original_string[character_index - 1].is_capital()
}
