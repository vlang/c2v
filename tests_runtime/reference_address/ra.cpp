#include <stdio.h>
#include <string.h>
class Str {
public:
	char data[32];
	int len;
	Str(const char *t) { strcpy(data, t); len = (int)strlen(t); }
	int Length() const { return len; }
	Str &operator=(const Str &text) {
		if (&text == this) {
			printf("self\n");
			return *this;
		}
		int l = text.Length();
		memcpy(data, text.data, l + 1);
		len = l;
		return *this;
	}
};
class Winding {
public:
	int num;
	int Compare(const Winding &w) const {
		const Winding *f1 = this;
		const Winding *f2 = &w;
		return f1->num * 10 + f2->num + (f1 == this ? 100 : 0);
	}
};
int main() {
	Str a("abc");
	Str b("hello");
	a = b;
	a = a;
	Winding w1 = {3};
	Winding w2 = {4};
	printf("%s %d %d\n", a.data, a.Length(), w1.Compare(w2));
	return 0;
}
