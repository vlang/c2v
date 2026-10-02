#include <assert.h>
#include <stdio.h>
#include <stdlib.h>

int main(void) {
    int checked = 0;
    assert(++checked == 1);
    printf("%d\n", checked);
    if (getenv("C2V_ASSERT_FAIL")) assert(0);
    return 0;
}
