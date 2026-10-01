#include <stdio.h>
#include <stddef.h>

struct Name {
	int Allocated() const { return 3; }
};

struct Sizes {
	size_t Allocated() const { return 4; }
};

struct Function {
	Name name;
	Sizes sizes;
	size_t Total() const { return name.Allocated() + sizes.Allocated(); }
	size_t Total2() const {
		size_t total = name.Allocated() + sizes.Allocated();
		return total;
	}
};

static int Neighbors() {
	static int neighbors[8][2] = {{0, 1}, {1, 1}, {1, 0}, {1, -1}, {0, -1}, {-1, -1}, {-1, 0}, {-1, 1}};
	int sum = 0;
	for (int i = 0; i < 8; i++) {
		sum += neighbors[i][0] * 10 + neighbors[i][1];
	}
	return sum;
}

int main() {
	Function f;
	printf("%d %d %d\n", (int)f.Total(), (int)f.Total2(), Neighbors());
	return 0;
}
