import os

fn main() {
	lines := os.read_lines('enum/types') or {
		println('enum/types not found')
		return
	}
	println('module main\n')
	println('import os\n')
	println('enum NodeKind {\nBAD\n')
	for line in lines {
		println(line.trim_space())
	}
	println('}\n')
	println('fn convert_str_into_node_kind(s string) NodeKind {')
	println('match s {')
	words := []string{}
	for line in lines {
		enum_val := line.trim_space()
		println('\'$enum_val\' { return .$enum_val }')
	}
	println('else {} }\nreturn .BAD\n}')
}
