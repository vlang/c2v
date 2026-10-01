#include <stdio.h>

class Sys {
public:
	virtual ~Sys() {}
	virtual int Milliseconds() = 0;
};

class SysLocal : public Sys {
public:
	int ms;
	SysLocal() { ms = 42; }
	int Milliseconds() { return ms; }
};

class OtherSys : public Sys {
public:
	int Milliseconds() { return 7; }
};

SysLocal sysLocal;
Sys *sys = &sysLocal;

struct Import {
	Sys *sys;
};

static void GetAPI(Import *import) {
	sys = import->sys;
}

int main() {
	printf("%d\n", sys->Milliseconds());
	OtherSys other;
	Import import;
	import.sys = &other;
	GetAPI(&import);
	printf("%d\n", sys->Milliseconds());
	return 0;
}
