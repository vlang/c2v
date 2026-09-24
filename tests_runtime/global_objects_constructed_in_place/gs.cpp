#include <stdio.h>
#include <stdlib.h>
#include <string.h>
class Str {
public:
	char *data;
	int alloced;
	char base[8];
	Str() { data = base; alloced = 8; base[0] = 0; }
	Str(const char *t) { data = base; alloced = 8; base[0] = 0; Set(t); }
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
class Var {
public:
	const char *name;
	int value;
	Var *next;
	static Var *head;
	Var(const char *n, int v) : name(n), value(v) { next = head; head = this; }
};
Var *Var::head = NULL;
Var var_a("a", 1);
Var var_b("b", 2);
Str caption;
Str greeting("hi");
int main() {
	caption.Set("a much longer caption than eight");
	greeting.Set("another long greeting text");
	int sum = 0;
	for (Var *v = Var::head; v; v = v->next) {
		v->value *= 10;
		sum += v->value;
	}
	printf("%s|%s|%d %d %d\n", caption.data, greeting.data, sum, var_a.value, var_b.value);
	return 0;
}
