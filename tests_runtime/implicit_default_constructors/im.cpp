#include <stdio.h>
class Hash {
public:
	int *hash;
	int mask;
	static int INVALID[1];
	Hash() { hash = INVALID; mask = 3; }
	int First(int key) const { return hash[key & mask & 0]; }
};
int Hash::INVALID[1] = { -1 };
class Manager {
public:
	int count;
	Hash tables[3];
	Hash single;
	int Find(int t) const { return tables[t].First(7) + single.First(1); }
};
Manager manager;
int main() {
	Manager local;
	printf("%d %d %d\n", manager.Find(2), local.Find(1), manager.tables[1].mask);
	return 0;
}
