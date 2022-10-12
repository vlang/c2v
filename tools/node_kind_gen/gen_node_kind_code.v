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
	mut previous_character_was_upper := false

	for character_index, character in value {
		if character.is_capital() {
			if character_index > 0 && character_index < value.len - 1
				&& (value[character_index + 1].is_capital() == false
				|| previous_character_was_upper == false) {
				snake_cased_string += '_'
			}

			snake_cased_string += character.ascii_str().to_lower()
			previous_character_was_upper = true
		} else {
			snake_cased_string += character.ascii_str()
			previous_character_was_upper = false
		}
	}

	return snake_cased_string
}
