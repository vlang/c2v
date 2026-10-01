#include <stdio.h>

class Mat3 {
public:
	float m[3];
	Mat3() { m[0] = m[1] = m[2] = 0; }
	Mat3 &operator=(const Mat3 &other) {
		m[0] = other.m[0];
		m[1] = other.m[1];
		m[2] = other.m[2];
		return *this;
	}
	void Scale(float s) { m[0] *= s; m[1] *= s; m[2] *= s; }
};

class Entity {
public:
	int isActor;
	Entity() : isActor(0) {}
	virtual ~Entity() {}
	void SetAxis(const Mat3 &axis);
	Entity *Self() { return this; }
};

class Actor : public Entity {
public:
	Mat3 viewAxis;
	Mat3 axes[2];
	Actor() { isActor = 1; }
};

void Entity::SetAxis(const Mat3 &axis) {
	if (isActor) {
		static_cast<Actor *>(this)->viewAxis = axis;
		((Actor *)Self())->axes[1] = axis;
		static_cast<Actor *>(this)->axes[0].Scale(3.0f);
	}
}

class Gui {
public:
	virtual ~Gui() {}
	virtual void SetState(int value) = 0;
	virtual int State() const = 0;
};

class GuiLocal : public Gui {
public:
	int state;
	GuiLocal() : state(0) {}
	void SetState(int value) { state = value; }
	int State() const { return state; }
};

static void ReadGui(Gui *&gui, int value) {
	if (gui) {
		gui->SetState(value);
	}
}

int main() {
	GuiLocal local;
	Gui *gui = NULL;
	gui = &local;
	ReadGui(gui, 42);
	printf("%d\n", local.State());
	Actor actor;
	actor.axes[0].m[0] = 1.0f;
	Mat3 axis;
	axis.m[0] = -1.0f;
	axis.m[1] = 2.0f;
	actor.SetAxis(axis);
	printf("%.1f %.1f %.1f %.1f\n", actor.viewAxis.m[0], actor.viewAxis.m[1], actor.axes[1].m[1], actor.axes[0].m[0]);
	return 0;
}
