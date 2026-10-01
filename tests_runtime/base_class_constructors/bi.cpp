struct Base {
	int v;
	Base() { v = 7; }
	Base(int x) { v = x; }
};
struct Derived : public Base {
	int w;
	Derived() { w = 1; }
	Derived(int x) : Base(x * 2) { w = 2; }
};
struct Implicit : public Derived {
	int z;
};
int use() {
	Derived a;
	Derived b(5);
	Implicit c;
	Implicit *d = new Implicit;
	return a.v + b.v + a.w + b.w + c.v * 100 + c.w * 1000 + d->v * 10000;
}
