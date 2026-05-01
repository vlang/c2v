void prefix_inc_condition(int *out) {
	int x = 0;
	if (++x == 1) {
		*out = x;
	}
	if (--x == 0) {
		*out += 2;
	}
	if (++x == 2) {
		*out += 4;
	} else if (!--x) {
		*out += 8;
	}
}
