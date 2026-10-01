#include <stdio.h>
#include <string.h>

class Vec3 {
public:
	float x, y, z;
	Vec3() : x(0), y(0), z(0) {}
	const float *ToFloatPtr() const { return &x; }
	float *ToFloatPtr() { return &x; }
	float &operator[](int i) { return (&x)[i]; }
	float Length2() const { return x * x + y * y + z * z; }
};

class Name {
public:
	char buffer[16];
	mutable int reads;
	Name() : reads(0) { buffer[0] = '\0'; }
	void Set(const char *text) { strcpy(buffer, text); }
	const char *c_str() const {
		reads++;
		return buffer;
	}
};

struct Joint {
	Name name;
	Vec3 t;
};

template <class T>
class List {
public:
	T items[4];
	int num;
	List() : num(4) {}
	T &operator[](int i) { return items[i]; }
	const T &operator[](int i) const { return items[i]; }
	T *Get(int i) { return &items[i]; }
};

static void Parse(int n, float *out, float base) {
	for (int i = 0; i < n; i++) {
		out[i] = base + i;
	}
}

int main() {
	List<Joint> joints;
	for (int i = 0; i < joints.num; i++) {
		Parse(3, joints[i].t.ToFloatPtr(), 10.0f * i);
		joints[i].name.Set(i % 2 ? "odd" : "even");
		joints.Get(i)->t[1] += 0.5f;
	}
	const char *names[4];
	for (int i = 0; i < 4; i++) {
		names[i] = joints[i].name.c_str();
	}
	const List<Joint> &view = joints;
	printf("%.1f %.1f %.1f %.1f\n", joints[1].t.x, joints[1].t.y, joints[3].t.z, view[2].t.Length2());
	printf("%s %s %d\n", names[0], names[3], joints[0].name.reads + joints.Get(3)->name.reads);
	return 0;
}
