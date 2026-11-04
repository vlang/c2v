// Run by wrapper_test.v against the wrapper of bits.h: V reads the bit-fields
// C wrote, writes new values for C to check, and compares record layouts.
import bits

fn main() {
	println('sizes ${sizeof(bits.Glyph)}=${bits.sizeof_glyph()} ${sizeof(bits.Gap)}=${bits.sizeof_gap()} ${sizeof(bits.Mixed)}=${bits.sizeof_mixed()} ${sizeof(bits.Overlay)}=${bits.sizeof_overlay()} ${sizeof(bits.Anon)}=${bits.sizeof_anon()} ${sizeof(bits.Outer)}=${bits.sizeof_outer()} ${sizeof(bits.After)}=${bits.sizeof_after()}')
	println('offsets ${__offsetof(bits.Mixed, tail)}=${bits.offsetof_mixed_tail()} ${__offsetof(bits.After, tail)}=${bits.offsetof_after_tail()}')
	mut g := bits.Glyph{}
	mut gap := bits.Gap{}
	mut m := bits.Mixed{}
	mut a := bits.Anon{}
	mut af := bits.After{}
	bits.fill(&g, &gap, &m, &a, &af)
	println('glyph ${g.colored()} ${g.visible()} ${g.sourceIdx()} ${g.codepoint():x} ${g.advanceX}')
	println('gap ${gap.x()} ${rune(gap.d)}')
	println('mixed ${m.s()} ${m.b()} ${m.m()} ${m.big():x} ${m.tail}')
	println('anon ${a.a()} ${a.b}')
	println('after ${af.g.codepoint()} ${af.flag()} ${rune(af.tail)}')
	g.set_colored(0)
	g.set_visible(1)
	g.set_sourceIdx(3)
	g.set_codepoint(0xFFFFFFFF) // truncated to 26 bits, as in C
	g.advanceX = 1.25
	gap.set_x(-65536)
	gap.d = `y`
	m.set_s(15)
	m.set_b(false)
	m.set_m(.mode_b)
	m.set_big(0xFFFFFFFFFF)
	m.tail = 300
	println('check ${bits.check(&g, &gap, &m)}')
}
