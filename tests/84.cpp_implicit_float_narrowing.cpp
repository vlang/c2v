extern double native_double(float value);

float narrow_float(float value) {
	return native_double(value);
}
