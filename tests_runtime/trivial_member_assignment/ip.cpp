#include <stdio.h>
class Vec4 {
public:
	float x, y, z, w;
	Vec4() {}
	Vec4(float a, float b, float c, float d) { x = a; y = b; z = c; w = d; }
	Vec4 operator+(const Vec4 &o) const { return Vec4(x + o.x, y + o.y, z + o.z, w + o.w); }
};
template <class type>
class Interpolate {
public:
	type startValue;
	type endValue;
	int duration;
	Interpolate() { duration = 0; }
};
int main() {
	Interpolate<Vec4> a;
	a.startValue = Vec4(1, 2, 3, 4);
	a.endValue = Vec4(5, 6, 7, 8);
	a.duration = 9;
	Interpolate<Vec4> b;
	b = a;
	Vec4 s = b.startValue + b.endValue;
	printf("%g %g %d\n", s.x, s.w, b.duration);
	return 0;
}
