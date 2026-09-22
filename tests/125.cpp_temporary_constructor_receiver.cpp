class idStr {
public:
	int len;
	int alloced;
	char *data;
	char baseBuffer[20];

	idStr(const char *text) {
	}

	int FileNameHash() const {
		return 7;
	}
};

int hash_name(const char *name) {
	return idStr(name).FileNameHash();
}
