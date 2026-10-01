#include <stdio.h>
#include <string.h>

class Var {
public:
	virtual ~Var() {}
	virtual const char *Str() const = 0;
	virtual void Set(const char *text) = 0;
};

class WinStr : public Var {
public:
	char buffer[32];
	WinStr() { buffer[0] = '\0'; }
	const char *Str() const { return buffer; }
	void Set(const char *text) { strcpy(buffer, text); }
};

struct Transition {
	Var *data;
	int offset;
};

static void Read(Transition &trans, const char *name) {
	trans.data = NULL;
	trans.offset = 4;
	if (name[0]) {
		WinStr *var = new WinStr();
		var->Set(name);
		trans.data = dynamic_cast<Var *>(var);
	}
}

int main() {
	Transition transitions[3];
	Read(transitions[0], "desktop");
	Read(transitions[1], "");
	WinStr *other = new WinStr();
	other->Set("static");
	transitions[2].data = static_cast<Var *>(other);
	transitions[2].offset = 8;
	for (int i = 0; i < 3; i++) {
		Var *data = transitions[i].data;
		printf("%d %s\n", transitions[i].offset, data ? ((WinStr *)data)->Str() : "-");
		delete transitions[i].data;
	}
	return 0;
}
