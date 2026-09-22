int local_anonymous_string_array() {
	static const struct {
		unsigned int width;
		unsigned char bytes[4];
	} item = { 3, "abc" };
	return item.width + item.bytes[1];
}
