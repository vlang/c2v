#include <stdio.h>

int constructed = 0;
int member_called = 0;
int operator_called = 0;
int destroyed = 0;

struct Counted {
    Counted() { ++constructed; }
    Counted(int value) { constructed += value; }
};

struct Trivial {
    Trivial() = default;
};

struct Callable {
    void method() { ++member_called; }
    void operator+=(int value) { operator_called += value; }
};

struct Managed {
    ~Managed() { ++destroyed; }
};

void check(bool flag) {
    flag ? static_cast<void>(Counted{}) : static_cast<void>(0);
    flag ? static_cast<void>(Counted(3)) : static_cast<void>(0);
    flag ? static_cast<void>(0) : static_cast<void>(Counted(7));
    flag ? static_cast<void>(Trivial()) : static_cast<void>(0);
    flag ? static_cast<void>(1 + 2) : static_cast<void>(0);
    Callable callable;
    flag ? static_cast<void>(callable.method()) : static_cast<void>(0);
    flag ? static_cast<void>(callable += 1) : static_cast<void>(0);
    flag ? static_cast<void>(new Counted()) : static_cast<void>(0);
    Managed *owned = new Managed;
    flag ? static_cast<void>(delete owned) : static_cast<void>(0);
    printf("%d %d %d %d\n", constructed, member_called, operator_called, destroyed);
    if (!flag) delete owned;
}

int main() {
    check(false);
    check(true);
    (void)Counted{};
    static_cast<void>(Counted{});
    (void)Trivial();
    static_cast<void>(Trivial());
    printf("%d\n", constructed);
    return 0;
}
