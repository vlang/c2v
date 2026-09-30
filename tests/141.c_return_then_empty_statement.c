// A macro that ends with `return rc;`, used as `WRAP(x);`, leaves an empty
// statement after the return: the function still ends with a return.
#define WRAP(code) \
	int rc = 0;    \
	if (code > 0) { \
		rc = code;  \
	}              \
	return rc;

int wrapped(int x) {
	WRAP(x + 1);
}

int main(void) {
	return wrapped(1);
}
