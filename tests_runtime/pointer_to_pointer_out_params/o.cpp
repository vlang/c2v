#include <stdio.h>
#include <stdlib.h>

typedef struct vertCache_s {
	int offset;
	int size;
	struct vertCache_s *next;
} vertCache_t;

struct srfTriangles_t {
	int numVerts;
	struct vertCache_s *ambientCache;
	struct vertCache_s *indexCache;
};

class VertexCache {
public:
	int used;
	VertexCache() : used(0) {}
	// Returns the new block through a pointer to the caller's pointer.
	void Alloc(void *data, int size, vertCache_t **buffer, bool indexBuffer = false) {
		(void)data;
		vertCache_t *block = (vertCache_t *)calloc(1, sizeof(vertCache_t));
		block->offset = used;
		block->size = size;
		used += size;
		*buffer = indexBuffer ? NULL : block;
	}
};

static VertexCache vertexCache;

static bool CreateAmbientCache(srfTriangles_t *tri) {
	if (tri->ambientCache) {
		return true;
	}
	vertexCache.Alloc(NULL, tri->numVerts * 16, &tri->ambientCache);
	return tri->ambientCache != NULL;
}

int main() {
	srfTriangles_t tris[3] = { { 4, NULL, NULL }, { 6, NULL, NULL }, { 2, NULL, NULL } };
	int created = 0;
	for (int i = 0; i < 3; i++) {
		created += CreateAmbientCache(&tris[i]);
		created += CreateAmbientCache(&tris[i]);
	}
	printf("%d %d %d %d\n", created, tris[1].ambientCache->offset, tris[2].ambientCache->size, vertexCache.used);
	return 0;
}
