int count_present(int *values) {
	int i;
	int count = 0;

	for (i = 0; values[i] != -1; i++) {
		if (values[i] == 0) {
			continue;
		}
		count++;
	}

	return count;
}
