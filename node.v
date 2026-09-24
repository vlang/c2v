// To generate example AST JSON, that Node structure maps,
// use clang -w -Xclang -ast-dump=json -fsyntax-only -fno-diagnostics-color -c 1.hello.c > ast.json command, for example.

module main

type Value = string | int | bool

// vfmt off
struct Node {
	id                   string
	kind_str             string       		@[json: 'kind'] 				// e.g. "IntegerLiteral"
	previous_declaration string       		@[json: 'previousDecl']
	name                 string 										// e.g. "my_var_name"
	member               string       		@[json: 'member']
	referenced_member_decl string      		@[json: 'referencedMemberDecl']
	ast_type             AstJsonType  		@[json: 'type']
	ctor_type            AstJsonType  		@[json: 'ctorType']
	class_modifier       string       		@[json: 'storageClass']
	tags                 string       		@[json: 'tagUsed']
	initialization_type  string       		@[json: 'init'] 				// "c" => "cinit"
	value                Value 				@[json: 'value'] 			// For CharacterLiterals, since `value` is a number there, not at string
	opcode               string 										// e.g. "+" in BinaryOperator
	mangled_name         string       		@[json: 'mangledName'] 		// C++ mangled name for methods
	cast_kind            string       		@[json: 'castKind'] 		// e.g. "BitCast" in ImplicitCastExpr
	value_category       string       		@[json: 'valueCategory'] 	// e.g. "lvalue" for reference-returning calls
	ast_argument_type    AstJsonType  		@[json: 'argType']
	bases                []CxxBaseSpecifier @[json: 'bases']
	declaration_id       string       		@[json: 'declId'] 			// for goto labels
		label_id             string       		@[json: 'targetLabelDeclId'] // for goto statements
		is_postfix           bool         		@[json: 'isPostfix']
		is_implicit          bool         		@[json: 'isImplicit']
		is_used              bool         		@[json: 'isUsed']
		is_pure              bool         		@[json: 'pure']
		is_virtual           bool         		@[json: 'virtual']
		complete_definition  bool         		@[json: 'completeDefinition']
		is_inline            bool         		@[json: 'inline']
		is_referenced        bool         		@[json: 'isReferenced']
		is_elidable          bool         		@[json: 'elidable'] // a copy/move construction C++ elides
		is_nrvo              bool         		@[json: 'nrvo'] // a local constructed directly in the return slot
		parent_decl_context_id string     		@[json: 'parentDeclContextId'] // set on out-of-line member definitions
		explicitly_defaulted string       		@[json: 'explicitlyDefaulted']
	mut:
	//parent_node &Node [skip] = unsafe {nil }
	location             NodeLocation 		@[json: 'loc']
	comment				 string		@[skip] // comment string before this node
	unique_id			 int		= -1 @[skip]
	range                Range
	inner                []Node
	array_filler         []Node 										// for InitListExpr
	ref_declaration      RefDeclarationNode @[json: 'referencedDecl'] 	//&Node
	any_init             RefDeclarationNode @[json: 'anyInit']
	template_argument_decl RefDeclarationNode @[json: 'decl']
	kind                 NodeKind           @[skip]
	current_child_id     int                @[skip]
	redeclarations_count int                @[skip] 						// increased when some *other* Node had previous_decl == this Node.id
	owned_tag_decl	 OwnedTagDecl  @[json: 'ownedTagDecl'] // for TagDecl nodes, to store the TagDecl node that is owned by this node
}
// vfmt on

struct NodeLocation {
mut:
	offset         int
	file           string @[json: 'file']
	line           int
	source_file    SourceFile @[json: 'includedFrom']
	spelling_file  SourceFile @[json: 'spellingLoc']
	expansion_file SourceFile @[json: 'expansionLoc']
	file_index     int = -1
}

struct Range {
mut:
	begin Begin
	end   End
}

struct Begin {
mut:
	offset         int
	file           string @[json: 'file']
	spelling_file  SourceFile @[json: 'spellingLoc']
	expansion_file SourceFile @[json: 'expansionLoc']
}

struct End {
mut:
	offset         int
	file           string @[json: 'file']
	spelling_file  SourceFile @[json: 'spellingLoc']
	expansion_file SourceFile @[json: 'expansionLoc']
}

struct SourceFile {
	offset        int @[json: 'offset']
	path          string @[json: 'file']
	included_from IncludedFrom @[json: 'includedFrom']
}

struct IncludedFrom {
	path string @[json: 'file']
}

struct AstJsonType {
	desugared_qualified string @[json: 'desugaredQualType']
	qualified           string @[json: 'qualType']
}

struct CxxBaseSpecifier {
	access         string
	written_access string @[json: 'writtenAccess']
	ast_type       AstJsonType @[json: 'type']
}

struct RefDeclarationNode {
	id       string
	kind_str string @[json: 'kind'] // e.g. "IntegerLiteral"
	name     string
	ast_type AstJsonType @[json: 'type']
mut:
	kind NodeKind @[skip]
}

struct OwnedTagDecl {
	id       string
	kind_str string @[json: 'kind']
	name     string
}

const bad_node = Node{
	kind: .bad
}

fn (value Value) to_str() string {
	if value is int {
		return value.str()
	} else if value is bool {
		return if value { 'true' } else { 'false' }
	} else {
		return value as string
	}
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
	if node.ref_declaration.kind_str != '' {
		node.ref_declaration.kind = convert_str_into_node_kind(node.ref_declaration.kind_str)
	}
	if node.any_init.kind_str != '' {
		node.any_init.kind = convert_str_into_node_kind(node.any_init.kind_str)
	}
	if node.template_argument_decl.kind_str != '' {
		node.template_argument_decl.kind = convert_str_into_node_kind(node.template_argument_decl.kind_str)
	}

	for mut child in node.inner {
		child.initialize_node_and_children()
	}
}
