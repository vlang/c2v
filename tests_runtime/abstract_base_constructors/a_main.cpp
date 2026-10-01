#include <stdio.h>
#include "winvar.h"

int main() {
	WinRect *r = new WinRect();
	WinRect *named = new WinRect("rect");
	WinBool *b = new WinBool();
	WinVar *vars[3] = { r, named, b };
	for (int i = 0; i < 3; i++) {
		vars[i]->Set("1");
		printf("%d %s\n", vars[i]->GetEval() ? 1 : 0, vars[i]->GetName() ? vars[i]->GetName() : "(null)");
	}
	printf("%d %d %d\n", r->w, named->w, b->data ? 1 : 0);
	WinVar *heap = new WinRect("heap");
	delete heap;
	for (int i = 2; i >= 0; i--) {
		delete vars[i];
	}
	return 0;
}
