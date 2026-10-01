#include <stdio.h>
#include <stdlib.h>
#include <string.h>

class Str {
public:
	Str() : data(buffer), len(0) { buffer[0] = '\0'; }
	Str(const Str &other) : data(buffer), len(0) { *this = other; }
	Str &operator=(const Str &other) {
		strcpy(buffer, other.data);
		len = other.len;
		return *this;
	}
	Str &operator=(const char *text) {
		strcpy(buffer, text);
		len = (int)strlen(text);
		return *this;
	}
	const char *c_str() const { return data; }

private:
	char *data;
	int len;
	char buffer[20];
};

template <class T>
class List {
public:
	List() : list(NULL), num(0), size(0) {}
	~List() { delete[] list; }
	int Append(const T &obj) {
		if (num == size) {
			Resize(size + 4);
		}
		list[num] = obj;
		return num++;
	}
	void Resize(int newSize) {
		T *old = list;
		list = new T[newSize];
		for (int i = 0; i < num; i++) {
			list[i] = old[i];
		}
		delete[] old;
		size = newSize;
	}
	T &operator[](int index) { return list[index]; }
	int Num() const { return num; }

private:
	T *list;
	int num;
	int size;
};

// No user-declared copy operations: the compiler copies member by member.
typedef struct {
	int type;
	Str name;
	Str data;
	float offset[3];
} Action;

static void Parse(Action &action, int i) {
	action.type = i;
	action.name = "fx";
	action.data = i % 2 ? "sparks.prt" : "smoke.prt";
	action.offset[2] = 0.5f * i;
}

int main() {
	List<Action> events;
	for (int i = 0; i < 6; i++) {
		Action action;
		Parse(action, i);
		events.Append(action);
	}
	Action copy = events[3];
	Action assigned;
	assigned = events[4];
	events[4].data = "changed";
	for (int i = 0; i < events.Num(); i++) {
		printf("%d %s %s %.1f\n", events[i].type, events[i].name.c_str(), events[i].data.c_str(), events[i].offset[2]);
	}
	printf("%s %s\n", copy.data.c_str(), assigned.data.c_str());
	return 0;
}
