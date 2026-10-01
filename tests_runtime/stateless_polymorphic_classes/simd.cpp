#include <stdio.h>

class Processor {
public:
	virtual ~Processor() {}
	virtual const char *GetName() const = 0;
	virtual float Dot(const float *a, const float *b, int n) = 0;
};

class Generic : public Processor {
public:
	virtual const char *GetName() const;
	virtual float Dot(const float *a, const float *b, int n);
};

const char *Generic::GetName() const { return "generic"; }
float Generic::Dot(const float *a, const float *b, int n) {
	float sum = 0;
	for (int i = 0; i < n; i++) {
		sum += a[i] * b[i];
	}
	return sum;
}

class Fast : public Generic {
public:
	virtual const char *GetName() const;
};

const char *Fast::GetName() const { return "fast"; }

class Shape {
public:
	virtual ~Shape() {}
	virtual int Sides() const;
	int Twice() const { return Sides() * 2; }
};

int Shape::Sides() const { return 0; }

class Square : public Shape {
public:
	int Sides() const { return 4; }
};

int main() {
	float a[3] = { 1, 2, 3 };
	float b[3] = { 4, 5, 6 };
	Processor *processors[2] = { new Generic(), new Fast() };
	for (int i = 0; i < 2; i++) {
		printf("%s %.1f\n", processors[i]->GetName(), processors[i]->Dot(a, b, 3));
	}
	Generic *generic = new Fast();
	printf("%s\n", generic->GetName());
	Shape *shape = new Square();
	printf("%d\n", shape->Twice());
	return 0;
}
