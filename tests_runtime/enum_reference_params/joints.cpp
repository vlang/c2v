#include <stdio.h>

typedef enum {
	INVALID_JOINT = -1
} jointHandle_t;

template <class type>
class List {
public:
	type items[16];
	int num;
	List() { num = 0; }
	int FindIndex(const type &obj) const {
		for (int i = 0; i < num; i++) {
			if (items[i] == obj) {
				return i;
			}
		}
		return -1;
	}
	int AddUnique(const type &obj) {
		int index = FindIndex(obj);
		if (index < 0) {
			items[num] = obj;
			index = num++;
		}
		return index;
	}
	bool Remove(const type &obj) {
		int index = FindIndex(obj);
		if (index < 0) {
			return false;
		}
		for (int i = index; i < num - 1; i++) {
			items[i] = items[i + 1];
		}
		num--;
		return true;
	}
};

int main() {
	List<jointHandle_t> list;
	for (int i = 0; i < 6; i++) {
		list.AddUnique((jointHandle_t)i);
	}
	list.AddUnique((jointHandle_t)3);
	list.Remove((jointHandle_t)2);
	list.Remove((jointHandle_t)4);
	printf("%d %d %d %d\n", list.num, list.FindIndex((jointHandle_t)5), list.FindIndex((jointHandle_t)2), list.items[2]);
	return 0;
}
