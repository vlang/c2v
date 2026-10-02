#define NDEBUG
#include <assert.h>
#include <stdio.h>

int main(void) {
    int checked = 0;
    assert(++checked == 1);
    int value = (assert(++checked == 2), 7);
    for (int i = 0; i < 2; (assert(++checked <= 4), assert(++checked <= 5), ++i)) {
        continue;
    }
    int i = 0;
    for (assert(++checked == 1); i < 2; ++i) {
        continue;
    }
    for ((assert(++checked == 1), i = 0, assert(++checked == 2)); i < 2; ++i) {
        continue;
    }
    printf("%d %d\n", checked, value);
    return 0;
}
