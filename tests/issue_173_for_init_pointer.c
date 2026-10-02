#include <stdio.h>

int main(void) {
    int value = 0;
    int *ptr = &value;
    int i = 0;
    for (++*ptr, i = 0; i < 1; ++i) {}
    for (++*ptr, --*ptr, ++*ptr, i = 0; i < 1; ++i) {}
    for (i = 0, ++*ptr; i < 1; ++i) {}
    printf("%d %d\n", value, i);
    return 0;
}
