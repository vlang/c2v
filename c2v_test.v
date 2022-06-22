module main

// import os

/*
fn test_nt_from_str() {
println('FSDFDSF')

s := '|   |   |-public false_type:struct std::__1::integral_constant<_Bool, false>'

	mut typ := node_type_from_str(s)
println(typ)
}
*/
fn new_node(line string) Node {
	mut c := C2V{}
	return c.parse_node(line)
}

fn test_get_vals() {
	// s := '| `-FunctionDecl 0x7f83f0cfb990 <line:205:1, line:208:43> line:205:9 used SanitizeOptions \'struct leveldb::Options (const std::string &, const class leveldb::InternalKeyC2Varator *, const class leveldb::InternalFilterPolicy *, const struct leveldb::Options &)\''
	/*
	s := 'ParmVarDecl 0x7f94d9026d70 <col:51, col:56> col:56 used pnOpt int \'int*\''
	mut n := Node{}
	n.get_vals(s)
	n.print()
	println('typ=$n.typ')
	*/

	/*
	println(123)
	mut s := '|-RecordDecl 0x7fef3e026720 <test/a.c:3:1, line:5:1> line:3:8 struct User definition'
	mut n := new_node(s)
	// mut n := Node{}
	// n.get_vals(s)
	n.print()
	println('"$n.location"')
	println(n.id)
	assert n.typ == .RecordDecl
	assert n.styp == 'RecordDecl'
	assert n.id == '0x7fef3e026720'
	assert n.indent == 2
	assert n.vals.len == 3
	assert n.vals[0] == 'struct'
	assert n.vals[1] == 'User'
	assert n.vals[2] == 'definition'
	assert n.location == '<test/a.c:3:1,line:5:1>line:3:8'
	// println(node_type_from_str(s))
	// assert node_type_from_str(s) == RecordDecl
	// ////////////////////////////////////
	s = "| `-FieldDecl 0x7fce5f876a00 <line:4:2, col:6> col:6 referenced age 'int'"
	n = new_node(s)
	assert n.typ == .FieldDecl
	assert n.vals.len == 3
	assert n.vals.last() == 'int'
	// ///////////////
	s = "`-FunctionDecl 0x7fef3e076aa0 <line:7:1, line:15:1> line:7:5 main 'int ()'"
	n = new_node(s)
	assert n.typ == .FunctionDecl
	assert n.vals[0] == 'main'
	// //////////////////////
	s = '|-RecordDecl 0x7f821c172ad0 <line:32532:1, line:32537:1> line:32532:8 struct vxworksFileId definition'
	// /////////////////
	s = "|-FunctionDecl 0x10c556658 prev 0x7f821c81fb28 <line:150466:12, line:150789:1> line:150466:16 used sqlite3_test_control 'int (int, ...)'"
	n = new_node(s)
	assert n.used
	// /////////////////
	s = "| |-FieldDecl 0x7f949788e4f8 <line:1801:3, col:30> col:9 referenced xClose 'int (*)(sqlite3_file *)'"
	n = new_node(s)
	fn_type := n.vals[2]
	typ := convert_type(fn_type)
	assert fn_type == 'int (*)(sqlite3_file *)' // make sure complex fn type is converted well
	assert typ.name == 'fn (&Sqlite3_file) int'
	// ///////////
	s = "|-FunctionDecl 0x7f86bb06e990 <line:55:1, ../doomtype.h:68:75> ../i_system.h:55:6 used I_Error 'void (const char *, ...) __attribute__((noreturn))' "
	n = new_node(s)
	n.print()
	// ////////////////////
	s = "|-VarDecl 0x7fce2f099b08 <line:75:1, /usr/include/sys/_types.h:52:33> r_draw.c:75:10 used background_buffer 'pixel_t *' cinit"
	n = new_node(s)
	assert n.vals[0] == 'background_buffer'
	// ///////
	n = new_node("`-VarDecl 0x7f8ee183bce0 <col:2, col:22> col:13 keeeek 'int' static cinit")
	mut nt := get_name_type(n)
	assert nt.name == 'keeeek'
	assert nt.typ.name == 'int'
	// ///////
	n = new_node("|   | `-VarDecl 0x7fb8e68b5970 parent 0x7fb8e5818ad0 <col:5, col:20> col:20 used advancedemo 'boolean':'boolean' extern")
	nt = get_name_type(n)
	assert nt.name == 'advancedemo'
	assert nt.typ.name == 'bool'
	// ///////
	n = new_node("|   | `-VarDecl 0x7f9fa406dfe8 <col:5, col:27> col:17 used exitmsg 'char [80]' static")
	nt = get_name_type(n)
	assert nt.name == 'exitmsg'
	assert nt.typ.name == '[80]i8'
	// ////////////
	n = new_node("|-VarDecl 0x7f9cde170608 <line:151:1, col:41> col:7 used consistancy 'byte [4][128]'")
	nt = get_name_type(n)
	assert nt.name == 'consistancy'
	assert nt.typ.name == '[4][128]u8'
	n.print()
	// ////////////
	n = new_node("| | | `-VarDecl 0x12e2520c0 <col:5, <built-in>:38:21> doom/p_spec.c:397:14 used height 'fixed_t':'int' cinit")
	mut nt2 := get_name_type(n)
	n.print()
	assert nt2.name == 'height'
	assert nt2.typ.name == 'int'
	*/
}

fn test_get_nt() {
	/*
	mut s := "|-VarDecl 0x7f821b826a00 <sqlite3.c:66:1, line:773:1> line:66:27 used sqlite3azC2VileOpt 'const char *const [2]' static cinit"
	mut n := new_node(s)
	n.print()
	nt := get_name_type(n)
	assert nt.name == 'sqlite3azC2VileOpt'
	assert nt.typ.name == '[2]&i8'
	*/
}

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

fn test_static() {
}

fn test_stringh_location() {
	n := new_node("|-FunctionDecl 0x7fdffa819d48 </usr/include/string.h:70:7> col:7 implicit memchr 'void *(const void *, int, unsigned long)' extern")
	println(n.location)
}

fn test_trim_underscore() {
	assert trim_underscores('__name') == 'name'
	assert trim_underscores('_name') == 'name'
}
