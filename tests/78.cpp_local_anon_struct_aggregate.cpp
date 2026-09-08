#include <stdio.h>

int local_anon_struct_value() {
	static const struct {
		int width;
		int height;
	} icon = { 48, 32 };
	return icon.width + icon.height;
}

int main() {
	printf("%d\n", local_anon_struct_value());
	return 0;
}
