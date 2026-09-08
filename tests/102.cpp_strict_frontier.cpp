#include <stdarg.h>
#include <stdio.h>
#include <sys/stat.h>

template<class T>
void idSwap(T &left, T &right) {
	T temporary = left;
	left = right;
	right = temporary;
}

class SwapBag {
public:
	int value;

	void Swap(SwapBag &other) {
		idSwap(value, other.value);
	}
};

class ParserValue {
public:
	int parsed;

	bool Parse(int *source) {
		parsed += *source;
		return true;
	}
};

class ParserHolder {
public:
	ParserValue values[1];
};

bool is_ready(bool ready) {
	return ready;
}

bool parse_after_condition(ParserHolder *holder, bool ready, int *source) {
	if (!is_ready(ready) || !holder->values[0].Parse(source)) {
		return false;
	}
	return true;
}

class BitReader {
public:
	int bit;

	int GetBit() {
		bit++;
		return bit;
	}

	int Combine(int value) {
		return (value << 1) + GetBit();
	}
};

bool update_references(int &offset, int &count) {
	offset = 3;
	count += offset;
	return count * 2 > 0;
}

bool call_update_references() {
	int offset = 0;
	int count = 1;
	return update_references(offset, count);
}

struct PointerNode {
	int value;
};

class PointerNodeList {
public:
	PointerNode **items;

	PointerNode *&operator[](int index) {
		return items[index];
	}
};

bool pointer_index_is_set(PointerNodeList &list) {
	return list[0] != 0;
}

typedef bool (*joint_callback_t)(int value);

bool getJointTransform(int value) {
	return value != 0;
}

bool invoke_callback(joint_callback_t GetJointTransform) {
	return GetJointTransform(1);
}

int consume_list(const char *format, va_list args) {
	return va_arg(args, int);
}

int forward_list(const char *format, ...) {
	va_list args;
	va_start(args, format);
	int result = consume_list(format, args);
	va_end(args);
	return result;
}

class idStr {
public:
	const char *data;

	const char *c_str() const {
		return data;
	}

	operator const char *() const {
		return data;
	}
};

class idToken : public idStr {
};

extern double atof(const char *text);

double parse_token(const idToken &token) {
	return atof(token);
}

int subtract_text_pointers(const idStr *left, const idStr *right) {
	return *left - *right;
}

class idVec3 {
public:
	float x;
	float y;
	float z;
};

class idBounds {
public:
	idVec3 b[2];

	idBounds(const idVec3 &point) {
		b[0] = point;
		b[1] = point;
	}

	idBounds(const idVec3 &mins, const idVec3 &maxs) {
		b[0] = mins;
		b[1] = maxs;
	}
};

idBounds construct_point_bounds(idVec3 point) {
	return idBounds(point);
}

idBounds construct_range_bounds(idVec3 mins, idVec3 maxs) {
	return idBounds(mins, maxs);
}

int default_case_fallthrough(int value) {
	switch (value) {
	case 0:
		return 10;
	default:
	case 1:
		return 20;
	case 2:
		return 30;
	}
}

int default_case_trailing_statements(int value) {
	int result = 0;
	switch (value) {
	default:
	case 1:
		result = 20;
		result += 1;
		break;
	case 2:
		result = 30;
		break;
	}
	return result;
}

int switch_character(char value) {
	switch (value) {
	case 'a':
		return 1;
	case '%':
		return 2;
	default:
		return 0;
	}
}

class ChecksumFile {
public:
	int checksum;

	void Reload(bool force) {
		if (force) {
			Load();
		}
	}

	void Load() {
		checksum++;
	}
};

class ChecksumOwner {
public:
	int checksum;

	class ChecksumFileList {
	public:
		ChecksumFile **items;

		ChecksumFile *const &operator[](int index) const {
			return items[index];
		}

		ChecksumFile *&operator[](int index) {
			return items[index];
		}
	};

	ChecksumFileList files;

	void ReloadFile(bool force) {
		checksum ^= files[0]->checksum;
		files[0]->Reload(force);
		checksum ^= files[0]->checksum;
	}
};

extern "C" {
struct OpaqueState;

typedef enum {
	LINK_STATUS_BAD = -1,
	LINK_STATUS_OK = 0
} LinkStatus;

struct LinkPayload {
	OpaqueState *state;
	LinkStatus status;
};
}

int return_from_endless_loop(int value) {
	for (;;) {
		if (value) {
			return 1;
		}
		return 0;
	}
}

int narrow_ftell(FILE *file) {
	return ftell(file);
}

class FloatBuffer {
public:
	float *values;

	float &operator[](int index) {
		return values[index];
	}
};

#define SCALE_BUFFER_VALUE(value) ((int)((value) * 2.0f))

int scale_buffer_value(FloatBuffer &buffer, int index) {
	return SCALE_BUFFER_VALUE(buffer[index]);
}

void assign_buffer_value(FloatBuffer &buffer, int index, float value) {
	buffer[index] = value;
}

void increment_buffer_reference(float &value) {
	value += 1.0f;
}

void pass_buffer_reference(FloatBuffer &buffer, int index) {
	increment_buffer_reference(buffer[index]);
}

float *address_buffer_value(FloatBuffer &buffer, int index) {
	return &buffer[index];
}

enum CVarFlags_t {
	CVAR_BOOL = 1,
	CVAR_SYSTEM = 8
};

int cvarSystem = 0;
