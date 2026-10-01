#include <stdio.h>
#include <string.h>

struct Node {
	const char *key;
	Node *next;
};

struct Table {
	Node *heads[4];
	Node pool[8];
	int used;

	Table() {
		memset(heads, 0, sizeof(heads));
		used = 0;
	}

	// Sorted insert through a pointer to the link slot: the post clause
	// reads the slot it has just advanced.
	void Set(const char *key, int hash) {
		Node **nextPtr, *node;
		for (nextPtr = &(heads[hash]), node = *nextPtr; node != NULL; nextPtr = &(node->next), node = *nextPtr) {
			int s = strcmp(node->key, key);
			if (s == 0) {
				return;
			}
			if (s > 0) {
				break;
			}
		}
		Node *fresh = &pool[used++];
		fresh->key = key;
		fresh->next = node;
		*nextPtr = fresh;
	}
};

int main() {
	Table t;
	t.Set("m", 1);
	t.Set("z", 1);
	t.Set("a", 1);
	t.Set("q", 1);
	t.Set("m", 1);
	int steps = 0;
	for (Node *n = t.heads[1]; n != NULL; n = n->next) {
		printf("%s ", n->key);
	}
	// Two post expressions where the second uses the first; `continue`
	// must still run both, in order.
	int i, j;
	for (i = 0, j = 0; i < 6; i++, j = i * 2) {
		if (i % 2 == 0) {
			continue;
		}
		steps += j;
	}
	printf("%d %d %d\n", t.used, steps, j);
	return 0;
}
