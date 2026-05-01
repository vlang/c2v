struct texture {
	char name[8];
};

void copy_bytes(void *dest, const void *src, unsigned int n);

void copy_texture_name(struct texture *dst, struct texture *src) {
	copy_bytes(dst->name, src->name, sizeof(dst->name));
}
