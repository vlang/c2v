#include <stdio.h>

// One record under two names: its tag and a typedef. A virtual method declared
// with one name is overridden with the other.
struct view_s {
	int width;
	int height;
};
typedef struct view_s view_t;

int TotalDepth(int first, int second);

class System {
public:
	virtual ~System() {}
	virtual int Area(const struct view_s *view) const = 0;
	virtual void Resize(view_t *view, int scale) = 0;
};

class LocalSystem : public System {
public:
	int Area(const view_t *view) const { return view->width * view->height; }
	void Resize(struct view_s *view, int scale) {
		view->width *= scale;
		view->height *= scale;
	}
};

int main() {
	LocalSystem local;
	System *system = &local;
	view_t view = { 4, 3 };
	struct view_s *same = &view;
	system->Resize(same, 2);
	printf("%d %d %d\n", system->Area(&view), local.Area(same), TotalDepth(5, 7));
	return 0;
}
