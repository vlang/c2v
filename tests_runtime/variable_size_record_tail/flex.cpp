#include <stdio.h>
#include <stdlib.h>

typedef struct polygon_s {
	int numEdges;
	float area;
	int edges[1];	// variable sized
} polygon_t;

struct Brush {
	int numPlanes;
	float planes[1];	// variable sized
};

polygon_t *AllocPolygon(int numEdges) {
	polygon_t *p = (polygon_t *)malloc(sizeof(polygon_t) + (numEdges - 1) * sizeof(p->edges[0]));
	p->numEdges = numEdges;
	return p;
}

int main() {
	polygon_t *p = AllocPolygon(5);
	for (int i = 0; i < p->numEdges; i++) {
		p->edges[i] = i * i;
	}
	Brush *b = (Brush *)malloc(sizeof(Brush) + 3 * sizeof(float));
	b->numPlanes = 4;
	for (int i = 0; i < b->numPlanes; i++) {
		b->planes[i] = i + 0.5f;
	}
	int sum = 0;
	for (int i = 0; i < p->numEdges; i++) {
		sum += p->edges[i];
	}
	printf("%d %d %.1f %d\n", sum, p->edges[4], b->planes[3], (int)sizeof(p->edges));
	return 0;
}
