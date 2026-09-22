class idStr {
public:
	char *data;
};

int sprintf(idStr &dest, const char *format, ...) {
	dest.data = (char *)format;
	return 1;
}

int format_path(const char *text) {
	idStr path;
	return sprintf(path, "%s", text);
}
