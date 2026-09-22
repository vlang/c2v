struct Point {
    int x;
    int y;
};

struct Initialized {
	int value;
	Initialized() {
		value = 42;
	}
};

struct Holder {
	Initialized item;
	Holder() {}
};

void test_new_delete() {
	Point* p = new Point();
	delete p;
	Initialized* initialized = new Initialized();
	delete initialized;
	Holder* holder = new Holder();
	delete holder;
}
