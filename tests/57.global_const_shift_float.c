#define FRACBITS 16
#define FRACUNIT (1 << FRACBITS)

typedef int fixed_t;

static fixed_t scale = (fixed_t)(.2 * FRACUNIT);

int get_scale(void) {
    return scale;
}
