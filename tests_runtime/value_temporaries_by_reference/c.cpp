#include <stdio.h>
#include <string.h>

// Temporaries bound to `const T &` parameters. A plain value (`a + b`,
// `Vec3(x, y, z)`) has no identity and lives for the full expression; an
// object pointing into itself (Text) must still be read through its own
// storage after it was constructed as a temporary.
class Vec3 {
public:
	float x, y, z;
	Vec3() {}
	Vec3(float x, float y, float z) { this->x = x; this->y = y; this->z = z; }
	Vec3 operator+(const Vec3 &a) const { return Vec3(x + a.x, y + a.y, z + a.z); }
	Vec3 operator-(const Vec3 &a) const { return Vec3(x - a.x, y - a.y, z - a.z); }
	Vec3 operator*(float a) const { return Vec3(x * a, y * a, z * a); }
	float operator*(const Vec3 &a) const { return x * a.x + y * a.y + z * a.z; }
	Vec3 Cross(const Vec3 &a) const { return Vec3(y * a.z - z * a.y, z * a.x - x * a.z, x * a.y - y * a.x); }
};

class Bounds {
public:
	Vec3 b[2];
	Bounds() {}
	Bounds(const Vec3 &mins, const Vec3 &maxs) { b[0] = mins; b[1] = maxs; }
	Vec3 Center() const { return (b[0] + b[1]) * 0.5f; }
	Bounds Expand(float d) const { return Bounds(b[0] - Vec3(d, d, d), b[1] + Vec3(d, d, d)); }
};

class Text {
public:
	char *data;
	int len;
	char buffer[16];
	Text(const char *text) { Set(text); }
	Text(const Text &other) { Set(other.data); }
	~Text() {}
	void Set(const char *text) {
		data = buffer;
		len = (int)strlen(text);
		memcpy(buffer, text, len + 1);
	}
	Text operator+(const Text &other) const {
		Text joined(data);
		memcpy(joined.buffer + len, other.data, other.len + 1);
		joined.len += other.len;
		return joined;
	}
};

class Shape {
public:
	virtual ~Shape() {}
	virtual float Distance(const Vec3 &point) const = 0;
};

class Plane : public Shape {
public:
	Vec3 normal;
	float dist;
	Plane(const Vec3 &n, float d) : normal(n), dist(d) {}
	float Distance(const Vec3 &point) const { return normal * point - dist; }
};

static float Sum(const Vec3 &v) { return v.x + v.y + v.z; }
static const Vec3 &Longer(const Vec3 &a, const Vec3 &b) { return a * a > b * b ? a : b; }
static float Volume(const Bounds &bounds) {
	Vec3 size = bounds.b[1] - bounds.b[0];
	return size.x * size.y * size.z;
}
static int Length(const Text &text) { return (int)strlen(text.data); }
static Text Greeting(const Text &name) { return Text("hi ") + name; }

static const Vec3 origin = Vec3(1.0f, 2.0f, 3.0f) + Vec3(0.5f, 0.5f, 0.5f);
static const float originSum = Sum(Vec3(1.0f, 2.0f, 3.0f) * 2.0f);

int main() {
	Vec3 a(1.0f, 2.0f, 3.0f), b(4.0f, 5.0f, 6.0f);
	float (*sum)(const Vec3 &) = Sum;
	Shape *shape = new Plane(Vec3(0.0f, 0.0f, 1.0f), 2.0f);

	printf("%g %g\n", Sum(a + b), Sum((a + b).Cross(a - b) * 2.0f));
	printf("%g\n", Sum(Longer(a + b, a - b)) + Sum(Longer(a * 0.5f, b * 0.25f)));
	printf("%g %g\n", sum(a * 3.0f), shape->Distance(a + b));
	printf("%g\n", Volume(Bounds(a, b).Expand(1.0f)) + Sum(Bounds(a - b, a + b).Center()));
	printf("%g %g\n", Sum(origin), originSum);

	float total = 0.0f;
	for (int i = 0; i < 1000; i++) {
		Vec3 step((float)i, 1.0f, 0.5f);
		total += Sum(i % 2 ? step + a : step - a);
		if (i > 500 && Sum(step * 2.0f) > 2000.0f) {
			total += shape->Distance(step.Cross(b) + Vec3(0.0f, 0.0f, (float)i));
		}
	}
	printf("%g\n", total);

	printf("%d %d %s\n", Length(Text("abc")), Length(Text("abc") + Text("defg")), Greeting(Text("bob")).data);
	delete shape;
	return 0;
}
