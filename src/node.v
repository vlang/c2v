// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
module main

const bad_node = Node{
	kind: .bad
}

pub fn (n &Node) str() string {
	return '{$n.kind} name:"$n.name" value:"$n.value" loc:$n.loc  #c: $n.inner.len typ:"$n.typ.q"'
}

fn (n Node) print() {
	mut ident := ''
	print(ident)
	println(n.str())
	if n.inner.len > 0 {
		println('')
	}
}

fn val_is_loc(val string) bool {
	return val.contains('line:') || val.contains('col:')
		|| (val.starts_with('/') && val.ends_with('>') && val.contains(':'))
		|| (val.contains('.c:')) || (val.starts_with('<') && val.contains('.cc:'))
		|| (val.starts_with('<') && val.contains('.cpp:'))
		|| (val.starts_with('<built-in>:')) || (val.contains('.h:'))
		|| (val.starts_with('../') && val.contains('.h:'))
}

fn line_is_source(val string) bool {
	return val.ends_with('.c')
}

fn line_is_builtin_header(val string) bool {
	return val.contains_any_substr(['usr/include', '/opt/', 'usr/lib', 'usr/local', '/Library/',
		'lib/clang'])
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
fn (node &Node) iss(kind NodeType) bool {
	return node.kind == kind
}

fn (node &Node) has(typ NodeType) bool {
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

fn (node &Node) nr_children(kind NodeType) int {
	mut res := 0
	for child in node.inner {
		if child.kind == kind {
			res++
		}
	}
	return res
}

fn (node &Node) find_child(kind NodeType) ?Node {
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

fn (node &Node) find_children(kind NodeType) []Node {
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

fn (node &Node) get(kind NodeType) Node {
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
		eprintln('get(): WANTED $kind.str() BUT GOT $child.kind.str() (num=${int(child.kind)})')
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
		vprintln('get2() OUT OF BOUNDS. node: $node.typ parent : vals')
		return bad_node
	}
	child := node.inner[node.child_i]
	unsafe {
		node.child_i++
	}
	return child
}

fn (mut node Node) set_node_kind_recursively() {
	node.kind = node_kind_from_str(node.kind_str)

	for mut child in node.inner {
		child.set_node_kind_recursively()
	}
}
