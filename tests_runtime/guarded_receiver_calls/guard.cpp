#include <stdio.h>
#include <string.h>

class Str {
public:
	char text[16];
	Str(const char *s) { strcpy(text, s); }
	int Length() const { return (int)strlen(text); }
};

class Counter {
public:
	int n;
	Counter() { n = 0; }
	int Length() { return ++n; }	// same name, mutating
};

class KeyValue {
public:
	Str *value;
	KeyValue(Str *v) : value(v) {}
	const Str &GetValue() const { return *value; }
};

const KeyValue *Find(bool found) {
	static Str shader("shader");
	static KeyValue kv(&shader);
	return found ? &kv : NULL;
}

int Check(bool found) {
	const KeyValue *kv = Find(found);
	if (kv && kv->GetValue().Length()) {
		return kv->GetValue().Length();
	}
	return -1;
}

int main() {
	Counter c;
	c.Length();
	printf("%d %d %d\n", Check(true), Check(false), c.Length());
	return 0;
}
