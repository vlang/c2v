#include "ode.h"

static void Derive(const float t, const float *state, float *derivatives, const void *userData) {
	derivatives[0] = state[0] * *(const float *)userData;
	derivatives[1] = state[1] + t;
}

int main() {
	float scale = 3.0f;
	ODE *ode = new ODE_Euler(2, Derive, &scale);
	printf("%.1f\n", ode->Evaluate(1.5f));
	return 0;
}
