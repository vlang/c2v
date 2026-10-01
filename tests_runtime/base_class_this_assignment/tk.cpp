#include <stdio.h>
#include <stdlib.h>
#include <string.h>
class Str {
public:
	char *data;
	int alloced;
	char base[8];
	Str() { data = base; alloced = 8; base[0] = 0; }
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
class Token : public Str {
public:
	int type;
	Token() { type = 0; }
	void operator=(const char *text) { static_cast<Str *>(this)->Set(text); }
	void operator=(const Str &text) { *static_cast<Str *>(this) = text; }
};
int main() {
	Token t;
	t = "a token text longer than eight";
	Str s;
	s.Set("from str");
	Token u;
	u = s;
	printf("%s|%s %d\n", t.data, u.data, t.type + u.type);
	return 0;
}
