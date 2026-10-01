#include <stdio.h>
#include <string.h>
#include <stdlib.h>

class Str {
public:
	int len;
	char *data;
	char base[20];
	Str() { len = 0; data = base; base[0] = 0; }
	Str(const char *text) { len = 0; data = base; base[0] = 0; *this = text; }
	Str(const Str &other) { len = 0; data = base; base[0] = 0; *this = other.data; }
	~Str() { if (data != base) free(data); }
	void operator=(const char *text) {
		int n = (int)strlen(text);
		if (data != base) free(data);
		data = n < 20 ? base : (char *)malloc(n + 1);
		memcpy(data, text, n + 1);
		len = n;
	}
	void operator=(const Str &other) { *this = other.data; }
	const char *c_str() const { return data; }
};

template <class T>
class List {
public:
	int num;
	int size;
	T *list;
	List() { num = 0; size = 0; list = NULL; }
	~List() { delete[] list; }
	void Resize(int newsize) {
		T *temp = list;
		size = newsize;
		list = new T[size];
		for (int i = 0; i < num; i++) {
			list[i] = temp[i];
		}
		delete[] temp;
	}
	int Append(const T &obj) {
		if (num == size) {
			Resize(size + 4);
		}
		list[num] = obj;
		num++;
		return num - 1;
	}
	const T &operator[](int index) const { return list[index]; }
};

struct KeyValue {
	Str key;
	Str value;
};

int main() {
	List<KeyValue> args;
	KeyValue kv;
	char key[32];
	for (int i = 0; i < 10; i++) {
		snprintf(key, sizeof(key), "#str_%05d", i);
		kv.key = key;
		kv.value = i % 2 ? "odd value" : "an even value that is long";
		args.Append(kv);
	}
	for (int i = 0; i < 10; i++) {
		printf("%s=%s\n", args[i].key.c_str(), args[i].value.c_str());
	}
	return 0;
}
