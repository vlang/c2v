#pragma once
#include <stdlib.h>

template <class type>
class List {
public:
	List() { list = NULL; num = 0; size = 0; }
	int Num() const { return num; }
	void SetNum(int n);
	void Resize(int n);
	type &operator[](int i) { return list[i]; }
private:
	type *list;
	int num;
	int size;
};

template <class type>
inline void List<type>::Resize(int n) {
	type *temp = list;
	size = n;
	list = new type[size];
	for (int i = 0; i < num; i++) {
		list[i] = temp[i];
	}
	delete[] temp;
}

template <class type>
inline void List<type>::SetNum(int n) {
	if (n > size) {
		Resize(n);
	}
	num = n;
}
