#include <stdio.h>

void for_test() {
	for (int i = 0; i < 10; i++) {
		printf("i = %d\n", i);
	}
	for (int i = 0; i < 10; i++) printf("single line");
	//
	int x = 1;
	int sum = 0;
	while (x < 10) {
		x++;
		sum += x;
	}
	//
	while (1) {
		printf("inf loop");
		break;
	}
}
