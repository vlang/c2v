#include <stdio.h>

class Force {
public:
	int strength;
	Force() { strength = 1; }
	virtual ~Force() {}
	virtual int Apply() const { return strength; }
};

class Force_Field : public Force {
public:
	Force_Field() { strength = 5; }
	int Apply() const { return strength * 10; }
};

class ForceField {
public:
	int radius;
	ForceField() { radius = 3; }
};

int main() {
	Force *field = new Force_Field();
	ForceField *entity = new ForceField();
	Force_Field *fields = new Force_Field[2];
	ForceField *entities = new ForceField[2];
	printf("%d %d %d %d\n", field->Apply(), entity->radius, fields[1].Apply(), entities[1].radius);
	return 0;
}
