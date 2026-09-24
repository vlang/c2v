#include <stdio.h>
struct Node {
	int value;
	Node *next;
};
int main() {
	Node c = {3, NULL};
	Node b = {2, &c};
	Node a = {1, &b};
	Node z = {9, NULL};
	Node *head = &a;
	Node *extra = &z;
	int sum = 0;
	Node *loop;
	for (loop = head; loop; loop == head ? loop = extra : loop = NULL) {
		sum += loop->value;
	}
	bool ascending = false;
	int items[4] = {10, 20, 30, 40};
	int order = 0;
	int i;
	for (i = ascending ? 0 : 3; ascending ? i < 4 : i >= 0; ascending ? i++ : i--) {
		if (items[i] == 30) {
			continue;
		}
		order = order * 100 + items[i];
	}
	int j = 0;
	int k = 0;
	for (int m = 0; m < 5; m++, k += 10) {
		if (m == 2) {
			continue;
		}
		j += m;
	}
	printf("%d %d %d %d\n", sum, order, j, k);
	return 0;
}
