#include <stdio.h>
#include <string.h>
class Str {
public:
	char data[32];
	int len;
	int copies;
	Str(const char *text) { strcpy(data, text); len = (int)strlen(text); copies = 0; }
	Str(const Str &text) { strcpy(data, text.data); len = text.len; copies = text.copies + 1; }
	void Append(const Str &other) { strcat(data, other.data); len += other.len; }
};
Str operator+(const Str &a, const Str &b) {
	Str result(a);
	result.Append(b);
	return result;
}
int main() {
	Str a("ab");
	Str b("cd");
	Str c = a + b;
	printf("%s %d %d\n", c.data, c.len, c.copies > 0 ? 1 : 0);
	return 0;
}
