#include <stdint.h>

struct P {
	int n_tab;
	unsigned ref;
};

static int bump(struct P *p, int k) {
	p->n_tab += k;
	return p->n_tab;
}

int next_cursor(struct P *p) {
	const int cursor = p->n_tab++;
	int other = p->n_tab--;
	return cursor + other;
}

void discard(struct P *p) {
	(void)bump(p, 1);
	p->n_tab ? (void)bump(p, 2) : (void)0;
}

int release(struct P *p, int measuring) {
	if (measuring == 0 && (--p->ref) > 0) {
		return 0;
	}
	return 1;
}

int copy_varint(unsigned char *out, unsigned char *in, unsigned char *stop) {
	unsigned char *start = out;
	while (((*(out++) = *(in++)) & 0x80) && in < stop)
		;
	return (int)(out - start);
}

signed char narrow(int x) {
	int8_t small = (int8_t)x;
	return small < 0 ? -1 : small;
}

const char *pick(int k, int i) {
	if (k) {
		static const char *names[] = {"a", "b", 0};
		return names[i];
	} else {
		static const char *names[] = {"x", 0};
		return names[i];
	}
}
