#include <stdio.h>
typedef struct {
    union { int pixels; float percent; } size;
    int type;
} Clay_SizingAxis;
typedef struct {
    struct { int trigger; } enter;
    struct { int trigger; } exit;
    union { int count; float fraction; } malloc;
} Clay_TransitionElementConfig;
int main(void) {
    Clay_SizingAxis axis = {.size.pixels = 80, .type = 1};
    Clay_TransitionElementConfig config = {.enter.trigger = 2, .exit.trigger = 3, .malloc.count = 4};
    printf("%d %d %d %d\n", axis.size.pixels, config.enter.trigger, config.exit.trigger, config.malloc.count);
    return 0;
}
