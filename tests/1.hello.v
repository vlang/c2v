[translated]
module main

[typedef]
struct C.FILE {}

// vstart

fn main() {
	C.printf(c'hello world!')
	return
}

struct Foo {
	bar int
}

fn implicit_inits() {
	num := 0
	foo := Foo{}
}
