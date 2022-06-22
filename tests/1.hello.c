#include <stdio.h>

int main() {
	printf("hello world!");
	return 0;
}

typedef struct Foo {
	int bar;
} Foo;

void implicit_inits() {
	int num;
	Foo foo;
}

