#include <stdio.h>

volatile int a = 7;
volatile int b = 11;
volatile int c = 13;
volatile int selector = 1;
const volatile int fixed = 17;
typedef const volatile int Fixed;
Fixed aliased_fixed = 19;
struct Register { volatile int value; };
Register left_register = {23};
Register right_register = {29};
int address_calls = 0;
int trace = 0;

void effect(int digit) { trace = trace * 10 + digit; }
volatile int *next_a() { ++address_calls; return &a; }
volatile int *next_b() { ++address_calls; return &b; }
Register *next_left() { ++address_calls; return &left_register; }
Register *next_right() { ++address_calls; return &right_register; }
volatile int &reference_a() { ++address_calls; return a; }
volatile int &reference_b() { ++address_calls; return b; }

void read_select(bool flag) { (void)(flag ? a : b); }
void read_nested(bool first, bool second) { (void)(first ? (second ? a : b) : c); }
void read_pointer(bool flag, volatile int *left, volatile int *right) {
    (void)(flag ? *left : *right);
}
void read_member(bool flag, Register *left, Register *right) {
    (void)(flag ? (*left).value : right->value);
}
void read_reference(bool flag, volatile int &left, volatile int &right) {
    (void)(flag ? left : right);
}
void read_const_reference(bool flag, const volatile int &left, const volatile int &right) {
    (void)(flag ? left : right);
}
void read_alias_reference(bool flag, Fixed &left, Fixed &right) {
    (void)(flag ? left : right);
}
void read_const_direct(const volatile int &reg) { (void)reg; }
void read_address_call(bool flag) { (void)(flag ? *next_a() : *next_b()); }
void read_member_call(bool flag) { (void)(flag ? next_left()->value : next_right()->value); }
void read_reference_call(bool flag) { (void)(flag ? reference_a() : reference_b()); }
void read_volatile_reference_call() { (void)(selector ? reference_a() : reference_b()); }
void read_comma() { (void)(effect(1), a); }
void read_branch_comma(bool flag) { (void)(flag ? (effect(2), a) : (effect(3), b)); }
void read_nested_comma() { (void)(effect(4), (effect(5), c)); }
void read_pure_comma() { (void)(1, a); }
void read_volatile_comma() { (void)(b, a); }
void read_volatile_condition() { (void)(selector ? a : b); }
void read_increment_comma() { (void)(address_calls++, a); }
void read_branch_increment(bool flag) {
    (void)(flag ? (++address_calls, a) : (address_calls++, b));
}

int main() {
    read_select(false);
    read_select(true);
    read_nested(false, true);
    read_nested(true, false);
    read_nested(true, true);
    read_pointer(false, nullptr, &b);
    read_pointer(true, &a, nullptr);
    read_member(false, nullptr, &right_register);
    read_member(true, &left_register, nullptr);
    read_reference(false, a, b);
    read_reference(true, a, b);
    read_const_reference(false, fixed, a);
    read_const_reference(true, fixed, a);
    read_alias_reference(false, fixed, aliased_fixed);
    read_alias_reference(true, fixed, aliased_fixed);
    read_const_direct(fixed);
    read_const_direct(next_left()->value);
    read_const_direct(*next_a());
    read_address_call(false);
    read_address_call(true);
    read_member_call(false);
    read_member_call(true);
    read_reference_call(false);
    read_reference_call(true);
    read_volatile_reference_call();
    read_comma();
    read_branch_comma(true);
    read_branch_comma(false);
    read_nested_comma();
    read_pure_comma();
    read_volatile_comma();
    read_volatile_condition();
    read_increment_comma();
    read_branch_increment(false);
    read_branch_increment(true);
    read_const_direct(selector ? fixed : a);
    read_const_direct((effect(6), fixed));
    printf("%d %d\n", address_calls, trace);
    return 0;
}
