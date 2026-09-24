#include <stdio.h>
class Vec3 {
public:
	float x, y, z;
	float &operator[](int index) { return (&x)[index]; }
	const float &At(int index) const { return (&x)[index]; }
};
class Mat3 {
public:
	Vec3 rows[3];
	Mat3 &operator*=(float s) {
		float *p = reinterpret_cast<float *>(this);
		for (int i = 0; i < 9; i++) {
			p[i] *= s;
		}
		return *this;
	}
	const Vec3 &Row(int i) const { return rows[i]; }
	Mat3 Scaled(float s) const {
		Mat3 copy;
		copy = *this;
		copy *= s;
		return copy;
	}
};
class Named {
public:
	char name[16];
	const char *Get() const { return name; }
};
int main() {
	Mat3 m;
	for (int i = 0; i < 3; i++) {
		m.rows[i].x = (float)i;
		m.rows[i].y = 1.0f;
		m.rows[i].z = 2.0f;
	}
	m *= 2.0f;
	m.rows[1][2] = 7.0f;
	const Vec3 &r = m.Row(1);
	Mat3 s = m.Scaled(0.5f);
	Named n = {"doom"};
	const char *nm = n.Get();
	n.name[0] = 'r';
	printf("%g %g %g %g %g %s\n", m.rows[2].x, r.At(2), r.y, s.rows[1].z, s.rows[2].x, nm);
	return 0;
}
