template <typename T>
struct Bag {
	T value;
};

struct Owner {};

typedef void (*handler_t)(Owner *, Bag<int> *);

struct Entry {
	handler_t handler;
};

void handle(Owner *, Bag<int> *) {}

Entry entries[] = {
	{ handle },
};
