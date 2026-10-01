#include <stdio.h>

struct Vec6 {
	float p[6];
	float Sum() const { float s = 0; for (int i = 0; i < 6; i++) { s += p[i]; } return s; }
};

class Body {
public:
	float response[16];
	Vec6 &GetResponseForce(int index) { return reinterpret_cast<Vec6 &>(response[index * 8]); }
	const Vec6 &ResponseForce(int index) const { return reinterpret_cast<const Vec6 &>(response[index * 8]); }
};

int main() {
	Body body;
	for (int i = 0; i < 16; i++) {
		body.response[i] = (float)i;
	}
	Vec6 &force = body.GetResponseForce(1);
	force.p[0] = 100.0f;
	printf("%.1f %.1f %.1f\n", body.response[8], body.GetResponseForce(0).Sum(), body.ResponseForce(1).Sum());
	return 0;
}
