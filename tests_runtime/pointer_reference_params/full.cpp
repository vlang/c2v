template <class T>
void swap_values(T &a, T &b) {
	T c = a;
	a = b;
	b = c;
}

struct Link {
	int value;
	Link *next;
};

void set_link(Link *&cursor, Link *target) {
	cursor = target;
}

int advance(Link *&cursor) {
	int value = cursor->value;
	set_link(cursor, cursor->next);
	return value;
}

int peek(const int &value) {
	int copy = value;
	return copy + value;
}

struct Walker {
	Link *at;
	int step() {
		return advance(at);
	}
	int read() const {
		return peek(at->value);
	}
};

int swap_both(int *a, int *b) {
	swap_values(*a, *b);
	swap_values(a, b);
	return *a;
}
#include <stdio.h>
int main() {
	int x = 1;
	int y = 2;
	int r = swap_both(&x, &y);
	Link third = {3, 0};
	Link second = {2, &third};
	Link first = {1, &second};
	Walker w;
	w.at = &first;
	int s = w.step();
	printf("%d %d %d %d %d %d\n", x, y, r, s, w.at->value, w.read());
	return 0;
}
