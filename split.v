module main

import os

// Split output.
//
// With `-split_files` (or `split_files = true` in c2v.toml), the translation of
// one C file is written as one V file per original source file: the code that
// `#line` directives attribute to `src/btree.c` goes to `btree.v`, declarations
// of a project header `util.h` go to `util_h.v`, and everything else to the V
// file of the translated file. This keeps an amalgamation (a single C file
// generated from many, such as SQLite's sqlite3.c built with `--linemacros`)
// organized like its original sources. All files form one V module.

// split_file_marker starts a line of generated V code that switches the output
// to another source file. It is removed before the files are written.
const split_file_marker = '//c2v_split_file:'

// split_globals_file stands for the file that holds the initialized globals.
// V infers their types only when it checks their declarations, file by file in
// name order, so they precede all uses: `0_globals.v` (as in project mode).
const split_globals_file = '\x01globals'

// V file name endings that V treats specially (platform specific, test or
// conditionally compiled files).
const v_special_file_suffixes = ['_test', '_windows', '_linux', '_darwin', '_macos', '_ios', '_android',
	'_termux', '_bsd', '_freebsd', '_openbsd', '_netbsd', '_dragonfly', '_solaris', '_qnx', '_serenity',
	'_plan9', '_vinix', '_haiku', '_nix', '_default', '_native', '_emscripten']

struct LineDirective {
	offset int    // byte offset of the first line the directive applies to
	file   string // the file name it gives, resolved like the main file's path when possible
}

// scan_line_directives returns the `#line N "file"` (and `# N "file"`)
// directives of C source text, in order.
fn scan_line_directives(src string, main_file string) []LineDirective {
	mut directives := []LineDirective{}
	main_dir := os.dir(main_file)
	mut line_start := 0
	for line_start < src.len {
		mut line_end := src.index_after_('\n', line_start)
		if line_end < 0 {
			line_end = src.len
		}
		line := src[line_start..line_end].trim_left(' \t')
		line_start = line_end + 1
		if !line.starts_with('#') {
			continue
		}
		mut rest := line[1..].trim_left(' \t')
		if rest.starts_with('line') {
			rest = rest[4..].trim_left(' \t')
		}
		if rest == '' || !rest[0].is_digit() {
			continue
		}
		mut i := 0
		for i < rest.len && rest[i].is_digit() {
			i++
		}
		rest = rest[i..].trim_left(' \t')
		if !rest.starts_with('"') {
			// `#line N` keeps the file name.
			continue
		}
		close := rest.index_after_('"', 1)
		if close < 0 {
			continue
		}
		mut file := rest[1..close].replace('\\\\', '\\')
		resolved := os.real_path(if os.is_abs_path(file) {
			file
		} else {
			os.join_path(main_dir, file)
		})
		if resolved == main_file {
			file = main_file
		}
		directives << LineDirective{
			offset: line_start
			file:   file
		}
	}
	return directives
}

// presumed_split_file returns the source file that `#line` directives give the
// byte offset `offset` of the main file.
fn (c &C2V) presumed_split_file(offset int) string {
	mut lo := 0
	mut hi := c.line_directives.len
	for lo < hi {
		mid := (lo + hi) / 2
		if c.line_directives[mid].offset <= offset {
			lo = mid + 1
		} else {
			hi = mid
		}
	}
	return if lo == 0 { c.split_main_file } else { c.line_directives[lo - 1].file }
}

// split_file_at returns the source file of the byte offset `offset` of the
// file clang read as `file`.
fn (c &C2V) split_file_at(file string, offset int) string {
	if file != '' && file != c.split_main_file {
		return file
	}
	return c.presumed_split_file(offset)
}

fn is_initialized_global_decl(node Node) bool {
	return node.kindof(.var_decl) && node.class_modifier != 'extern'
		&& node.inner.any(!it.kindof(.visibility_attr) && !it.kindof(.full_comment)
			&& !it.kindof(.record_decl) && !it.kindof(.cxx_record_decl) && !it.kindof(.enum_decl)
			&& !it.kindof(.typedef_decl))
}

fn node_start_offset(node Node) int {
	for offset in [node.range.begin.offset, node.range.begin.expansion_file.offset,
		node.location.offset, node.location.expansion_file.offset] {
		if offset > 0 {
			return offset
		}
	}
	return 0
}

// split_source_file returns the source file of the top level node `node`, or
// '' when it is unknown (the node stays with the preceding code).
fn (c &C2V) split_source_file(node Node) string {
	if is_initialized_global_decl(node) {
		return split_globals_file
	}
	actual := c.top_level_node_files[node.id] or { '' }
	if actual != '' && actual != c.split_main_file {
		// A declaration of a project header.
		return actual
	}
	offset := node_start_offset(node)
	if offset <= 0 {
		return ''
	}
	return c.presumed_split_file(offset)
}

// mark_split_file switches the output to the V file of `source_file`.
fn (mut c C2V) mark_split_file(source_file string) {
	if source_file == '' || source_file == c.split_current_file {
		return
	}
	if c.cur_out_line != '' {
		c.genln('')
	}
	c.out.writeln(split_file_marker + source_file)
	c.out_line_empty = true
	c.split_current_file = source_file
}

// split_output_file_name returns the V file name for C source file `path`:
// `btree.c` => `btree.v`, `sqliteInt.h` => `sqliteInt_h.v`. A name that V
// would treat specially (`os_linux.c`: a Linux only file) gets a `_c` suffix.
fn split_output_file_name(path string) string {
	if path == split_globals_file {
		return '0_globals'
	}
	base := os.file_name(path)
	mut name := if base.ends_with('.c') { base[..base.len - 2] } else { base }
	name = name.bytes().map(if it.is_alnum() || it == `_` { it } else { `_` }).bytestr()
	name = name.replace('_notd_', '_notdd_').replace('_d_', '_dd_')
	if name == '' || v_special_file_suffixes.any(name.ends_with(it)) {
		name += '_c'
	}
	return name
}

fn contains_v_code(text string) bool {
	for line in text.split_into_lines() {
		t := line.trim_space()
		if t != '' && !t.starts_with('//') && t != '@[translated]' && !t.starts_with('module ') {
			return true
		}
	}
	return false
}

// write_split_files writes the translation `s`, which contains split file
// markers, to one V file per source file in the output directory.
fn (mut c C2V) write_split_files(s string) {
	mut texts := map[string]string{}
	mut order := [c.split_main_file]
	mut current := c.split_main_file
	mut start := 0
	for start < s.len {
		mut marker := s.index_after_(split_file_marker, start)
		for marker > 0 && s[marker - 1] != `\n` {
			marker = s.index_after_(split_file_marker, marker + 1)
		}
		end := if marker < 0 { s.len } else { marker }
		texts[current] = (texts[current] or { '' }) + s[start..end]
		if marker < 0 {
			break
		}
		line_end := s.index_after_('\n', marker)
		current = s[marker + split_file_marker.len..if line_end < 0 { s.len } else { line_end }]
		if current !in texts {
			texts[current] = ''
			order << current
		}
		start = if line_end < 0 { s.len } else { line_end + 1 }
	}
	out_dir := c.project_output_root
	bad_targets := ['/', '.', '..', os.home_dir(), os.getwd(), c.target_root]
	if os.exists(out_dir) && out_dir !in bad_targets {
		os.rmdir_all(out_dir) or { c.verror('cannot clean the output directory ${out_dir}: ${err}') }
	}
	os.mkdir_all(out_dir) or { c.verror('cannot create the output directory ${out_dir}: ${err}') }
	mut used_names := map[string]bool{}
	mut written := 0
	for file in order {
		text := texts[file] or { '' }
		if file != c.split_main_file && !contains_v_code(text) {
			// Only comments: the file's code was not compiled (`#if`).
			continue
		}
		base_name := split_output_file_name(file)
		mut name := base_name
		mut n := 2
		for (name in used_names) {
			name = '${base_name}_${n}'
			n++
		}
		used_names[name] = true
		path := os.join_path(out_dir, name + '.v')
		mut content := if file == c.split_main_file {
			text
		} else {
			c.v_module_header() + '\n' + text
		}
		if c.skip_comments {
			content = strip_v_comments(content)
		}
		if c.project_module_name != 'main' {
			content = make_declarations_public(content)
		}
		os.write_file(path, content) or { c.verror('cannot write ${path}: ${err}') }
		c.format_output_file(path)
		written++
	}
	println(' split into ${written} files in ${out_dir}')
}
