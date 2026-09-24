#include <stdio.h>
struct Var {
	const char **strings;
	void Init(const char *name, const char **values) { strings = values; }
	void InitNamed(const char *name) { Init(name, NULL); }
};
int main() {
	Var v;
	v.InitNamed("x");
	const char *list[] = { "a", "b", NULL };
	Var w;
	w.Init("y", list);
	printf("%d %s\n", v.strings == NULL ? 1 : 0, w.strings[1]);
	return 0;
}
