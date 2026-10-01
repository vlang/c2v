#include <stdio.h>

class Plain {
public:
	int v;
	float f;
	const int &Get() const { return v; }
	const float &GetF() const { return f; }
};

template <class type>
class Box {
public:
	type value;
	const type &Get() const { return value; }
};

int main() {
	Plain plain;
	plain.v = 4;
	plain.f = 1.5f;
	Box<float> box;
	box.value = 2.0f;
	int y = plain.Get() * 3 + 1;
	float z = plain.GetF() * 2.0f + box.Get() * 3.0f;
	float w = box.Get() + plain.GetF();
	printf("%d %.2f %.2f\n", y, z, w);
	return 0;
}
