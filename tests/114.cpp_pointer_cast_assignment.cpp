void stamp_word(int index) {
	unsigned char data[16] = {};
	unsigned char color[4] = { 1, 2, 3, 4 };
	*(int *)&data[index] = *(int *)&color[0];
}
