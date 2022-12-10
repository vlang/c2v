module main

// vfmt off
struct Node {
	id            	  string
	kind_str      	  string      		 [json: 'kind']		 	  	 // e.g. "IntegerLiteral"
	name          	  string 					 		 	  		 // e.g. "my_var_name"
	value         	  string 					 		 	  		 // e.g. "777" for IntegerLiteral
	value_number  	  int         		 [json: 'value'] 		 	 // For CharacterLiterals, since `value` is a number there, not at string
	loc           	  Loc
	typ           	  AstJsonType 		 [json: 'type']
	arg_type      	  AstJsonType 		 [json: 'argType']
	inner         	  []Node
	array_filler  	  []Node 							 	  		 // for InitListExpr
	storage_class 	  string      		 [json: 'storageClass']
	tag_used      	  string      		 [json: 'tagUsed']
	init          	  string 							 	  		 // "c" => "cinit"
	opcode        	  string 							 	  		 // e.g. "+" in BinaryOperator
	range         	  Range
	decl_id       	  string      		 [json: 'declId']			 // for goto labels
	label_id 	  	  string	  		 [json: 'targetLabelDeclId'] // for goto statements
mut:
	referenced_decl   ReferencedDeclNode [json: 'referencedDecl'] 	 //&Node
	child_i           int                [skip]
	kind              NodeKind           [skip]
	is_std            bool               [skip]
	previous_decl     string             [json: 'previousDecl']
	nr_redeclarations int                [skip] 					 // increased when some *other* Node had previous_decl == this Node.id
	is_postfix        bool               [json: 'isPostfix']
}
// vfmt on

const bad_node = Node{
	kind: .bad
}

fn (this_node Node) kindof(expected_kind NodeKind) bool {
	return this_node.kind == expected_kind
}

fn (this_node Node) has_child_of_kind(expected_kind NodeKind) bool {
	for child in this_node.inner {
		if child.kindof(expected_kind) {
			return true
		}
	}

	return false
}

fn (this_node Node) count_children_of_kind(expected_kind NodeKind) int {
	mut count := 0

	for child in this_node.inner {
		if child.kindof(expected_kind) {
			count++
		}
	}

	return count
}

fn (this_node Node) find_children(wanted_kind NodeKind) []Node {
	mut suitable_children := []Node{}

	if this_node.inner.len == 0 {
		return suitable_children
	}

	for child in this_node.inner {
		if child.kindof(wanted_kind) {
			suitable_children << child
		}
	}

	return suitable_children
}

fn (node &Node) get(kind NodeKind) Node {
	// println('get child_i=$node.child_i')
	if node.child_i >= node.inner.len {
		eprintln('child i > len')
		exit(1)
		// return BAD_NODE
	}
	mut child := node.inner[node.child_i]
	if child.kind != kind {
		eprintln('\n\n')
		eprintln('ast line: node.ast_line_nr')
		// println(node.vals)
		eprintln('get(): WANTED ${kind.str()} BUT GOT ${child.kind.str()} (num=${int(child.kind)})')
		exit(1)
	}
	unsafe {
		node.child_i++
	}
	return child
}

fn (node &Node) get2() Node {
	if node.child_i == node.inner.len {
		// vals := node.vals.str()
		vprintln('get2() OUT OF BOUNDS. node: ${node.typ} parent : vals')
		return bad_node
	}
	child := node.inner[node.child_i]
	unsafe {
		node.child_i++
	}
	return child
}

fn (mut node Node) set_node_kind_recursively() {
	node.kind = convert_str_into_node_kind(node.kind_str)

	for mut child in node.inner {
		child.set_node_kind_recursively()
	}
}
