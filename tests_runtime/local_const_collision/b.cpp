#include <stdio.h>
int frame_code();
int count_frames(int n) {
	int onFrame = 0;
	int onAction = 1;
	for (int i = 0; i < n; i++) {
		onFrame++;
		onAction += 2;
	}
	return onFrame * 100 + onAction;
}
int main() {
	printf("%d %d\n", count_frames(3), frame_code());
	return 0;
}
