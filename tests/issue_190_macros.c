#include <stdio.h>
#define UNION_A(name) union { int i; int j; } name
#define UNION_B(name) union { float f; unsigned int bits; } name
#define RECORD_C(name) struct { int x; } name
#define TWO_RECORDS struct { int left; } d = {3}; struct { int right; } e = {4}
#define FIELD_RECORD(field) struct { int field; }
#define SAME_TOKEN_RECORDS FIELD_RECORD(shared_first) f = {5}; FIELD_RECORD(shared_second) g = {6}
int main(void) {
    UNION_A(a);
    UNION_B(b);
    RECORD_C(c);
    TWO_RECORDS;
    SAME_TOKEN_RECORDS;
    UNION_A(h);
    a.i = 5;
    b.f = 1.0f;
    c.x = 2;
    h.i = 8;
    printf("%d %x %d %d %d %d %d %d\n", a.j, b.bits, c.x, d.left, e.right, f.shared_first, g.shared_second, h.j);
    printf("%zu %zu %zu\n", sizeof(a), sizeof(b), sizeof(c));
    return 0;
}
