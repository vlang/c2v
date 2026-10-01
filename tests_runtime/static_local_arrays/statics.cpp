#include <stdio.h>

class Vec3 {
public:
	float x, y, z;
	Vec3() {}
	Vec3(float a, float b, float c) { x = a; y = b; z = c; }
};

float Winding(int i) {
	static Vec3 winding[4] = {
		Vec3(1.0f, 1.0f, 0.0f),
		Vec3(-1.0f, 1.0f, 0.0f),
		Vec3(-1.0f, -1.0f, 0.0f),
		Vec3(1.0f, -1.0f, 0.0f)
	};
	winding[i].z += 1.0f;
	return winding[i].x + winding[i].y * 10 + winding[i].z * 100;
}

int Table(int i) {
	static int table[2][3] = { { 1, 2, 3 }, { 4, 5, 6 } };
	return table[i / 3][i % 3]++;
}

int main() {
	printf("%.0f %.0f %.0f %.0f\n", Winding(0), Winding(1), Winding(0), Winding(3));
	printf("%d %d %d %d\n", Table(0), Table(5), Table(0), Table(4));
	return 0;
}
