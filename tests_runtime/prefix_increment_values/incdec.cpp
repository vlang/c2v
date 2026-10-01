#include <stdio.h>

template <class T>
class List {
public:
	T items[8];
	int num;
	List() { num = 0; }
	T &operator[](int i) { return items[i]; }
	int Num() const { return num; }
	void Append(T v) { items[num++] = v; }
};

int Twice(int v) { return v * 2; }

int main() {
	List<int> list;
	for (int i = 0; i < 4; i++) {
		list.Append(10 + i);
	}
	int c = list.Num();
	int sum = 0;
	while (c > 0) {
		int v = list[--c];
		sum = sum * 100 + v;
	}
	int d = 0;
	int a = list[d++];
	int b = list[++d];
	int arr[4] = { 1, 2, 3, 4 };
	int e = 3;
	int x = arr[--e];
	int y = Twice(--e);
	int z = Twice(e++);
	printf("%d %d %d %d %d %d %d %d %d\n", sum, a, b, d, x, y, z, e, c);
	int queue[5] = { 3, 1, 4, 1, 5 };
	int start = 0;
	int total = 0;
	int cur;
	for (cur = queue[start]; start < 4; cur = queue[++start]) {
		total = total * 10 + cur;
	}
	for (int i = 0, j = 4; i < j; ++i, --j) {
		total += i * j;
	}
	char text[8] = "2.500";
	int l = 5;
	while (l > 0 && text[l - 1] == '0') text[--l] = '\0';
	printf("%d %d %s %d\n", total, cur, text, l);
	return 0;
}
