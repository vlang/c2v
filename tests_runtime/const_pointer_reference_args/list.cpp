#include <stdio.h>
#include <stdlib.h>

template <class T>
class List {
public:
	List() : list(NULL), num(0), size(0) {}
	int Append(const T &obj) {
		if (num == size) {
			size += 4;
			T *grown = (T *)realloc(list, size * sizeof(T));
			list = grown;
		}
		list[num] = obj;
		return num++;
	}
	T &operator[](int index) { return list[index]; }
	const T &operator[](int index) const { return list[index]; }
	int Num() const { return num; }
	void Clear() { num = 0; }

private:
	T *list;
	int num;
	int size;
};

struct Body {
	int id;
	Body *parent;
	List<Body *> children;
};

static void Sort_r(List<Body *> &sorted, Body *body) {
	for (int i = 0; i < body->children.Num(); i++) {
		sorted.Append(body->children[i]);
	}
	for (int i = 0; i < body->children.Num(); i++) {
		Sort_r(sorted, body->children[i]);
	}
}

static int Sum(const List<Body *> &list) {
	int sum = 0;
	for (int i = 0; i < list.Num(); i++) {
		const Body *b = list[i];
		sum = sum * 10 + b->id;
	}
	return sum;
}

int main() {
	Body bodies[5];
	List<Body *> all;
	for (int i = 0; i < 5; i++) {
		bodies[i].id = i + 1;
		bodies[i].parent = i == 0 ? NULL : &bodies[(i - 1) / 2];
		if (bodies[i].parent) {
			bodies[i].parent->children.Append(&bodies[i]);
		}
		all.Append(&bodies[4 - i]);
	}
	int root = 0;
	while (root < all.Num() && all[root]->parent) {
		root++;
	}
	Body *body = all[root];
	all.Clear();
	all.Append(body);
	Sort_r(all, body);
	printf("%d %d\n", all.Num(), Sum(all));
	// A pointer reference variable and a const view pass the pointer values.
	Body *&first = all[0];
	const List<Body *> &view = all;
	List<Body *> copy;
	copy.Append(first);
	copy.Append(view[4]);
	copy.Append(all[2]);
	printf("%d %d\n", copy.Num(), Sum(copy));
	return 0;
}
