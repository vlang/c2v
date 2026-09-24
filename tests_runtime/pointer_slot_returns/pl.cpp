#include <stdio.h>
struct Item {
	int value;
};
template <class T>
void SwapValues(T &a, T &b) {
	T c = a;
	a = b;
	b = c;
}
template <class type>
class List {
public:
	type slots[4];
	int num;
	List() : num(0) {}
	type &operator[](int index) { return slots[index]; }
	const type &operator[](int index) const { return slots[index]; }
	type &Alloc() { return slots[num++]; }
};
Item *First(List<Item *> &list) {
	return list[0];
}
int main() {
	Item a = {1};
	Item b = {2};
	List<Item *> list;
	list.Alloc() = &a;
	list.Alloc() = &b;
	int sum = list[0]->value + list[1]->value;
	Item *p = list[1];
	list[0] = NULL;
	int nulls = list[0] == NULL ? 1 : 0;
	list[0] = &b;
	list[1] = &a;
	SwapValues(list[0], list[1]);
	const List<Item *> &view = list;
	printf("%d %d %d %d %d %d\n", sum, p->value, nulls, list[0]->value, First(list)->value, view[1]->value);
	return 0;
}
