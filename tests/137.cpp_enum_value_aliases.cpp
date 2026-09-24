enum key_t {
	K_A = 5,
	K_B = 7,
	K_FIRST = 5,
	K_C,
	K_D,
	K_E = 20,
	K_LAST = K_E
};
const char *key_name(int key) {
	switch ((key_t)key) {
		case K_A: return "a";
		case K_B: return "b";
		case K_C: return "c";
		case K_LAST: return "last";
		default: return "?";
	}
}
