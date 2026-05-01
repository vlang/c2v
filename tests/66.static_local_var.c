int next_value(void) {
	static int value = 41;
	value++;
	return value;
}

int current_value(void) {
	static int value;
	return value;
}
