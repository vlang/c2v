import os

fn testsuite_begin() {
	os.chdir(os.dir(@FILE))!
}

fn test_verify_formatting_of_source_code() {
	res := os.system('${os.quoted_path(@VEXE)} fmt -verify .')
	assert res == 0
	println('> source code is formatted, good')
}

fn test_verify_formatting_of_markdown_docs() {
	res := os.system('${os.quoted_path(@VEXE)} check-md .')
	assert res == 0
	println('> markdown documentation is formatted, good')
}

fn test_dir_mode_emits_c_extern_alias_for_extern_uppercase_global() {
	tmp_dir := os.join_path(os.temp_dir(), 'c2v_dir_global_test')
	os.rmdir_all(tmp_dir) or {}
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}
	os.write_file(os.join_path(tmp_dir, 'c2v.toml'), '[project]\noutput_dirname = "out"\nadditional_flags = "-I."\n') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'item.h'), 'typedef struct {\n    int value;\n} Item_t;\n\ntypedef enum {\n    item_low,\n    item_high\n} item_kind_t;\n\nextern Item_t S_items[2];\nint pick_item(item_kind_t kind);\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'a.c'), '#include "item.h"\n\nint get_item_value(int idx) {\n    return S_items[idx].value + pick_item(item_high);\n}\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'b.c'), '#include "item.h"\n\nItem_t S_items[2] = {\n    {1},\n    {2}\n};\n\nint pick_item(item_kind_t kind) {\n    return kind;\n}\n') or {
		panic(err)
	}

	build_res := os.execute('${os.quoted_path(@VEXE)} -o c2v -experimental -w .')
	assert build_res.exit_code == 0
	if build_res.exit_code != 0 {
		eprintln(build_res.output)
	}
	c2v_res :=
		os.execute('${os.quoted_path(os.join_path(os.getwd(), 'c2v'))} ${os.quoted_path(tmp_dir)}')
	assert c2v_res.exit_code == 0
	if c2v_res.exit_code != 0 {
		eprintln(c2v_res.output)
	}
	out_dir := os.join_path(tmp_dir, 'out')
	globals := os.read_file(os.join_path(out_dir, '0_globals.v')) or { panic(err) }
	assert globals.contains('@[c_extern]\n__global C.S_items [2]Item_t')
	assert globals.contains('@[weak] __global S_items [2]Item_t')

	check_res := os.execute('${os.quoted_path(@VEXE)} -translated -cflags -c -o ${os.quoted_path(os.join_path(tmp_dir, 'out.o'))} ${os.quoted_path(out_dir)}')
	assert check_res.exit_code == 0
	if check_res.exit_code != 0 {
		eprintln(check_res.output)
	}
}

fn test_dir_mode_qualifies_translation_unit_static_globals() {
	tmp_dir := os.join_path(os.temp_dir(), 'c2v_static_global_test')
	os.rmdir_all(tmp_dir) or {}
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}
	os.write_file(os.join_path(tmp_dir, 'c2v.toml'), '[project]\noutput_dirname = "out"\nadditional_flags = "-I."\nsingle_module = true\ngenerate_stubs = false\nrequire_no_stubs = true\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'a.c'), 'static int values[2];\nint a_value(void) { values[0] = 1; return values[0]; }\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'b.c'), 'static int values[2];\nint b_value(void) { values[0] = 2; return values[0]; }\n') or {
		panic(err)
	}

	build_res := os.execute('${os.quoted_path(@VEXE)} -o c2v -experimental -w .')
	assert build_res.exit_code == 0
	if build_res.exit_code != 0 {
		eprintln(build_res.output)
	}
	c2v_res :=
		os.execute('${os.quoted_path(os.join_path(os.getwd(), 'c2v'))} ${os.quoted_path(tmp_dir)}')
	assert c2v_res.exit_code == 0
	if c2v_res.exit_code != 0 {
		eprintln(c2v_res.output)
	}
	out_dir := os.join_path(tmp_dir, 'out')
	globals := os.read_file(os.join_path(out_dir, '0_globals.v')) or { panic(err) }
	assert globals.contains('__global c2v_static_global_test_a_values')
	assert globals.contains('__global c2v_static_global_test_b_values')
	a_output := os.read_file(os.join_path(out_dir, 'a.v')) or { panic(err) }
	b_output := os.read_file(os.join_path(out_dir, 'b.v')) or { panic(err) }
	assert a_output.contains('c2v_static_global_test_a_values[0]')
	assert b_output.contains('c2v_static_global_test_b_values[0]')

	check_res := os.execute('${os.quoted_path(@VEXE)} -translated -cflags -c -o ${os.quoted_path(os.join_path(tmp_dir, 'out.o'))} ${os.quoted_path(out_dir)}')
	assert check_res.exit_code == 0
	if check_res.exit_code != 0 {
		eprintln(check_res.output)
	}
}

fn test_dir_mode_synthesizes_late_abstract_default_methods() {
	tmp_dir := os.join_path(os.temp_dir(), 'c2v_abstract_default_method_test')
	os.rmdir_all(tmp_dir) or {}
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}
	os.write_file(os.join_path(tmp_dir, 'c2v.toml'), '[project]\noutput_dirname = "out"\nadditional_flags = "-I."\nsingle_module = true\ngenerate_stubs = false\nrequire_no_stubs = true\nsource_manifest = "sources.txt"\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'sources.txt'), 'a.cpp\nb.cpp\n') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'abstract.h'), '#pragma once\nclass AbstractConfig {\npublic:\n    int value;\n    int get_value() const { return value; }\n    virtual void set_value(int next) = 0;\n};\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'derived.h'), '#pragma once\n#include "abstract.h"\nclass ConcreteConfig : public AbstractConfig {\npublic:\n    void set_value(int next) { value = next; }\n};\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'a.cpp'), '#include "abstract.h"\nint read_abstract(AbstractConfig *config) { return config->get_value(); }\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'b.cpp'), '#include "derived.h"\nint read_concrete(ConcreteConfig *config) { return config->get_value(); }\n') or {
		panic(err)
	}

	build_res := os.execute('${os.quoted_path(@VEXE)} -o c2v -experimental -w .')
	assert build_res.exit_code == 0
	if build_res.exit_code != 0 {
		eprintln(build_res.output)
	}
	c2v_res :=
		os.execute('${os.quoted_path(os.join_path(os.getwd(), 'c2v'))} ${os.quoted_path(tmp_dir)}')
	assert c2v_res.exit_code == 0
	if c2v_res.exit_code != 0 {
		eprintln(c2v_res.output)
	}
	out_dir := os.join_path(tmp_dir, 'out')
	a_output := os.read_file(os.join_path(out_dir, 'a.v')) or { panic(err) }
	b_output := os.read_file(os.join_path(out_dir, 'b.v')) or { panic(err) }
	// A method that does not change its object takes it by reference.
	assert a_output.contains('fn (this &AbstractConfig) get_value() int')
	assert b_output.contains('fn (this &ConcreteConfig) get_value() int')
	assert b_output.contains('fn (this &ConcreteConfig) c2v_default_get_value() int')

	check_res := os.execute('${os.quoted_path(@VEXE)} -translated -cflags -c -o ${os.quoted_path(os.join_path(tmp_dir, 'out.o'))} ${os.quoted_path(out_dir)}')
	assert check_res.exit_code == 0
	if check_res.exit_code != 0 {
		eprintln(check_res.output)
	}
}

// A strict C++ project exercising general C++ rules end to end: it must build
// with V and compute the same results as the C++ program.
fn test_strict_cpp_project_runs_like_native() {
	tmp_dir := os.join_path(os.temp_dir(), 'c2v_strict_cpp_runtime_test')
	os.rmdir_all(tmp_dir) or {}
	os.mkdir_all(tmp_dir) or { panic(err) }
	defer {
		os.rmdir_all(tmp_dir) or {}
	}
	os.write_file(os.join_path(tmp_dir, 'c2v.toml'), '[project]\noutput_dirname = "out"\nadditional_flags = "-I."\nsingle_module = true\ngenerate_stubs = false\nrequire_no_stubs = true\nrequire_main = true\nsource_manifest = "sources.txt"\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'sources.txt'), 'a.cpp\nb.cpp\n') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'lib.h'), '#pragma once
void DefinedNowhere(int &value);
class Limits {
public:
	static const int MAX_ARGS = 64;
	static const int MAX_STRING = 2 * MAX_ARGS;
	int argc;
	int Limit() const;
	void NeverUsed() { DefinedNowhere(argc); }
};
class Shape {
public:
	virtual int Area() const = 0;
	virtual ~Shape() {}
};
class Square : public Shape {
public:
	int side;
	Square(int s) : side(s) {}
	int Area() const { return side * side; }
};
template<class type> class List {
public:
	typedef int cmp_t(const type *, const type *);
	type *items;
	int num;
	List() : items(0), num(0) {}
	void Append(type value) {
		type *old = items;
		items = new type[num + 1];
		for (int i = 0; i < num; i++) { items[i] = old[i]; }
		items[num] = value;
		num++;
		delete[] old;
	}
	type &operator[](int i) { return items[i]; }
	int Compare(cmp_t *compare) { return compare(&items[0], &items[1]); }
};
class Base;
typedef void (Base::*callback_t)(void);
class Base {
public:
	int total;
	Base() : total(0) {}
	void Add(int v) { total += v; }
	void Mul(int a, int b) { total += a * b; }
	void Dispatch(callback_t cb, int argc, const int *data) {
		if (argc == 1) {
			typedef void (Base::*callback_1_t)(int);
			(this->*(callback_1_t)cb)(data[0]);
		} else {
			typedef void (Base::*callback_2_t)(int, int);
			(this->*(callback_2_t)cb)(data[0], data[1]);
		}
	}
};
class Derived : public Base {
public:
	int extra;
};
struct Name {
	int len;
};
typedef Name *namePtr;
template<class type> int CompareItems(const type *a, const type *b) { return a->len - b->len; }
template<> inline int CompareItems<namePtr>(const namePtr *a, const namePtr *b) {
	return (*b)->len - (*a)->len;
}
template<class namePtr> int ComparePaths(const namePtr *a, const namePtr *b) { return 0; }
template<class T> void SwapValues(T &a, T &b) {
	T c = a;
	a = b;
	b = c;
}
') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'a.cpp'), '#include "lib.h"\nint first_unit() {\n\tint x = 1;\n\tint y = 2;\n\tSwapValues(x, y);\n\treturn x;\n}\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'b.cpp'), '#include "lib.h"
int Limits::Limit() const { return argc < MAX_ARGS ? MAX_STRING : 0; }
int cmpInt(const int *a, const int *b) { return *a - *b; }
int main() {
	int failures = 0;
	Limits limits;
	limits.argc = 3;
	failures += limits.Limit() == 128 ? 0 : 1;
	List<Shape *> shapes;
	shapes.Append(new Square(1));
	shapes.Append(new Square(2));
	shapes.Append(new Square(3));
	int area = 0;
	for (int i = 0; i < shapes.num; i++) { area += shapes[i]->Area(); }
	failures += area == 14 ? 0 : 1;
	List<int> numbers;
	numbers.Append(5);
	numbers.Append(3);
	failures += numbers.Compare(cmpInt) == 2 ? 0 : 1;
	Derived derived;
	int data[2] = { 3, 4 };
	static_cast<Base *>(&derived)->Dispatch((callback_t)&Base::Add, 1, data);
	derived.Dispatch((callback_t)&Base::Mul, 2, data);
	failures += derived.total == 15 ? 0 : 1;
	Name n1 = { 1 };
	Name n2 = { 2 };
	Name *p1 = &n1;
	Name *p2 = &n2;
	failures += CompareItems(&n1, &n2) == -1 ? 0 : 1;
	failures += CompareItems(&p1, &p2) == 1 ? 0 : 1;
	int x = 1;
	int y = 2;
	SwapValues(x, y);
	SwapValues(p1, p2);
	failures += x == 2 && p1->len == 2 && p2->len == 1 ? 0 : 1;
	return failures;
}
') or {
		panic(err)
	}

	build_res := os.execute('${os.quoted_path(@VEXE)} -o c2v -experimental -w .')
	assert build_res.exit_code == 0
	c2v_res :=
		os.execute('${os.quoted_path(os.join_path(os.getwd(), 'c2v'))} ${os.quoted_path(tmp_dir)}')
	assert c2v_res.exit_code == 0, c2v_res.output
	out_dir := os.join_path(tmp_dir, 'out')
	program := os.join_path(tmp_dir, 'program')
	v_res := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(program)} ${os.quoted_path(out_dir)}')
	assert v_res.exit_code == 0, v_res.output
	run_res := os.execute(os.quoted_path(program))
	assert run_res.exit_code == 0, 'failed checks: ${run_res.exit_code}'
}

// Every directory in tests_runtime/ is a C++ program with the output of its
// native build in expected.txt. Translated as a strict project, built with V
// and run, it must print the same.
fn test_strict_cpp_runtime_programs_match_native() {
	build_res := os.execute('${os.quoted_path(@VEXE)} -o c2v -experimental -w .')
	assert build_res.exit_code == 0, build_res.output
	c2v_exe := os.join_path(os.getwd(), 'c2v')
	mut dirs := os.ls('tests_runtime') or { panic(err) }
	dirs.sort()
	for name in dirs {
		source_dir := os.join_path(os.getwd(), 'tests_runtime', name)
		if !os.is_dir(source_dir) {
			continue
		}
		tmp_dir := os.join_path(os.temp_dir(), 'c2v_runtime_${name}')
		os.rmdir_all(tmp_dir) or {}
		os.mkdir_all(tmp_dir) or { panic(err) }
		mut sources := []string{}
		for file in os.ls(source_dir) or { panic(err) } {
			if file.ends_with('.cpp') || file.ends_with('.h') {
				os.cp(os.join_path(source_dir, file), os.join_path(tmp_dir, file)) or { panic(err) }
			}
			if file.ends_with('.cpp') {
				sources << file
			}
		}
		sources.sort()
		os.write_file(os.join_path(tmp_dir, 'sources.txt'), sources.join('\n') + '\n') or {
			panic(err)
		}
		os.write_file(os.join_path(tmp_dir, 'c2v.toml'), '[project]\noutput_dirname = "out"\nadditional_flags = "-I."\nsingle_module = true\ngenerate_stubs = false\nrequire_no_stubs = true\nrequire_main = true\nsource_manifest = "sources.txt"\n') or {
			panic(err)
		}
		c2v_res := os.execute('${os.quoted_path(c2v_exe)} ${os.quoted_path(tmp_dir)}')
		assert c2v_res.exit_code == 0, '${name}: ${c2v_res.output}'
		program := os.join_path(tmp_dir, 'program')
		v_res := os.execute('${os.quoted_path(@VEXE)} -o ${os.quoted_path(program)} ${os.quoted_path(os.join_path(tmp_dir, 'out'))}')
		assert v_res.exit_code == 0, '${name}: ${v_res.output}'
		run_res := os.execute(os.quoted_path(program))
		expected := os.read_file(os.join_path(source_dir, 'expected.txt')) or { panic(err) }
		assert run_res.output == expected, '${name}: got ${run_res.output}'
		// Large translated programs are built by the old compiler backend.
		old_program := os.join_path(tmp_dir, 'program_old')
		old_v_res := os.execute('${os.quoted_path(@VEXE)} -old-compiler -o ${os.quoted_path(old_program)} ${os.quoted_path(os.join_path(tmp_dir, 'out'))}')
		assert old_v_res.exit_code == 0, '${name} (old compiler): ${old_v_res.output}'
		old_run_res := os.execute(os.quoted_path(old_program))
		assert old_run_res.output == expected, '${name} (old compiler): got ${old_run_res.output}'
		os.rmdir_all(tmp_dir) or {}
	}
}

fn test_run_tests() {
	res := os.system('${os.quoted_path(@VEXE)} tests/run_tests.vsh')
	assert res == 0
}
