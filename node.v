// To generate example AST JSON, that Node structure maps,
// use clang -w -Xclang -ast-dump=json -fsyntax-only -fno-diagnostics-color -c 1.hello.c > ast.json command, for example.

module main

import os
import json2
import strings
import math

// Read Clang's AST incrementally. Decode small subtrees directly, and split
// larger nodes into metadata and child arrays. Neither the complete JSON text
// nor a token table for the entire translation unit is kept in memory, and
// garbage collection can remain enabled even for large amalgamations.
struct AstReader {
mut:
	file           os.File
	buffer         []u8 = []u8{len: 64 * 1024}
	pos            int
	end            int
	offset         u64
	decode_jobs    chan AstDecodeJob
	decode_results chan AstDecodeResult
	workers        []thread
	pending        int
}

@[params]
struct AstReadOptions {
	jobs int = 1
}

struct AstDecodeJob {
	text        string
	index       int
	depth       int
	reservation bool
}

struct AstDecodeResult {
	index         int
	nodes         []Node
	reservations  []TypeReservationNode
	error_message string
}

fn decode_ast_worker(jobs chan AstDecodeJob, results chan AstDecodeResult) {
	for {
		job := <-jobs or { break }
		results <- decode_ast_job(job)
	}
}

fn decode_ast_job(job AstDecodeJob) AstDecodeResult {
	defer { unsafe { job.text.free() } }
	if job.reservation {
		mut nodes := json2.decode[[]TypeReservationNode](job.text) or {
			return AstDecodeResult{ index: job.index, error_message: err.msg() }
		}
		for mut node in nodes {
			node.discard_expression_nodes(job.depth)
		}
		return AstDecodeResult{ index: job.index, reservations: nodes }
	}
	nodes := json2.decode[[]Node](job.text) or {
		return AstDecodeResult{ index: job.index, error_message: err.msg() }
	}
	return AstDecodeResult{ index: job.index, nodes: nodes }
}

fn read_ast[T](path string, options AstReadOptions) !T {
	mut reader := AstReader{ file: os.open(path)! }
	// Small inputs are cheaper to decode on the calling thread. Pending jobs
	// are bounded to one 64 KiB chunk per worker, including on error paths.
	workers := if options.jobs > 1 {
		int(math.min(u64(options.jobs), os.file_size(path) / u64(64 * 1024)))
	} else {
		1
	}
	if workers > 1 {
		// Keep enough input ahead of the decoder to fill every worker's queue.
		// Individual jobs still contain at most 64 KiB of JSON.
		unsafe { reader.buffer.free() }
		reader.buffer = []u8{len: workers * 64 * 1024}
		reader.decode_jobs = chan AstDecodeJob{cap: workers}
		reader.decode_results = chan AstDecodeResult{cap: workers}
		for _ in 0 .. workers {
			reader.workers << spawn decode_ast_worker(reader.decode_jobs, reader.decode_results)
		}
	}
	defer {
		if reader.workers.len > 0 {
			reader.decode_jobs.close()
			reader.workers.wait()
		}
		reader.file.close()
		unsafe { reader.buffer.free() }
	}
	result := reader.read_node[T](0)!
	reader.whitespace()!
	reader.peek()!
	if reader.end != 0 {
		return reader.invalid('unexpected data after the AST')
	}
	return result
}

fn (r &AstReader) invalid(message string) IError {
	return error('invalid AST JSON at byte ${r.offset + u64(r.pos)}: ${message}')
}

fn (mut r AstReader) peek() !u8 {
	if r.pos == r.end {
		r.offset += u64(r.end)
		r.pos = 0
		r.end = r.file.read(mut r.buffer) or {
			if err is os.Eof { 0 } else { return err }
		}
	}
	return if r.end == 0 { u8(0) } else { r.buffer[r.pos] }
}

fn (mut r AstReader) whitespace() ! {
	for r.peek()! in [u8(` `), `\n`, `\r`, `\t`] {
		r.pos++
	}
}

fn (mut r AstReader) expect(ch u8) ! {
	r.whitespace()!
	if r.peek()! != ch {
		return r.invalid('expected `${ch.ascii_str()}`')
	}
	r.pos++
}

// Copy a JSON value in buffer-sized spans, respecting escaped strings and
// nested objects/arrays. The metadata decoder validates its JSON syntax.
fn (mut r AstReader) value(mut out strings.Builder) ! {
	r.whitespace()!
	mut closers := []u8{}
	defer { unsafe { closers.free() } }
	mut quoted := false
	mut escaped := false
	mut started := false
	for {
		if r.peek()! == 0 {
			return r.invalid('unexpected end of input')
		}
		start := r.pos
		for r.pos < r.end {
			ch := r.buffer[r.pos]
			if !quoted && closers.len == 0 && started
				&& ch in [u8(`,`), `}`, `]`, ` `, `\n`, `\r`, `\t`] {
				out.write(r.buffer[start..r.pos])!
				return
			}
			r.pos++
			started = true
			if quoted {
				if escaped {
					escaped = false
				} else if ch == `\\` {
					escaped = true
				} else if ch == `"` {
					quoted = false
					if closers.len == 0 {
						out.write(r.buffer[start..r.pos])!
						return
					}
				}
			} else if ch == `"` {
				quoted = true
			} else if ch in [u8(`{`), `[`] {
				closers << if ch == `{` { u8(`}`) } else { u8(`]`) }
			} else if ch in [u8(`}`), `]`] {
				if closers.len == 0 || closers.pop() != ch {
					return r.invalid('unmatched closing delimiter')
				}
				if closers.len == 0 {
					out.write(r.buffer[start..r.pos])!
					return
				}
			}
		}
		out.write(r.buffer[start..r.pos])!
	}
}

fn (mut r AstReader) read_node[T](depth int) !T {
	r.whitespace()!
	// Decode subtrees that fit in the input buffer in one call. This gives
	// their child arrays exact capacities and avoids per-node scratch work,
	// with each JSON input limited to 64 KiB.
	if end := r.buffered_node_end() {
		text := r.buffer[r.pos..end].bytestr()
		r.pos = end
		defer { unsafe { text.free() } }
		mut node := json2.decode[T](text)!
		$if T is TypeReservationNode {
			node.discard_expression_nodes(depth)
		}
		return node
	}
	r.expect(`{`)!
	mut metadata := strings.new_builder(512)
	mut key_text := strings.new_builder(32)
	defer {
		unsafe {
			metadata.free()
			key_text.free()
		}
	}
	metadata.write_u8(`{`)
	mut inner := []T{}
	mut array_filler := []Node{}
	mut first := true
	r.whitespace()!
	for r.peek()! != `}` {
		if !first {
			r.expect(`,`)!
		}
		first = false
		key_text.clear()
		r.value(mut key_text)!
		key_json := key_text.str()
		if key_json.len < 2 || key_json[0] != `"` || key_json[key_json.len - 1] != `"` {
			return r.invalid('expected an object key')
		}
		key := if key_json.contains('\\') {
			json2.decode[string](key_json)!
		} else {
			key_json[1..key_json.len - 1]
		}
		r.expect(`:`)!
		if key == 'inner' {
			inner = r.children[T](depth)!
		} else if key == 'array_filler' {
			$if T is Node {
				array_filler = r.children[Node](depth)!
			} $else {
				// Array initializers cannot reserve declaration names. Still read
				// them incrementally so a large initializer cannot inflate the
				// reservation pass's metadata/token buffer.
				r.children[T](depth + 1)!
			}
		} else {
			metadata.write_string(key_json)
			metadata.write_u8(`:`)
			r.value(mut metadata)!
			metadata.write_u8(`,`)
		}
		r.whitespace()!
	}
	r.pos++
	if metadata.len > 1 && metadata[metadata.len - 1] == `,` {
		metadata.trim(metadata.len - 1)
	}
	metadata.write_u8(`}`)
	mut node := json2.decode[T](metadata.str())!
	node.inner = inner
	$if T is Node {
		node.array_filler = array_filler
	}
	return node
}

fn (r &AstReader) buffered_node_end() ?int {
	if r.pos == r.end || r.buffer[r.pos] != `{` {
		return none
	}
	mut depth := 0
	mut quoted := false
	mut escaped := false
	limit := math.min(r.end, r.pos + 64 * 1024)
	for i := r.pos; i < limit; i++ {
		ch := r.buffer[i]
		if quoted {
			if escaped {
				escaped = false
			} else if ch == `\\` {
				escaped = true
			} else if ch == `"` {
				quoted = false
			}
		} else if ch == `"` {
			quoted = true
		} else if ch == `{` {
			depth++
		} else if ch == `}` {
			depth--
			if depth == 0 {
				return i + 1
			}
		}
	}
	return none
}

fn (mut r AstReader) children[T](depth int) ![]T {
	r.expect(`[`)!
	mut nodes := []T{cap: 1}
	mut chunk := strings.new_builder(if r.workers.len > 0 { 64 * 1024 } else { 0 })
	defer { unsafe { chunk.free() } }
	chunk.write_u8(`[`)
	mut chunk_count := 0
	mut first := true
	r.whitespace()!
	for r.peek()! != `]` {
		if !first {
			r.expect(`,`)!
		}
		first = false
		r.whitespace()!
		if r.workers.len > 0 {
			if end := r.buffered_node_end() {
				if chunk_count > 0 && chunk.len + end - r.pos + 2 > 64 * 1024 {
					r.submit_decode[T](mut chunk, nodes.len - chunk_count, depth + 1)
					chunk_count = 0
					if r.pending == r.workers.len {
						$if T is TypeReservationNode {
							r.drain_decodes[T](mut nodes, depth)!
						} $else {
							r.collect_decode[T](mut nodes)!
						}
					}
				}
				if chunk_count > 0 {
					chunk.write_u8(`,`)
				}
				chunk.write(r.buffer[r.pos..end])!
				r.pos = end
				chunk_count++
				nodes << T{}
				r.whitespace()!
				continue
			}
			// Nested arrays use the same pool. Finish this array's queued work
			// before recursing so result indices always belong to one array.
			if chunk_count > 0 {
				r.submit_decode[T](mut chunk, nodes.len - chunk_count, depth + 1)
				chunk_count = 0
			}
			r.drain_decodes[T](mut nodes, depth)!
		}
		node := r.read_node[T](depth + 1)!
		$if T is TypeReservationNode {
			if depth > 0 && !node.needed_for_type_reservation() {
				r.whitespace()!
				continue
			}
		}
		nodes << node
		r.whitespace()!
	}
	r.pos++
	if chunk_count > 0 {
		r.submit_decode[T](mut chunk, nodes.len - chunk_count, depth + 1)
	}
	r.drain_decodes[T](mut nodes, depth)!
	return nodes
}

fn (mut r AstReader) submit_decode[T](mut chunk strings.Builder, index int, depth int) {
	chunk.write_u8(`]`)
	r.decode_jobs <- AstDecodeJob{
		text:        chunk.str()
		index:       index
		depth:       depth
		reservation: $if T is TypeReservationNode { true } $else { false }
	}
	r.pending++
	chunk.write_u8(`[`)
}

fn (mut r AstReader) collect_decode[T](mut nodes []T) ! {
	result := <-r.decode_results
	r.pending--
	if result.error_message != '' {
		return error(result.error_message)
	}
	$if T is Node {
		for i, node in result.nodes {
			nodes[result.index + i] = node
		}
	} $else {
		for i, node in result.reservations {
			nodes[result.index + i] = node
		}
	}
}

fn (mut r AstReader) drain_decodes[T](mut nodes []T, depth int) ! {
	for r.pending > 0 {
		r.collect_decode[T](mut nodes)!
	}
	$if T is TypeReservationNode {
		if depth > 0 {
			nodes = nodes.filter(it.needed_for_type_reservation())
		}
	}
}

type Value = string | int | bool

// vfmt off
struct Node {
	id                   string
	kind_str             string       		@[json: 'kind'] 				// e.g. "IntegerLiteral"
	previous_declaration string       		@[json: 'previousDecl']
	name                 string 										// e.g. "my_var_name"
	union_field          RefDeclarationNode @[json: 'field'] // selected field in a union initializer
	member               string       		@[json: 'member']
	referenced_member_decl string      		@[json: 'referencedMemberDecl']
	ast_type             AstJsonType  		@[json: 'type']
	ctor_type            AstJsonType  		@[json: 'ctorType']
	class_modifier       string       		@[json: 'storageClass']
	tags                 string       		@[json: 'tagUsed']
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
		is_bitfield          bool         		@[json: 'isBitfield'] // a FieldDecl with a width
		is_implicit          bool         		@[json: 'isImplicit']
		is_used              bool         		@[json: 'isUsed']
		is_pure              bool         		@[json: 'pure']
		is_virtual           bool         		@[json: 'virtual']
		is_array             bool         		@[json: 'isArray'] // `delete[]` / `new T[n]`
		is_arrow             bool         		@[json: 'isArrow'] // a MemberExpr accessed with `->`
		complete_definition  bool         		@[json: 'completeDefinition']
		is_inline            bool         		@[json: 'inline']
		is_referenced        bool         		@[json: 'isReferenced']
		is_elidable          bool         		@[json: 'elidable'] // a copy/move construction C++ elides
		is_nrvo              bool         		@[json: 'nrvo'] // a local constructed directly in the return slot
		parent_decl_context_id string     		@[json: 'parentDeclContextId'] // set on out-of-line member definitions
		explicitly_defaulted string       		@[json: 'explicitlyDefaulted']
		explicitly_deleted   bool         		@[json: 'explicitlyDeleted']
	mut:
	initialization_type  string       		@[json: 'init'] 				// "c" => "cinit"
	//parent_node &Node [skip] = unsafe {nil }
	location             NodeLocation 		@[json: 'loc']
	comment				 string		@[skip] // comment string before this node
	unique_id			 int		= -1 @[skip]
	range                Range
	inner                []Node
	array_filler         []Node 										// for InitListExpr
	ref_declaration      RefDeclarationNode @[json: 'referencedDecl'] 	//&Node
	any_init             RefDeclarationNode @[json: 'anyInit']
	base_init            AstJsonType        @[json: 'baseInit'] // the base class a constructor initializer constructs
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
	col            int
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
	line           int
	col            int
	file           string     @[json: 'file']
	spelling_file  SourceFile @[json: 'spellingLoc']
	expansion_file SourceFile @[json: 'expansionLoc']
}

struct End {
mut:
	offset         int
	col            int        @[json: 'col']
	tok_len        int        @[json: 'tokLen']
	file           string     @[json: 'file']
	spelling_file  SourceFile @[json: 'spellingLoc']
	expansion_file SourceFile @[json: 'expansionLoc']
}

struct SourceFile {
	offset                 int    @[json: 'offset']
	path                   string @[json: 'file']
	line                   int
	col                    int
	is_macro_arg_expansion bool         @[json: 'isMacroArgExpansion']
	included_from          IncludedFrom @[json: 'includedFrom']
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
	written_access string      @[json: 'writtenAccess']
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
