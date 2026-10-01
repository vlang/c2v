#include <stdio.h>

class UserInterface {
public:
	virtual ~UserInterface() {}
	virtual const char *Name() const = 0;
};

class Gui : public UserInterface {
public:
	const char *name;
	Gui(const char *n) { name = n; }
	const char *Name() const { return name; }
};

struct RenderEntity {
	UserInterface *gui[3];
};

static void AddRenderGui(const char *name, UserInterface **gui) {
	*gui = new Gui(name);
}

struct Vec3 {
	float x, y, z;
	Vec3 operator-() const { Vec3 r; r.x = -x; r.y = -y; r.z = -z; return r; }
};

struct Mat3 {
	Vec3 rows[3];
	const Vec3 &operator[](int i) const { return rows[i]; }
};

struct Camera {
	Mat3 axis;
	bool flipAxis;
	int modelAxis;
	Vec3 GetAxis() const { return flipAxis ? -axis[modelAxis] : axis[modelAxis]; }
	Vec3 GetRow(int i) const { return axis[i]; }
	const Vec3 &RowRef(int i) const { return axis[i]; }
};

int main() {
	RenderEntity renderEntity;
	const char *names[3] = { "hud", "pda", "scoreboard" };
	for (int i = 0; i < 3; i++) {
		AddRenderGui(names[i], &renderEntity.gui[i]);
	}
	Camera camera;
	for (int i = 0; i < 3; i++) {
		camera.axis.rows[i].x = (float)i;
		camera.axis.rows[i].y = (float)(i * 2);
		camera.axis.rows[i].z = (float)(i * 3);
	}
	camera.modelAxis = 2;
	camera.flipAxis = true;
	Vec3 flipped = camera.GetAxis();
	camera.flipAxis = false;
	Vec3 plain = camera.GetAxis();
	Vec3 row = camera.axis[1];
	Vec3 copies[2] = { camera.axis[0], camera.axis[2] };
	Vec3 returned = camera.GetRow(2);
	Vec3 viaRef = camera.RowRef(1);
	printf("%s %s %.0f %.0f %.0f %.0f\n", renderEntity.gui[0]->Name(), renderEntity.gui[2]->Name(), flipped.y, plain.z, row.y, copies[1].z);
	printf("%.0f %.0f\n", returned.y, viaRef.z);
	return 0;
}
