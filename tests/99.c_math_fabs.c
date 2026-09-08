#include <math.h>
#include <string.h>

double magnitude(double value) {
	return fabs(value);
}

float magnitude_f(float value) {
	return fabsf(value);
}

size_t combined_length(int prefix, const char *value) {
	return (size_t)prefix + strlen(value);
}
