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
	assert a_output.contains('fn (this AbstractConfig) get_value() int')
	assert b_output.contains('fn (this ConcreteConfig) get_value() int')
	assert b_output.contains('fn (this ConcreteConfig) c2v_default_get_value() int')

	check_res := os.execute('${os.quoted_path(@VEXE)} -translated -cflags -c -o ${os.quoted_path(os.join_path(tmp_dir, 'out.o'))} ${os.quoted_path(out_dir)}')
	assert check_res.exit_code == 0
	if check_res.exit_code != 0 {
		eprintln(check_res.output)
	}
}

fn test_run_tests() {
	res := os.system('${os.quoted_path(@VEXE)} tests/run_tests.vsh')
	assert res == 0
}
