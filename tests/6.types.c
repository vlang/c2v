#include <stdio.h>
#include <stddef.h>
#include <stdbool.h>
#include <stdint.h>

// standard types should be lower-cased
typedef unsigned short ushort;
typedef float f32;
typedef size_t size_t;
typedef void *null;
typedef size_t usize;
typedef ptrdiff_t isize;
typedef bool maybe;

// not sure how this is supposed to work
typedef intptr_t iptr;

int main()
{
    void *pointers[8];

    return 0;
}
