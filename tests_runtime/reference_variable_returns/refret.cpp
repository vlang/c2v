#include <stdio.h>

struct Function {
	int total;
	int locals;
};

class Pool {
public:
	Function items[4];
	int num;
	Pool() { num = 0; }
	Function *Alloc() { return &items[num++]; }
	Function &AllocRef() {
		Function &func = *Alloc();
		func.total = 10 * num;
		func.locals = 0;
		return func;
	}
	int &Counter(int &value) {
		int &alias = value;
		alias += 1;
		return alias;
	}
	Function &Pass(Function &f) { return f; }
};

int main() {
	Pool pool;
	Function &a = pool.AllocRef();
	a.locals = 3;
	Function &b = pool.AllocRef();
	pool.Pass(b).locals = 7;
	int n = 5;
	pool.Counter(n) += 10;
	printf("%d %d %d %d %d %d\n", pool.items[0].total, pool.items[0].locals, pool.items[1].total, pool.items[1].locals, n, pool.num);
	return 0;
}
