extern const unsigned short int **__ctype_b_loc(void);

enum {
	_ISspace = 8192
};

int first_is_space(char *text) {
	return (*__ctype_b_loc())[(int)text[0]] & _ISspace;
}
