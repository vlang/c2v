#include <stdio.h>

int calls = 0;
int condition_calls = 0;
int constructions = 0;
volatile int watched = 17;

bool condition(bool value) {
    ++condition_calls;
    return value;
}

void touch(int digit) { calls = calls * 10 + digit; }
int return_digit(int digit) { touch(digit); return 42; }

struct Counted {
    Counted() { ++constructions; }
};

struct Member {
    void touch() { ::touch(9); }
};

void check(bool flag) {
    condition(flag) ? void(touch(1)) : void();
    flag ? void() : void(touch(2));
    flag ? void(return_digit(3)) : void(return_digit(4));
    flag ? void((touch(5), touch(6))) : void();
    flag ? void(flag ? void(touch(7)) : void()) : void();
    void(flag ? void(touch(8)) : void());
    Member member;
    flag ? void(member.touch()) : void();
    flag ? void(Counted{}) : void();
    flag ? void(watched + 1) : void();
    watched ? void() : void();
    printf("%d %d %d\n", calls, condition_calls, constructions);
}

int main() {
    check(false);
    check(true);
    return 0;
}
