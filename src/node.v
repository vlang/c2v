module main

// vfmt off
struct Node {
	id            	  	string
	kind_str      	  	string      	   [json: 'kind']		 	   // e.g. "IntegerLiteral"
	name          	  	string 					 		 	  		   // e.g. "my_var_name"
	value         	  	string 					 		 	  		   // e.g. "777" for IntegerLiteral
	value_number  	  	int         	   [json: 'value'] 		 	   // For CharacterLiterals, since `value` is a number there, not at string
	location          	NodeLocation	   [json: 'loc']
	ast_type          	AstJsonType 	   [json: 'type']
	ast_argument_type 	AstJsonType 	   [json: 'argType']
	array_filler  	  	[]Node 							 	  		   // for InitListExpr
	class_modifier    	string      	   [json: 'storageClass']
	tags              	string 			   [json: 'tagUsed']
	initialization_type string 			   [json: 'init']			   // "c" => "cinit"
	opcode        	  	string 							 	  		   // e.g. "+" in BinaryOperator
	range         	  	Range
	declaration_id      string      	   [json: 'declId']			   // for goto labels
	label_id 	  	  	string	  		   [json: 'targetLabelDeclId'] // for goto statements
mut:
	kind              	NodeKind           [skip]
	referenced_decl   	ReferencedDeclNode [json: 'referencedDecl']    //&Node
	current_child_id  	int                [skip]
	is_std            	bool               [skip]
	previous_decl     	string             [json: 'previousDecl']
	nr_redeclarations 	int                [skip] 					   // increased when some *other* Node had previous_decl == this Node.id
	is_postfix        	bool               [json: 'isPostfix']
	inner         	  	[]Node
}
// vfmt on

struct NodeLocation {
	offset        int
	file          string
	line          int
	source_file   SourceFile [json: 'includedFrom']
	spelling_file SourceFile [json: 'spellingLoc']
}

struct Range {
	begin Begin
}

struct Begin {
	spelling_file SourceFile [json: 'spellingLoc']
}

struct SourceFile {
	path string [json: 'file']
}

struct AstJsonType {
	qualified           string [json: 'qualType']
	desugared_qualified string [json: 'desugaredQualType']
}

struct ReferencedDeclNode {
	kind_str string [json: 'kind'] // e.g. "IntegerLiteral"
	name     string
mut:
	kind NodeKind [skip]
}

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

fn (this_node Node) count_children_of_kind(kind_filter NodeKind) int {
	mut count := 0

	for child in this_node.inner {
		if child.kindof(kind_filter) {
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

fn (mut this_node Node) try_get_next_child_of_kind(wanted_kind NodeKind) !Node {
	if this_node.current_child_id >= this_node.inner.len {
		return error('No more children')
	}

	mut current_child := this_node.inner[this_node.current_child_id]

	if current_child.kindof(wanted_kind) == false {
		error('try_get_next_child_of_kind(): WANTED ${wanted_kind.str()} BUT GOT ${current_child.kind.str()}')
	}

	this_node.current_child_id++

	return current_child
}

fn (mut this_node Node) try_get_next_child() !Node {
	if this_node.current_child_id >= this_node.inner.len {
		return error('No more children')
	}

	current_child := this_node.inner[this_node.current_child_id]
	this_node.current_child_id++

	return current_child
}

fn (mut this_node Node) initialize_node_and_children() {
	this_node.kind = convert_str_into_node_kind(this_node.kind_str)

	for mut child in this_node.inner {
		child.initialize_node_and_children()
	}
}
