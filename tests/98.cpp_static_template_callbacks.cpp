typedef void (*callback_t)(const char *value);

class Completion {
public:
	template<int minimum, int maximum>
	static void Range(const char *value) {
	}

	template<const char **strings>
	static void Choice(const char *value) {
	}
};

const char *choices[2] = { "first", 0 };

callback_t range_callback() {
	return Completion::Range<-1, 2>;
}

callback_t choice_callback() {
	return Completion::Choice<choices>;
}

class AllocatedBase {
};

class AllocatedChild : public AllocatedBase {
};

template<class T>
AllocatedBase *allocate_instance() {
	return new T;
}

typedef AllocatedBase *(*allocator_t)();

allocator_t child_allocator() {
	return allocate_instance<AllocatedChild>;
}
