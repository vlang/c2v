#include "ode.h"

ODE_Euler::ODE_Euler(const int dim, deriveFunction_t dr, const void *ud) {
	dimension = dim;
	derivatives = new float[dim];
	derive = dr;
	userData = ud;
}

ODE_Euler::~ODE_Euler() {
	delete[] derivatives;
}

float ODE_Euler::Evaluate(float t) {
	float state[2] = { t, t * 2 };
	derive(t, state, derivatives, userData);
	return derivatives[0] + derivatives[1];
}
