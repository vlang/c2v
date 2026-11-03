import os

fn test_directory_globals_keep_native_storage_and_linkage() ! {
	$if windows {
		return
	}
	os.chdir(os.dir(@FILE))!
	tmp_dir := os.join_path(os.vtmp_dir(), 'c2v_global_storage_${os.getpid()}')
	os.mkdir_all(tmp_dir)!
	defer { os.rmdir_all(tmp_dir) or {} }
	header := os.join_path(tmp_dir, 'globals.h')
	os.write_file(header, 'typedef struct { int before; int value; int after; } Record;
extern int public_zero;
extern Record public_record;
extern int public_init;
extern int public_array[3];
extern int only_native_reads;
extern int only_native_zero;
extern int native_trailing_tentative;
extern int native_value;
int FirstStep(void);
int SecondStep(void);
int ReadPublic(void);
int StorageWidths(void);
int NativeChecks(void);
')!
	first := os.join_path(tmp_dir, 'a.c')
	os.write_file(first, '#include "globals.h"
int public_zero;
Record public_record;
int public_init = 7;
int public_array[3] = {2, 3, 5};
int only_native_reads;
int only_native_reads = 42;
int only_native_zero;
int native_trailing_tentative = 71;
int native_trailing_tentative;
static int private_zero;
static Record private_record;
static int private_init = 11;
static int private_values[2] = {17, 19};
int FirstStep(void) {
    ++private_zero;
    private_record.value += 4;
    ++public_zero;
    public_record.value += 2;
    --public_array[1];
    native_value += 3;
    return private_zero + private_record.value + private_init
        + private_values[0] + private_values[1];
}
int StorageWidths(void) {
    return sizeof(public_zero) == 4 && sizeof(public_init) == 4
        && sizeof(public_array) == 12 && sizeof(Record) == 12;
}
')!
	second := os.join_path(tmp_dir, 'b.c')
	os.write_file(second, '#include "globals.h"
static int private_zero;
int SecondStep(void) { private_zero += 10; return private_zero + public_zero; }
int ReadPublic(void) { return public_init + public_array[1]; }
')!
	native := os.join_path(tmp_dir, 'native.c')
	os.write_file(native, '#include "globals.h"
int native_value = -23;
int NativeChecks(void) {
    if (!StorageWidths()) return 8;
    if (public_zero != 0 || public_record.value != 0 || only_native_zero != 0
        || only_native_reads != 42 || native_trailing_tentative != 71) return 1;
    if (public_init != 7 || public_array[0] != 2 || public_array[1] != 3
        || public_array[2] != 5) return 2;
    if (FirstStep() != 52 || SecondStep() != 11) return 3;
    if (public_zero != 1 || public_record.value != 2 || native_value != -20
        || public_array[0] != 2 || public_array[1] != 2 || public_array[2] != 5) return 4;
    public_zero = -101;
    public_record.before = 0x12345678;
    public_record.value = -41;
    public_record.after = -1234567;
    public_init = -101;
    public_array[0] = 0x12345678;
    public_array[1] = -103;
    public_array[2] = 0x23456789;
    only_native_reads = -107;
    if (FirstStep() != 57 || SecondStep() != -80) return 5;
    if (public_zero != -100 || public_record.value != -39 || native_value != -17
        || public_record.before != 0x12345678 || public_record.after != -1234567) return 6;
    if (ReadPublic() != -205 || only_native_reads != -107
        || public_array[0] != 0x12345678 || public_array[2] != 0x23456789) return 7;
    return 0;
}
')!
	main := os.join_path(tmp_dir, 'main.c')
	os.write_file(main, '#include <stdio.h>
#include "globals.h"
int main(void) {
    int result = NativeChecks();
    if (result != 0) return result;
    puts("global storage ok");
    return 0;
}
')!
	os.write_file(os.join_path(tmp_dir, 'sources.txt'), 'a.c\nb.c\n')!
	native_program := os.join_path(tmp_dir, 'native')
	native_build := os.exec(['cc', '-std=c11', first, second, native, main, '-o', native_program])
	assert native_build.exit_code == 0, native_build.output
	native_run := os.exec([native_program])
	assert native_run.exit_code == 0, native_run.output
	assert native_run.output.trim_space() == 'global storage ok'
	native_object := os.join_path(tmp_dir, 'native.o')
	native_object_build := os.exec(['cc', '-std=c11', '-c', native, '-o', native_object])
	assert native_object_build.exit_code == 0, native_object_build.output
	translator := os.join_path(tmp_dir, 'c2v')
	build := os.exec([@VEXE, '-w', '-o', translator, '.'])
	assert build.exit_code == 0, build.output
	mut failures := []string{}
	for mode in ['default', 'strict'] {
		config := '[project]\noutput_dirname = "${mode}"\nadditional_flags = "-I."\nsource_manifest = "sources.txt"\n' +
			if mode == 'strict' {
				'single_module = true\ngenerate_stubs = false\nrequire_no_stubs = true\n'
			} else {
				''
			}
		os.write_file(os.join_path(tmp_dir, 'c2v.toml'), config)!
		translated := os.exec([translator, tmp_dir])
		assert translated.exit_code == 0, translated.output
		out_dir := os.join_path(tmp_dir, mode)
		// Native code must observe and mutate the exact storage used by the
		// translated units, including the definition only the native code uses.
		os.write_file(os.join_path(out_dir, 'runtime_check.c.v'), 'module main
#flag ${os.quoted_path(native_object)}
@[c_extern]
fn C.NativeChecks() i32
fn init() {
    assert C.NativeChecks() == 0
    println("global storage ok")
}
' + if mode == 'strict' { 'fn main() {}\n' } else { '' })!
		program := os.join_path(tmp_dir, mode + '_program')
		compiled := os.exec([@VEXE, '-new-compiler', '-no-retry-compilation', '-translated', '-gc',
			'none', '-cc', 'cc', '-o', program, out_dir])
		if compiled.exit_code != 0 {
			failures << '${mode} compilation: ${compiled.output}'
			continue
		}
		run := os.exec([program])
		if run.exit_code != 0 || run.output != native_run.output {
			failures << '${mode} runtime (${run.exit_code}): ${run.output}'
		}
	}
	assert failures.len == 0, failures.join('\n')
}
