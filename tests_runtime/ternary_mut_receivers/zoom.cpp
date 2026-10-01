#include <stdio.h>

class Weapon {
public:
	int zoomFov;
	int queries;
	Weapon() { zoomFov = 45; queries = 0; }
	int GetZoomFov() { queries++; return zoomFov; }
};

class WeaponPtr {
public:
	Weapon *w;
	WeaponPtr() { w = NULL; }
	Weapon *GetEntity() { return w; }
};

float CalcFov(WeaponPtr &weapon, bool honorZoom) {
	float fov;
	fov = (honorZoom && weapon.GetEntity()) ? (float)weapon.GetEntity()->GetZoomFov() : 90.0f;
	return fov;
}

int main() {
	WeaponPtr p;
	float a = CalcFov(p, true);
	Weapon w;
	p.w = &w;
	float b = CalcFov(p, true);
	float c = CalcFov(p, false);
	printf("%.0f %.0f %.0f %d\n", a, b, c, w.queries);
	return 0;
}
