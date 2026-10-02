#include <stdio.h>

int main(void) {
    int a = 8, b = 1, shift = 3;
    printf("%d %d %d %d %d %d\n", a & b << shift, a & b + 7,
        a >> b + 1, b | 2 ^ 3, b << 2 * 2, 2 + 1 << 2);
    if (a & b << shift) puts("yes");
    else puts("no");
    return 0;
}
