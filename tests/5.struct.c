#include <stdio.h>

const int PI= 314;

struct User {
	char *name;
	int age;
};

// lots of structs are typedef'ed in C
typedef struct {
	char *name;
	int age;
} TUser;

// struct names have to be capitalized in V
struct small {
	int foo;
};

struct small3 {
	int foo;
};

struct small2 {
	struct small struct_field; // make sure field types are capitalized
	struct small* struct_field_ptr;
	struct small3** struct_field_ptr2;
};

void small_fn(struct small param) { // make sure arg types are capitalized

}

typedef unsigned int angle_t;

enum Color {
	red, green, blue,
};

void handle_user(struct User user) {

}

void handle_tuser(TUser user) {

}

void multi_assign() {
	int aa = 0;
	int bb = 10;
	int cc = 20;
	aa = bb = cc;
}

void x(int pi) {}

#define arrlen(array) (sizeof(array) / sizeof(*array))

static int *weapon_keys[] = { 0, 0, 0 };
void sizeof_array() {
	int x = 10;
	int c = sizeof(x);
	int n = arrlen(weapon_keys);
}

int checkcoord[12][4] =
{
    {3,0,2,1},
    {3,0,2,0},
    {3,1,2,0},
    {0,0,0,0},
    {2,0,2,1},
    {0,0,0,0},
    {3,1,3,0},
    {0,0,0,0},
    {2,0,3,1},
    {2,1,3,1},
    {2,1,3,0}
};

void i_error(char* s, ...) {
	puts(s);
}

static unsigned long long sixtyfour(void) {
	return 64;
}

typedef union {
	int a;
	char b;
} MyUnion;

int main() {
	struct User user;
	user.age = 20;
	user.name = "Bob";
	printf("age=%d", user.age);
	handle_user(user);

	unsigned long long sf = sixtyfour();
	printf("sixtyfour=%lld", sf);
	// TODO
	// struct User user2 = { .age = 30, .name = "Peter" };
	TUser user2;
	user2.age = 30;
	user2.name = "Peter";
	handle_tuser(user2);
	//
	struct small s; // make sure struct inits are capitalized
	struct small s2 = { .foo = 10 };
	x(PI); // make sure cap consts stay capitalized
	return 0;
}
