#include <stdio.h>
#include <stdlib.h>

static void assertion_failed(const char *expr, const char *file,
                             unsigned int line, const char *function) {
    printf("failure %s %u %s\n", expr, line, function);
    exit(42);
}

#ifdef NDEBUG
#define test_assert(expr) ((void)0)
#define block_assert(expr) ((void)0)
#else
#define test_assert(expr) \
    ((void)sizeof((expr) ? 1 : 0), __extension__({ \
        if (expr) ; else assertion_failed(#expr, __FILE__, __LINE__, \
                                         __extension__ __PRETTY_FUNCTION__); \
    }))
#define block_assert(expr) \
    ((void)__extension__({ \
        if (!(expr)) assertion_failed(#expr, __FILE__, __LINE__, \
                                      __extension__ __PRETTY_FUNCTION__); \
    }))
#endif

#line 1 "issue_173_for_init_gnu.c"
int main(void) {
    int checked = 0;
    int iterations = 0;
    int order = 0;
    for (test_assert(++checked == 1 && !getenv("C2V_FOR_INIT_FAIL"));
         iterations < 2; ++iterations) {
        order = order * 10 + checked;
    }
    int comma_iterations = 0;
    for ((order = order * 10 + 2, test_assert(++checked == 2),
          order = order * 10 + 3);
         comma_iterations < 2; ++comma_iterations) {
        order += checked;
        continue;
    }
    int empty_iterations = 0;
    for (block_assert(++checked == 3); empty_iterations < 0; ++empty_iterations) {
        abort();
    }
    int declared = 0;
    for (int scoped = (block_assert(++checked == 4 && !getenv("C2V_FOR_INIT_BLOCK_FAIL")), 1);
         scoped < 3; ++scoped) {
        declared += scoped;
    }
    for (int scoped = 4; scoped < 6; ++scoped) {
        declared += scoped;
    }
    int scoped = 7;
    printf("%d %d %d %d %d %d\n", checked, iterations, comma_iterations,
           empty_iterations, order, declared + scoped);
    return 0;
}
