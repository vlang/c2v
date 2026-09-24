#include <stdarg.h>
#include <stdio.h>

struct stream_s {
	int avail;
};
typedef stream_s *streamp;

extern "C" {
int stream_init(streamp strm, int level);
streamp stream_next(streamp strm);
int format_into(char *buf, size_t n, const char *fmt, va_list args);
}

int start(stream_s *s, char *buf, const char *fmt, va_list args) {
	stream_init(stream_next(s), 3);
	return format_into(buf, 16, fmt, args);
}
