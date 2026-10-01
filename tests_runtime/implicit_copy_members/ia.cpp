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
class Token : public Str {
public:
	int type;
	Token() { type = 0; }
};
class Lexer {
public:
	Token token;
	bool hasToken;
	Lexer() { hasToken = false; }
	void Unread(const Token *t) { token = *t; hasToken = true; }
	void Grow() { token.Set("the lexer now holds a much longer token text"); }
};
int main() {
	Token t;
	t.Set("a token that is longer than eight");
	t.type = 3;
	Lexer lex;
	lex.Unread(&t);
	printf("%s\n", lex.token.data);
	lex.Grow();
	Token copy = t;
	copy.Set("copy changed to another long text");
	printf("%s|%s|%s %d %d\n", t.data, lex.token.data, copy.data, lex.token.type, copy.type);
	return 0;
}
