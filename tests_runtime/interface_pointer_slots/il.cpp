#include <stdio.h>
class Model {
public:
	virtual int Id() const = 0;
	virtual ~Model() {}
};
class Box : public Model {
public:
	int id;
	Box(int i) : id(i) {}
	int Id() const { return id; }
};
template <class type>
class List {
public:
	type slots[4];
	int num;
	List() : num(0) {}
	type &operator[](int index) { return slots[index]; }
	type &Alloc() { return slots[num++]; }
};
void Replace(Model *&slot, Model *with) {
	slot = with;
}
int main() {
	Box a(1);
	Box b(2);
	List<Model *> models;
	models.Alloc() = &a;
	models.Alloc() = &b;
	int first = models[0]->Id();
	models[0] = &b;
	Replace(models[1], &a);
	Model *m = models[1];
	printf("%d %d %d %d\n", first, models[0]->Id(), m->Id(), models[1] == &a ? 1 : 0);
	return 0;
}
