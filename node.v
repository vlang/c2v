// To generate example AST JSON, that AstNode structure maps,
// use clang -w -Xclang -ast-dump=json -fsyntax-only -fno-diagnostics-color -c 1.hello.c > ast.json command, for example.

module main

import strconv

type NodeValue = string | int | bool

// json_unescape decodes JSON escape sequences in a raw JSON string body.
// json2 passes the raw (not yet unescaped) contents to custom `StringDecoder`
// implementations, so this is needed for e.g. `\"` or `\n` sequences.
fn json_unescape(raw string) string {
	if !raw.contains('\\') {
		return raw
	}
	mut out := []u8{cap: raw.len}
	mut i := 0
	for i < raw.len {
		ch := raw[i]
		if ch != `\\` {
			out << ch
			i++
			continue
		}
		i++
		if i >= raw.len {
			break
		}
		esc := raw[i]
		i++
		match esc {
			`"` { out << `"` }
			`\\` { out << `\\` }
			`/` { out << `/` }
			`b` { out << u8(8) }
			`f` { out << u8(12) }
			`n` { out << `\n` }
			`r` { out << `\r` }
			`t` { out << `\t` }
			`u` {
				if i + 4 > raw.len {
					break
				}
				mut code := u32(strconv.parse_uint(raw[i..i + 4], 16, 32) or { 0xFFFD })
				i += 4
				if code >= 0xD800 && code <= 0xDBFF && i + 6 <= raw.len && raw[i] == `\\`
					&& raw[i + 1] == `u` {
					low := u32(strconv.parse_uint(raw[i + 2..i + 6], 16, 32) or { 0 })
					if low >= 0xDC00 && low <= 0xDFFF {
						code = u32(0x10000) + ((code - 0xD800) << 10) + (low - 0xDC00)
						i += 6
					}
				}
				out << rune(code).bytes()
			}
			else {
				out << esc
			}
		}
	}
	return out.bytestr()
}

// Custom json2 decoders, so that clang AST JSON `value` fields (which can be
// strings, numbers or booleans) can be decoded into the NodeValue sum type.
fn (mut v NodeValue) from_json_string(raw string) ! {
	v = NodeValue(json_unescape(raw))
}

fn (mut v NodeValue) from_json_number(raw string) ! {
	if raw.contains('.') || raw.contains('e') || raw.contains('E') {
		v = NodeValue(int(raw.f64()))
	} else {
		v = NodeValue(int(raw.i64()))
	}
}

fn (mut v NodeValue) from_json_boolean(b bool) {
	v = NodeValue(b)
}

// vfmt off
struct AstNode {
	id                   string
	kind_str             string       		@[json: 'kind'] 				// e.g. "IntegerLiteral"
	previous_declaration string       		@[json: 'previousDecl']
	name                 string 										// e.g. "my_var_name"
	ast_type             AstJsonType  		@[json: 'type']
	class_modifier       string       		@[json: 'storageClass']
	tags                 string       		@[json: 'tagUsed']
	initialization_type  string       		@[json: 'init'] 				// "c" => "cinit"
	value                NodeValue 				@[json: 'value'] 			// For CharacterLiterals, since `value` is a number there, not at string
	opcode               string 										// e.g. "+" in BinaryOperator
	mangled_name         string       		@[json: 'mangledName'] 		// C++ mangled name for methods
	cast_kind            string       		@[json: 'castKind'] 		// e.g. "BitCast" in ImplicitCastExpr
	ast_argument_type    AstJsonType  		@[json: 'argType']
	bases                []CxxBaseSpecifier @[json: 'bases']
	declaration_id       string       		@[json: 'declId'] 			// for goto labels
	label_id             string       		@[json: 'targetLabelDeclId'] // for goto statements
	is_postfix           bool         		@[json: 'isPostfix']
mut:
	//parent_node &AstNode [skip] = unsafe {nil }
	location             NodeLocation 		@[json: 'loc']
	comment				 string		@[skip] // comment string before this node
	unique_id			 int		= -1 @[skip]
	range                Range
	inner                []AstNode
	array_filler         []AstNode 										// for InitListExpr
	ref_declaration      RefDeclarationNode @[json: 'referencedDecl'] 	//&AstNode
	kind                 NodeKind           @[skip]
	current_child_id     int                @[skip]
	redeclarations_count int                @[skip] 						// increased when some *other* AstNode had previous_decl == this AstNode.id
	owned_tag_decl	 OwnedTagDecl  @[json: 'ownedTagDecl'] // for TagDecl nodes, to store the TagDecl node that is owned by this node
}
// vfmt on

struct NodeLocation {
mut:
	offset        int
	file          string @[json: 'file']
	line          int
	source_file   SourceFile @[json: 'includedFrom']
	spelling_file SourceFile @[json: 'spellingLoc']
	file_index    int = -1
}

struct Range {
mut:
	begin Begin
	end   End
}

struct Begin {
mut:
	offset         int
	file           string     @[json: 'file']
	spelling_file  SourceFile @[json: 'spellingLoc']
	expansion_file SourceFile @[json: 'expansionLoc']
}

struct End {
mut:
	offset         int
	file           string     @[json: 'file']
	spelling_file  SourceFile @[json: 'spellingLoc']
	expansion_file SourceFile @[json: 'expansionLoc']
}

struct SourceFile {
	offset int    @[json: 'offset']
	path   string @[json: 'file']
}

struct AstJsonType {
	desugared_qualified string @[json: 'desugaredQualType']
	qualified           string @[json: 'qualType']
}

struct CxxBaseSpecifier {
	access         string
	written_access string      @[json: 'writtenAccess']
	ast_type       AstJsonType @[json: 'type']
}

struct RefDeclarationNode {
	kind_str string @[json: 'kind'] // e.g. "IntegerLiteral"
	name     string
mut:
	kind NodeKind @[skip]
}

struct OwnedTagDecl {
	id       string
	kind_str string @[json: 'kind']
	name     string
}

const bad_node = AstNode{
	kind: .bad
}

fn (value NodeValue) to_str() string {
	if value is int {
		return value.str()
	} else if value is bool {
		return if value { 'true' } else { 'false' }
	} else {
		return value as string
	}
}

fn (node AstNode) kindof(expected_kind NodeKind) bool {
	return node.kind == expected_kind
}

fn (node AstNode) has_child_of_kind(expected_kind NodeKind) bool {
	for child in node.inner {
		if child.kindof(expected_kind) {
			return true
		}
	}

	return false
}

fn (node AstNode) count_children_of_kind(kind_filter NodeKind) int {
	mut count := 0

	for child in node.inner {
		if child.kindof(kind_filter) {
			count++
		}
	}

	return count
}

fn (node AstNode) find_children(wanted_kind NodeKind) []AstNode {
	mut suitable_children := []AstNode{}

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

fn (mut node AstNode) try_get_next_child_of_kind(wanted_kind NodeKind) !AstNode {
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

fn (mut node AstNode) try_get_next_child() !AstNode {
	if node.current_child_id >= node.inner.len {
		return error('No more children')
	}

	current_child := node.inner[node.current_child_id]
	node.current_child_id++

	return current_child
}

fn (mut node AstNode) initialize_node_and_children() {
	node.kind = convert_str_into_node_kind(node.kind_str)

	for mut child in node.inner {
		child.initialize_node_and_children()
	}
}
