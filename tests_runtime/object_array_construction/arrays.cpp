#include <stdio.h>

class Node {
public:
	Node *self;
	int value;
	Node() { self = this; value = 7; }
	bool Ok() const { return self == this; }
};

class Event {
public:
	int time;
	Node node;
};

class Counter {
public:
	int count;
	Counter(int start = 3) { count = start; }
};

Event pool[4];
static Node grid[2][3];
Counter counters[2];

int CheckLocal() {
	Event local[3];
	Node pair[2];
	int ok = 0;
	for (int i = 0; i < 3; i++) {
		ok += local[i].node.Ok() ? 1 : 0;
	}
	for (int i = 0; i < 2; i++) {
		ok += pair[i].Ok() && pair[i].value == 7 ? 1 : 0;
	}
	return ok;
}

int CheckStatic() {
	static Node cache[3];
	int ok = 0;
	for (int i = 0; i < 3; i++) {
		ok += cache[i].Ok() ? 1 : 0;
	}
	return ok;
}

int main() {
	int ok = 0;
	for (int i = 0; i < 4; i++) {
		ok += pool[i].node.Ok() ? 1 : 0;
	}
	for (int i = 0; i < 2; i++) {
		for (int j = 0; j < 3; j++) {
			ok += grid[i][j].Ok() && grid[i][j].value == 7 ? 1 : 0;
		}
	}
	printf("globals %d counters %d %d\n", ok, counters[0].count, counters[1].count);
	printf("locals %d statics %d\n", CheckLocal(), CheckStatic());
	return 0;
}
