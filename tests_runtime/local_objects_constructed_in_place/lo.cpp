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
	Str(const Str &o) { data = base; alloced = 8; base[0] = 0; Set(o.data); }
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
Str Make(const char *t) {
	Str s(t);
	return s;
}
int main() {
	Str a("x");
	a.Set("a much longer text than the inline buffer");
	Str b = Make("y");
	b.Set("another text that is longer than eight");
	Str c = Make("short");
	printf("%s|%s|%s\n", a.data, b.data, c.data);
	return 0;
}
