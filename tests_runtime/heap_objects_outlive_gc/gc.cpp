#include <stdio.h>

struct Entry {
	int id;
	char name[64];
	Entry *next;
	Entry() {
		id = -1;
		name[0] = 0;
		next = NULL;
	}
};

struct Plain {
	int value;
	Plain *link;
};

int main() {
	const int count = 200000;
	Entry **entries = new Entry *[count];
	Plain **plains = new Plain *[count];
	for (int i = 0; i < count; i++) {
		entries[i] = new Entry();
		entries[i]->id = i;
		snprintf(entries[i]->name, sizeof(entries[i]->name), "entry %d", i);
		plains[i] = new Plain;
		plains[i]->value = i * 2;
		plains[i]->link = i > 0 ? plains[i - 1] : NULL;
	}
	long sum = 0;
	int bad = 0;
	for (int i = 0; i < count; i++) {
		sum += entries[i]->id + plains[i]->value;
		if (entries[i]->id != i || plains[i]->value != i * 2) {
			bad++;
		}
	}
	printf("%ld %d %s %d\n", sum, bad, entries[count - 1]->name, plains[count - 1]->link->value);
	for (int i = 0; i < count; i++) {
		delete entries[i];
		delete plains[i];
	}
	delete[] entries;
	delete[] plains;
	return 0;
}
