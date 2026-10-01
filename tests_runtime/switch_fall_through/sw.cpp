#include <stdio.h>


static bool Receive(int event) {
	switch (event) {
		case 0: {
		}
		default: {
			return false;
		}
	}
}

static int Classify(int value) {
	int result = 0;
	switch (value) {
		case 1:
			result += 1;
		case 2: {
			result += 10;
		}
		case 3:
			result += 100;
			break;
		default:
			result = -1;
	}
	return result;
}

static int Keys(int type, int code) {
	int result = 0;
	switch (type) {
		case 1:
			result = 5;
			// fall through
		case 2: {
			int sc = code * 2;
			int keycode = sc + 1;
			result += keycode;
			break;
		}
		case 3: {
			int sc = code * 3;
			result = sc;
			break;
		}
	}
	return result;
}

int main() {
	printf("%d %d\n", Receive(0), Receive(5));
	for (int i = 0; i < 5; i++) {
		printf("%d ", Classify(i));
	}
	printf("\n%d %d %d\n", Keys(1, 4), Keys(2, 4), Keys(3, 4));
	return 0;
}
