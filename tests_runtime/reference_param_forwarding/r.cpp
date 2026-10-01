#include <stdio.h>

struct Vec {
	float x, y;
};

class Model {
public:
	int type;
	float size;
	Model() : type(0), size(2.0f) {}
	void MassProperties(float density, float &mass, Vec &center, int &calls) const {
		calls++;
		if (type == 1) {
			// A polygon: forward the reference parameters to a solid copy.
			Model solid;
			solid.size = size * 2;
			solid.MassProperties(density, mass, center, calls);
			return;
		}
		mass = density * size;
		center.x = size / 2;
	}
};

static void Scale(float &value, float factor) { value *= factor; }
static void Twice(float &value) {
	Scale(value, 2.0f);
	Scale(value, 2.0f);
}

struct Anim {
	int id;
};

struct Node {
	Anim *value;
	Node(Anim *v) : value(v) {}
};

// A pointer reference parameter passed on by value passes the pointer.
struct PtrTable {
	Node *node;
	PtrTable() : node(0) {}
	void Set(Anim *&value) { node = new Node(value); }
};

int main() {
	Anim anim = { 7 };
	Anim *animPtr = &anim;
	PtrTable table;
	table.Set(animPtr);
	animPtr = 0;

	Model box, poly;
	poly.type = 1;
	float mass1 = 0, mass2 = 0, v = 1.5f;
	Vec c1 = { 0, 0 }, c2 = { 0, 0 };
	int calls = 0;
	box.MassProperties(3.0f, mass1, c1, calls);
	poly.MassProperties(3.0f, mass2, c2, calls);
	Twice(v);
	printf("%.1f %.1f %.1f %.1f %d %.1f %d\n", mass1, c1.x, mass2, c2.x, calls, v, table.node->value->id);
	return 0;
}
