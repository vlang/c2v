#include <stdio.h>
#include <string.h>

struct DrawWin {
	void *simp;
	void *win;
};

class Window {
public:
	const char *name;
	DrawWin children[2];
	int count;
	Window(const char *n) { name = n; count = 0; }
	DrawWin *FindChild(const char *n) {
		static DrawWin dw;
		if (strcmp(name, n) == 0) {
			dw.simp = NULL;
			dw.win = this;
			return &dw;
		}
		for (int i = 0; i < count; i++) {
			if (children[i].win && strcmp(((Window *)children[i].win)->name, n) == 0) {
				return &children[i];
			}
		}
		return NULL;
	}
};

int *Counter() {
	static int calls = 0;
	calls++;
	return &calls;
}

int main() {
	Window desktop("desktop");
	Window child("child");
	desktop.children[0].win = &child;
	desktop.children[0].simp = NULL;
	desktop.count = 1;
	DrawWin *a = desktop.FindChild("desktop");
	DrawWin *b = desktop.FindChild("child");
	DrawWin *c = child.FindChild("child");
	Counter();
	int *calls = Counter();
	printf("%d %d %d %d %d\n", a->win == &desktop, b->win == &child, c == a, c->win == &child, *calls);
	return 0;
}
