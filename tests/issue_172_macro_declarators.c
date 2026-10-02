#include <stddef.h>
#include <stdio.h>

#define PAIR(A, B) struct { int x; } *A, B, *A##_again
#define ARRAYS(P, V) struct { int item; } *P[2], V[2], *P##_again[2]
#define MEMBERS PAIR(a, b); PAIR(c, d); ARRAYS(ap, av); ARRAYS(bp, bv)

typedef struct {
    MEMBERS;
    int after;
} macro_declarators;

int main(void) {
    macro_declarators value = {
        .b = {.x = 11},
        .d = {.x = 13},
        .av = {{.item = 17}, {.item = 19}},
        .bv = {{.item = 23}, {.item = 29}},
        .after = 31,
    };
    value.a = &value.b;
    value.a_again = &value.b;
    value.c = &value.d;
    value.c_again = &value.d;
    value.ap[0] = &value.av[0];
    value.ap_again[1] = &value.av[1];
    value.bp[0] = &value.bv[0];
    value.bp_again[1] = &value.bv[1];
    value.a->x += 1;
    value.c->x += 2;
    value.ap[0]->item += 3;
    value.bp[0]->item += 4;

    printf("%d %d %d %d %d\n", value.a->x, value.a_again->x,
        value.c->x, value.c_again->x, value.after);
    printf("%d %d %d %d\n", value.ap[0]->item, value.ap_again[1]->item,
        value.bp[0]->item, value.bp_again[1]->item);
    printf("%zu %zu %zu %zu %zu %zu\n", sizeof(macro_declarators),
        sizeof(value.a), sizeof(value.b), sizeof(value.ap),
        sizeof(value.av), sizeof(value.after));
    printf("%zu %zu %zu %zu %zu %zu\n", offsetof(macro_declarators, a),
        offsetof(macro_declarators, b), offsetof(macro_declarators, c),
        offsetof(macro_declarators, av), offsetof(macro_declarators, bp),
        offsetof(macro_declarators, after));
    return 0;
}
