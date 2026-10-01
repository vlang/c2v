#include <stdio.h>

class Class;
typedef void (Class::*spawnFunc_t)(void);

struct TypeInfo {
	const char *name;
	TypeInfo *super;
	spawnFunc_t Spawn;
};

class Class {
public:
	virtual ~Class() {}
	void Spawn() { spawns++; }
	int spawns;
	int entitySpawns;
	int actorSpawns;
	Class() { spawns = 0; entitySpawns = 0; actorSpawns = 0; }
	spawnFunc_t CallSpawnFunc(TypeInfo *cls) {
		spawnFunc_t func;
		if (cls->super) {
			func = CallSpawnFunc(cls->super);
			if (func == cls->Spawn) {
				return func;
			}
		}
		(this->*cls->Spawn)();
		return cls->Spawn;
	}
};

class Entity : public Class {
public:
	void Spawn() { entitySpawns++; }
};

class Mover : public Entity {
	// no Spawn of its own
};

class Actor : public Mover {
public:
	void Spawn() { actorSpawns++; }
};

TypeInfo classType = { "Class", NULL, &Class::Spawn };
TypeInfo entityType = { "Entity", &classType, (spawnFunc_t)&Entity::Spawn };
TypeInfo moverType = { "Mover", &entityType, (spawnFunc_t)&Mover::Spawn };
TypeInfo actorType = { "Actor", &moverType, (spawnFunc_t)&Actor::Spawn };

int main() {
	Actor a;
	a.CallSpawnFunc(&actorType);
	printf("%d %d %d %d\n", a.spawns, a.entitySpawns, a.actorSpawns, moverType.Spawn == entityType.Spawn);
	return 0;
}
