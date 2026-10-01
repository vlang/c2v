#include <stdio.h>
#include <stdlib.h>

static int liveModels = 0;

class Model {
public:
	Model() { refs = 1; liveModels++; }
	virtual ~Model() { liveModels--; }
	virtual int Name() const = 0;
	int refs;
};

class StaticModel : public Model {
public:
	int id;
	StaticModel(int i) { id = i; }
	virtual int Name() const { return id; }
};

template <class type>
class List {
public:
	List() { list = NULL; num = 0; size = 0; }
	int Num() const { return num; }
	type &operator[](int i) { return list[i]; }
	void Append(const type &v) {
		if (num == size) {
			Resize(size + 4);
		}
		list[num++] = v;
	}
	void Resize(int newsize) {
		type *temp;
		temp = list;
		size = newsize;
		list = new type[size];
		for (int i = 0; i < num; i++) {
			list[i] = temp[i];
		}
		delete[] temp;
	}
private:
	type *list;
	int num;
	int size;
};

int main() {
	List<Model *> models;
	for (int i = 0; i < 11; i++) {
		models.Append(new StaticModel(i * 3));
	}
	int sum = 0;
	for (int i = 0; i < models.Num(); i++) {
		sum = sum * 2 + models[i]->Name();
	}
	printf("%d %d %d %d\n", models.Num(), sum, models[3]->refs, liveModels);
	for (int i = 0; i < models.Num(); i += 2) {
		delete models[i];
	}
	printf("%d\n", liveModels);
	return 0;
}
