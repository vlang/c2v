#include <stdio.h>
#include "list.h"
#include "str.h"

int main() {
	List<Str> names;
	names.SetNum(1);
	names[0] = "a rather long name";
	names.SetNum(3);
	names[1] = "short";
	names[2] = Str("another long name");
	names.SetNum(9);
	names[0] = "an even longer first name";
	names[2] = names[0];
	names[1] = "now a long second name";
	printf("%d %s %s %s\n", names.Num(), names[0].c_str(), names[1].c_str(), names[2].c_str());
	return 0;
}
