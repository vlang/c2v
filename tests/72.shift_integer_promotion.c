struct mapthing {
	short x;
	unsigned short y;
	signed char z;
	unsigned char w;
};

int build_x(struct mapthing *m) {
	int a = m->x << 16;
	int b = m->y << 16;
	int c = m->z << 16;
	int d = m->w << 16;
	return a + b + c + d;
}
