#include <stdio.h>

class Entity {
public:
	int health;
	Entity() { health = 3; }
	virtual ~Entity() {}
	virtual const char *Kind() const;
	virtual void Spawn();
};

const char *Entity::Kind() const { return "entity"; }
void Entity::Spawn() { health += 1; }

class Remover : public Entity {
public:
	virtual const char *Kind() const;
	virtual void Spawn();
};

const char *Remover::Kind() const { return "remover"; }
void Remover::Spawn() { health += 10; }

class ObjectiveComplete : public Remover {
public:
	virtual const char *Kind() const;
};

const char *ObjectiveComplete::Kind() const { return "objective"; }

int main() {
	Entity *entities[3] = { new Entity(), new Remover(), new ObjectiveComplete() };
	for (int i = 0; i < 3; i++) {
		entities[i]->Spawn();
		printf("%s %d\n", entities[i]->Kind(), entities[i]->health);
	}
	return 0;
}
