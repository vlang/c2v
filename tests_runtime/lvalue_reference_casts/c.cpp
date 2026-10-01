#include <stdio.h>

typedef int ammo_t;

enum trmType_t { TRM_INVALID, TRM_BOX, TRM_OCTAHEDRON, TRM_CUSTOM };
enum removeStatus_t { REMOVE_ALIVE = 0, REMOVE_WAIT = 1, REMOVE_DONE = 2 };

struct TraceModel {
	trmType_t type;
	int numVerts;
};

struct Vec2 {
	float x, y;
	float &operator[](int i) { return (&x)[i]; }
};

struct Pair {
	int a, b;
};

struct Emitter {
	removeStatus_t removeStatus;
	unsigned int flags;
};

static int next_value = 1;

static void ReadInt(int &value) { value = next_value++; }
static void ReadUnsigned(unsigned int &value) { value = 40u + (unsigned int)next_value++; }

int main() {
	TraceModel trm;
	trm.type = TRM_INVALID;
	trm.numVerts = 0;
	Emitter emitter;
	emitter.removeStatus = REMOVE_ALIVE;
	emitter.flags = 0;
	ReadInt((int &)trm.type);
	ReadInt(trm.numVerts);
	ReadInt((int &)emitter.removeStatus);
	int flags_as_int = 0;
	ReadInt(flags_as_int);
	ReadUnsigned((unsigned int &)flags_as_int);
	trmType_t local = TRM_INVALID;
	ReadInt(reinterpret_cast<int &>(local));
	printf("%d %d %d %d %d\n", (int)trm.type, trm.numVerts, (int)emitter.removeStatus, flags_as_int, (int)local);
	ammo_t ammoType = 0;
	ReadInt((int &)ammoType);
	printf("%d\n", ammoType);
	Pair pair;
	pair.a = 7;
	pair.b = 9;
	ReadInt(((Pair &)trm).b);
	Vec2 &view = (Vec2 &)pair;
	printf("%d %d\n", ((Pair &)trm).a, (int)sizeof(view));
	return 0;
}
