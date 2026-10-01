#include <stdio.h>
#include <stdlib.h>
#include <string.h>
class Str {
public:
	char *data;
	int alloced;
	char base[8];
	Str() { data = base; alloced = 8; base[0] = 0; }
	void operator=(const Str &o) { Set(o.data); }
	void Set(const char *t) {
		int n = (int)strlen(t) + 1;
		if (n > alloced) {
			if (data != base) {
				data = (char *)realloc(data, n);
			} else {
				data = (char *)malloc(n);
			}
			alloced = n;
		}
		memcpy(data, t, n);
	}
};
struct Plain {
	int a;
	float b;
};
template <class type>
class List {
public:
	type *list;
	int num;
	int size;
	List() : list(NULL), num(0), size(0) {}
	void Resize(int newsize) {
		type *temp = list;
		size = newsize;
		list = new type[size];
		for (int i = 0; i < num; i++) {
			list[i] = temp[i];
		}
		delete[] temp;
	}
	type &Append(const type &obj) {
		if (num == size) {
			Resize(size + 2);
		}
		list[num] = obj;
		return list[num++];
	}
};
int main() {
	List<Str> names;
	Str a;
	a.Set("first name that is long");
	names.Append(a);
	Str b;
	b.Set("second");
	names.Append(b);
	names.Append(a);
	List<Plain> plains;
	Plain p = {3, 1.5f};
	plains.Append(p);
	plains.Append(p);
	plains.Append(p);
	int constructed = names.list[3].data == names.list[3].base ? 1 : 0;
	printf("%s|%s|%s %d %g %d\n", names.list[0].data, names.list[1].data, names.list[2].data, plains.list[2].a, plains.list[1].b, constructed);
	return 0;
}
