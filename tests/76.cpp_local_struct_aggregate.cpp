#include <stdio.h>

int local_struct_value() {
	struct builtin {
		const char *string;
		int id;
	} builtin[] = {
		{ "first", 7 },
		{ NULL, 0 }
	};
	return builtin[0].id;
}

int main() {
	printf("%d\n", local_struct_value());
	return 0;
}
