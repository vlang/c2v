module main

import os

// Comment-free output.
//
// With `-skip_comments` (or `skip_comments = true` in c2v.toml), c2v does not
// carry the comments of the C sources over, and removes the comments it
// generates itself, so the V output contains no comments at all.

// strip_v_comments removes the `//` and `/* */` comments of V source `src`,
// outside string and rune literals. Lines that only held a comment are
// dropped, together with a blank line that would then be doubled.
fn strip_v_comments(src string) string {
	mut out := []string{cap: src.count('\n') + 1}
	mut in_block := false
	mut drop_next_blank := false
	for line in src.split('\n') {
		mut kept := []u8{cap: line.len}
		mut quote := u8(0)
		mut had_comment := in_block
		mut i := 0
		for i < line.len {
			ch := line[i]
			if in_block {
				if ch == `*` && i + 1 < line.len && line[i + 1] == `/` {
					in_block = false
					i += 2
				} else {
					i++
				}
				continue
			}
			if quote != 0 {
				kept << ch
				if ch == `\\` && i + 1 < line.len {
					kept << line[i + 1]
					i += 2
					continue
				}
				if ch == quote {
					quote = 0
				}
				i++
				continue
			}
			if ch in [`'`, `"`, `\``] {
				quote = ch
			} else if ch == `/` && i + 1 < line.len && line[i + 1] == `/` {
				had_comment = true
				break
			} else if ch == `/` && i + 1 < line.len && line[i + 1] == `*` {
				had_comment = true
				in_block = true
				i += 2
				continue
			}
			kept << ch
			i++
		}
		if !had_comment {
			if line.trim_space() == '' && drop_next_blank {
				drop_next_blank = false
				continue
			}
			drop_next_blank = false
			out << line
			continue
		}
		code := kept.bytestr().trim_right(' \t')
		if code.trim_space() == '' {
			// A comment line: drop it, and keep blank lines around it single.
			drop_next_blank = out.len > 0 && out.last().trim_space() == ''
			continue
		}
		drop_next_blank = false
		out << code
	}
	return out.join('\n')
}

// strip_output_comments removes the comments of the V files in the output
// directory of a project translation, then formats them again.
fn (mut c2v C2V) strip_output_comments() {
	if !os.exists(c2v.project_output_root) {
		return
	}
	for path in os.walk_ext(c2v.project_output_root, '.v') {
		src := os.read_file(path) or { continue }
		stripped := strip_v_comments(src)
		if stripped != src {
			os.write_file(path, stripped) or { c2v.verror('cannot write ${path}: ${err}') }
			c2v.format_output_file(path)
		}
	}
}
