#include <stdint.h>
struct Page {
	int n;
};
struct Heap {
	void *slots[4];
	Page *last;
	void set(char *block) {
		intptr_t *link = (intptr_t *)(block + 8);
		slots[1] = (void *)(*link);
		last = (Page *)(*((intptr_t *)(block + 8)));
	}
};
