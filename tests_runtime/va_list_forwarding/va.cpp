#include <stdarg.h>
#include <stdio.h>
#include <string.h>

enum Kind { KIND_A, KIND_B, KIND_C };

struct Arg {
	int type;
	long value;
};

struct Point {
	int x, y;
};

// Consumes a va_list received from another function.
static int SumInts(int count, va_list args) {
	int sum = 0;
	for (int i = 0; i < count; i++) {
		sum += va_arg(args, int);
	}
	return sum;
}

int Sum(int count, ...) {
	va_list args;
	va_start(args, count);
	int sum = SumInts(count, args);
	va_end(args);
	return sum;
}

static void Describe(char *out, int numargs, va_list args) {
	out[0] = '\0';
	for (int i = 0; i < numargs; i++) {
		Arg *arg = va_arg(args, Arg *);
		char part[32];
		snprintf(part, sizeof(part), "%c=%ld ", arg->type, arg->value);
		strcat(out, part);
	}
}

void Post(char *out, int numargs, ...) {
	va_list args;
	va_start(args, numargs);
	Describe(out, numargs, args);
	va_end(args);
}

// Reads mixed types in the variadic function itself, and copies the list.
double Mixed(const char *format, ...) {
	va_list args, copy;
	va_start(args, format);
	va_copy(copy, args);
	double total = 0;
	for (const char *f = format; *f; f++) {
		switch (*f) {
		case 'i': total += va_arg(args, int); break;
		case 'l': total += (double)va_arg(args, long long); break;
		case 'd': total += va_arg(args, double); break;
		case 'u': total += va_arg(args, unsigned int); break;
		case 'k': total += 100 * (int)(Kind)va_arg(args, int); break;
		case 's': total += strlen(va_arg(args, const char *)); break;
		case 'p': { Point p = va_arg(args, Point); total += p.x * 10 + p.y; break; }
		}
	}
	int first = va_arg(copy, int);
	va_end(copy);
	va_end(args);
	return total + first * 1000;
}

// Formats the arguments that remain after reading the first one.
void Tagged(char *out, size_t size, const char *format, ...) {
	va_list args;
	va_start(args, format);
	int tag = va_arg(args, int);
	int n = snprintf(out, size, "[%d] ", tag);
	vsnprintf(out + n, size - n, format, args);
	va_end(args);
}

int main() {
	int a = 40;
	long big = 5000000000L;
	float f = 1.5f;
	Point p = { 3, 4 };
	printf("%d\n", Sum(4, 1, a, a + 2, 2000000));
	Arg x = { 'd', 7 };
	Arg y = { 'f', -3 };
	char out[128];
	Post(out, 2, &x, &y);
	printf("%s\n", out);
	printf("%.1f\n", Mixed("ildukspi", a, (long long)big, f, 3u, KIND_C, "four", p, 2));
	Tagged(out, sizeof(out), "%s %d %.2f", 9, "rest", a, (double)f);
	printf("%s\n", out);
	return 0;
}
