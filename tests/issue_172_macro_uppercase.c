#include <stdio.h>

#define ANONYMOUS_MEMBER union { int x; }

typedef struct {
    ANONYMOUS_MEMBER;
    int C2v_anonymous_0;
} macro_uppercase;

int main(void) {
    macro_uppercase value = {.x = 3, .C2v_anonymous_0 = 7};
    printf("%d %d %zu\n", value.x, value.C2v_anonymous_0, sizeof(macro_uppercase));
    return 0;
}
