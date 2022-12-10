// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
module main

// vfmt off
[heap]
struct Node {
	id            	  string
	kind_str      	  string      		 [json: 'kind']		 	  	 // e.g. "IntegerLiteral"
	name          	  string 					 		 	  		 // e.g. "my_var_name"
	value         	  string 					 		 	  		 // e.g. "777" for IntegerLiteral
	value_number  	  int         		 [json: 'value'] 		 	 // For CharacterLiterals, since `value` is a number there, not at string
	mangled_name  	  string      		 [json: 'mangledName']
	loc           	  Loc
	typ           	  AstJsonType 		 [json: 'type']
	arg_type      	  AstJsonType 		 [json: 'argType']
	inner         	  []Node
	array_filler  	  []Node 							 	  		 // for InitListExpr
	used          	  bool        		 [json: 'isUsed']
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

fn (node &Node) get_file_from_location() string {
	// println('get_file_from_loc "$node.location"')
	// println(node)
	if node.loc.file.contains('.cc') || node.loc.file.contains('.c') {
		return node.loc.file.find_between('<', ':')
	}
	if !node.loc.file.contains('/') {
		return ''
	}
	return node.loc.file.find_between('/', ':')
}

// |-FunctionDecl 0x7ffe1292eb48 <test/a.c:3:1, line:6:1> line:3:5 used add 'int (int, int)'
fn (node &Node) iss(kind NodeKind) bool {
	return node.kind == kind
}

fn (node &Node) has(typ NodeKind) bool {
	// return node.inner.filter(_.iss(typ)).len > 0
	for child in node.inner {
		if child.iss(typ) {
			return true
		}
	}
	return false
}

fn (node &Node) first() Node {
	return if node.inner.len < 1 { bad_node } else { node.inner[0] }
}

fn (node &Node) nr_children(kind NodeKind) int {
	mut res := 0
	for child in node.inner {
		if child.kind == kind {
			res++
		}
	}
	return res
}

fn (node &Node) find_child(kind NodeKind) ?Node {
	if node.inner.len == 0 {
		return none
	}
	for child in node.inner {
		if child.kind == kind {
			return child
		}
	}
	return none
}

fn (node &Node) find_children(kind NodeKind) []Node {
	mut res := []Node{}
	if node.inner.len == 0 {
		return res
	}
	for child in node.inner {
		if child.kind == kind {
			res << child
		}
	}
	return res
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
