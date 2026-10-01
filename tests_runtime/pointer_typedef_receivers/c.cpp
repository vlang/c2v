#include <stdio.h>
#include <string.h>

// Methods called through a value whose type is a typedef of a pointer.
class Name {
public:
	char text[16];
	int uses;
	int Compare(const char *other) const { return strcmp(text, other); }
	operator const char *() const { return text; }
	operator const char *() { uses++; return text; }
	void Touch() { uses++; }
};

typedef Name *NamePtr;

static int CompareNames(const NamePtr *a, const NamePtr *b) { return (*a)->Compare(**b); }

static NamePtr Pick(NamePtr *names, int index) { return names[index]; }

int main() {
	Name first, second;
	strcpy(first.text, "alpha");
	strcpy(second.text, "beta");
	first.uses = 0;
	second.uses = 0;
	NamePtr names[2];
	names[0] = &second;
	names[1] = &first;
	NamePtr current = names[0];
	current->Touch();
	(*names[1]).Touch();
	names[1]->Touch();
	Pick(names, 0)->Touch();
	const char *text = *Pick(names, 1);
	printf("%d %d %d %d %s\n", CompareNames(&names[0], &names[1]) > 0, CompareNames(&names[1], &names[0]) < 0,
		first.uses, second.uses, text);
	return 0;
}
