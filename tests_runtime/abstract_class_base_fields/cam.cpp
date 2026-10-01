#include <stdio.h>

class Entity {
public:
	int health;
	const char *name;
	Entity() { health = 100; name = "entity"; }
	virtual ~Entity() {}
	int Health() const { return health; }
};

class Camera : public Entity {
public:
	virtual int Fov() const = 0;
};

class FixedCamera : public Camera {
public:
	int fov;
	FixedCamera() { fov = 90; name = "fixed"; health = 42; }
	int Fov() const { return fov; }
};

struct Game {
	Camera *camera;
	int Describe() const {
		printf("%s %d %d %d\n", camera->name, camera->health, camera->Fov(), camera->Health());
		camera->health -= 2;
		return camera->health;
	}
};

int main() {
	Game game;
	game.camera = new FixedCamera();
	int left = game.Describe();
	printf("%d %d\n", left, game.camera->health);
	return 0;
}
