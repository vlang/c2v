struct Values {
	float items[3];

	float operator[](int index) const {
		return items[index];
	}

	float &operator[](int index) {
		return items[index];
	}

	float &front() {
		return items[0];
	}
};

float read_value(Values &values) {
	return values[1] + values[2];
}

float read_pointer(Values *values) {
	return (*values)[0];
}

void write_value(Values &values) {
	values[1] = 4.0f;
}

void write_front(Values &values) {
	values.front() = 5.0f;
}

float consume_float(float value) {
	return value;
}

float read_reference_argument(Values &values) {
	return consume_float(values[1]);
}

struct CountValue {
	int value;

	int &front() {
		return value;
	}
};

float read_cast_reference_argument(CountValue &count) {
	return consume_float((float)count.front());
}

struct Entry {
	float value;
};

struct EntryList {
	Entry *entry;

	Entry *const &operator[](int) const {
		return entry;
	}
};

struct Text {
	char *data;

	char &operator[](int index) {
		return data[index];
	}
};

struct ReferenceNode {
	int symbol;
};

int receive_after_char_reference(ReferenceNode *node, int *value) {
	*value = node->symbol;
	return *value;
}

void send_after_char_reference(int *value) {
	*value = 2;
}

const float &read_member(EntryList &entries) {
	return entries[0]->value;
}

void write_member(EntryList &entries) {
	entries[0]->value = 6.0f;
}

void write_character(Text &text) {
	text[1] = 'x';
}

char read_character_local(Text &text) {
	char ch = text[1];
	return ch;
}

float copy_reference_local(float &value) {
	float copy = value;
	return copy;
}
