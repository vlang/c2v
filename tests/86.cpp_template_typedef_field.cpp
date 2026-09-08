typedef struct item_s {
	int value;
} item_t;

template <typename T>
struct idBag {
	T *items;
};

struct Holder {
	idBag<item_t> bag;
};

int first_value(Holder *holder) {
	return holder->bag.items[0].value;
}
