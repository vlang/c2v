typedef enum _alpm_siglevel_t {
  ALPM_SIG_PACKAGE = (1 << 0),
  ALPM_SIG_PACKAGE_OPTIONAL = (1 << 1),
  ALPM_SIG_PACKAGE_MARGINAL_OK = (1 << 2),
  ALPM_SIG_PACKAGE_UNKNOWN_OK = (1 << 3),
  ALPM_SIG_DATABASE = (1 << 10),
  ALPM_SIG_DATABASE_OPTIONAL = (1 << 11),
  ALPM_SIG_DATABASE_MARGINAL_OK = (1 << 12),
  ALPM_SIG_DATABASE_UNKNOWN_OK = (1 << 13),
  ALPM_SIG_USE_DEFAULT = (1 << 30)
} alpm_siglevel_t;

enum shift_values {
  SHIFT_BASE = 1,
  SHIFT_LEFT = (1U << 5),
  SHIFT_ALIAS = (1 << 5),
  SHIFT_AFTER_ALIAS,
  SHIFT_RIGHT = 64 >> 2,
  SHIFT_COMBINED = (1 << 1) | (1 << 3),
  SHIFT_PRECEDENCE = (1 + 2) << (2 + 1),
  SHIFT_NESTED = (1 << 2) << 1,
  SHIFT_NEGATIVE = -(1 << 2),
  SHIFT_RIGHT_NEGATIVE = -32 >> 1,
  SHIFT_REFERENCE = SHIFT_BASE << 6,
  SHIFT_UNSIGNED = (~0U) >> 1
};

int main(void) {
  alpm_siglevel_t level = ALPM_SIG_DATABASE;
  enum shift_values alias = SHIFT_ALIAS;
  enum shift_values after = SHIFT_AFTER_ALIAS;
  return 0;
}
