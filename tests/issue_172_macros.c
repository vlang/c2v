#include <stdio.h>
#define FIRST_UNION union { int first; unsigned int first_unsigned; }
#define SECOND_UNION union { double second; unsigned long long second_bits; }
#define FIRST_STRUCT struct { int third; int fourth; }
#define SECOND_STRUCT struct { int fifth; int sixth; }
#define UNION_MEMBERS FIRST_UNION; SECOND_UNION
#define STRUCT_MEMBERS FIRST_STRUCT; SECOND_STRUCT
typedef struct {
    UNION_MEMBERS;
    STRUCT_MEMBERS;
    int c2v_anonymous_0;
    int c2v_anonymous_0_1;
} macro_records;
int main(void) {
    macro_records value = {
        .first = 1,
        .second = 2.5,
        .third = 3,
        .fourth = 4,
        .fifth = 5,
        .sixth = 6,
        .c2v_anonymous_0 = 7,
        .c2v_anonymous_0_1 = 8,
    };
    printf("%d %.1f %d %d %d %d %d %d %zu\n", value.first, value.second,
        value.third, value.fourth, value.fifth, value.sixth,
        value.c2v_anonymous_0, value.c2v_anonymous_0_1, sizeof(macro_records));
    return 0;
}
