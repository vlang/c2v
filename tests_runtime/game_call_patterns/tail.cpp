#include <stdio.h>
#include <stdint.h>

class CVar {
public:
	float value;
	void SetFloat(float v) { value = v; }
};

class Class {
public:
	int events;
	Class() { events = 0; }
	virtual ~Class() {}
	void ProcessEvent(int ev) { events += ev; }
};

class Entity : public Class {
public:
	int id;
};

class Projectile : public Entity {
public:
	int exploded;
	void Explode(int power) { exploded = power; }
};

class Rocket : public Projectile {
public:
	void Explode(int power) { return Projectile::Explode(power * 2); }
};

struct GameLocal {
	Entity *entities[4];
	int skill;
};

GameLocal gameLocal;

static void ReturnValue(int *out, int v) { *out = v; }
static void Finish(int *out) { return ReturnValue(out, 42); }

struct Trace {
	float fraction;
	int contents;
};

struct Vec6 {
	float p[6];
};

struct Lcp {
	float response[12];
	const Vec6 &Row(int i) const { return *reinterpret_cast<const Vec6 *>(&response[i * 6]); }
};

int main() {
	CVar armor;
	gameLocal.skill = 1;
	armor.SetFloat((gameLocal.skill < 2) ? 0.4f : 0.2f);
	for (int i = 0; i < 4; i++) {
		gameLocal.entities[i] = new Entity();
	}
	for (int i = 0; i < 4; i++) {
		gameLocal.entities[i]->ProcessEvent(i + 1);
	}
	Rocket rocket;
	rocket.Explode(3);
	int out = 0;
	Finish(&out);
	Trace trace;
	trace.contents = 7;
	intptr_t arg = reinterpret_cast<intptr_t>(&trace);
	int contents = reinterpret_cast<Trace *>(arg)->contents;
	Lcp lcp;
	for (int i = 0; i < 12; i++) {
		lcp.response[i] = (float)i;
	}
	printf("%.1f %d %d %d %d %.1f\n", armor.value, gameLocal.entities[3]->events, rocket.exploded, out, contents, lcp.Row(1).p[2]);
	return 0;
}
