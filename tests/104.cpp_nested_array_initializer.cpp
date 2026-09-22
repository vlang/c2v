int sum_nested_array(void) {
	static int neighbors[2][2] = {
		{ 0, 1 }, { 1, -1 }
	};
	return neighbors[0][1] + neighbors[1][0];
}

float first_zero_value(void) {
	float vector[3] = {};
	return vector[0];
}

struct GlobalCell {
	GlobalCell();
	float value;
};

GlobalCell::GlobalCell() {
}

static GlobalCell global_cells[2];

float read_global_cell(void) {
	return global_cells[1].value;
}

typedef unsigned int Word;
static Word global_words[2] = { 255, 0 };

Word read_global_word(int index) {
	return global_words[index];
}
