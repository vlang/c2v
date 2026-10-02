#include <stdio.h>
typedef enum { asymbol, anumber } atom_type;
typedef struct sexpr_ sexpr;
typedef struct {
    atom_type type;
    union { char *a; double num; };
} atom;
typedef enum { slist, satom } sexpr_type;
typedef struct { int len; sexpr *a; } list;
typedef struct sexpr_ {
    sexpr_type type;
    union { list *list; atom *atom; };
} sexpr;
int main(void) {
    atom a = {.type = anumber, .num = 2.5};
    sexpr s = {.type = satom, .atom = &a};
    printf("%d %.1f %zu %zu\n", s.type, s.atom->num, sizeof(atom), sizeof(sexpr));
    return 0;
}
