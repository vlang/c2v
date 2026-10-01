#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>

struct Item {
	int key;
};

static int CompareItems(const void *a, const void *b) {
	return ((const Item *)a)->key - ((const Item *)b)->key;
}

class Mixer {
public:
	static void *Run(void *parm) {
		int *count = (int *)parm;
		for (int i = 0; i < 1000; i++) {
			Item *items = new Item[8];
			for (int j = 0; j < 8; j++) {
				items[j].key = (j * 5) % 8;
			}
			qsort(items, 8, sizeof(Item), CompareItems);
			*count += items[7].key;
			delete[] items;
		}
		return NULL;
	}
};

int main() {
	int count = 0;
	pthread_t thread;
	pthread_create(&thread, NULL, Mixer::Run, &count);
	pthread_join(thread, NULL);
	printf("%d\n", count);
	return 0;
}
