#include <stdio.h>

typedef enum {
	INVALID_JOINT = -1
} jointHandle_t;

struct JointInfo {
	jointHandle_t num;
	jointHandle_t parentNum;
};

int main() {
	JointInfo joints[4];
	int parents[4] = { -1, 0, 1, 1 };
	for (int i = 0; i < 4; i++) {
		joints[i].num = static_cast<jointHandle_t>(i);
		joints[i].parentNum = parents[i] >= 0 ? (jointHandle_t)parents[i] : INVALID_JOINT;
	}
	jointHandle_t h = jointHandle_t(3);
	printf("%d %d %d %d %d\n", joints[2].num, joints[3].num, joints[3].parentNum, joints[0].parentNum, h);
	return 0;
}
