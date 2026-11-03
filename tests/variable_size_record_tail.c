#include <stdio.h>
#include <stdlib.h>

typedef struct __attribute__((packed)) {
    short width;
    short height;
    short leftoffset;
    short topoffset;
    int columnofs[8];
} Patch;

typedef struct {
    int values[8];
    int after;
} Guard;

int main(int argc, char **argv) {
    Patch *patch = malloc(sizeof(Patch) + 8 * sizeof(int));
    if (patch == NULL) return 2;
    patch->width = 16;
    for (int i = 0; i < patch->width; i++) {
        patch->columnofs[i] = i * 3;
    }
    int first = patch->width / 2;
    patch->columnofs[first] += 7;
    int *entry = &patch->columnofs[first + 1];
    (*entry)++;
    int old = patch->columnofs[first + 2]++;
    int sum = 0;
    for (int i = 0; i < patch->width; i++) {
        sum += patch->columnofs[i];
    }
    Guard guard = {{0}, 99};
    if (argc > 1) return guard.values[argc + 6];
    printf("%d %d %d %d %d %d\n", (int)sizeof(Patch),
           (int)sizeof(patch->columnofs), sum, old, *entry, patch->columnofs[first]);
    free(patch);
    return 0;
}
