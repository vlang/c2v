float transform(float value) {
	return value * 2.0f;
}

float apply_transform(float value) {
	float transform = 1.0f;
	return transform + ::transform(value);
}

struct Utility {
	static float scale(float value) {
		return value * 3.0f;
	}
};

float apply_scale(float value) {
	float scale = 1.0f;
	return scale + Utility::scale(value);
}
