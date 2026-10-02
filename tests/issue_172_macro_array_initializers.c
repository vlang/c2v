#include <stddef.h>
#include <stdio.h>

#define FULL_MEMBER struct { int number; } full[2]
#define PARTIAL_MEMBER struct { double fraction; int tag; } partial[3]
#define SPARSE_MEMBER struct { unsigned int code; } sparse[4]
#define GRID_MEMBER struct { int first; int last; } grid[3][3]
#define UNION_MEMBER union { int integer; double real; } choices[3]
#define ARRAY_MEMBERS FULL_MEMBER; PARTIAL_MEMBER; SPARSE_MEMBER; GRID_MEMBER; UNION_MEMBER

typedef struct {
    ARRAY_MEMBERS;
} macro_array_initializers;

#define FIRST_POINTER_MEMBER struct { int number; } *a[2]
#define SECOND_POINTER_MEMBER struct { double fraction; } *b[2]
#define POINTER_MEMBERS FIRST_POINTER_MEMBER; SECOND_POINTER_MEMBER

typedef struct {
    POINTER_MEMBERS;
    int tag;
} macro_pointer_initializers;

int main(void) {
    macro_array_initializers value = {
        .full = {{.number = 11}, {.number = 12}},
        .partial = {{.fraction = 2.5, .tag = 21}},
        .sparse = {[2] = {.code = 31}},
        .grid = {
            {{.first = 41, .last = 42}},
            {[2] = {.first = 51, .last = 52}},
        },
        .choices = {[1] = {.real = 6.5}},
    };

    printf("%d %d\n", value.full[0].number, value.full[1].number);
    printf("%.1f %d %.1f %d %.1f %d\n", value.partial[0].fraction,
        value.partial[0].tag, value.partial[1].fraction, value.partial[1].tag,
        value.partial[2].fraction, value.partial[2].tag);
    printf("%u %u %u %u\n", value.sparse[0].code, value.sparse[1].code,
        value.sparse[2].code, value.sparse[3].code);
    printf("%d %d %d %d %d %d\n", value.grid[0][0].first,
        value.grid[0][0].last, value.grid[0][1].first, value.grid[0][1].last,
        value.grid[0][2].first, value.grid[0][2].last);
    printf("%d %d %d %d %d %d\n", value.grid[1][0].first,
        value.grid[1][0].last, value.grid[1][1].first, value.grid[1][1].last,
        value.grid[1][2].first, value.grid[1][2].last);
    printf("%d %d %d %d %d %d\n", value.grid[2][0].first,
        value.grid[2][0].last, value.grid[2][1].first, value.grid[2][1].last,
        value.grid[2][2].first, value.grid[2][2].last);
    printf("%d %.1f %d\n", value.choices[0].integer,
        value.choices[1].real, value.choices[2].integer);
    printf("%zu %zu %zu %zu %zu %zu\n", sizeof(macro_array_initializers),
        sizeof(value.full), sizeof(value.partial), sizeof(value.sparse),
        sizeof(value.grid), sizeof(value.choices));
    printf("%zu %zu %zu %zu %zu\n", offsetof(macro_array_initializers, full),
        offsetof(macro_array_initializers, partial),
        offsetof(macro_array_initializers, sparse),
        offsetof(macro_array_initializers, grid),
        offsetof(macro_array_initializers, choices));

    macro_pointer_initializers pointers = {.a = {0}, .b = {0}, .tag = 1};
    printf("%d %d %d %d %d\n", pointers.a[0] == NULL, pointers.a[1] == NULL,
        pointers.b[0] == NULL, pointers.b[1] == NULL, pointers.tag);
    return 0;
}
