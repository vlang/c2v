#include <alloca.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#define ALLOCA16(x) ((void *)((((uintptr_t)alloca((x) + 15)) + 15) & ~15))

static int Sum(int n) {
	int *values = (int *)alloca(n * sizeof(int));
	for (int i = 0; i < n; i++) {
		values[i] = i * i;
	}
	int total = 0;
	for (int i = 0; i < n; i++) {
		total += values[i];
	}
	return total;
}

class Mixer {
public:
	int channels;
	Mixer() : channels(3) {}
	float Mix(int samples) const {
		float *buffer = (float *)ALLOCA16(samples * channels * sizeof(float));
		if (((uintptr_t)buffer & 15) != 0) {
			return -1.0f;
		}
		for (int i = 0; i < samples * channels; i++) {
			buffer[i] = 0.5f * i;
		}
		return buffer[samples * channels - 1];
	}
};

static const char *Upper(const char *s, char *out) {
	size_t len = strlen(s);
	char *tmp = (char *)alloca(len + 1);
	for (size_t i = 0; i <= len; i++) {
		tmp[i] = (s[i] >= 'a' && s[i] <= 'z') ? s[i] - 32 : s[i];
	}
	strcpy(out, tmp);
	return out;
}

int main() {
	long total = 0;
	Mixer mixer;
	float mixed = 0;
	for (int i = 0; i < 200000; i++) {
		total += Sum(64);
		mixed += mixer.Mix(16);
	}
	char out[16];
	printf("%ld %.1f %s\n", total, mixed, Upper("doom", out));
	return 0;
}
