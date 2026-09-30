module main

import os
import strings

// Translation into a named module.
//
// By default the V code is in `module main`. With `module_name = "libpq"` in
// c2v.toml, it is in that module instead, and all its declarations are public,
// so that other V modules can import the translated library.

// v_module_header returns the lines that start a generated V file.
fn (c &C2V) v_module_header() string {
	return '@[translated]\nmodule ${c.project_module_name}\n'
}

// make_declarations_public marks the top level declarations of V source
// `src` as `pub`, and the fields of its records as `pub mut`.
fn make_declarations_public(src string) string {
	mut out := []string{cap: src.count('\n') + 1}
	mut in_record := false
	mut record_has_access := false
	for line in src.split('\n') {
		if in_record {
			trimmed := line.trim_space()
			if line.starts_with('}') {
				in_record = false
				out << line
				continue
			}
			if trimmed in ['mut:', 'pub:', 'pub mut:', '__global:'] {
				out << if trimmed == 'mut:' { 'pub mut:' } else { line }
				record_has_access = true
				continue
			}
			if !record_has_access && trimmed != '' && !trimmed.starts_with('//') {
				// Fields before any access modifier are private: open them.
				out << 'pub mut:'
				record_has_access = true
			}
			out << line
			continue
		}
		if line.starts_with('struct ') || line.starts_with('union ') {
			if line.starts_with('struct C.') || line.starts_with('union C.') {
				out << line
				continue
			}
			out << 'pub ' + line
			if line.trim_space().ends_with('{') && !line.trim_space().ends_with('{}') {
				in_record = true
				record_has_access = false
			}
			continue
		}
		if line.starts_with('fn ') {
			if line.starts_with('fn C.') || line.starts_with('fn init()')
				|| line.starts_with('fn main()') {
				out << line
				continue
			}
			out << 'pub ' + line
			continue
		}
		if line.starts_with('enum ') || line.starts_with('type ') || line.starts_with('const ')
			|| line.starts_with('interface ') {
			out << 'pub ' + line
			continue
		}
		out << line
	}
	return out.join('\n')
}

// make_output_declarations_public applies make_declarations_public and
// alias_c_functions to the V files in the output directory of a project
// translation.
fn (mut c2v C2V) make_output_declarations_public() {
	if !os.exists(c2v.project_output_root) {
		return
	}
	paths := os.walk_ext(c2v.project_output_root, '.v')
	mut sources := map[string]string{}
	for path in paths {
		sources[path] = os.read_file(path) or { continue }
	}
	aliased := alias_c_functions(sources)
	for path, src in sources {
		public := make_declarations_public(aliased[path] or { src })
		if public != src {
			os.write_file(path, public) or { c2v.verror('cannot write ${path}: ${err}') }
			c2v.format_output_file(path)
		}
	}
}

// alias_c_functions renames the C functions that V sources declare
// (`fn C.localtime_r(...)`) to `C.c2v_localtime_r`, with the C name in a
// `@[c: 'localtime_r']` attribute. V rejects a C function that two modules
// declare with different signatures, and a translated library cannot know the
// declarations of the modules it is used with.
fn alias_c_functions(sources map[string]string) map[string]string {
	mut functions := map[string]bool{}
	mut records := map[string]bool{}
	for _, src in sources {
		lines := src.split('\n')
		for i, line in lines {
			if line.starts_with('fn C.') {
				name := line['fn C.'.len..].all_before('(')
				if i > 0 && lines[i - 1].starts_with('@[c:') {
					continue
				}
				functions[name] = true
			} else if line.starts_with('struct C.') || line.starts_with('union C.') {
				records[line.all_after('C.').all_before(' ').all_before('{')] = true
			}
		}
	}
	mut result := map[string]string{}
	for path, src in sources {
		mut out := strings.new_builder(src.len + 1024)
		mut i := 0
		for i < src.len {
			start := src.index_after_('C.', i)
			if start < 0 {
				out.write_string(src[i..])
				break
			}
			out.write_string(src[i..start])
			mut end := start + 2
			for end < src.len && (src[end].is_alnum() || src[end] == `_`) {
				end++
			}
			name := src[start + 2..end]
			preceded := start > 0 && (src[start - 1].is_alnum() || src[start - 1] == `_`
				|| src[start - 1] == `.`)
			called := end < src.len && src[end] == `(`
			if !preceded && name in functions && (called || name !in records) {
				is_declaration := start >= 3 && src[start - 3..start] == 'fn '
					&& (start == 3 || src[start - 4] == `\n`)
				if is_declaration {
					out.go_back(3)
					out.write_string("@[c: '" + name + "']\nfn ")
				}
				out.write_string('C.c2v_' + name)
			} else {
				out.write_string(src[start..end])
			}
			i = end
		}
		result[path] = out.str()
	}
	return result
}
