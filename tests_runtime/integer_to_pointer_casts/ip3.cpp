#include <stdint.h>
#include <stdio.h>
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
int main() {
	Page page = {42};
	intptr_t storage[2] = {0, (intptr_t)&page};
	Heap heap;
	heap.set((char *)storage);
	printf("%d %d\n", ((Page *)heap.slots[1])->n, heap.last->n);
	return 0;
}
