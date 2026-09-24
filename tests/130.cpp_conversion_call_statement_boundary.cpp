class Text {
public:
	const char *data;

	operator const char *() const {
		return data;
	}
};

class Entry {
public:
	Text key;

	const Text &GetKey() const {
		return key;
	}
};

class Dictionary {
public:
	const Entry *FindKey(const char *key) const;
};

bool lookup_then_test(const Dictionary *dictionary, const Entry *entry) {
	const Entry *found;
	found = dictionary->FindKey(entry->GetKey());
	if (found == 0) {
		return false;
	}
	return true;
}
