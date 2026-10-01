#include <stdio.h>
#include <string.h>

struct Vec3 {
	float x, y, z;
};

struct Bounds {
	Vec3 b[2];
};

struct Holder {
	Bounds &bounds;
	int &count;
	Holder(Bounds &b, int &c) : bounds(b), count(c) {}
	int Sizes() const { return (int)(sizeof(bounds) + sizeof(count)); }
};

static int Read(Vec3 &vec, const unsigned char *data) {
	memcpy(&vec, data, sizeof(vec));
	return (int)sizeof(vec);
}

static int ReadBounds(Bounds &bounds, const unsigned char *data) {
	memcpy(&bounds, data, sizeof(bounds));
	return (int)(sizeof(bounds) / sizeof(float));
}

int main() {
	unsigned char data[64];
	for (int i = 0; i < 64; i++) {
		data[i] = (unsigned char)i;
	}
	Vec3 v;
	Bounds b;
	int n = Read(v, data);
	int floats = ReadBounds(b, data);
	int count = 0;
	Holder h(b, count);
	Vec3 &alias = v;
	printf("%d %d %d %d %d\n", n, floats, h.Sizes(), (int)sizeof(alias), b.b[1].z == v.z ? 0 : 1);
	return 0;
}
