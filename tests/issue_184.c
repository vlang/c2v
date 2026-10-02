#include <stdio.h>

int main(void) {
    int value = 1, n = 2;
    __atomic_store_n(&value, n > 0 && n <= 2, __ATOMIC_RELAXED);
    int before = __atomic_fetch_add(&value, 3, __ATOMIC_SEQ_CST);
    int expected = 4;
    int exchanged = __atomic_compare_exchange_n(&value, &expected, 7, 0,
        __ATOMIC_SEQ_CST, __ATOMIC_RELAXED);
    printf("%d %d %d\n", before, exchanged,
        __atomic_load_n(&value, __ATOMIC_SEQ_CST));
    return 0;
}
