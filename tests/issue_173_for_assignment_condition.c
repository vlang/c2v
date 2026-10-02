#include <stdio.h>
#include <stdlib.h>

static void assertion_failed(void) { exit(42); }
#define block_assert(expr) \
    ((void)__extension__({ if (!(expr)) assertion_failed(); }))

int condition_calls = 0;
int next_value(int limit) {
    ++condition_calls;
    if (condition_calls <= limit) return condition_calls;
    return 0;
}

void run_case(int limit, int stop, int skip) {
    condition_calls = 0;
    int initialized = 0;
    int value = -1;
    int posts = 0;
    int body = 0;
    int sum = 0;
    int order = 0;
    for (block_assert(++initialized == 1); value = next_value(limit);
         (++posts, order = order * 10 + value, ++value)) {
        ++body;
        sum += value;
        if (value == stop) break;
        if (value == skip) continue;
        sum += 10;
    }
    printf("%d %d %d %d %d %d %d\n", initialized, condition_calls, value,
           posts, body, sum, order);
}

void short_circuit(int enabled) {
    condition_calls = 0;
    int initialized = 0;
    int value = -1;
    int posts = 0;
    int body = 0;
    for (block_assert(++initialized == 1); enabled && (value = next_value(2));
         ++posts) {
        body += value;
        continue;
    }
    printf("%d %d %d %d %d\n", initialized, condition_calls, value, posts, body);
}

void parenthesized_condition(void) {
    condition_calls = 0;
    int initialized = 0;
    int value = -1;
    int posts = 0;
    int sum = 0;
    for (block_assert(++initialized == 1); (value = next_value(2)); ++posts) {
        sum += value;
    }
    printf("%d %d %d %d %d\n", initialized, condition_calls, value, posts, sum);
}

void compound_condition(void) {
    int initialized = 0;
    int value = 3;
    int posts = 0;
    int sum = 0;
    for (block_assert(++initialized == 1); value -= 1; ++posts) { sum += value; }
    printf("%d %d %d %d\n", initialized, value, posts, sum);
}

int main(void) {
    run_case(3, 0, 0);
    run_case(3, 0, 2);
    run_case(3, 2, 0);
    run_case(0, 0, 0);
    short_circuit(0);
    short_circuit(1);
    parenthesized_condition();
    compound_condition();
    return 0;
}
