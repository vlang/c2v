#include <stdio.h>

template <class T>
class List {
public:
	T items[4];
	int num;
	List() : num(0) {}
	int Append(const T &obj) {
		items[num] = obj;
		return num++;
	}
	T &operator[](int i) { return items[i]; }
	int Num() const { return num; }
};

class Constraint {
public:
	int id;
	virtual ~Constraint() {}
	virtual int Rows() const { return 1; }
};

class Contact : public Constraint {
public:
	int depth;
	int Rows() const { return 3; }
};

class Physics {
public:
	List<Contact *> contacts;
	List<Constraint *> frame;
	void AddFrameConstraint(Constraint *c) { frame.Append(c); }
	int Setup() {
		for (int i = 0; i < contacts.Num(); i++) {
			AddFrameConstraint(contacts[i]);
		}
		int rows = 0;
		for (int i = 0; i < frame.Num(); i++) {
			rows += frame[i]->Rows() * 10 + frame[i]->id;
		}
		return rows;
	}
};

int main() {
	Contact a, b;
	a.id = 1;
	b.id = 2;
	Physics p;
	p.contacts.Append(&a);
	p.contacts.Append(&b);
	printf("%d %d\n", p.Setup(), p.frame.Num());
	return 0;
}
