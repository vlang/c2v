typedef __builtin_va_list va_list;

int m_vsnprintf(char *buf, unsigned long buf_len, const char *s, va_list args);

int call_m_vsnprintf(char *buf, unsigned long buf_len, const char *s, va_list args) {
    return m_vsnprintf(buf, buf_len, s, args);
}
