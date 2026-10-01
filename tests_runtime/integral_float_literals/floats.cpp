#include <stdio.h>

struct View {
	float projection[16];
};

int main() {
	View v;
	v.projection[0] = 2.0f / 640.0f;
	v.projection[5] = -2.0f / 480.0f;
	v.projection[10] = -2.0f / 1.0f;
	int half = 7;
	float h = half / 2.0f;
	double d = 1.0 / 3.0;
	float scale = 3.0f;
	printf("%.6f %.6f %.1f %.2f %.4f %.1f\n", v.projection[0], v.projection[5], v.projection[10], h, d, scale / 2.0f);
	return 0;
}
