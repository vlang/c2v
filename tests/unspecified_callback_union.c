typedef void (*action_v)();
typedef void (*action_p1)(void *);
typedef void (*action_p2)(void *, void *);

typedef union {
	action_v acv;
	action_p1 acp1;
	action_p2 acp2;
} action_t;

void add_one();
void add_pair();
void no_arguments(void);

static action_t actions[] = {{add_one}, {add_pair}, {no_arguments}};

void add_one(int *value) {
	*value += 1;
}

void add_pair(int *left, int *right) {
	*left += *right;
}

void no_arguments(void) {}

int main(void) {
	int value = 10;
	int other = 20;
	actions[0].acp1(&value);
	actions[1].acp2(&value, &other);
	actions[2].acv();
	return value == 31 ? 0 : 1;
}
