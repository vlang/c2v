struct Vec {
	float x;

	float operator*(const Vec &other) const {
		return x * other.x;
	}

	float operator*(float scale) const {
		return x * scale;
	}

	Vec &operator-=(const Vec &other) {
		x -= other.x;
		return *this;
	}

	Vec &operator*=(float scale) {
		x *= scale;
		return *this;
	}

	void adjust(float scale) {
		*this *= scale;
	}
};

float scaled_x(Vec *value, float scale) {
	return *value * scale;
}

void scale_local(float scale) {
	Vec value{};
	value *= scale;
}
