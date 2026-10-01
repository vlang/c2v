#include <stdio.h>

class Item {
public:
	int count;
	Item() : count(0) {}
	int *CountAddress() { return &count; }
	const Item *Self() const { return this; }
};

class Base {
public:
	int tag;
	Base() : tag(0) {}
	virtual ~Base() {}
	int *TagAddress() { return &tag; }
};

class Derived : public Base {
public:
	int extra[8];
};

struct Slot {
	Item item;
};

class Holder {
public:
	Item items[4];
	Slot slots[2];
	Derived derived[3];
	Item grid[2][3];
	Item *pointer;
	Item &First() { return items[0]; }
	Item *Ptr() { return items; }
};

static Holder holder;

static Holder *GetHolder() { return &holder; }
static Holder &HolderRef() { return holder; }

int main() {
	*GetHolder()->items[1].CountAddress() = 5;
	*HolderRef().items[2].CountAddress() = 6;
	*GetHolder()->grid[1][2].CountAddress() = 7;
	*GetHolder()->First().CountAddress() = 8;
	printf("%d %d %d %d\n", holder.items[1].count, holder.items[2].count, holder.grid[1][2].count,
		holder.items[0].count);
	printf("%d\n", GetHolder()->items[3].Self() == &holder.items[3]);
	*GetHolder()->slots[1].item.CountAddress() = 9;
	*HolderRef().derived[2].TagAddress() = 10;
	printf("%d %d\n", holder.slots[1].item.count, holder.derived[2].tag);
	holder.pointer = holder.items;
	*GetHolder()->Ptr()[3].CountAddress() = 11;
	*HolderRef().pointer[2].CountAddress() += 1;
	printf("%d %d\n", holder.items[3].count, holder.items[2].count);
	return 0;
}
