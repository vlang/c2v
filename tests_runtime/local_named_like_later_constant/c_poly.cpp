#include <stdio.h>
#include "powerups.h"

const float EPSILON = 1e-6f;

float Clamp(float x) {
	return x > EPSILON ? x : 0.0f;
}
