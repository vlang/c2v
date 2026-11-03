#include <stdio.h>

#ifdef __cplusplus
typedef bool boolean;
#else
typedef _Bool boolean;
#endif

typedef struct {
    unsigned char lead;
    boolean value;
    short after;
} BuiltinFrame;

int sum_builtin_values(const boolean *values) {
    return (int)values[0] + (int)values[1] * 10 + (int)values[2] * 100;
}

int main(void) {
    boolean values[3] = {(boolean)0, (boolean)2, (boolean)-1};
    BuiltinFrame frame = {7, (boolean)2, 9};
    printf("layout %d %d\n", (int)sizeof(boolean), (int)sizeof(BuiltinFrame));
    printf("builtin %d %d %d %d %d\n", (int)values[0], (int)values[1],
           (int)values[2], sum_builtin_values(values), (int)frame.value);
#ifdef __cplusplus
    printf("literals %d %d\n", (int)false, (int)true);
#endif
    return 0;
}
