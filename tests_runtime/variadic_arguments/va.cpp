#include <stdio.h>
#include <stdarg.h>
const int BUILD_NUMBER = 1305;
const int BIG_NUMBER = 5000000;
void Log(const char *fmt, ...) {
	char buf[256];
	va_list ap;
	va_start(ap, fmt);
	vsnprintf(buf, sizeof(buf), fmt, ap);
	va_end(ap);
	printf("%s\n", buf);
}
int main() {
	int a = 40;
	int b = 2;
	Log("%i %d %d %d", BUILD_NUMBER, a + b, BIG_NUMBER, a * 3000000);
	return 0;
}
