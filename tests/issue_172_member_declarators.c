#include <stddef.h>
#include <stdio.h>

#define SMALL_MEMBERS struct { int small; } macro_small[2]
#define LARGE_MEMBERS struct { double large; } macro_cells[2][2]
#define MACRO_MEMBERS SMALL_MEMBERS; LARGE_MEMBERS

typedef struct {
    struct { int value; } *pointer, pointed;
    struct { int value; } matrix[2][3];
    struct { int value; } *pointers[2], targets[2];
    const struct { int value; } *read_only, read_only_value;
    struct { int value; } *const fixed_pointer;
    MACRO_MEMBERS;
} member_declarators;

int main(void) {
    member_declarators value = {0};
    value.pointer = &value.pointed;
    value.pointer->value = 11;
    value.matrix[1][2].value = 13;
    value.pointers[0] = &value.targets[1];
    value.pointers[0]->value = 19;
    value.read_only = &value.read_only_value;
    value.macro_small[1].small = 29;
    value.macro_cells[1][1].large = 31.5;

    printf("%d %d %d %d %d %.1f\n", value.pointer->value,
        value.matrix[1][2].value, value.pointers[0]->value,
        value.read_only->value, value.macro_small[1].small,
        value.macro_cells[1][1].large);
    printf("%zu %zu %zu %zu %zu %zu %zu %zu %zu\n", sizeof(value.pointer),
        sizeof(value.matrix), sizeof(value.pointers), sizeof(value.read_only),
        sizeof(value.fixed_pointer), sizeof(value.macro_small),
        sizeof(value.macro_cells), sizeof(value.macro_small[1]),
        sizeof(value.macro_cells[1]));
    printf("%zu %zu %zu %zu %zu %zu %zu %zu\n", sizeof(member_declarators),
        offsetof(member_declarators, pointer), offsetof(member_declarators, matrix),
        offsetof(member_declarators, pointers), offsetof(member_declarators, read_only),
        offsetof(member_declarators, fixed_pointer),
        offsetof(member_declarators, macro_small),
        offsetof(member_declarators, macro_cells));
    return 0;
}
