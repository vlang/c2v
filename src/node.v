// To generate example AST JSON, that Node structure maps,
// use clang -w -Xclang -ast-dump=json -fsyntax-only -fno-diagnostics-color -c 1.hello.c > ast.json command, for example.

module main

// vfmt off
struct Node {
	id                   string
	kind_str             string       		[json: 'kind'] 				// e.g. "IntegerLiteral"
	location             NodeLocation 		[json: 'loc']
	range                Range
	previous_declaration string       		[json: 'previousDecl']
	name                 string 										// e.g. "my_var_name"
	ast_type             AstJsonType  		[json: 'type']
	class_modifier       string       		[json: 'storageClass']
	tags                 string       		[json: 'tagUsed']
	initialization_type  string       		[json: 'init'] 				// "c" => "cinit"
	value                string 										// e.g. "777" for IntegerLiteral
	value_number         int          		[json: 'value'] 			// For CharacterLiterals, since `value` is a number there, not at string
	opcode               string 										// e.g. "+" in BinaryOperator
	ast_argument_type    AstJsonType  		[json: 'argType']
	array_filler         []Node 										// for InitListExpr
	declaration_id       string       		[json: 'declId'] 			// for goto labels
	label_id             string       		[json: 'targetLabelDeclId'] // for goto statements
	is_postfix           bool         		[json: 'isPostfix']
	ast_line_nr          int [skip]
mut:
	//parent_node &Node [skip] = unsafe {nil }
	inner                []Node
	ref_declaration      RefDeclarationNode [json: 'referencedDecl'] 	//&Node
	kind                 NodeKind           [skip]
	current_child_id     int                [skip]
	is_builtin_type      bool               [skip]
	redeclarations_count int                [skip] 						// increased when some *other* Node had previous_decl == this Node.id
}
// vfmt on

struct NodeLocation {
	offset        ?int
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
	desugared_qualified string [json: 'desugaredQualType']
	qualified           string [json: 'qualType']
}

struct RefDeclarationNode {
	kind_str string [json: 'kind'] // e.g. "IntegerLiteral"
	name     string
mut:
	kind NodeKind [skip]
}

const bad_node = Node{
	kind: .bad
}

fn (node Node) kindof(expected_kind NodeKind) bool {
	return node.kind == expected_kind
}

fn (node Node) has_child_of_kind(expected_kind NodeKind) bool {
	for child in node.inner {
		if child.kindof(expected_kind) {
			return true
		}
	}

	return false
}

fn (node Node) count_children_of_kind(kind_filter NodeKind) int {
	mut count := 0

	for child in node.inner {
		if child.kindof(kind_filter) {
			count++
		}
	}

	return count
}

fn (node Node) find_children(wanted_kind NodeKind) []Node {
	mut suitable_children := []Node{}

	if node.inner.len == 0 {
		return suitable_children
	}

	for child in node.inner {
		if child.kindof(wanted_kind) {
			suitable_children << child
		}
	}

	return suitable_children
}

fn (mut node Node) try_get_next_child_of_kind(wanted_kind NodeKind) !Node {
	if node.current_child_id >= node.inner.len {
		return error('No more children')
	}

	mut current_child := node.inner[node.current_child_id]

	if current_child.kindof(wanted_kind) == false {
		error('try_get_next_child_of_kind(): WANTED ${wanted_kind.str()} BUT GOT ${current_child.kind.str()}')
	}

	node.current_child_id++

	return current_child
}

fn (mut node Node) try_get_next_child() !Node {
	if node.current_child_id >= node.inner.len {
		return error('No more children')
	}

	current_child := node.inner[node.current_child_id]
	node.current_child_id++

	return current_child
}

fn (mut node Node) initialize_node_and_children() {
	node.kind = convert_str_into_node_kind(node.kind_str)

	for mut child in node.inner {
		child.initialize_node_and_children()
	}
}

fn (node &Node) is_builtin() bool {
	return (node.location.file == '' && node.location.line == 0 && node.location.offset == 0
		&& node.location.spelling_file.path == '' && node.range.begin.spelling_file.path == '')
		|| line_is_builtin_header(node.location.file)
		|| line_is_builtin_header(node.location.source_file.path)
		|| line_is_builtin_header(node.location.spelling_file.path)
		|| line_is_builtin_header(node.range.begin.spelling_file.path)
		|| node.name in builtin_fn_names
}
