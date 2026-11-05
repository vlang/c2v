#include "bits.h"

size_t sizeof_glyph(void) { return sizeof(Glyph); }
size_t sizeof_gap(void) { return sizeof(struct Gap); }
size_t sizeof_mixed(void) { return sizeof(struct Mixed); }
size_t sizeof_overlay(void) { return sizeof(union Overlay); }
size_t sizeof_anon(void) { return sizeof(Anon); }
size_t sizeof_outer(void) { return sizeof(struct Outer); }
size_t sizeof_after(void) { return sizeof(struct After); }
size_t offsetof_mixed_tail(void) { return offsetof(struct Mixed, tail); }
size_t offsetof_after_tail(void) { return offsetof(struct After, tail); }

// C writes the bit-fields for V to read...
void fill(Glyph *g, struct Gap *gap, struct Mixed *m, Anon *a, struct After *af) {
	g->Colored = 1;
	g->Visible = 0;
	g->SourceIdx = 9;
	g->Codepoint = 0x1F600;
	g->AdvanceX = 7.5f;
	gap->c[0] = 'a';
	gap->c[1] = 'b';
	gap->x = -31072;
	gap->d = 'z';
	m->s = -11;
	m->b = 1;
	m->m = MODE_D;
	m->big = 0xABCDEF0123ULL;
	m->tail = -2;
	a->a = 5;
	a->b = 77;
	af->g.Codepoint = 65;
	af->flag = 6;
	af->tail = 'q';
}

// ...and reads back what V wrote.
int check(const Glyph *g, const struct Gap *gap, const struct Mixed *m) {
	return g->Colored == 0 && g->Visible == 1 && g->SourceIdx == 3 && g->Codepoint == 0x3FFFFFF
		&& g->AdvanceX == 1.25f && gap->x == -65536 && gap->d == 'y' && gap->c[1] == 'b'
		&& m->s == 15 && m->b == 0 && m->m == MODE_B && m->big == 0xFFFFFFFFFFULL
		&& m->tail == 300;
}
