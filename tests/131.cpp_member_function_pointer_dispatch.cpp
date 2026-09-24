class Base;
typedef void (Base::*callback_t)(void);

class Base {
public:
	int total;

	void Add(int v) {
		total += v;
	}

	void Twice(int a, int b) {
		total += a * b;
	}

	void Dispatch(callback_t cb, int argc, const int *data) {
		switch (argc) {
		case 1: {
			typedef void (Base::*callback_1_t)(int);
			(this->*(callback_1_t)cb)(data[0]);
			break;
		}
		case 2: {
			typedef void (Base::*callback_2_t)(int, int);
			(this->*(callback_2_t)cb)(data[0], data[1]);
			break;
		}
		}
	}
};

int dispatch_all(Base &b, const int *data) {
	b.Dispatch((callback_t)&Base::Add, 1, data);
	b.Dispatch((callback_t)&Base::Twice, 2, data);
	return b.total;
}
