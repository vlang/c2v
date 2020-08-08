#include <stdio.h>

int main() {
	if (10 > 5) {
		printf("10 > 5");
	}
	else {
		printf("no");
	}
	int x = 10;
	int y = 20;
	if (y > x) {
		printf("y > x");
	}
	if (y + 1 > x); // TODO
	if (1) printf("one");
	else if (1 > 0 || x < y || (x > y && x < y + 1)) {
		printf("two");
		printf("three");
	}
	return 0;
}

