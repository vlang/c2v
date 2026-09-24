#include <stdio.h>
struct Vec3 {
	float x, y, z;
	float &operator[](int i) { return (&x)[i]; }
	float operator[](int i) const { return (&x)[i]; }
};
struct Bounds {
	Vec3 b[2];
	Vec3 &operator[](int i) { return b[i]; }
	const Vec3 &operator[](int i) const { return b[i]; }
};
struct Work {
	Bounds bounds;
	Vec3 start;
};
Bounds MakeBounds() {
	Bounds result;
	result[1][0] = 7.0f;
	return result;
}
int main() {
	Work tw;
	for (int i = 0; i < 3; i++) {
		tw.start[i] = (float)i;
		tw.bounds[0][i] = tw.start[i] * 2;
		tw.bounds[1][i] = tw.bounds[0][i] + 1;
	}
	const Work &view = tw;
	printf("%g %g %g %g\n", tw.bounds[0][2], tw.bounds.b[1].y, view.bounds[1][2], MakeBounds()[1][0]);
	return 0;
}
