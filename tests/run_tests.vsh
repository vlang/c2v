// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
import term
import os

fn replace_file_extension(file_path string, old_extension string, new_extension string) string {
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

fn build_c2v(c2v_dir string) {
	chdir(c2v_dir) or {
		println('Cannot change directory to ' + c2v_dir)
		exit(1)
	}

	println('building c2v...')
	c2v_build_command_result := execute('v -o c2v -experimental -w .')

	if !exists(c2v_dir + '/c2v') || c2v_build_command_result.exit_code != 0 {
		println('c2v compilation failed:')
		println(c2v_build_command_result.output)
		println('c2vdir="${c2v_dir}"')

		println(ls(c2v_dir) or {
			println('Cannot list c2v directory')
			exit(1)
		})

		exit(1)
	}

	println('done')
}

fn start_testing_process(filter string, tests_dir string, c2v_dir string) {
	if run_tests('.c', '', filter, tests_dir, c2v_dir) == false
		|| run_tests('.h', 'wrapper', filter, tests_dir, c2v_dir) == false {
		exit(1)
	}
}

fn run_tests(test_file_extension string, c2v_command string, filter string, tests_dir string, c2v_dir string) bool {
	mut files := get_test_files(tests_dir, test_file_extension)
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

		execute_c2v_command(c2v_command, file, c2v_dir)

		generated_file := try_get_generated_file(file, test_file_extension) or {
			println(term.red('FAIL'))
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

fn get_test_files(tests_dir string, extension string) []string {
	return walk_ext(tests_dir, extension)
}

fn try_compile_test_file(file string) bool {
	// Make sure the C test is a correct C program first
	cmd := 'cc -c -w ${file} -o ${os.quoted_path(os.temp_dir())}/${os.file_name(file)}.o'
	res := execute(cmd)

	if res.exit_code != 0 {
		eprintln(term.red('failed to compile C test `${file}`'))
		eprintln('command: ${cmd}')
		return false
	}

	return true
}

fn execute_c2v_command(options string, file string, c2v_dir string) {
	system('${c2v_dir}/c2v ' + options + ' ${file} > /dev/null')
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
	println(term.red('\nFAIL'))
	println('expected:')
	println(expected)
	println('\n===got:')
	println(got)

	println('\n====diff=====')
	expected_file_form := temp_dir() + '/expected.txt'
	got_file_form := temp_dir() + '/got.txt'

	write_file(expected_file_form, expected) or { println('Cannot write expected file') }
	write_file(got_file_form, got) or { println('Cannot write got file') }

	diff := execute('diff -u ${expected_file_form} ${got_file_form}')
	println(diff.output)

	println('\n')
}

fn do_post_test_cleanup(generated_file string) {
	os.rm(generated_file) or {}
}

exe := executable()
tests_dir := dir(exe)
c2v_dir := dir(tests_dir)
mut filter := ''

if os.args.len > 1 {
	filter = try_process_filter_argument()
}

build_c2v(c2v_dir)
start_testing_process(filter, tests_dir, c2v_dir)
