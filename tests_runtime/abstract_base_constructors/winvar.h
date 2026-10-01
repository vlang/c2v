#pragma once
class WinVar {
public:
	WinVar();
	WinVar(const char *n);
	virtual ~WinVar();
	virtual void Set(const char *value) = 0;
	bool GetEval() const { return eval; }
	const char *GetName() const { return name; }
protected:
	const char *name;
	bool eval;
	int serial;
};

class WinRect : public WinVar {
public:
	WinRect() : WinVar() { w = 0; }
	WinRect(const char *n) : WinVar(n) { w = 1; }
	virtual void Set(const char *value) { w = 5; }
	int w;
};

class WinBool : public WinVar {
public:
	WinBool() { data = false; }
	virtual void Set(const char *value) { data = true; }
	bool data;
};
