#include <stdio.h>

class Link {
public:
	Link *head;
	Link *next;
	Link() { head = this; next = this; }
	bool InList() const { return head != this; }
	bool Alone() const { return !InList(); }
	bool Both() const { return Alone() && next == this; }
	int Depth() const { return Alone() ? 0 : 1 + head->Depth(); }
	void Join(Link &list) { head = &list; next = list.next; list.next = this; }
};

int main() {
	Link list;
	Link a;
	printf("%d %d %d\n", a.InList() ? 1 : 0, a.Alone() ? 1 : 0, a.Both() ? 1 : 0);
	a.Join(list);
	printf("%d %d %d %d\n", a.InList() ? 1 : 0, a.Alone() ? 1 : 0, a.Both() ? 1 : 0, a.Depth());
	return 0;
}
