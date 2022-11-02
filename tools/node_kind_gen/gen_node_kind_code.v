import os
import string_case_converter

fn main() {
	lines := os.read_lines('types') or {
		println('types file not found')
		return
	}

	println('enum NodeKind {')

	for line in lines {
		node_kind_name := line.trim_space()
		println(".{string_case_converter.string_to_snake_case(node_kind_name)}")
	}

	println('}')
	println('\n')

	println('const str_to_node_kind_map = {')
	print_map_pair('BAD', 'NodeKind.bad')

	for line in lines {
		node_kind_name := line.trim_space()
		print_map_pair(node_kind_name, ".{string_case_converter.string_to_snake_case(node_kind_name)}")
	}

	println('}')
}

fn print_map_pair(key string, value string) {
	println("\'{key}\': {value}")
}
