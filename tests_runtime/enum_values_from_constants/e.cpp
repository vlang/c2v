#include <stdio.h>

const int NUM_ATTRS = 3;
static const int BASE = 10;

typedef enum {
	PS_NONE = 0,
	PS_VIEW = 1,
	PS_LOCATION = 2,
	PS_AIR = 4,
	// Values computed from constants, and one following implicitly.
	PS_ALL = (1 << NUM_ATTRS) - 1,
	PS_NEXT
} portal_t;

enum Weapon {
	WP_FIRST = BASE * 2,
	WP_SECOND,
	WP_MASK = (1 << (NUM_ATTRS + 1)) | PS_AIR
};

int main() {
	int blocked = PS_ALL & ~PS_LOCATION;
	printf("%d %d %d %d %d %d\n", (int)PS_ALL, (int)PS_NEXT, blocked, (int)WP_FIRST, (int)WP_SECOND, (int)WP_MASK);
	return 0;
}
