#include <stdio.h>
#include <stdlib.h>

template <class T>
class List {
public:
	List() : list(NULL), num(0), size(0) {}
	int Append(const T &obj) {
		if (num == size) {
			size += 4;
			list = (T *)realloc(list, size * sizeof(T));
		}
		list[num] = obj;
		return num++;
	}
	T &operator[](int index) { return list[index]; }
	const T &operator[](int index) const { return list[index]; }
	int Num() const { return num; }

private:
	T *list;
	int num;
	int size;
};

struct Entry {
	int refCount;
	float volume;
};

static List<Entry *> cache;

int Alloc(int value) {
	for (int i = 0; i < cache.Num(); i++) {
		if (cache[i]->refCount > 0 && (int)cache[i]->volume == value) {
			cache[i]->refCount++;
			cache[i]->volume += 0.25f;
			return i;
		}
	}
	Entry *entry = new Entry;
	entry->refCount = 1;
	entry->volume = value;
	return cache.Append(entry);
}

void Free(int index) {
	if (index < 0 || index >= cache.Num() || cache[index]->refCount <= 0) {
		printf("uncached %d\n", index);
		return;
	}
	cache[index]->refCount--;
}

int main() {
	int a = Alloc(3);
	int b = Alloc(3);
	int c = Alloc(5);
	Free(a);
	Free(b);
	Free(b);
	Free(c);
	printf("%d %d %d %d %.2f\n", a, b, c, cache[0]->refCount, cache[0]->volume);
	return 0;
}
