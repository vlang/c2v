enum shifted {
  NEG = -1,
  VALUE = (-NEG) << 1,
  FOLDED = -(~0) << 2
};

enum {
  ANON_NEG = -1,
  ANON_VALUE = (-ANON_NEG) << 1,
  ANON_FOLDED = -(~0) << 2
};

int main(void) {
  enum shifted named = VALUE;
  int anonymous = ANON_VALUE;
  int folded = ANON_FOLDED;
  return 0;
}
