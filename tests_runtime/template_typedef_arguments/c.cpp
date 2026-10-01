#include <stdio.h>

typedef int index_t;
typedef unsigned int flags_t;
typedef float real_t;

template <class T>
class List {
public:
	T items[4];
	int num;
	List() : num(0) {}
	void Append(T value) { items[num++] = value; }
};

static int Sum(List<index_t> &list) {
	int sum = 0;
	for (int i = 0; i < list.num; i++) {
		sum += list.items[i];
	}
	return sum;
}

static unsigned int Mask(List<flags_t> &list) {
	unsigned int mask = 0;
	for (int i = 0; i < list.num; i++) {
		mask |= list.items[i];
	}
	return mask;
}

static float Total(List<real_t> &list) {
	float total = 0;
	for (int i = 0; i < list.num; i++) {
		total += list.items[i];
	}
	return total;
}

int main() {
	List<int> ints;
	ints.Append(3);
	ints.Append(4);
	List<unsigned int> flags;
	flags.Append(1);
	flags.Append(8);
	List<float> reals;
	reals.Append(1.5f);
	printf("%d %u %.1f\n", Sum(ints), Mask(flags), Total(reals));
	return 0;
}
