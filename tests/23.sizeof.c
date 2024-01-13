#include <unistd.h>
int main() {
  char hello[] = "Hello, unistd world!\n";
  write ( 1, hello, sizeof hello );
  return 0; }