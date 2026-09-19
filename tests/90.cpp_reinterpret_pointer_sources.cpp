struct Pair {
	float x;
	float y;

	bool clear() {
		x = 0.0f;
		return true;
	}
};

struct Triple {
	float x;
	float y;
	float z;

	Pair &pair() {
		return *reinterpret_cast<Pair *>(this);
	}

	Pair &pair_cstyle() {
		return *(Pair *)this;
	}
};

struct Values6 {
	float values[6];

	float *data() {
		return values;
	}

	Triple &part(int index) {
		return *reinterpret_cast<Triple *>(values + index * 3);
	}
};

struct Plane {
	float a;
	float b;
	float c;

	Triple &normal() {
		return *reinterpret_cast<Triple *>(&a);
	}
};

struct CachedPair {
	float x;
	float y;
	bool cached;

	CachedPair(float x, float y) : x(x), y(y), cached(false) {
	}
};

bool clear_pair(Triple *triple) {
	return reinterpret_cast<Pair *>(triple)->clear();
}

struct EvalValue {
	int value;
};

struct ValueDef {
	void set_value(const EvalValue &value, bool constant) {
	}
};

void pass_dereferenced_value(ValueDef *def, const EvalValue *value) {
	def->set_value(*value, true);
}

struct SurfaceBase {
};

struct SurfaceDerived : SurfaceBase {
	int marker;
};

void take_surface(SurfaceBase *surface) {
}

void pass_conditional_surface(bool use_null, SurfaceDerived *surface) {
	take_surface(use_null ? __null : surface);
}

void pass_dereferenced_surface(SurfaceDerived **surface) {
	take_surface(*surface);
}

int surface_pointer_offset(SurfaceDerived *item, SurfaceDerived *base) {
	return item - base;
}

struct SurfaceNode {
	SurfaceDerived child;
};

class SurfaceNodeList {
public:
	SurfaceNode *item;

	SurfaceNode *const &operator[](int index) const {
		return item;
	}
};

void pass_indexed_surface(SurfaceNodeList &list) {
	take_surface(&list[0]->child);
}

class SurfaceValueList {
public:
	SurfaceDerived item;

	SurfaceDerived &operator[](int index) {
		return item;
	}
};

void take_surface_reference(const SurfaceBase &surface) {
}

void pass_indexed_surface_value(SurfaceValueList &list) {
	take_surface_reference(list[0]);
}

class SurfacePointerValueList {
public:
	SurfaceDerived *item;

	SurfaceDerived *const &operator[](int index) const {
		return item;
	}
};

void pass_indexed_pointer_value(SurfacePointerValueList &list) {
	take_surface_reference(*list[0]);
}

void assign_indexed_pointer_value(SurfacePointerValueList &list) {
	list[0]->marker = 1;
}

void assign_indexed_surface_value(SurfaceValueList &list, SurfaceValueList &other) {
	list[0] = other[0];
}

class SurfaceThisList {
public:
	SurfaceDerived item;

	SurfaceDerived &operator[](int index) {
		return item;
	}

	void assign_from(SurfaceThisList &other) {
		(*this)[0] = other[0];
	}
};

typedef int cmp_t(const void *left, const void *right);

int compare_surface_pointers(const SurfaceDerived **left, const SurfaceDerived **right) {
	return 0;
}

void accept_surface_compare(cmp_t *compare) {
}

void pass_surface_compare() {
	accept_surface_compare((cmp_t *)&compare_surface_pointers);
}

CachedPair make_cached_pair() {
	return CachedPair(1.0f, 2.0f);
}
