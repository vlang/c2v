// Another translation unit with a typedef of the same name for its own record.
typedef struct depth_view_s {
	int depth;
	struct depth_view_s *next;
} view_t;

static int Depth(const view_t *view) {
	int total = 0;
	for (const view_t *v = view; v; v = v->next) {
		total += v->depth;
	}
	return total;
}

int TotalDepth(int first, int second) {
	view_t tail = { second, 0 };
	view_t head = { first, &tail };
	return Depth(&head);
}
