class Processor {
public:
	typedef void *(*Callback)(void *);

	int code;

	virtual float apply(float value) = 0;
	virtual float apply(float left, float right) = 0;
	virtual void set_code(int value) = 0;
	virtual void set_callback(Callback callback) = 0;
	virtual void get_callback(Callback *callback) = 0;
	virtual void log(const char *message, ...) = 0;
};

class Generic : public Processor {
public:
	float apply(float value) override {
		return value;
	}

	float apply(float left, float right) override {
		return left + right;
	}

	void set_code(int value) override {
		code = value;
	}

	void set_callback(Callback) override {
	}

	void get_callback(Callback *) override {
	}

	void log(const char *, ...) override {
	}
};

Processor *processor = nullptr;

void init_processor() {
	processor = new Generic;
	processor->set_code(1);
	processor->log("ready", 1);
}

float run_processor() {
	return processor->apply(2.0f) + processor->apply(3.0f, 4.0f);
}

float run_local_processor() {
	Processor *local = nullptr;
	local = new Generic;
	return local->apply(1.0f);
}

float run_uninitialized_local_processor() {
	Processor *local;
	local = new Generic;
	return local->apply(2.0f);
}

bool processor_missing() {
	return processor == nullptr;
}

bool processor_ready() {
	return nullptr != processor;
}

bool processor_truthy(Processor *value) {
	return value ? true : false;
}

bool processors_match(Processor *left, Processor *right) {
	return left == right;
}

class ProcessorList {
public:
	Processor *item;

	Processor *const &operator[](int) const {
		return item;
	}
};

Processor *read_processor(ProcessorList &items) {
	Processor *local = items[0];
	return local;
}
