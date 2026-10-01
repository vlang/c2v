#include <stdio.h>

typedef unsigned char byte;

static int Clamped(float d) {
	int b = (byte)(d * 255);
	if (b <= 0) {
		b = 0;
	} else if (b > 255) {
		b = 255;
	}
	return b;
}

int main() {
	float values[3] = {0.5f, 1.0f, 1.437f};
	for (int i = 0; i < 3; i++) {
		unsigned short s = static_cast<unsigned short>(values[i] * 70000.0f);
		byte implicit_byte = values[i] * 300.0f;
		printf("%d %d %d\n", Clamped(values[i]), (int)s, (int)implicit_byte);
	}
	return 0;
}
