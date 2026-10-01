#include <stdio.h>
#include <string.h>
#include <stdlib.h>

struct Str {
	char *data;
	Str() { data = strdup(""); }
	Str(const char *s) { data = strdup(s); }
	Str(const Str &o) { data = strdup(o.data); }
	~Str() { free(data); }
	Str &operator=(const Str &o) {
		if (this != &o) { free(data); data = strdup(o.data); }
		return *this;
	}
};

struct Server {
	Str info;
	int ping;
	char nickname[4][8];
	short pings[4];
	Str tags[2];
};

int main() {
	Server a;
	a.info = "server one";
	a.ping = 42;
	for (int i = 0; i < 4; i++) {
		snprintf(a.nickname[i], 8, "p%d", i);
		a.pings[i] = (short)(i * 10);
	}
	a.tags[0] = "tag zero";
	a.tags[1] = "tag one";
	Server b(a);
	a.tags[0] = "changed";
	a.nickname[1][0] = 'X';
	a.pings[2] = 99;
	printf("%s %d", b.info.data, b.ping);
	for (int i = 0; i < 4; i++) printf(" %s/%d", b.nickname[i], b.pings[i]);
	printf(" %s|%s\n", b.tags[0].data, b.tags[1].data);
	Server c;
	c = a;
	printf("%s %s %d %s\n", c.tags[0].data, c.nickname[1], c.pings[2], c.info.data);
	return 0;
}
