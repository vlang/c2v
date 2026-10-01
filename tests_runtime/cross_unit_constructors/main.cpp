#include <stdio.h>
#include "model.h"

class PhysicsStatic : public Physics {
public:
	Model *model;
	PhysicsStatic() : model(NULL) {}
	Model *GetClipModel(int id = 0) const { return id == 0 ? model : NULL; }
	void SetClipModel(Model *m, float density, int id = 0, bool freeOld = true) {
		if (model && model != m && freeOld) {
			delete model;
		}
		model = m;
		(void)density; (void)id;
	}
};

class Entity {
public:
	Physics *physics;
	Entity() : physics(NULL) {}
	Physics *GetPhysics() const { return physics; }
};

class Projectile : public Entity {
public:
	PhysicsStatic physicsObj;
	void Spawn() {
		physicsObj.SetClipModel(new Model(GetPhysics()->GetClipModel()), 1.0f);
	}
};

int main() {
	PhysicsStatic ps;
	ps.model = new Model(7);
	Projectile p;
	p.physics = &ps;
	p.Spawn();
	Model *copy = new Model(*ps.model);
	printf("%d %d %d\n", p.physicsObj.GetClipModel()->index, copy->index, Model::live);
	return 0;
}
