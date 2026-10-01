#include <stdio.h>
#include <alloca.h>
#include <string.h>
#include <sys/resource.h>

// `alloca` storage is released when the function returns: 200000 calls with
// 4 KB each would grow the process by 800 MB if it leaked.
static int Work(int n) {
	char *buffer = (char *)alloca(4096 + n % 7);
	memset(buffer, n & 0x7f, 64);
	if (n % 3 == 0) {
		return buffer[1];
	}
	char *more = (char *)alloca(128);
	more[0] = buffer[2];
	return more[0];
}

static long PeakMegabytes() {
	struct rusage usage;
	getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
	return usage.ru_maxrss / (1024 * 1024);
#else
	return usage.ru_maxrss / 1024;
#endif
}

int main() {
	long sum = 0;
	for (int i = 0; i < 1000; i++) {
		sum += Work(i);
	}
	long before = PeakMegabytes();
	for (int i = 0; i < 200000; i++) {
		sum += Work(i);
	}
	long growth = PeakMegabytes() - before;
	printf("%ld %s\n", sum, growth < 200 ? "released" : "leaked");
	return 0;
}
