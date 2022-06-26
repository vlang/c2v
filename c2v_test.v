module main

fn check_ct(str_typ string, expected string) {
	t := convert_type(str_typ)
	assert t.name == expected
	if t.name != expected {
		println('!!!' + t.name)
	}
}

fn test_convert_type() {
	check_ct('FuncDef *[23]', '[23]&FuncDef')
	check_ct('void (*)(void *, void *)', 'fn (voidptr, voidptr)')
	check_ct('const char **', '&&u8')
	check_ct('byte [20]', '[20]u8')
	check_ct('byte *', '&u8')
	check_ct('byte *:byte *', '&u8')
	check_ct('short', 'i16')
	check_ct('signed char', 'i8')
	check_ct('int **', '&&int')
	check_ct('void **', '&voidptr')
}

fn test_stringh_location() {
	n := new_node("|-FunctionDecl 0x7fdffa819d48 </usr/include/string.h:70:7> col:7 implicit memchr 'void *(const void *, int, unsigned long)' extern")
	println(n.location)
}

fn test_trim_underscore() {
	assert trim_underscores('__name') == 'name'
	assert trim_underscores('_name') == 'name'
}
