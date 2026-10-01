#include <stdio.h>

class Object {
public:
	int kind;
	Object(int k) : kind(k) {}
	virtual ~Object() {}
	virtual int Value() const { return kind; }
};

class Entity : public Object {
public:
	int health;
	Entity(int h) : Object(2), health(h) {}
	int Value() const { return health; }
};

template <class T>
class List {
public:
	T items[8];
	int num;
	List() : num(0) {}
	T &operator[](int i) { return items[i]; }
	void Append(const T &value) { items[num++] = value; }
};

int main() {
	List<Object *> objects;
	objects.Append(new Object(1));
	objects.Append(new Entity(40));
	objects.Append(new Entity(55));
	int sum = 0;
	for (int i = 0; i < objects.num; i++) {
		if (objects[i]->kind == 2) {
			Entity *ent = static_cast<Entity *>(objects[i]);
			sum += ent->health;
			Entity *same = (Entity *)objects[i];
			sum += same->Value();
		}
	}
	printf("%d\n", sum);
	return 0;
}
