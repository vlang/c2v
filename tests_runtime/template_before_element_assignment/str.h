#pragma once
#include <string.h>
#include <stdlib.h>

class Str {
public:
	char *data;
	int len;
	char base[8];
	Str() { data = base; len = 0; base[0] = 0; }
	Str(const char *s);
	void operator=(const Str &o);
	void operator=(const char *s);
	const char *c_str() const { return data; }
private:
	void Set(const char *s);
};

inline Str::Str(const char *s) { data = base; len = 0; base[0] = 0; Set(s); }
inline void Str::operator=(const Str &o) { Set(o.data); }
inline void Str::operator=(const char *s) { Set(s); }
inline void Str::Set(const char *s) {
	int l = (int)strlen(s);
	if (data == base && l >= 8) { data = (char *)malloc(l + 1); }
	else if (data != base && l >= 8) { data = (char *)realloc(data, l + 1); }
	strcpy(data, s);
	len = l;
}
