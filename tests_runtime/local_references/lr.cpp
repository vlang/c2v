#include <stdio.h>
struct Poly {
	int count;
	int data[4];
};
Poly global_polys[4];
int fill(int index, const Poly &src) {
	static Poly lut[8];
	if (lut[index].count == 0) {
		Poly &ph = lut[index];
		ph = src;
		ph.count += 1;
		Poly &gp = global_polys[index];
		gp.count = ph.count * 10;
	}
	return lut[index].count;
}
int main() {
	Poly p = {5, {1, 2, 3, 4}};
	int a = fill(2, p);
	int b = fill(2, p);
	printf("%d %d %d\n", a, b, global_polys[2].count);
	return 0;
}
