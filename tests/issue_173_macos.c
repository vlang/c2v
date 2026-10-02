#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    int checked = 0;
    assert(++checked == 1);
    int value = (assert(++checked == 2), 7);
    int loops = 0;
    for (; loops < 2; assert(++checked <= 4)) {
        ++loops;
        continue;
    }
    int sequenced = 0;
    for (int i = 0; i < 2; (assert(++checked <= 6), ++i)) {
        sequenced += checked;
    }
    printf("%d %d %d %d\n", checked, value, loops, sequenced);
    if (getenv("C2V_ASSERT_FAIL")) assert(0);
    return 0;
}
