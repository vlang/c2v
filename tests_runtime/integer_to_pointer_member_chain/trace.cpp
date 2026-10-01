#include <stdio.h>
#include <stdint.h>

struct Material {
	const char *name;
};

struct Contact {
	const Material *material;
	int id;
};

struct Trace {
	float fraction;
	Contact c;
};

struct EventArg {
	int type;
	intptr_t value;
};

int main() {
	Material metal = { "metal" };
	Trace trace;
	trace.fraction = 0.5f;
	trace.c.material = &metal;
	trace.c.id = 12;
	EventArg arg;
	arg.type = 1;
	arg.value = reinterpret_cast<intptr_t>(&trace);
	if (reinterpret_cast<Trace *>(arg.value)->c.material != NULL) {
		printf("%s %d\n", reinterpret_cast<Trace *>(arg.value)->c.material->name, reinterpret_cast<Trace *>(arg.value)->c.id);
	}
	return 0;
}
