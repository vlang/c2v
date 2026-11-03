import os

fn test_directory_pointer_updates_share_helpers_across_translation_units() ! {
	$if windows {
		return
	}
	os.chdir(@VMODROOT)!
	tmp_dir := os.join_path(os.vtmp_dir(), 'c2v_directory_pointer_updates_${os.getpid()}')
	os.mkdir_all(tmp_dir)!
	defer { os.rmdir_all(tmp_dir) or {} }
	os.write_file(os.join_path(tmp_dir, 'sources.txt'), 'numbers.c\nrecords.c\n')!
	os.write_file(os.join_path(tmp_dir, 'numbers.c'), 'int number_updates(void) {
    int values[3] = {3, 5, 7};
    int *cursor = values;
    int *old = cursor++;
    if (*old != 3 || *cursor != 5) return 1;
    int *next = ++cursor;
    if (*next != 7 || next != cursor) return 2;
    old = cursor--;
    if (*old != 7 || *cursor != 5) return 3;
    next = --cursor;
    if (*next != 3 || next != values || next != cursor) return 4;
    return 0;
}
')!
	os.write_file(os.join_path(tmp_dir, 'records.c'), 'typedef struct { long value; } Record;
int record_updates(void) {
    Record values[3] = {{11}, {13}, {17}};
    Record *cursor = values;
    Record *old = cursor++;
    if (old->value != 11 || cursor->value != 13) return 5;
    Record *next = ++cursor;
    if (next->value != 17 || next != cursor) return 6;
    old = cursor--;
    if (old->value != 17 || cursor->value != 13) return 7;
    next = --cursor;
    if (next->value != 11 || next != values || next != cursor) return 8;
    return 0;
}
')!
	os.write_file(os.join_path(tmp_dir, 'native_main.c'), 'int number_updates(void);
int record_updates(void);
int main(void) { return number_updates() + record_updates(); }
')!
	native := os.join_path(tmp_dir, 'native')
	native_build := os.exec(['cc', '-std=c11', os.join_path(tmp_dir, 'numbers.c'),
		os.join_path(tmp_dir, 'records.c'), os.join_path(tmp_dir, 'native_main.c'), '-o', native])
	assert native_build.exit_code == 0, native_build.output
	native_run := os.exec([native])
	assert native_run.exit_code == 0, native_run.output
	translator := os.join_path(tmp_dir, 'c2v')
	build := os.exec([@VEXE, '-w', '-no-parallel', '-o', translator, '.'])
	assert build.exit_code == 0, build.output
	for mode in ['default', 'strict'] {
		config := '[project]\noutput_dirname = "${mode}"\nsource_manifest = "sources.txt"\njobs = 1\n' +
			if mode == 'strict' {
				'single_module = true\ngenerate_stubs = false\nrequire_no_stubs = true\n'
			} else {
				''
			}
		os.write_file(os.join_path(tmp_dir, 'c2v.toml'), config)!
		translated := os.exec([translator, tmp_dir])
		assert translated.exit_code == 0, translated.output
		out_dir := os.join_path(tmp_dir, mode)
		mut program_source := ''
		for path in os.walk_ext(out_dir, '.v') {
			program_source += os.read_file(path)!
		}
		assert program_source.count('fn c2v_pointer_postfix[') == 1
		assert program_source.count('fn c2v_pointer_prefix[') == 1
		for unit in ['numbers.v', 'records.v'] {
			source := os.read_file(os.join_path(out_dir, unit))!
			assert source.count('c2v_pointer_postfix(') == 2
			assert source.count('c2v_pointer_prefix(') == 2
		}
		os.write_file(os.join_path(out_dir, 'runtime_check.v'), 'module main\nfn init() { assert number_updates() == 0; assert record_updates() == 0 }\n' +
			if mode == 'strict' { 'fn main() {}\n' } else { '' })!
		program := os.join_path(tmp_dir, 'translated_${mode}')
		compiled := os.exec([@VEXE, '-new-compiler', '-no-retry-compilation', '-no-parallel',
			'-translated', '-gc', 'none', '-cc', 'cc', '-o', program, out_dir])
		assert compiled.exit_code == 0, compiled.output
		run := os.exec([program])
		assert run.exit_code == native_run.exit_code, run.output
		assert run.output == native_run.output
	}
}
