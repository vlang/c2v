#include <stdio.h>
typedef void (*deriveFunction_t)(const float t, const float *state, float *derivatives, const void *userData);

class ODE {
public:
	virtual ~ODE() {}
	virtual float Evaluate(float t) = 0;
};

class ODE_Euler : public ODE {
public:
	ODE_Euler(const int dim, const deriveFunction_t dr, const void *ud);
	virtual ~ODE_Euler();
	virtual float Evaluate(float t);
protected:
	int dimension;
	deriveFunction_t derive;
	const void *userData;
	float *derivatives;
};
