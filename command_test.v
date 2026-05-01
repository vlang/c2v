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
	os.write_file(os.join_path(tmp_dir, 'c2v.toml'),
		'[project]\noutput_dirname = "out"\nadditional_flags = "-I."\n') or { panic(err) }
	os.write_file(os.join_path(tmp_dir, 'item.h'),
		'typedef struct {\n    int value;\n} Item_t;\n\ntypedef enum {\n    item_low,\n    item_high\n} item_kind_t;\n\nextern Item_t S_items[2];\nint pick_item(item_kind_t kind);\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'a.c'),
		'#include "item.h"\n\nint get_item_value(int idx) {\n    return S_items[idx].value + pick_item(item_high);\n}\n') or {
		panic(err)
	}
	os.write_file(os.join_path(tmp_dir, 'b.c'),
		'#include "item.h"\n\nItem_t S_items[2] = {\n    {1},\n    {2}\n};\n\nint pick_item(item_kind_t kind) {\n    return kind;\n}\n') or {
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
	globals := os.read_file(os.join_path(out_dir, '_globals.v')) or { panic(err) }
	assert globals.contains('@[c_extern]\n__global C.S_items [2]Item_t')
	assert globals.contains('@[weak] __global S_items [2]Item_t')

	check_res := os.execute('${os.quoted_path(@VEXE)} -translated -cflags -c -o ${os.quoted_path(os.join_path(tmp_dir,
		'out.o'))} ${os.quoted_path(out_dir)}')
	assert check_res.exit_code == 0
	if check_res.exit_code != 0 {
		eprintln(check_res.output)
	}
}

fn test_run_tests() {
	res := os.system('${os.quoted_path(@VEXE)} tests/run_tests.vsh')
	assert res == 0
}
