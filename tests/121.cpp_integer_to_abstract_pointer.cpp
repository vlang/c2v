class AbstractValueReader {
public:
	virtual int read() const = 0;
};

long erase_abstract(AbstractValueReader *reader) {
	return (long)reader;
}

int read_erased_abstract(long raw) {
	return ((AbstractValueReader *)raw)->read();
}

class AbstractDetailedReader : public AbstractValueReader {
public:
	virtual int depth() const = 0;
};

int read_abstract_depth(AbstractValueReader *reader) {
	return ((AbstractDetailedReader *)reader)->depth();
}
