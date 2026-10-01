#include <stdio.h>
#include <stdint.h>

class WinVar {
public:
	const char *name;
	virtual ~WinVar() {}
	virtual void Set(const char *value) = 0;
	virtual float x() const { return 0.0f; }
};

class WinFloat : public WinVar {
public:
	float data;
	virtual void Set(const char *value) { data = 2.5f; }
	virtual float x() const { return data; }
};

class WinBool : public WinVar {
public:
	bool data;
	virtual void Set(const char *value) { data = true; }
	virtual float x() const { return data ? 1.0f : 0.0f; }
};

struct Op {
	int type;
	intptr_t a;
};

float Evaluate(const Op &op) {
	if (!op.a) {
		return -1.0f;
	}
	return ((WinVar *)(op.a))->x();
}

int main() {
	WinFloat f;
	WinBool b;
	WinVar *vars[2] = { &f, &b };
	Op ops[3];
	for (int i = 0; i < 2; i++) {
		vars[i]->Set("x");
		ops[i].type = i;
		ops[i].a = (intptr_t)vars[i];
	}
	ops[2].a = 0;
	void *erased = vars[1];
	WinVar *back = (WinVar *)erased;
	printf("%.1f %.1f %.1f %.1f %d\n", Evaluate(ops[0]), Evaluate(ops[1]), Evaluate(ops[2]), back->x(), back == &b);
	return 0;
}
