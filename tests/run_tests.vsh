#!/usr/bin/env -S v

// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
import term
import os

const c2v_dir = @VMODROOT
const tests_dir = join_path(c2v_dir, 'tests')
const exe_path = join_path(c2v_dir, $if windows {
	'c2v.exe'
} $else {
	'c2v'
})

fn replace_file_extension(file_path string, old_extension string, new_extension string) string {
	// NOTE: It can't be just `file_path.replace(old_extenstion, new_extension)`, because it will replace all occurencies of old_extenstion string.
	//	 Path '/dir/dir/dir.c.c.c.c.c.c/kalle.c' will become '/dir/dir/dir.json.json.json.json.json.json/kalle.json'.
	return file_path.trim_string_right(old_extension) + new_extension
}

fn try_process_filter_argument() string {
	second_argument := os.args[1]

	if second_argument == '-h' {
		println('Usage: v run tests/run_tests.vsh ([testname])')
		exit(0)
	} else {
		return second_argument
	}

	return ''
}

fn build_c2v() {
	chdir(c2v_dir) or {
		eprintln('Cannot change directory to ' + c2v_dir)
		exit(1)
	}

	println('building c2v...')
	c2v_build_command_result := execute('v -o c2v -experimental -w .')

	if !exists(exe_path) || c2v_build_command_result.exit_code != 0 {
		eprintln('c2v compilation failed:')
		eprintln(c2v_build_command_result.output)
		eprintln('c2vdir="${c2v_dir}"')

		eprintln(ls(c2v_dir) or {
			eprintln('Cannot list c2v directory')
			exit(1)
		})

		exit(1)
	}

	println('done')
}

fn start_testing_process(filter string) {
	if run_tests('.c', '', filter) == false || run_tests('.h', 'wrapper', filter) == false {
		exit(1)
	}

	os.chdir(tests_dir) or {
		panic('Failed to switch folder to tests folder for testing translation for relative paths - ${err}')
	}

	if run_tests('.c', '', filter) == false || run_tests('.h', 'wrapper', filter) == false {
		exit(1)
	}
}

fn run_tests(test_file_extension string, c2v_opts string, filter string) bool {
	mut files := get_test_files(test_file_extension).filter(it.all_after_last('/').starts_with('IGNORE_') == false)

	files.sort()

	current_platform := os.user_os()
	next_file: for file in files {
		// skip all platform dependent .c/.out pairs, on non matching platforms:
		for platform in ['linux', 'macos', 'windows'] {
			if file.ends_with('_${platform}.c') && current_platform != platform {
				println('    >>>>> skipping `${file}` on ${current_platform} .')
				continue next_file
			}
		}

		print(file + '...  ')

		if filter != '' {
			file.index(filter) or { continue }
		}

		if try_compile_test_file(file) == false {
			return false
		}

		c2v_cmd := '${exe_path} ${c2v_opts} ${file}'
		c2v_res := execute(c2v_cmd)
		eprintln(c2v_res.output)

		if c2v_res.exit_code != 0 {
			eprintln(c2v_res.output)
			eprintln('command: ${c2v_cmd}')
			return false
		}

		generated_file := try_get_generated_file(file, test_file_extension) or {
			eprintln(term.red('FAIL'))
			return false
		}

		format_generated_file(generated_file)

		expected := get_expected_file_content(file, test_file_extension)
		result := get_result_file_content(generated_file, test_file_extension)

		if expected != result {
			print_test_fail_details(expected, result)
			return false
		} else {
			do_post_test_cleanup(generated_file)
			println(term.green('OK'))
		}
	}

	return true
}

fn get_test_files(extension string) []string {
	return walk_ext(tests_dir, extension)
}

fn try_compile_test_file(file string) bool {
	// Make sure the C test is a correct C program first
	o_path := join_path(temp_dir(), file_name(file)) + '.o'
	cmd := 'cc -c -w ${file} -o ${o_path}'
	res := execute(cmd)

	if res.exit_code != 0 {
		eprintln('failed to compile C test `${file}`')
		eprintln('command: ${cmd}')
		return false
	}

	return true
}

fn try_get_generated_file(file string, test_file_extension string) !string {
	generated_file := replace_file_extension(file, test_file_extension, '.v')
	println(generated_file)

	if !exists(generated_file) {
		return error('Expected generated file `${generated_file}` does not exist')
	}

	return generated_file
}

fn format_generated_file(file string) {
	system('v fmt -w ${file}')
}

fn get_expected_file_content(file string, test_file_extension string) string {
	file_content := read_file(replace_file_extension(file, test_file_extension, '.out')) or { '' }
	return file_content.trim_space()
}

fn get_result_file_content(file string, test_file_extension string) string {
	file_content := read_file(file) or { '' }
	return file_content.after('// vstart').trim_space()
}

fn print_test_fail_details(expected string, got string) {
	eprintln(term.red('\nFAIL'))
	eprintln('expected:')
	eprintln(expected)
	eprintln('\n===got:')
	eprintln(got)

	eprintln('\n====diff=====')
	expected_file_form := join_path(temp_dir(), 'expected.txt')
	got_file_form := join_path(temp_dir(), 'got.txt')

	write_file(expected_file_form, expected) or { eprintln('Cannot write expected file') }
	write_file(got_file_form, got) or { eprintln('Cannot write got file') }

	diff := execute('diff -u ${expected_file_form} ${got_file_form}')
	eprintln(diff.output)

	eprintln('\n')
}

fn do_post_test_cleanup(generated_file string) {
	os.rm(generated_file) or {}
}

mut filter := ''

if os.args.len > 1 {
	filter = try_process_filter_argument()
}

build_c2v()
start_testing_process(filter)
