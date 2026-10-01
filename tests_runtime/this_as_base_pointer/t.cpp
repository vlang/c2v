#include <stdio.h>

class Entity {
public:
	int id;
	Entity *target;
	Entity() : id(0), target(NULL) {}
	virtual ~Entity() {}
};

static const Entity *Find(const Entity *source, const Entity *ignore) {
	return source == ignore ? NULL : source->target;
}

static int Distance(const Entity *a, const Entity *b) {
	return a->id - b->id;
}

class AI : public Entity {
public:
	int speed;
	AI() : speed(3) {}
	// Methods that do not modify the object pass `this` on as a base pointer.
	const Entity *Path() const { return Find(this, NULL); }
	int Gap() const { return Distance(this, target); }
	bool Ignores(const Entity *other) { return Find(this, other) == NULL; }
};

int main() {
	AI a, b;
	a.id = 7;
	b.id = 2;
	a.target = &b;
	printf("%d %d %d %d\n", a.Path() == &b, a.Gap(), a.Ignores(&a), a.Ignores(&b));
	return 0;
}
