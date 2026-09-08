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

struct Entry {
	float value;
};

struct EntryList {
	Entry *entry;

	Entry *const &operator[](int) const {
		return entry;
	}
};

const float &read_member(EntryList &entries) {
	return entries[0]->value;
}

void write_member(EntryList &entries) {
	entries[0]->value = 6.0f;
}
