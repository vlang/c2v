#include <stdio.h>
struct Tri {
	int id;
	Tri *next;
};
Tri *Merge(Tri *a, Tri *b) {
	Tri **prev = &a;
	while (*prev) {
		prev = &(*prev)->next;
	}
	*prev = b;
	return a;
}
struct List {
	Tri *head;
	int Count(Tri *start) const {
		Tri **walk = &start;
		int n = 0;
		while (*walk) {
			n++;
			walk = &(*walk)->next;
		}
		return n;
	}
};
int main() {
	Tri t3 = {3, NULL};
	Tri t2 = {2, NULL};
	Tri t1 = {1, &t2};
	Tri *m = Merge(&t1, &t3);
	Tri *e = Merge(NULL, &t3);
	List l;
	l.head = m;
	printf("%d %d %d %d\n", m->next->next->id, e->id, l.Count(m), l.Count(NULL));
	return 0;
}
