#include <stdio.h>

struct Stats {
	int count;
	float total;
	int values[3];
};

template <class T>
class List {
public:
	T items[4];
	T &operator[](int i) { return items[i]; }
	T *Get(int i) { return &items[i]; }
};

static void Bump(int &count, float &total, float amount) {
	count++;
	total += amount;
}

static bool Parse(const char *text, int &out) {
	out = 0;
	for (const char *p = text; *p; p++) {
		out = out * 10 + (*p - '0');
	}
	return true;
}

int main() {
	List<Stats> stats;
	for (int i = 0; i < 4; i++) {
		stats[i].count = 0;
		stats[i].total = 0;
	}
	Bump(stats[1].count, stats[1].total, 2.5f);
	Bump(stats.Get(2)->count, stats.Get(2)->total, 1.5f);
	Parse("42", stats[3].values[1]);
	printf("%d %.1f %d %.1f %d\n", stats[1].count, stats[1].total, stats[2].count, stats[2].total, stats[3].values[1]);
	return 0;
}
