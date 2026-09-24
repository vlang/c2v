#include <stdio.h>
enum cull_t { CT_FRONT, CT_BACK, CT_TWO };
enum flags_t { F_NONE = 1, F_LINEAR = 2, F_NOSTOP = 0x40 };
static int last_cull = -1;
void set_cull(int cull) { last_cull = cull; }
int pick(int kind, int flags) {
	int r = 0;
	switch ((flags_t)(flags & ~F_NOSTOP)) {
		case F_NONE: set_cull(CT_BACK); r += 10; break;
		case F_LINEAR: set_cull(CT_TWO); return 2;
		default: set_cull(CT_FRONT); r += 20; break;
	}
	switch ((cull_t)kind) {
		case CT_FRONT: r += 100; break;
		case CT_BACK:
		default: r += 1000; break;
	}
	return r + last_cull;
}
int main() {
	printf("%d %d %d %d\n", pick(0, 1 | F_NOSTOP), pick(1, 2), pick(2, 4), pick(1, 1));
	return 0;
}
