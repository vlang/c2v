// Copyright (c) 2022 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by a GPL license that can
// be found in the LICENSE file.
import term
import os

exe := executable()
tests_dir := dir(exe)
c2v_dir := dir(tests_dir)
filter := if os.args.len > 1 { os.args[1] } else { '' }

if filter == '-h' {
	println('Usage: v run tests/run_tests.vsh ([testname])')
	exit(0)
}

chdir(c2v_dir)?
println('building c2v...')
x := execute('v -o c2v -experimental -w .')
if !exists(c2v_dir + '/c2v') || x.exit_code != 0 {
	println('c2v compilation failed:')
	println(x.output)
	println('c2vdir="$c2v_dir"')
	println(ls(c2v_dir)?)
	exit(1)
}
println('done')

tmpfolder := os.temp_dir()
mut ok := true

files := walk_ext(tests_dir, '.c')
for file in files {
	fname := os.file_name(file)
	print(file + '...  ')
	if filter != '' {
		file.index(filter) or { continue }
	}
	// Make sure the C test is a correct C program first
	cmd := 'cc -c -w $file -o ${os.quoted_path(tmpfolder)}/${fname}.o'
	res := execute(cmd)
	if res.exit_code != 0 {
		eprintln(term.red('failed to compile C test `$file`'))
		eprintln('command: $cmd')
		exit(1)
	}
	system('$c2v_dir/c2v $file > /dev/null')
	vfile := file.replace('.c', '.v')
	if !exists(vfile) {
		println(term.red('FAIL'))
		exit(1)
	}
	system('v fmt -w $vfile')
	mut expected := read_file(file.replace('.c', '.out'))?
	mut got := read_file(vfile)?
	got = got.after('// vstart').trim_space()
	expected = expected.trim_space()
	if expected.trim_space() != got {
		println(term.red('\nFAIL'))
		println('expected:')
		println(expected)
		println('\n===got:')
		println(got)
		println('\n====diff=====')
		f1 := temp_dir() + '/expected.txt'
		f2 := temp_dir() + '/got.txt'
		write_file(f1, expected)?
		write_file(f2, got)?
		diff := execute('diff -u $f1 $f2')
		println(diff.output)
		println('\n')
		ok = false
	} else {
		// remove the temporary generated V file, to avoid polution
		os.rm(vfile) or {}
	}
	println(term.green('OK'))
}

println('')

if !ok {
	exit(1)
}
