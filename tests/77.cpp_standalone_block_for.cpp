#include <stdio.h>

int standalone_block_value() {
	int total = 0;
	{
		int i;
		for (i = 0; i < 3; i++) {
			total += i;
		}
	}
	return total;
}

int main() {
	printf("%d\n", standalone_block_value());
	return 0;
}
