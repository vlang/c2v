#include <stdio.h>
#include <sys/resource.h>

// Deleted objects must give their memory back: 2000 iterations of 3 x 256 KB
// allocations would grow the process by 1.5 GB if `delete` leaked them.
class Block {
public:
	char data[1 << 18];
	int id;
	Block(int i) : id(i) { data[0] = (char)i; }
	virtual ~Block() {}
};

class Named {
public:
	virtual ~Named() {}
	virtual int Id() const = 0;
};

class BigNamed : public Named {
public:
	char data[1 << 18];
	int id;
	BigNamed(int i) : id(i) {}
	int Id() const { return id; }
};

static long PeakMegabytes() {
	struct rusage usage;
	getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
	return usage.ru_maxrss / (1024 * 1024);
#else
	return usage.ru_maxrss / 1024;
#endif
}

static long Churn(int count) {
	long sum = 0;
	for (int i = 0; i < count; i++) {
		Block *block = new Block(i);
		sum += block->id;
		delete block;
		char *bytes = new char[1 << 18];
		bytes[0] = 1;
		sum += bytes[0];
		delete[] bytes;
		Named *named = new BigNamed(i);
		sum += named->Id();
		delete named;
	}
	return sum;
}

int main() {
	long sum = Churn(100);
	long before = PeakMegabytes();
	sum += Churn(2000);
	long growth = PeakMegabytes() - before;
	printf("%ld %s\n", sum, growth < 200 ? "released" : "leaked");
	return 0;
}
