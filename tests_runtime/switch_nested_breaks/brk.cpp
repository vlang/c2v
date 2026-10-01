#include <stdio.h>

static int Parse(int token, int flag) {
	int result = 0;
	switch (token) {
		case 1:
			if (flag) {
				result = 10;
				break;
			}
			result = 20;
			break;
		case 2:
			for (int i = 0; i < 5; i++) {
				if (i == 3) {
					break;
				}
				result += i;
			}
			result += 100;
			break;
		default:
			result = -1;
	}
	return result;
}

int main() {
	printf("%d %d %d %d\n", Parse(1, 1), Parse(1, 0), Parse(2, 0), Parse(7, 0));
	return 0;
}
