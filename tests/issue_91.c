#include <stdio.h>

void CheckName(void) {
    puts(__func__);
    puts(__FUNCTION__);
    puts(__PRETTY_FUNCTION__);
}

int main(void) {
    CheckName();
    return 0;
}
