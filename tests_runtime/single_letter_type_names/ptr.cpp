#include <stdio.h>
#include <stdlib.h>
struct P { int n; int *data; };
int main() {
	P p;
	p.data = (int *)malloc(4 * sizeof(int));
	int *q = p.data;
	q[3] = 7;
	p.data[2] = q[3] + 1;
	printf("%d %d\n", p.data[2], q[3]);
	return 0;
}
