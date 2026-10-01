#include <stdio.h>
#include <string.h>

class Decl {
public:
	const char *name;
	Decl *self;
	Decl() { name = "decl"; self = NULL; Describe("ctor"); }
	virtual ~Decl() {}
	virtual const char *Kind() const { return "decl"; }
	virtual int Parse(const char *text) { return (int)strlen(text); }
	virtual Decl *Clone() const { return new Decl(*this); }
	void Describe(const char *when) const { printf("%s %s %s\n", when, name, Kind()); }
	int Load(const char *text) { return self ? self->Parse(text) : Parse(text); }
};

class Material : public Decl {
public:
	int stages;
	Material() { stages = 0; name = "material"; }
	const char *Kind() const { return "material"; }
	int Parse(const char *text) {
		stages = 0;
		for (const char *p = text; *p; p++) {
			if (*p == '{') {
				stages++;
			}
		}
		return stages * 100 + Decl::Parse(text);
	}
	Material *Clone() const { return new Material(*this); }
};

class Plain {
public:
	int x;
};

class Table : public Decl {
public:
	Plain plain;
};

class SortedTable : public Table {
public:
	const char *Kind() const { return "sorted"; }
};

static int Use(Decl &decl, const char *text) {
	return decl.Parse(text) + (int)strlen(decl.Kind());
}

int main() {
	Decl *decls[4];
	decls[0] = new Decl();
	decls[1] = new Material();
	decls[2] = new Table();
	decls[3] = new SortedTable();
	for (int i = 0; i < 4; i++) {
		Decl *holder = new Decl();
		holder->self = decls[i];
		Decl *copy = decls[i]->Clone();
		printf("%s %d %d %s\n", decls[i]->Kind(), holder->Load("{ a } { b }"), Use(*decls[i], "{x}"), copy->Kind());
		decls[i]->Describe("later");
		delete copy;
		delete holder;
	}
	SortedTable local;
	Table &table = local;
	printf("%s %d\n", table.Kind(), ((Material *)decls[1])->stages);
	for (int i = 0; i < 4; i++) {
		delete decls[i];
	}
	return 0;
}
