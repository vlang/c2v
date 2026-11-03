void fill_boolean_values(void *memory);
int sum_boolean_values(const void *memory);

#ifndef C2V_BOOLEAN_NATIVE_HEADER
#include <stddef.h>
#include <stdio.h>
#include <string.h>

typedef enum { false, true } boolean;

#ifdef C2V_BOOLEAN_NATIVE_HELPER
void fill_boolean_values(void *memory) {
    boolean *values = memory;
    values[0] = (boolean)-1;
    values[1] = false;
    values[2] = true;
}

int sum_boolean_values(const void *memory) {
    const boolean *values = memory;
    return (int)values[0] * 10 + (int)values[1] * 2 + (int)values[2];
}
#else
typedef struct {
    unsigned char lead;
    boolean rotate;
    short lump[2];
    unsigned char flip[2];
} Frame;

typedef struct {
    boolean values[3];
    int guard[4];
} Values;

int classify_rotation(boolean value) {
    switch ((int)value) {
    case -1: return 9;
    case 0: return 10;
    case 1: return 11;
    default: return 12;
    }
}

int truth_rotation(boolean value) {
    return value ? 1 : 0;
}

int main(void) {
    Frame frame;
    memset(&frame, -1, sizeof(frame));
    printf("layout %d %d %d %d %d\n", (int)sizeof(boolean), (int)sizeof(Frame),
           (int)offsetof(Frame, rotate), (int)offsetof(Frame, lump),
           (int)offsetof(Frame, flip));
    printf("sentinel %d %d %d %d %d\n", (int)frame.rotate,
           frame.rotate == false, frame.rotate == true,
           classify_rotation(frame.rotate), truth_rotation(frame.rotate));
    frame.rotate = false;
    printf("false %d %d %d\n", (int)frame.rotate,
           classify_rotation(frame.rotate), truth_rotation(frame.rotate));
    frame.rotate = true;
    printf("true %d %d %d\n", (int)frame.rotate,
           classify_rotation(frame.rotate), truth_rotation(frame.rotate));
    Values values;
    memset(&values, 0, sizeof(values));
    values.guard[0] = 1234;
    fill_boolean_values(values.values);
    printf("array %d %d %d %d\n", (int)sizeof(values.values),
           (int)((char *)&values.values[1] - (char *)&values.values[0]),
           sum_boolean_values(values.values), values.guard[0]);
    return 0;
}
#endif
#endif
