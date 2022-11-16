// This code implements a small tool that can be used to generate a NodeKind and str_to_node_kind_map constructions,
// used in the node_kind.v. Since there can be pretty big list of AST node types, making this by hand is not the most
// optimal way to do it.
//
// To use this tool, simply put a list of node type names into the 'types' file, and place in next to this file.
// Content in this file should look like this:
// 	AccessSpecDecl
//	AcquireCapabilityAttr
//	AddrLabelExpr
import os
import artemkakun.textproc.src.case

// Generates node kind related code, based on the 'types' file.
//
// Example:
// 	Content of 'types' file:
// 		AccessSpecDecl
//		AcquireCapabilityAttr
//		AddrLabelExpr
//
// 	Generated code:
// 		enum NodeKind {
// 			acces_spec_decl,
// 			acquire_capability_attr,
// 			addr_label_expr,
// 		}
//
// 		const str_to_node_kind_map = {
// 			'AccessSpecDecl': .acces_spec_decl,
// 			'AcquireCapabilityAttr': .acquire_capability_attr,
// 			'AddrLabelExpr': .addr_label_expr,
// 		}
fn main() {
	types_file := 'types'

	lines := os.read_lines(types_file) or {
		println('{types_file} file not found')
		return
	}

	println('enum NodeKind {')
	println('bad')

	for line in lines {
		node_kind_name := line.trim_space()
		println(case.string_to_snake_case(node_kind_name))
	}

	println('}')

	print('\n')

	println('const str_to_node_kind_map = {')
	print_map_pair('BAD', 'NodeKind.bad')

	for line in lines {
		node_kind_name := line.trim_space()
		print_map_pair(node_kind_name, '.${case.string_to_snake_case(node_kind_name)}')
	}

	println('}')
}

fn print_map_pair(key string, value string) {
	println('\'${key}\': ${value}')
}
