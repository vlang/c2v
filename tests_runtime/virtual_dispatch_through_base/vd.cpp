#include <stdio.h>

class Var {
public:
	int value;
	Var *internal;
	Var() { value = 0; internal = this; }
	virtual ~Var() {}
	void SetInteger(int v) { internal->InternalSetInteger(v); }
	int GetInteger() const { return internal->value; }
	virtual void InternalSetInteger(int v) {}
	virtual const char *Kind() const { return "var"; }
};

class InternalVar : public Var {
public:
	int sets;
	InternalVar() { sets = 0; }
	void InternalSetInteger(int v) { value = v; sets++; }
	const char *Kind() const { return Var::Kind(); }
};

class LoudVar : public InternalVar {
public:
	virtual void InternalSetInteger(int v) override { InternalVar::InternalSetInteger(v * 10); }
	const char *Kind() const override { return "loud"; }
};

int main() {
	Var plain;
	InternalVar internal;
	LoudVar loud;
	Var *vars[3] = { &plain, &internal, &loud };
	Var front;
	front.internal = &internal;
	front.SetInteger(7);
	for (int i = 0; i < 3; i++) {
		vars[i]->InternalSetInteger(i + 1);
		printf("%s %d\n", vars[i]->Kind(), vars[i]->GetInteger());
	}
	Var &ref = loud;
	ref.InternalSetInteger(5);
	printf("%d %d %d %s\n", front.GetInteger(), internal.sets, loud.value, ref.Kind());
	return 0;
}
