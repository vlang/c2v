int default_case_fallthrough(int value) {
	switch (value) {
	default:
		value++;
	case 1:
	case 2:
		return value + 10;
	case 3:
		return 30;
	}
}
