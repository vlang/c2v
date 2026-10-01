#include <stdio.h>
#include <string.h>

typedef struct {
	int target;
	int ident;
	char name[16];
} progDef_t;

static const int MAX_PROGS = 8;

static progDef_t progs[MAX_PROGS] = {
	{ 1, 10, "test.vfp" },
	{ 2, 20, "interaction.vfp" },
	// more can be added at run time
};

struct Pair { int a; int b; };
Pair pairs[4] = { { 1, 2 } };
int counts[5] = { 7 };

int Find(const char *name) {
	int i;
	for (i = 0; progs[i].name[0]; i++) {
		if (strcmp(progs[i].name, name) == 0) {
			return progs[i].ident;
		}
	}
	progs[i].target = 3;
	progs[i].ident = 30 + i;
	strncpy(progs[i].name, name, sizeof(progs[i].name) - 1);
	return progs[i].ident;
}

int main() {
	printf("%d %d %d %d\n", Find("interaction.vfp"), Find("shadow.vp"), Find("glass.txt"), Find("shadow.vp"));
	pairs[3].b = 9;
	counts[4] = 3;
	printf("%d %d %d %d %d %d\n", pairs[0].a, pairs[0].b, pairs[3].a, pairs[3].b, counts[0], counts[4]);
	printf("%d %d\n", (int)(sizeof(progs) / sizeof(progs[0])), (int)(sizeof(pairs) / sizeof(pairs[0])));
	int local[6] = { 4, 5 };
	int holes[6] = { [2] = 5, [4] = 7 };
	Pair lp[3] = { { 8, 9 } };
	local[5] = 1;
	printf("%d %d %d %d | %d %d %d %d | %d %d %d\n", local[0], local[1], local[2], local[5], holes[0], holes[2], holes[3], holes[4], lp[0].b, lp[2].a, (int)(sizeof(holes) / sizeof(holes[0])));
	return 0;
}
