import os
import term

const doom_src = home_dir() + '/code/doom/chocolate-doom/src/'

const c2v_src = os.dir(os.dir(@FILE))

const verbose = os.getenv('VVERBOSE') != ''

const sdl_cflags = os.execute('sdl2-config --cflags').output.trim_space()

fn cprintln(s string) {
	println(term.colorize(term.bold, term.colorize(term.green, s)))
}

fn run(s string) {
	println('    execute: ${term.colorize(term.green, s)}')
	ret := os.execute(s)
	if ret.exit_code != 0 {
		eprintln('Failed command: ${s}')
		eprintln(ret.output)
		eprintln('Exiting.')
		exit(1)
	}
	if verbose {
		println(ret.output)
	}
}

file := os.args[1]

os.mkdir('/tmp/doom') or {}

if !exists(join_path(doom_src, '${file}.c')) {
	eprintln(join_path(doom_src, '${file}.c') + ' does not exist')
	exit(1)
}

cur_dir := os.getwd()
cprintln('Current folder: ${cur_dir} ; change to folder: ${doom_src}')
chdir(doom_src)?

if os.args.len < 2 {
	println('usage: v run build_doom_file.vsh doom/p_enemy')
	exit(1)
}

cprintln('Cleanup previous build artefacts')
run('make clean')

if os.args.contains('-g') {
	f := file.replace('doom/', 'doom.dir/')
	run('cc -g  -I. -I.. -I../.. ${sdl_cflags} -w -ferror-limit=100 -c -I ${doom_src} -o ' +
		'${doom_src}/doom/CMakeFiles/${f}.c.o ${file}.c')
	run('make -j 6 chocolate-doom')
	println('-g done')
	exit(0)
} else if os.args.contains('-prod') {
	f := file.replace('doom/', 'doom.dir/')
	run('cc -O2  -I. -I.. -I../.. ${sdl_cflags} -w -ferror-limit=100 -c -I ${doom_src} -o ' +
		'/var/tmp/${f}.c.o2.o ${file}.c')
	println('-o2 done')
	exit(0)
}

// ast_file := join_path(doom_src, '${file}.json')
v_file := join_path(doom_src, '${file}.v')

/*
if !exists(ast_file) {
	println('${file}.json is missing, generating it...')
	// run('clang -v ${file}.c')
	run('clang -fparse-all-comments -I. -I.. -I../.. $sdl_cflags -w ' +
		'-Xclang -ast-dump=json -fno-diagnostics-color ' + '-c ${file}.c > ${file}.json')
}

if !exists(ast_file) {
	eprintln('failed to generate $ast_file')
	exit(1)
}
*/

println('> change folder to: ${c2v_src}')
chdir(c2v_src)?

cprintln('Converting C to V...')
c_file := join_path(doom_src, '${file}.c')
run('./c2v -keep_ast ${c_file}')

if !exists(v_file) {
	eprintln('failed to generate v file ${v_file}')
	exit(1)
}

// cprintln('Formatting translated v file...')
// run('v -w fmt -translated -w $v_file')

cprintln('Building translated v file...')
run('v -cc clang -d 4bytebool -showcc -w -cg -keepc -gc none -translated ' +
	'-cflags "-fPIE -w -ferror-limit=100 -I ${doom_src} ${sdl_cflags} -c" -o /tmp/${file}.o ${v_file}')

chdir(os.dir(doom_src))?
if file.starts_with('doom/') {
	f := file.replace('doom/', 'doom.dir/')
	source_file := '/tmp/${file}.o'
	target_file := '${doom_src}/doom/CMakeFiles/${f}.c.o'
	cprintln('Move by copying: ${source_file} => ${target_file}')
	os.mv_by_cp('/tmp/${file}.o', target_file)?

	cprintln('Remake chocolate-doom')
	run('make -j 6 chocolate-doom')
}

println('Done. You can run doom with: `src/chocolate-doom -width 640`')
