#include <stdio.h>
#include <stdint.h>

template <class type>
class Extrapolate {
public:
	type speed;
	type base;
	const type &GetSpeed() const { return speed; }
	const type &GetBase() const { return base; }
};

struct Trace {
	float fraction;
	int contents;
};

class Class;
typedef void (Class::*SaveFunc)(int);

class Class {
public:
	virtual ~Class() {}
	virtual int Id() const = 0;
};

class Mover : public Class {
public:
	int saved;
	Mover() { saved = 0; }
	int Id() const { return 3; }
	void Save(int value) { saved = value * 2; }
};

struct Variable {
	float *floatPtr;
};

int main() {
	Extrapolate<float> extrapolate;
	extrapolate.speed = 2.5f;
	extrapolate.base = 1.0f;
	float value = extrapolate.GetBase() + extrapolate.GetSpeed() * (4.0f * 0.5f);

	Trace trace;
	trace.fraction = 0.25f;
	trace.contents = 9;
	intptr_t arg = reinterpret_cast<intptr_t>(&trace);
	int contents = reinterpret_cast<Trace *>(arg)->contents;

	float f = 1.5f;
	Variable var;
	var.floatPtr = &f;
	(*var.floatPtr)++;
	(*var.floatPtr)++;
	(*var.floatPtr)--;

	Mover mover;
	Class *object = &mover;
	SaveFunc save = static_cast<SaveFunc>(&Mover::Save);
	(object->*save)(21);

	printf("%.2f %d %.2f %d %d\n", value, contents, f, mover.saved, object->Id());
	return 0;
}
