#include <stdio.h>

class Class {
public:
	virtual ~Class() {}
	virtual const char *KindName() const = 0;
};

class Entity : public Class {
public:
	int health;
	Entity() { health = 10; }
	const char *KindName() const { return "entity"; }
};

class Camera : public Entity {
public:
	virtual int Fov() const = 0;
};

class FixedCamera : public Camera {
public:
	int Fov() const { return 75; }
	const char *KindName() const { return "fixedcamera"; }
};

static void Write(const Class *object) {
	printf("%s\n", object ? object->KindName() : "NULL");
}

int main() {
	Camera *camera = new FixedCamera();
	Camera *none = NULL;
	Write(camera);
	Write(none);
	const Class *asClass = camera;
	printf("%s %d\n", asClass->KindName(), camera->Fov());
	return 0;
}
