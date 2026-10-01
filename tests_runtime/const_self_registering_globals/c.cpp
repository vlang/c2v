#include <stdio.h>
#include <string.h>

class EventDef {
public:
	EventDef(const char *name, int args);
	const char *Name() const { return name; }
	int Num() const { return num; }
	static const EventDef *Find(const char *name);

private:
	const char *name;
	int args;
	int num;
	static EventDef *defs[16];
	static int numDefs;
};

EventDef *EventDef::defs[16];
int EventDef::numDefs = 0;

EventDef::EventDef(const char *n, int a) : name(n), args(a) {
	num = numDefs;
	defs[numDefs++] = this;
}

const EventDef *EventDef::Find(const char *n) {
	for (int i = 0; i < numDefs; i++) {
		if (!strcmp(defs[i]->name, n)) {
			return defs[i];
		}
	}
	return NULL;
}

const EventDef EV_PlayAnim("playAnim", 2);
const EventDef EV_Wait("wait", 1);
static const EventDef EV_Local("local", 0);

int main() {
	const EventDef *found = EventDef::Find("wait");
	printf("%d %d %d %s\n", found == &EV_Wait, EventDef::Find("playAnim") == &EV_PlayAnim,
		EventDef::Find("local") == &EV_Local, EV_Wait.Name());
	return 0;
}
