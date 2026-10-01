#include <stdio.h>

float AdjustAngles(int run) {
	float speed;
	if (run) {
		speed = 2.5f;
	} else {
		speed = 1.0f;
	}
	return speed * 2;
}

int Powerup(int which);
float Clamp(float x);

int Side(float d) {
	float d1 = d, epsilon = 0.1f;
	if (d1 > epsilon) {
		return 0;
	} else if (d1 < -epsilon) {
		return 1;
	}
	return 2;
}

int main() {
	printf("%.1f %.1f %d\n", AdjustAngles(1), AdjustAngles(0), Powerup(1));
	printf("%d %d %d %.3f\n", Side(0.5f), Side(-0.5f), Side(0.05f), Clamp(0.0000001f) + Clamp(0.5f));
	return 0;
}
