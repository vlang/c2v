#include <stdio.h>

volatile int watched = 7;
const volatile int watched_const = 17;
int address_calls = 0;

volatile int *next_register(void) {
    ++address_calls;
    return &watched;
}

void read_condition(void) {
    watched ? (void)0 : (void)0;
}

void read_const(void) {
    watched_const ? (void)0 : (void)0;
}

void read_selected(int flag, volatile int *reg) {
    flag ? (void)(watched + 1) : (void)0;
    flag ? (void)*reg : (void)0;
    flag ? (void)(*next_register() + 1) : (void)0;
    printf("%d\n", address_calls);
}

int main(void) {
    read_condition();
    read_const();
    read_selected(0, NULL);
    read_selected(1, &watched);
    return 0;
}
