// Records with bit-fields, for wrapper_test.v: the wrapper's records must
// have the layout of this compiled C code.
#include <stddef.h>

typedef enum Mode { MODE_A, MODE_B, MODE_C, MODE_D, MODE_E } Mode;

// As Dear ImGui's ImFontGlyph: bit-fields that share an `unsigned int`.
typedef struct Glyph {
	unsigned int Colored : 1;
	unsigned int Visible : 1;
	unsigned int SourceIdx : 4;
	unsigned int Codepoint : 26;
	float AdvanceX;
} Glyph;

// `x` does not fit after `c` in the first `int`, so C starts it at offset 4.
struct Gap {
	char c[2];
	int x : 17;
	char d;
};

// Signed, bool and enum bit-fields, a zero-width one, and one wider than 32
// bits that starts a new `unsigned long long`.
struct Mixed {
	int s : 5;
	_Bool b : 1;
	Mode m : 3;
	unsigned : 0;
	unsigned long long big : 40;
	short tail;
};

union Overlay {
	unsigned u : 4;
	float f;
};

typedef struct {
	unsigned a : 3;
	int b;
} Anon;

// An anonymous member record with a bit-field, then more bit-fields.
struct Outer {
	int head;
	union {
		unsigned u : 4;
		float f;
	};
	unsigned z : 5;
};

// Bit-fields after a record member.
struct After {
	Glyph g;
	unsigned flag : 3;
	char tail;
};

size_t sizeof_glyph(void);
size_t sizeof_gap(void);
size_t sizeof_mixed(void);
size_t sizeof_overlay(void);
size_t sizeof_anon(void);
size_t sizeof_outer(void);
size_t sizeof_after(void);
size_t offsetof_mixed_tail(void);
size_t offsetof_after_tail(void);
void fill(Glyph *g, struct Gap *gap, struct Mixed *m, Anon *a, struct After *af);
int check(const Glyph *g, const struct Gap *gap, const struct Mixed *m);
