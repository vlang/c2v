class Name {
public:
	int len;
	Name() : len(0) {}
	Name &operator=(const char *text) {
		len = 0;
		while (text[len] != 0) {
			len++;
		}
		return *this;
	}
};

class PooledName : public Name {
public:
	int users;
	PooledName() : users(0) {}
};

int assign_through_base(PooledName *pooled, const char *text) {
	*static_cast<Name *>(pooled) = text;
	pooled->users = 1;
	return pooled->len + pooled->users;
}
