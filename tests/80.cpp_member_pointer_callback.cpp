struct CallbackBase {};

typedef void (CallbackBase::*callback_t)();

struct CallbackEntry {
	callback_t function;
};

struct CallbackOwner : CallbackBase {
	int last;

	void invoke(int value) {
		last = value;
	}

	void empty() {
	}
};

CallbackEntry callbacks[] = {
	{ (callback_t)&CallbackOwner::invoke },
	{ (callback_t)&CallbackOwner::empty },
};

int main() {
	return sizeof(callbacks) == 0;
}
