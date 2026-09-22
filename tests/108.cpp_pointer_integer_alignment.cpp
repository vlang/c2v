#include <stdint.h>

float storage[17];
float *aligned_storage = (float *)(((intptr_t)storage + 15) & ~(intptr_t)15);

float *get_aligned_storage(void) {
	return aligned_storage;
}
