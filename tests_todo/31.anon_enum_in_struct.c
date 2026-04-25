// Test for anonymous enums inside structs
// V doesn't support anonymous inline enum types like struct/union,
// so C2V needs to generate a named enum before the struct.

struct with_anon_enum {
  int id;
  enum { STATUS_OK, STATUS_ERROR } status;
};

struct with_anon_enum_values {
  enum { COLOR_RED = 1, COLOR_GREEN = 2, COLOR_BLUE = 4 } color;
  int intensity;
};
