#include <stdio.h>

class Vec4 {
public:
	float x, y, z, w;
	float operator[](int index) const { return (&x)[index]; }
	float &operator[](int index) { return (&x)[index]; }
	float Sum() const { return x + y + z + w; }
};

struct Raw {
	float values[4];
};

int main() {
	float registers[4] = { 0.0f, 1.0f, 2.0f, 3.0f };
	Vec4 plain = { 1.5f, 2.5f, 3.5f, 4.5f };
	Vec4 *pointer = &plain;
	Raw raw = { { 10.0f, 20.0f, 30.0f, 40.0f } };
	// An operator and a method called on an object seen through a reference cast.
	registers[0] = ((Vec4 &)*pointer)[(int)registers[2]];
	registers[1] = ((Vec4 &)raw)[(int)registers[3]];
	((Vec4 &)raw)[1] = 25.0f;
	((Vec4 &)raw)[2] += registers[0];
	printf("%g %g %g %g %g\n", registers[0], registers[1], raw.values[1], raw.values[2], ((Vec4 &)raw).Sum());
	return 0;
}
