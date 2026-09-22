unsigned short swap16(unsigned short value) {
	return __builtin_bswap16(value);
}

unsigned int swap32(unsigned int value) {
	return __builtin_bswap32(value);
}

float float_swap(float value) {
	union {
		float f;
		unsigned int u;
	} __attribute__((may_alias)) data;
	data.f = value;
	data.u = __builtin_bswap32(data.u);
	return data.f;
}
