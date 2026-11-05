import os

// Wrappers are checked against a C library compiled on its own, the way they
// are used: a V program imports the generated module and calls into the C code.

struct WrappedLibrary {
	dir  string
	path string // the generated wrapper module directory
}

fn wrap_c_library(name string, header string, source string) !WrappedLibrary {
	root := os.dir(@FILE)
	build := os.exec([@VEXE, '-o', 'c2v', '-w', root])
	if build.exit_code != 0 {
		return error(build.output)
	}
	dir := os.join_path(os.vtmp_dir(), 'c2v_wrapper_${name}_${os.getpid()}')
	module_dir := os.join_path(dir, name)
	os.rmdir_all(dir) or {}
	os.mkdir_all(module_dir)!
	header_path := os.join_path(module_dir, '${name}.h')
	os.write_file(header_path, header)!
	os.write_file(os.join_path(module_dir, '${name}_impl.c'), source)!
	wrapped := os.exec([os.join_path(root, 'c2v'), 'wrapper', header_path])
	if wrapped.exit_code != 0 {
		return error(wrapped.output)
	}
	// The wrapper declares the C API; the program still has to build the C side.
	os.write_file(os.join_path(module_dir, 'native.c.v'),
		'module ${name}\n\n#flag @VMODROOT/${name}_impl.c\n')!
	os.write_file(os.join_path(dir, 'v.mod'), "Module { name: 'c2v_wrapper_test' }\n")!
	return WrappedLibrary{
		dir:  dir
		path: module_dir
	}
}

fn run_with_wrapper(lib WrappedLibrary, program string) os.Result {
	main_path := os.join_path(lib.dir, 'main.v')
	os.write_file(main_path, program) or { panic(err) }
	exe_path := os.join_path(lib.dir, 'main')
	// (Built apart from the run: only the program's own output is checked.)
	build := os.exec([@VEXE, '-path', '${lib.dir}|@vlib|@vmodules', '-o', exe_path, main_path])
	if build.exit_code != 0 {
		return build
	}
	return os.exec([exe_path])
}

fn test_wrapper_types_and_fields_are_public() {
	lib := wrap_c_library('point', 'typedef enum Axis { AXIS_X, AXIS_Y } Axis;\ntypedef struct Point { int x; int y; } Point;\nint point_get(const Point *p, Axis axis);\nPoint *point_origin(void);\n',
		'#include "point.h"\nstatic Point origin = {0, 7};\nint point_get(const Point *p, Axis axis) { return axis == AXIS_X ? p->x : p->y; }\nPoint *point_origin(void) { return &origin; }\n') or {
		panic(err)
	}
	defer { os.rmdir_all(lib.dir) or {} }
	// Another module builds the wrapper's struct, reads its fields and passes
	// its enum: all of that must be public.
	res := run_with_wrapper(lib, 'import point\n\nfn main() {\n\tp := point.Point{\n\t\tx: 2\n\t\ty: 40\n\t}\n\tprintln(point.get(&p, point.Axis.axis_y))\n\tprintln(point.origin().y)\n}\n')
	assert res.exit_code == 0, res.output
	assert res.output.trim_space() == '40\n7', res.output
}

fn test_bitfields_have_the_c_layout() {
	fixtures := os.join_path(os.dir(@FILE), 'tests_wrapper', 'bitfields')
	lib := wrap_c_library('bits', os.read_file(os.join_path(fixtures, 'bits.h'))!,
		os.read_file(os.join_path(fixtures, 'bits_impl.c'))!) or { panic(err) }
	defer { os.rmdir_all(lib.dir) or {} }
	wrapper := os.read_file(os.join_path(lib.path, 'bits.v'))!
	assert wrapper.contains('@[aligned: 8]\npub struct Mixed {'), wrapper
	res := run_with_wrapper(lib, os.read_file(os.join_path(fixtures, 'main.v'))!)
	assert res.exit_code == 0, res.output
	assert res.output.trim_space() == [
		'sizes 8=8 8=8 16=16 4=4 8=8 12=12 12=12',
		'offsets 14=14 9=9',
		'glyph 1 0 9 1f600 7.5',
		'gap -31072 z',
		'mixed -11 true mode_d abcdef0123 -2',
		'anon 5 77',
		'after 65 6 q',
		'check 1',
	].join('\n'), res.output
}

fn test_variadic_function_is_called_through_its_c_declaration() {
	lib := wrap_c_library('vsum', 'int vsum(int n, ...);\n',
		'#include <stdarg.h>\nint vsum(int n, ...) {\n\tva_list ap;\n\tva_start(ap, n);\n\tint s = 0;\n\tfor (int i = 0; i < n; i++) s += va_arg(ap, int);\n\tva_end(ap);\n\treturn s;\n}\n') or {
		panic(err)
	}
	defer { os.rmdir_all(lib.dir) or {} }
	wrapper := os.read_file(os.join_path(lib.path, 'vsum.v'))!
	assert wrapper.contains('fn C.vsum(n i32, ...) i32'), wrapper
	// A V function cannot pass C variadic arguments on; a wrapper would drop them.
	assert !wrapper.contains('pub fn vsum'), wrapper
	res := run_with_wrapper(lib, 'import vsum as _\n\nfn main() {\n\tprintln(C.vsum(3, 1, 2, 39))\n}\n')
	assert res.exit_code == 0, res.output
	assert res.output.trim_space() == '42', res.output
}
