// A do-while body that ends with a return never reaches its condition, and a
// local named like a V builtin function (`error`) is renamed.
int check(int x) {
	int error = 0;
	do {
		if (x > 10) {
			error = 1;
			break;
		}
		return x * 2;
	} while (0);
	return error ? -1 : 0;
}

int main(void) {
	return check(3) + check(11);
}
