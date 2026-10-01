#include <stdio.h>

class Entity {
public:
	int hidden;
	int values[4];
	Entity() : hidden(1) {
		for (int i = 0; i < 4; i++) {
			values[i] = i;
		}
	}
	virtual ~Entity() {}
	int &operator[](int i) { return values[i]; }
	Entity &operator+=(int n) {
		hidden += n;
		return *this;
	}
};

class Animated : public Entity {
public:
	int frame;
	Animated() : frame(0) {}
	int &FrameRef() { return frame; }
	int *FramePtr() { return &frame; }
};

class Player : public Animated {
public:
	int health;
	Player() : health(100) {}
};

static Player player;
static Animated model;

static Player &GetPlayer() { return player; }
static Animated *GetModel() { return &model; }

static void Hide(Entity *entity) { entity->hidden = 2; }
static void HideRef(Entity &entity) { entity.hidden = 3; }
static void Frame(Animated &animated) { animated.frame = 7; }
static int *Address(Entity &entity) { return &entity.hidden; }

int main() {
	GetPlayer()[2] = 20;
	GetPlayer() += 5;
	(*GetModel())[1] = 10;
	printf("%d %d %d\n", player.values[2], player.hidden, model.values[1]);
	Hide(GetModel());
	printf("%d\n", model.hidden);
	HideRef(GetPlayer());
	Frame(GetPlayer());
	printf("%d %d\n", player.hidden, player.frame);
	*Address(*GetModel()) = 9;
	*Address(GetPlayer()) = 11;
	printf("%d %d\n", model.hidden, player.hidden);
	(*GetModel()).FrameRef() = 3;
	*(*GetModel()).FramePtr() += 1;
	printf("%d\n", model.frame);
	return 0;
}
