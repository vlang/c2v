#include <stdio.h>

typedef unsigned char Byte;

typedef struct {
    Byte before;
    Byte top[4];
    Byte after;
    Byte lower_before;
    Byte bottom[4];
    Byte lower_after;
} Padded;

typedef struct {
    Byte values[4];
    Byte after;
} Guard;

static int index_calls;

int lower_index(void) {
    ++index_calls;
    return -1;
}

int main(int argc, char **argv) {
    Padded plane = {0};
    Padded *p = &plane;
    int left = -1;
    int right = 4;
    p->top[left] = 11;
    p->top[right] = 17;
    p->bottom[left] = 23;
    p->bottom[right] = 29;
    p->top[left] += 3;
    int old = p->bottom[right]++;
    Byte *entry = &p->top[right];
    ++*entry;
    p->top[1] = 9;
    int counted = p->top[lower_index()];
    printf("%d %d %d %d %d %d %d %d %d %d %d\n", (int)sizeof(Padded),
           (int)sizeof(p->top), (int)((char *)&p->top[0] - (char *)p),
           (int)((char *)&p->bottom[0] - (char *)p), p->before, p->after,
           p->lower_before, p->lower_after, old, counted, index_calls);
    Guard guard = {{0}, 99};
    if (argc > 1) return guard.values[argc + 2];
    return 0;
}
