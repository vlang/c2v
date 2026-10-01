#include <stdio.h>
#include <string.h>

class Program {
public:
	int count;
	int Checksum() const {
		typedef struct {
			unsigned short op;
			int a;
			int b;
			unsigned short line;
		} statementBlock_t;

		statementBlock_t *list = new statementBlock_t[count];
		memset(list, 0, sizeof(statementBlock_t) * count);
		int sum = 0;
		for (int i = 0; i < count; i++) {
			list[i].op = (unsigned short)(i + 1);
			list[i].a = i * 3;
			list[i].b = i * 5;
			list[i].line = (unsigned short)(i * 7);
			sum += list[i].op + list[i].a + list[i].b + list[i].line;
		}
		delete[] list;
		return sum + (int)sizeof(statementBlock_t);
	}
};

int main() {
	struct Point {
		int x;
		int y;
	};
	Point p = { 3, 4 };
	Program program;
	program.count = 5;
	printf("%d %d\n", program.Checksum(), p.x * p.y);
	return 0;
}
