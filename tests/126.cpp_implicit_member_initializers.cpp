struct Entry {
	Entry() {
	}
};

struct Bucket {
	int value;

	Bucket(int initial = 16) : value(initial) {
	}
};

struct Plain {
	int value;
};

struct Holder {
	Entry entries[2];
	Entry nestedEntries[2][3];
	Bucket buckets[2];
	Plain plain[2];
	int camelField;

	Holder() : camelField(7) {
	}
};

Holder make_holder() {
	return Holder();
}
