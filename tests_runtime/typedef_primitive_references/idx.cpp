#include <stdio.h>

typedef int aasIndex_t;

template <class T>
class List {
public:
	T items[8];
	int num;
	List() { num = 0; }
	const T &operator[](int index) const { return items[index]; }
	T &operator[](int index) { return items[index]; }
	void Append(const T &value) { items[num++] = value; }
};

class AASFile {
public:
	List<aasIndex_t> edgeIndex;
	const aasIndex_t &GetEdgeIndex(int index) const { return edgeIndex[index]; }
	aasIndex_t EdgeValue(int index) const { return edgeIndex[index]; }
	List<int> order;
	const aasIndex_t &Ordered(int i) const { return edgeIndex[order[i]]; }
};

void SetIndex(aasIndex_t &out, int v) { out = v; out += 1; }
int Twice(const aasIndex_t &v) { return v * 2; }

int main() {
	AASFile file;
	file.edgeIndex.Append(5);
	file.edgeIndex.Append(-7);
	const aasIndex_t &ref = file.GetEdgeIndex(1);
	file.edgeIndex[1] = 9;
	file.order.Append(1);
	file.order.Append(0);
	printf("%d %d %d\n", file.GetEdgeIndex(0), ref, file.EdgeValue(1));
	printf("%d %d\n", file.Ordered(0), file.Ordered(1));
	const aasIndex_t &a = file.edgeIndex[0];
	int &b = file.edgeIndex[1];
	b = 3;
	b += 2;
	const int &t = 5;
	const aasIndex_t &d = file.EdgeValue(0);
	file.edgeIndex[0] = 11;
	printf("%d %d %d %d %d\n", a, b, t, d, file.edgeIndex[1]);
	SetIndex(file.edgeIndex[0], 20);
	aasIndex_t local = 3;
	SetIndex(local, 30);
	printf("%d %d %d %d\n", a, local, Twice(file.edgeIndex[0]), Twice(local));
	return 0;
}
