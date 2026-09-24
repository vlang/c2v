#include <stdio.h>
int values[4] = {1, 2, 3, 4};
int bump(int i) {
	int &r = values[i];
	r += 5;
	int y = r * 2;
	r++;
	float scale = 1.5f;
	float &s = scale;
	s = s * 2.0f;
	return y + r + (int)scale;
}
int main() {
	int t = bump(2);
	printf("%d %d\n", t, values[2]);
	return 0;
}
