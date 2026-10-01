#include <stdio.h>
#include <string.h>

class WinVar {
public:
	WinVar() { eval = true; }
	virtual ~WinVar() {}
	virtual void Init(const char *name) { Set(name); }
	virtual void Set(const char *value) = 0;
	virtual const char *c_str() const = 0;
	bool eval;
};

class WinStr : public WinVar {
public:
	char data[32];
	WinStr() { data[0] = 0; }
	virtual void Init(const char *name) { WinVar::Init(name); }
	virtual void Set(const char *value) { strcpy(data, value); }
	virtual const char *c_str() const { return data; }
};

class WinBackground : public WinStr {
public:
	char data[32];
	int loads;
	WinBackground() { data[0] = 0; loads = 0; }
	virtual void Init(const char *name) { WinStr::Init(name); }
	virtual void Set(const char *value) { strcpy(data, value); loads++; }
	virtual const char *c_str() const { return data; }
};

int main() {
	WinStr s;
	WinBackground b;
	WinVar *vars[2] = { &s, &b };
	vars[0]->Init("plain");
	vars[1]->Init("gui/mainmenu/star");
	b.Init("gui/mainmenu/star1");
	printf("%s %s %d %s\n", s.c_str(), b.c_str(), b.loads, b.WinStr::c_str());
	return 0;
}
