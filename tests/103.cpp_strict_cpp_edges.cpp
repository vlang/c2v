class TextBuffer {
public:
	const char *data;

	TextBuffer &operator+=(const char *text) {
		data = text;
		return *this;
	}

	TextBuffer &operator+=(char marker) {
		if (marker) {
			data = data;
		}
		return *this;
	}
};

void append_marker(TextBuffer &text) {
	text += '_';
}

bool consume_text(const char *text);

bool conditional_array_decay(bool has_key) {
	char key[4];
	return consume_text(has_key ? key : 0);
}

enum State {
	STATE_IDLE,
	STATE_ACTIVE
};

State activate() {
	State state = STATE_IDLE;
	state = STATE_ACTIVE;
	(void)0;
	return state;
}

typedef int StateChannel;

void consume_state_channel(StateChannel channel);

void send_state_channel() {
	consume_state_channel(STATE_ACTIVE);
}

void consume_const_count(const int &count);

void send_const_count() {
	consume_const_count(-1);
}

class BaseList {
public:
	int value;

	BaseList &operator=(const BaseList &other) {
		value = other.value;
		return *this;
	}

	void Clear() {
		value = 0;
	}
};

class DerivedList : public BaseList {
public:
	void Copy(const BaseList &other) {
		BaseList::operator=(other);
	}

	void Reset() {
		BaseList::Clear();
	}
};

typedef BaseList BaseAlias;

class AliasDerived : public BaseList {
public:
	void CopyAlias(const BaseAlias &other) {
		BaseList::operator=(other);
	}
};

class RootOps {
public:
	int count;

	void Touch() {
		count = 1;
	}
};

class MidOps : public RootOps {
};

class LeafOps : public MidOps {
public:
	void TouchRoot() {
		RootOps::Touch();
	}

	void TouchThroughMid() {
		MidOps::Touch();
	}
};

class CastRoot {
public:
	int value;
};

class CastDerived : public CastRoot {
};

struct CastHolder {
	CastDerived item;
};

CastHolder &cast_holder();
void consume_cast_root(const CastRoot &value);

void send_cast_root() {
	consume_cast_root(cast_holder().item);
}

bool pointer_truth(int **cursor) {
	while (*cursor) {
		return true;
	}
	return false;
}

void consume_index(int index);

void advance_reference(int &index) {
	consume_index(index++);
}

class PhysicsBody {
public:
	void ApplyImpulse(int id) {
		id = id;
	}
};

void apply_physics_impulse(PhysicsBody &physics, int id) {
	physics.ApplyImpulse(id);
}

class AbstractValue {
public:
	virtual int Read() const = 0;
	virtual void Write(int value) = 0;
};

class ConcreteRootState {
public:
	int state;

	int ReadState() const {
		return state;
	}
};

class AbstractWithRootState : public ConcreteRootState {
public:
	virtual void SetState(int value) = 0;

	int ReadRootState() const {
		return ConcreteRootState::ReadState();
	}
};

class ConcreteWithRootState : public AbstractWithRootState {
public:
	void SetState(int value) {
		state = value;
	}
};

int read_abstract_root_state(AbstractWithRootState *value) {
	return value->ReadRootState();
}

bool has_abstract_value(AbstractValue *value) {
	return value != 0;
}

AbstractValue *empty_abstract_value() {
	AbstractValue *value = 0;
	value = 0;
	if (value) {
		return value;
	}
	return value;
}

void consume_abstract_value(AbstractValue *value);

void send_empty_abstract_value() {
	consume_abstract_value(0);
}

class TryMade {
};

TryMade *make_try_made() {
	try {
		return new TryMade;
	} catch (...) {
		return 0;
	}
}

float half_speed() {
	float speed = 0.0f;
	return speed * 0.5f;
}
