#include <stdio.h>

static int liveCount = 0;
static int log[16];
static int logCount = 0;

class Node {
public:
	int id;
	Node(int i) { id = i; }
	~Node() { log[logCount++] = id; }
};

class Entity {
public:
	int id;
	Node tag;
	Entity(int i) : tag(i * 10) { id = i; liveCount++; }
	virtual ~Entity() { liveCount--; log[logCount++] = -id; }
	virtual int Kind() const { return 1; }
};

class Monster : public Entity {
public:
	Node claw;
	Monster(int i) : Entity(i), claw(i * 100) {}
	~Monster() { log[logCount++] = 1000 + id; }
	int Kind() const { return 2; }
};

int main() {
	Entity *a = new Entity(1);
	Entity *b = new Monster(2);
	printf("%d %d %d\n", liveCount, a->Kind(), b->Kind());
	delete a;
	delete b;
	printf("%d:", liveCount);
	for (int i = 0; i < logCount; i++) {
		printf(" %d", log[i]);
	}
	printf("\n");
	return 0;
}
