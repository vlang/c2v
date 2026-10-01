#include <stdio.h>
#include "winvar.h"

static int counter = 0;

WinVar::WinVar() {
	name = 0;
	eval = true;
	serial = ++counter;
}

WinVar::WinVar(const char *n) {
	name = n;
	eval = true;
	serial = ++counter;
}

WinVar::~WinVar() {
	printf("~WinVar %s\n", name ? name : "(null)");
}
