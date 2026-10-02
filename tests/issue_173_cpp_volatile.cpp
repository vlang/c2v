#include <stdio.h>

volatile int watched = 7;
const volatile int watched_const = 17;
volatile long wide = 9;
volatile double floating = 3.5;
int ordinary = 5;
int *volatile storage = &ordinary;
volatile int *pointee = &watched;
typedef volatile int Vol;
Vol aliased = 11;
struct Registers { volatile short field; };
Registers registers = {13};
int address_calls = 0;

volatile int *next_register() {
    ++address_calls;
    return &watched;
}

void read_direct(bool flag) {
    flag ? static_cast<void>(watched) : static_cast<void>(0);
}

void read_const(bool flag) {
    flag ? static_cast<void>(watched_const) : static_cast<void>(0);
}

void read_arithmetic(bool flag) {
    flag ? static_cast<void>(watched + 1) : static_cast<void>(0);
}

void read_condition() {
    watched ? static_cast<void>(0) : static_cast<void>(0);
}

void read_wide(bool flag) {
    flag ? static_cast<void>(wide) : static_cast<void>(0);
}

void read_floating(bool flag) {
    flag ? static_cast<void>(floating) : static_cast<void>(0);
}

void read_pointer(bool flag) {
    flag ? static_cast<void>(storage) : static_cast<void>(0);
}

void read_pointee(bool flag) {
    flag ? static_cast<void>(*pointee) : static_cast<void>(0);
}

void read_alias(bool flag) {
    flag ? static_cast<void>(aliased) : static_cast<void>(0);
}

void read_member(bool flag) {
    flag ? static_cast<void>(registers.field) : static_cast<void>(0);
}

void read_reference(bool flag, volatile int &reg) {
    flag ? static_cast<void>(reg) : static_cast<void>(0);
}

void read_ordinary_pointer(bool flag) {
    flag ? static_cast<void>(pointee) : static_cast<void>(0);
}

void read_null(bool flag, volatile int *reg) {
    flag ? static_cast<void>(*reg) : static_cast<void>(0);
}

void read_once(bool flag) {
    flag ? static_cast<void>(*next_register() + 1) : static_cast<void>(0);
    printf("%d\n", address_calls);
}

int main() {
    read_direct(true);
    read_const(true);
    read_arithmetic(true);
    read_condition();
    read_wide(true);
    read_floating(true);
    read_pointer(true);
    read_pointee(true);
    read_alias(true);
    read_member(true);
    read_reference(true, watched);
    read_ordinary_pointer(true);
    read_null(false, nullptr);
    read_once(false);
    read_once(true);
    return 0;
}
