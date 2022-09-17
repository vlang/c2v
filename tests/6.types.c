#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>

// standard types should be lower-cased
typedef unsigned short v_u16;
typedef float v_f32;
typedef size_t v_usize;
typedef void *v_voidptr;
typedef bool v_bool;

// disabled for macOS/Linux compatibility
//#include <stddef.h>
//typedef ptrdiff_t v_isize;

// not sure how this is supposed to work
typedef intptr_t c_intptr_t;

int main()
{
    void *pointers[8];

    return 0;
}
