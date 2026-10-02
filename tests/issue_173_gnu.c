#include <stdio.h>
#include <stdlib.h>

static void assertion_failed(void) { abort(); }

#ifdef NDEBUG
#define test_assert(expr) ((void)0)
#else
#define test_assert(expr) \
    ((void)sizeof((expr) ? 1 : 0), __extension__({ \
        if (expr) ; else assertion_failed(); \
    }))
#endif

int main(void) {
    int checked = 0;
    test_assert(++checked == 1);
    printf("%d\n", checked);
    if (getenv("C2V_ASSERT_FAIL")) test_assert(0);
    return 0;
}
