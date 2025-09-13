#include <stdio.h>

int main() {
	int x = 1;

	// else while
	if (x == 2) {
		printf("x=2\n");
	} else while (x!=2) {
		x=2;
	}

	// else goto
	if (x == 2) {
		printf("x=2\n");
	} else goto done;

	// else switch
	if (x == 2) {
		printf("x=2\n");
		} else switch (x) {
			case 1 :
				break;
			default:
				break;
		}

	// else do
	if (x == 2) {
		printf("x=2\n");
		} else do {
		} while(0);

	// else for
	if (x == 2) {
		printf("x=2\n");
	} else for (int i=0; i<2; i++) {
		printf("x!=2\n");
	}

done:
	return 100;
}
