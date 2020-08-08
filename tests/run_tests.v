import os
import term

exe := os.executable()
tests_dir := os.base_dir(exe)
dir := os.base_dir(tests_dir)

os.chdir(dir)
println('building c2v...')
os.system('v -experimental -w .')
if !os.exists(dir + '/c2v') {
	println('c2v compilation failed')
	exit(1)
}
println('done')


files := os.walk_ext(tests_dir, '.c')
for file in files {
	print(file + '...  ')
	// Make sure the C test is a correct C program first
	res := os.exec('cc -c -w $file') or {
		continue
	}
	if res.exit_code != 0 {
		println(term.red('failed to compile C test `$file`'))
		exit(1)
	}
	os.system('$dir/c2v $file > /dev/null')
	vfile := file.replace('.c', '.v')
	if !os.exists(vfile) {
		println(term.red('FAIL'))
		exit(1)
	}
	expected := os.read_file(file.replace('.c', '.out'))?
	mut got := os.read_file(vfile)?
	got = got.after('// vstart').trim_space()
	if expected.trim_space() != got {
		println(term.red('FAIL'))
		println('expected:')
		println(expected)
		println('\n===got:')
		println(got)
	}
	println(term.green('OK'))
}

println('')
