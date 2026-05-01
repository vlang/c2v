int dc_x;

int sum_global_x(int limit) {
	int total = 0;
	for (dc_x = 1; dc_x < limit; dc_x++) {
		total += dc_x;
	}
	return total;
}
