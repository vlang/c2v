#include <stdio.h>

class Physics {
public:
	virtual ~Physics() {}
	virtual int GetAxis() = 0;
};

class RigidBody : public Physics {
public:
	int calls;
	RigidBody() { calls = 0; }
	virtual int GetAxis() { return ++calls; }
};

class Entity {
public:
	Physics *physics;
	int lookups;
	Entity() { physics = NULL; lookups = 0; }
	Physics *GetPhysics() { lookups++; return physics; }
};

class EntityPtr {
public:
	Entity *e;
	EntityPtr(Entity *p) { e = p; }
	Entity *GetEntity() { return e; }
};

int Query(EntityPtr &ent) {
	if (ent.GetEntity()->GetPhysics()) {
		return ent.GetEntity()->GetPhysics()->GetAxis();
	}
	return -1;
}

int main() {
	Entity e;
	EntityPtr p(&e);
	int a = Query(p);
	RigidBody body;
	e.physics = &body;
	int b = Query(p);
	int c = Query(p);
	printf("%d %d %d %d\n", a, b, c, e.lookups);
	return 0;
}
