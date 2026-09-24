#include <stdio.h>
struct Vert {
	float xyz[3];
};
float sample(const Vert ctrl[3][3], int vPoint, int axis) {
	float a = ctrl[0][vPoint].xyz[axis];
	float b = ctrl[1][vPoint].xyz[axis];
	float c = ctrl[2][vPoint].xyz[axis];
	return a + b * 10 + c * 100;
}
int main() {
	Vert grid[3][3];
	for (int i = 0; i < 3; i++) {
		for (int j = 0; j < 3; j++) {
			for (int k = 0; k < 3; k++) {
				grid[i][j].xyz[k] = (float)(i + j + k);
			}
		}
	}
	printf("%g\n", sample(grid, 1, 2));
	return 0;
}
