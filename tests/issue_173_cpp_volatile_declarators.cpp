#include <stdio.h>

typedef int Scalar;
typedef long Wide;
Scalar watched = 17;
volatile Wide wide_storage = 19;
Scalar *volatile pointer_storage = &watched;

int callback_target(int value) { return value + 1; }
int (*volatile callback_storage)(int) = callback_target;

typedef int Row[3];
Row row = {3, 5, 7};
Row *volatile row_storage = &row;

void read_scalar(bool flag) {
    flag ? static_cast<void>(wide_storage) : static_cast<void>(0);
}

void read_alias(bool flag) {
    flag ? static_cast<void>(pointer_storage) : static_cast<void>(0);
}

void read_callback(bool flag) {
    flag ? static_cast<void>(callback_storage) : static_cast<void>(0);
}

void read_row(bool flag) {
    flag ? static_cast<void>(row_storage) : static_cast<void>(0);
}

int main() {
    read_scalar(false);
    read_alias(false);
    read_callback(false);
    read_row(false);
    read_scalar(true);
    read_alias(true);
    read_callback(true);
    read_row(true);
    printf("%d %d\n", callback_target(watched), row[1]);
    return 0;
}
