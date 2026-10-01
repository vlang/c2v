#include <stdio.h>

class Class {
public:
	virtual ~Class() {}
	virtual const char *KindName() const { return "class"; }
};

class Entity : public Class {
public:
	int health;
	Entity() { health = 5; }
	const char *KindName() const { return "entity"; }
};

class Actor : public Entity {
public:
	const char *KindName() const { return "actor"; }
};

class Camera : public Entity {
public:
	virtual int Fov() const = 0;
};

class FixedCamera : public Camera {
public:
	int Fov() const { return 60; }
};

class Restore {
public:
	Class *objects[4];
	int next;
	void ReadObject(Class *&obj) { obj = objects[next++]; }
};

struct Saved {
	Actor *self;
	Camera *camera;
	Entity *missing;
};

int main() {
	Actor actor;
	FixedCamera camera;
	Restore restore;
	restore.objects[0] = &actor;
	restore.objects[1] = &camera;
	restore.objects[2] = NULL;
	restore.next = 0;
	Saved saved;
	saved.missing = &actor;
	restore.ReadObject(reinterpret_cast<Class *&>(saved.self));
	restore.ReadObject(reinterpret_cast<Class *&>(saved.camera));
	restore.ReadObject(reinterpret_cast<Class *&>(saved.missing));
	printf("%s %d %d %s\n", saved.self->KindName(), saved.self->health, saved.camera->Fov(), saved.missing ? "set" : "null");
	return 0;
}
