void *stack_alloc(int size);
void *heap_alloc(int size);

#define PICK_ALLOC(SIZE, ON_STACK) \
	((SIZE) < 10 ? ((ON_STACK) = true, stack_alloc(SIZE)) : ((ON_STACK) = false, heap_alloc(SIZE)))

void *choose_storage(int size) {
	bool on_stack = false;
	void *storage = (void *)PICK_ALLOC(size, on_stack);
	return storage;
}
