#include <stdio.h>

class Entity {
public:
	int hidden;
	int id;
	Entity() : hidden(1), id(0) {}
	virtual ~Entity() {}
	void Show() { hidden = 0; }
	int *IdAddress() { return &id; }
	virtual int Kind() const { return 1; }
};

class Animated : public Entity {
public:
	int frames[64];
	Animated() {
		for (int i = 0; i < 64; i++) {
			frames[i] = i;
		}
	}
	virtual int Kind() const { return 2 + frames[63]; }
};

class Named {
public:
	const char *name;
	Named() : name("none") {}
	void Rename(const char *text) { name = text; }
};

class Player : public Animated, public Named {
public:
	int health;
	Player() : health(100) {}
};

template <class T>
class Handle {
public:
	T *object;
	T *Get() const { return object; }
};

struct Slot {
	Animated model;
};

static Animated world_model;
static Player player;
static Slot slot;

static Player &GetPlayer() { return player; }
static Slot &GetSlot() { return slot; }

struct Weapon {
	Handle<Animated> model;
	Player *owner;
	Player &Owner() { return *owner; }
	void ShowModel() {
		if (model.Get()) {
			model.Get()->Show();
		}
	}
};

int main() {
	Weapon weapon;
	weapon.model.object = &world_model;
	weapon.owner = &player;
	weapon.ShowModel();
	printf("%d %d\n", world_model.hidden, weapon.model.Get()->Kind());
	*GetPlayer().IdAddress() = 7;
	weapon.Owner().Show();
	weapon.Owner().Rename("marine");
	printf("%d %d %d %s\n", player.id, player.hidden, player.health, player.name);
	GetSlot().model.Show();
	*GetSlot().model.IdAddress() = 9;
	printf("%d %d %d\n", slot.model.hidden, slot.model.id, GetSlot().model.Kind());
	return 0;
}
