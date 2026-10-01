#include <stdio.h>
#include <stdlib.h>
#include <string.h>
class Str {
public:
	char *data;
	int alloced;
	char base[8];
	Str() { data = base; alloced = 8; base[0] = 0; }
	Str(const Str &o) { data = base; alloced = 8; base[0] = 0; Set(o.data); }
	void operator=(const Str &o) { Set(o.data); }
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
struct Vec2 {
	float x, y;
};
struct Surface {
	Str name;
	Vec2 st;
	int flags;
};
int main() {
	Surface a;
	a.name.Set("a surface name longer than eight");
	a.st.x = 1.5f;
	a.st.y = 2.5f;
	a.flags = 7;
	Surface b;
	b = a;
	b.name.Set("b renamed with another long text");
	printf("%s|%s %g %g %d\n", a.name.data, b.name.data, b.st.x, b.st.y, b.flags);
	return 0;
}
