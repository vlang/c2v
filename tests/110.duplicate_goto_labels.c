int first_jump(int fail_now) {
	if (fail_now) {
		goto fail;
	}
	return 1;
fail:
	return 0;
}

int second_jump(int fail_now) {
	if (fail_now) {
		goto fail;
	}
	return 2;
fail:
	return 0;
}
