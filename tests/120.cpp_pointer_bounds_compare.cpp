int pointer_bounds_compare(int index) {
	int values[4] = {};
	int *cursor = &values[index];
	return cursor >= &values[4];
}

bool pointer_identity_compare(int *left, int *right) {
	return left != right;
}

bool pointer_before_array(int *cursor) {
	int values[4] = {};
	return cursor < values;
}
