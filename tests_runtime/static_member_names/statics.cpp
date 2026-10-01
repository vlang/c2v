#include <stdio.h>

typedef void (*PrintFunc_t)(const char *name, const char *value);

static void PrintPlain(const char *name, const char *value) { printf("%s=%s\n", name, value); }
static void PrintQuoted(const char *name, const char *value) { printf("%s=\"%s\"\n", name, value); }

class Tools {
public:
	static PrintFunc_t Write;
	static void Use(bool quoted) { Write = quoted ? PrintQuoted : PrintPlain; }
};
PrintFunc_t Tools::Write = NULL;

class ForceField {
public:
	static int Type;
};
int ForceField::Type = 1;

class Force_Field {
public:
	static int Type;
};
int Force_Field::Type = 2;

class Thread {
public:
	int id;
	static Thread *currentThread;
	static Thread *CurrentThread(void) { return currentThread; }
};
Thread *Thread::currentThread = NULL;

int main() {
	Tools::Use(false);
	Tools::Write("plain", "a");
	Tools::Use(true);
	Tools::Write("quoted", "b");
	Thread thread;
	thread.id = 4;
	Thread::currentThread = &thread;
	printf("%d %d %d\n", ForceField::Type, Force_Field::Type, Thread::CurrentThread()->id);
	return 0;
}
