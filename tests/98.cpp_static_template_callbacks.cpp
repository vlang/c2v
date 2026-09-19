typedef void (*callback_t)(const char *value);

class Completion {
public:
	template<int minimum, int maximum>
	static void Range(const char *value) {
	}

	template<const char **strings>
	static void Choice(const char *value) {
		for (int i = 0; strings[i]; i++) {
			value = strings[i];
		}
	}
};

const char *choices[2] = { "first", 0 };

callback_t range_callback() {
	return Completion::Range<-1, 2>;
}

callback_t choice_callback() {
	return Completion::Choice<choices>;
}

class CallbackFactory {
public:
	void Add(const char *name, callback_t callback) {
		callback(name);
	}

	void Init(callback_t callback) {
		Add("default", callback);
	}
};

void *lookup_extension(const char *name);
typedef void (*extension_callback_t)(int value);
extension_callback_t extension_callback;

void bind_extension() {
	extension_callback = (extension_callback_t)lookup_extension("extension");
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
