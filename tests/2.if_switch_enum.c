#include <stdio.h>

typedef enum {
	one, two
} Number;

Number return_number() {
	return one;
}

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
	switch (x) {
		case 0: return 0;
		case 1: printf("one"); printf("ONE"); break;
		case 2: printf("two"); if (1 > 0) { printf("OK"); } break;
	}
	Number n = one;
	switch (n) {
		//case one: printf("one!"); int x = one + 1; break;
			//x := .one + 1
		case one: printf("one"); break;
		case two: printf("two"); break;
	}
	// handle enum <=> int in C: enum switch needs explicit casts to ints
	int m = 0;
	switch (m) {
		case one: printf("one"); break;
		case two: printf("two"); break;
	}
	return 0;
}

