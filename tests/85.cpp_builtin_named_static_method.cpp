struct MathHelpers {
	static float sqrt(float value) {
		return value;
	}
	static float sqrt(int value) {
		return value + 1.0f;
	}
};

float call_sqrt_method(float value) {
	return MathHelpers::sqrt(value);
}

float call_sqrt_int_method(int value) {
	return MathHelpers::sqrt(value);
}
