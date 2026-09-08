class DictionaryHolder {
public:
	struct {
		int key;
		int value;
	} dictionary[16];

	void initialize() {
		dictionary[0].key = 1;
		dictionary[0].value = 2;
	}
};

int compare_bytes(const unsigned char *left, const unsigned char *right);

int compare_buffers() {
	unsigned char left[8];
	unsigned char right[8];
	return compare_bytes(left, right);
}

class InitializableBase {
public:
	void Init(int value) {
	}
};

class InitializableChild : public InitializableBase {
public:
	InitializableChild() {
	}
};

template<class T>
class TinyList {
public:
	T *items;
};

class TemplateArrayHolder {
public:
	TinyList<int> lists[4];
};
