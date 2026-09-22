struct idVec4 {
	float x;
};

struct idStr {
	const char *data;

	const char *c_str() const {
		return data;
	}
};

class idWinFloat {
public:
	float data;

	operator float() const {
		return data;
	}
};

class idWinStr {
public:
	idStr data;

	operator const char *() const {
		return data.c_str();
	}
};

class idWinVec4 {
public:
	idVec4 data;

	operator const idVec4 &() const {
		return data;
	}
};

float consume(float scale, const char *text, const idVec4 &color, idVec4 copy) {
	return scale + color.x + copy.x + text[0];
}

float use_conversions(idWinFloat scale, idWinStr text, idWinVec4 color) {
	return consume(scale, text, color, color) + scale;
}
