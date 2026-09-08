#include <stddef.h>

extern int *UpperGlobal;

int *first = NULL;
int *second = NULL;
int *UpperGlobal = NULL;

int globals_are_null() {
	return first == NULL && second == NULL && UpperGlobal == NULL;
}
