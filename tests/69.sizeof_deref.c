typedef struct Entry {
	int x;
	int y;
} Entry;

int entry_size(Entry *entry) {
	return sizeof(*entry);
}
