#include <stdio.h>
#include <stdlib.h>

static void assertion_failed(const char *expr, const char *file,
                             unsigned int line, const char *function) {
    if (getenv("C2V_ASSERT_METADATA")) {
        printf("%s %u %s\n", expr, line, function);
        fflush(stdout);
        exit(42);
    }
    abort();
}

#ifdef NDEBUG
#define test_assert(expr) ((void)0)
#else
#define test_assert(expr) \
    ((void)sizeof((expr) ? 1 : 0), __extension__({ \
        if (expr) ; else assertion_failed(#expr, __FILE__, __LINE__, \
                                         __extension__ __PRETTY_FUNCTION__); \
    }))
#endif

#line 1 "issue_173_gnu.c"
int main(void) {
    int checked = 0;
    test_assert(++checked == 1);
    int value = (test_assert(++checked == 2), 7);
    int loops = 0;
    for (; loops < 2; test_assert(++checked <= 4)) {
        ++loops;
        continue;
    }
    int sequenced = 0;
    for (int i = 0; i < 2; (test_assert(++checked <= 6), ++i)) {
        sequenced += checked;
    }
    printf("%d %d %d %d\n", checked, value, loops, sequenced);
    if (getenv("C2V_ASSERT_FAIL")) test_assert(0);
    return 0;
}
