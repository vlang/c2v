#include <stdio.h>

typedef unsigned int dword;
union flint { dword i; float f; };

static dword table[4] = { 0, 0, 0, 0 };

float InvSqrtish(float x) {
	dword a = ((union flint *)(&x))->i;
	union flint seed;
	seed.i = ((((3 * 127 - 1) - ((a >> 23) & 0xFF)) >> 1) << 23) | table[a & 3];
	return seed.f;
}

int FloatBits(float f) {
	return *(int *)&f;
}

void Scale(float &out, float by) {
	float local = out * by;
	unsigned char *bytes = (unsigned char *)&local;
	bytes[3] ^= 0x80;	// flip the sign
	out = local;
}

int main() {
	float v = 2.0f;
	Scale(v, 3.0f);
	void *p = &v;
	printf("%g %g %x %g %d\n", InvSqrtish(4.0f), InvSqrtish(16.0f), FloatBits(1.0f), v, *(float *)p == v);
	return 0;
}
