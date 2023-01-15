#include <stdio.h>

int main()
{
	char buf[12];

	sprintf(buf, "Hello world");
	printf("%s\n", buf);

	return 0;
}
