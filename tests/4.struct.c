#include <stdio.h>

struct User {
	char *name;
	int age;
};

// lots of structs are typedef'ed in C
typedef struct {
	char *name;
	int age;
} TUser;

/*
enum Color {
	red, green, blue,
};
*/

void handle_user(struct User user) {

}

void handle_tuser(TUser user) {

}

int main() {
	struct User user;
	user.age = 20;
	user.name = "Bob";
	printf("age=%d", user.age);
	handle_user(user);
	// TODO
	// struct User user2 = { .age = 30, .name = "Peter" };
	TUser user2;
	user2.age = 30;
	user2.name = "Peter";
	handle_tuser(user2);
	return 0;
}
