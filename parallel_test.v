module main

import os

const parallel_test_root = os.join_path(os.temp_dir(), 'c2v_parallel_${os.getpid()}')
const parallel_test_exe = os.join_path(parallel_test_root, 'c2v' + $if windows { '.exe' } $else { '' })

fn testsuite_begin() {
	os.chdir(@VMODROOT)!
	os.mkdir_all(parallel_test_root)!
	build := os.exec([@VEXE, '-o', parallel_test_exe, '.'])
	assert build.exit_code == 0, build.output
}

fn testsuite_end() {
	os.rmdir_all(parallel_test_root) or {}
}

fn test_worker_count_defaults_and_overrides() {
	assert translation_jobs(['c2v', 'project'], 0, 12)! == 12
	assert translation_jobs(['c2v', 'project'], 3, 12)! == 3
	assert translation_jobs(['c2v', '-j', '4', 'project'], 1, 12)! == 4
	assert translation_jobs(['c2v', '-j1', 'file.c'], 4, 12)! == 1
	assert translation_jobs(['c2v', '--jobs=0', 'file.c'], 4, 12)! == 12
	assert translation_jobs(['c2v', '--jobs', '2', 'file.c'], 0, 12)! == 2
	assert translation_jobs(['c2v', 'file.c'], 0, 0)! == 1
	for args in [['c2v', '-j', 'file.c'], ['c2v', '-j-2', 'file.c'], ['c2v', '-j', 'bad', 'file.c'],
		['c2v', '--jobs=', 'file.c'], ['c2v', '-j99999999999999999999999', 'file.c']] {
		if _ := translation_jobs(args, 0, 12) {
			assert false, 'accepted invalid worker count: ${args}'
		}
	}
	if _ := translation_jobs(['c2v', 'project'], -1, 12) {
		assert false, 'accepted a negative project.jobs'
	}
}

fn parallel_output_snapshot(folder string) map[string]string {
	mut snapshot := map[string]string{}
	for file in os.walk_ext(folder, '.v') {
		snapshot[file[folder.len..]] = os.read_file(file) or { panic(err) }
	}
	return snapshot
}

// A compiler wrapper records overlap without relying on elapsed-time assertions.
// It only delays AST generation; startup probes and preprocessing run normally.
fn parallel_compiler_environment(folder string, events string) !map[string]string {
	mut env := os.environ()
	$if windows {
		return env
	} $else {
		bin := os.join_path(folder, 'compiler bin')
		os.mkdir_all(bin)!
		real_clang := os.find_abs_path_of_executable('clang')!
		wrapper := os.join_path(bin, 'clang-18')
		os.write_file(wrapper, '#!/bin/sh\ncase "$*" in\n*"-ast-dump=json"*)\n' +
			'printf "start\\n" >> ${os.quoted_path(events)}\nsleep 0.15\n' +
			'${os.quoted_path(real_clang)} "$@"\ncode=$?\n' +
			'printf "end\\n" >> ${os.quoted_path(events)}\nexit "$code"\n;;\n' +
			'*) exec ${os.quoted_path(real_clang)} "$@" ;;\nesac\n')!
		os.chmod(wrapper, 0o755)!
		env['PATH'] = bin + os.path_delimiter + os.getenv('PATH')
	}
	return env
}

fn parallel_run(args []string, env map[string]string) (int, string) {
	mut process := os.new_process(parallel_test_exe)
	process.set_args(args)
	process.set_environment(env)
	process.set_redirect_stdio()
	process.run()
	output := process.stdout_slurp() + process.stderr_slurp()
	process.wait()
	code := process.code
	process.close()
	return code, output
}

fn assert_compiler_overlap(events string, limit int, overlapping bool) ! {
	$if windows {
		return
	}
	mut active := 0
	mut peak := 0
	for line in os.read_lines(events)! {
		active += if line == 'start' { 1 } else { -1 }
		assert active >= 0
		if active > peak { peak = active }
	}
	assert active == 0, 'a compiler process was left running'
	assert peak <= limit
	assert peak >= if overlapping { 2 } else { 1 }
}

fn test_parallel_project_matches_serial_and_compiles_concurrently() {
	folder := os.join_path(parallel_test_root, "project with spaces and 'quote")
	os.mkdir_all(folder)!
	config := os.join_path(folder, 'c2v.toml')
	os.write_file(config, '[project]\noutput_dirname = "out"\nsingle_module = true\njobs = 1\n')!
	os.write_file(os.join_path(folder, 'api.h'), 'typedef struct { int count; } Item;\nextern int total;\nint fetch(void);\n')!
	os.write_file(os.join_path(folder, 'a.c'), '#include "api.h"\nstatic int shared(void) { return 2; }\nint fetch(void) { Item item = {3}; return item.count + shared() + total; }\n')!
	os.write_file(os.join_path(folder, 'b.c'), '#include "api.h"\nstatic int shared(void) { return 4; }\nint total = 7;\nint second(void) { return shared() + fetch(); }\n')!
	// Same output basename, different languages: AST files must never race.
	os.write_file(os.join_path(folder, 'same.c'), 'typedef struct Late { int value; } Late;\nint earlier(void) { return 1; }\n')!
	os.write_file(os.join_path(folder, 'same.cpp'), 'struct Other { int value; };\nint later() { Other item = {2}; return item.value; }\n')!
	events := os.join_path(folder, 'compiler-events.txt')
	env := parallel_compiler_environment(folder, events)!
	serial_code, serial_output := parallel_run([folder], env)
	assert serial_code == 0, serial_output
	serial := parallel_output_snapshot(os.join_path(folder, 'out'))
	assert serial.len > 2
	assert_compiler_overlap(events, 1, false)!
	os.write_file(events, '')!
	parallel_code, parallel_output := parallel_run(['-j', '3', folder], env)
	assert parallel_code == 0, parallel_output
	assert parallel_output.contains('with 3 workers'), parallel_output
	assert_compiler_overlap(events, 3, true)!
	assert parallel_output_snapshot(os.join_path(folder, 'out')) == serial
	for file in os.walk_ext(os.join_path(folder, 'out'), '') {
		assert !file.contains('.c2v-prepared-') && !file.ends_with('.diagnostics'), file
	}
}

fn test_parallel_strict_errors_join_compilers_and_remove_staged_files() {
	folder := os.join_path(parallel_test_root, 'strict-error')
	os.mkdir_all(folder)!
	os.write_file(os.join_path(folder, 'c2v.toml'), '[project]\noutput_dirname = "out"\nsingle_module = true\ngenerate_stubs = false\nrequire_no_stubs = true\n')!
	os.write_file(os.join_path(folder, 'a_bad.c'), 'int broken = c2v_missing_symbol;\n')!
	for i in 0 .. 5 {
		os.write_file(os.join_path(folder, 'ok_${i}.c'), 'int value_${i}(void) { return ${i}; }\n')!
	}
	events := os.join_path(folder, 'compiler-events.txt')
	env := parallel_compiler_environment(folder, events)!
	code, output := parallel_run(['-j3', folder], env)
	assert code != 0
	assert output.contains('c2v_missing_symbol'), output
	assert output.contains('strict translation will not use a recovered AST'), output
	assert_compiler_overlap(events, 3, true)!
	for file in os.walk_ext(os.join_path(folder, 'out'), '') {
		assert !file.contains('.c2v-prepared-') && !file.ends_with('.diagnostics'), file
	}
}

fn test_parallel_preparation_preserves_recovered_ast_diagnostics() {
	source := os.join_path(parallel_test_root, 'recover.c')
	ast := source + '.json'
	os.write_file(source, 'int unresolved = c2v_missing_recovery_symbol;\n')!
	result := prepare_ast_job(AstPreparationJob{ path: source, ast_path: ast })
	assert result.error_message == '', result.error_message
	assert result.clang_failed
	assert result.diagnostics.contains('c2v_missing_recovery_symbol')
	assert os.file_size(ast) > 64
}
