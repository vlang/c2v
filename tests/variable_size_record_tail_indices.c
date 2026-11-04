#include <stdbool.h>
#include <stdio.h>

typedef enum { index_zero, index_one, index_two } Index;
typedef struct { int values[8]; } Tail;

static int index_calls;

int counted_index(void) {
    ++index_calls;
    return 1;
}

int main(void) {
    Tail tail = {{11, 17, 23, 29, 31, 37, 41, 43}};
    int indices[2] = {0, 1};
    int left = 1;
    int right = 2;
    bool flag = true;
    int comparison = tail.values[left < right];
    int parenthesized = tail.values[(left < right)];
    int negation = tail.values[!(left < right)];
    int boolean = tail.values[flag];
    int enumeration = tail.values[index_one];
    int nested = tail.values[indices[flag] + index_one];
    tail.values[left > right] += 7;
    int old = tail.values[left < right]++;
    int side_effect = tail.values[counted_index()];
    printf("%d %d %d %d %d %d %d %d %d %d\n", comparison, parenthesized,
           negation, boolean, enumeration, nested, tail.values[0], old,
           side_effect, index_calls);
    return 0;
}
