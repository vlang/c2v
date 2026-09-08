int next_value(int value) {
	return value - 1;
}

void countdown(int start) {
	int value = start;
	for (; next_value(value) > 0; value = next_value(value)) {
	}
}
