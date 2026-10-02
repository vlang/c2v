#include <stdio.h>
int main(void) {
    union {int i; int j;} a;
    union {float f; unsigned int bits;} b;
    struct {int x;} c;
    a.i = 5;
    b.f = 1.0f;
    c.x = 2;
    printf("%d %x %d\n", a.j, b.bits, c.x);
    printf("%zu %zu %zu\n", sizeof(a), sizeof(b), sizeof(c));
    return 0;
}
