module main

import os
import strings

// External C surface.
//
// Declarations that come from system headers (libc, POSIX and any third-party
// library found on the compiler's system include paths) are not translated.
// Translated code reaches them through V's C interop instead. The exact types,
// record layouts and enum constants are read from Clang's AST of the current
// target, so no library has to be described by hand.

struct SystemRecordField {
	name   string
	c_type string
	// The key of the field's anonymous record type (`union { ... } key;`).
	anon_key string
}

struct SystemRecord {
mut:
	is_union bool
	defined  bool
	fields   []SystemRecordField
}

struct SystemSurface {
mut:
	// Typedefs of scalars, pointers and functions: typedef name => underlying C type.
	typedefs map[string]string
	// Typedefs naming a record: typedef name => record key.
	record_typedefs map[string]string
	// Record layouts keyed by tag, or by Clang node id for anonymous records.
	records map[string]SystemRecord
	// C spellings of the anonymous record types of system record fields.
	anonymous_types map[string]bool
	// The V spelling produced by `convert_type` => the C spelling of the record.
	record_v_names map[string]string
	enum_constants map[string]bool
	// C spelling of a system declaration => the header declaring it.
	declaring_headers map[string]string
	// Header => the file that included it.
	included_from map[string]string
	real_paths    map[string]string
	// Node ids of system declarations nested in a project `extern "C"` block of
	// the current translation unit.
	nested_ids map[string]bool
}

fn (mut c C2V) system_real_path(path string) string {
	if cached := c.system.real_paths[path] {
		return cached
	}
	mut real := os.real_path(path)
	if real == '' {
		real = path
	}
	c.system.real_paths[path] = real
	return real
}

// collect_system_surface records the system-header declarations of one
// translation unit. The surface is shared by all translation units of a project.
fn (mut c C2V) collect_system_surface(root &Node) {
	c.system.nested_ids.clear()
	c.collect_system_surface_nodes(root.inner, '', false)
}

// Returns the file of the last node, which Clang's location encoding carries
// over to the following nodes.
fn (mut c C2V) collect_system_surface_nodes(nodes []Node, file string, in_project_block bool) string {
	mut current_file := file
	for node in nodes {
		node_file := resolve_node_file_path(node)
		if node_file != '' && !is_synthetic_source_path(node_file) {
			current_file = c.system_real_path(node_file)
			if node.location.file != '' && node.location.source_file.path != '' {
				c.system.included_from[current_file] =
					c.system_real_path(node.location.source_file.path)
			}
		}
		// A header that starts with a macro (e.g. `__BEGIN_DECLS`) names its
		// includer only in the macro's spelling and expansion locations.
		for loc in [node.location.spelling_file, node.location.expansion_file,
			node.range.begin.spelling_file, node.range.begin.expansion_file] {
			if loc.path != '' && loc.included_from.path != '' {
				c.system.included_from[c.system_real_path(loc.path)] =
					c.system_real_path(loc.included_from.path)
			}
		}
		is_system := current_file != '' && line_is_builtin_header(current_file)
		if is_system && in_project_block {
			c.system.nested_ids[node.id] = true
		}
		if node.kind_str == 'LinkageSpecDecl' {
			// A project header can open `extern "C" {` around its system includes.
			current_file = c.collect_system_surface_nodes(node.inner, current_file, in_project_block
				|| !is_system)
			continue
		}
		if is_system {
			c.collect_system_declaration(node, current_file)
		}
	}
	return current_file
}

// Removes the system declarations nested in project `extern "C"` blocks: like
// all other system declarations, they are used through C instead of translated.
fn (c &C2V) prune_nested_system_decls(mut nodes []Node) {
	if c.system.nested_ids.len == 0 {
		return
	}
	for mut node in nodes {
		if node.kind_str == 'LinkageSpecDecl' {
			node.inner = node.inner.filter(it.id !in c.system.nested_ids)
			c.prune_nested_system_decls(mut node.inner)
		}
	}
}

// Runs before node kinds are resolved, so declarations are matched by kind_str.
fn (mut c C2V) collect_system_declaration(node Node, header string) {
	if node.kind_str in ['RecordDecl', 'CXXRecordDecl'] {
		key := if node.name != '' { node.name } else { node.id }
		mut record := c.system.records[key] or { SystemRecord{} }
		record.is_union = node.tags == 'union'
		mut fields := []SystemRecordField{}
		mut anon_record_id := ''
		for child in node.inner {
			if child.kind_str in ['RecordDecl', 'CXXRecordDecl'] && child.name == '' {
				c.collect_system_declaration(child, header)
				anon_record_id = child.id
				continue
			}
			if child.kind_str != 'FieldDecl' {
				continue
			}
			c_type := child.ast_type.qualified
			if is_anonymous_c_type(c_type) {
				c.system.anonymous_types[c_type] = true
			}
			fields << SystemRecordField{
				name: child.name
				c_type: c_type
				anon_key: if is_anonymous_c_type(c_type) { anon_record_id } else { '' }
			}
		}
		if node.complete_definition || fields.len > 0 {
			record.defined = true
			record.fields = fields
		}
		c.system.records[key] = record
		if node.name != '' {
			c.system.declaring_headers[node.name] = header
			c.register_system_record_v_name(node.name)
		}
		return
	}
	if node.kind_str == 'TypedefDecl' {
		name := node.name
		if name == '' {
			return
		}
		c.system.declaring_headers[name] = header
		mut qualified := node.ast_type.qualified.trim_space()
		desugared := node.ast_type.desugared_qualified.trim_space()
		if (desugared.starts_with('struct ') || desugared.starts_with('union '))
			&& !desugared.contains('*') && !desugared.contains('(') {
			// A typedef of a typedef of a record (`pthread_mutex_t` ->
			// `__darwin_pthread_mutex_t` -> `struct _opaque_pthread_mutex_t`) names
			// the record too.
			qualified = desugared
		}
		if (qualified.starts_with('struct ') || qualified.starts_with('union ')
			|| qualified.starts_with('class ')) && !qualified.contains('*') && !qualified.contains('(') {
			mut key := qualified.all_after(' ').trim_space()
			for child in node.inner {
				// C++ names an anonymous typedef'd record after the typedef; the
				// record itself is only reachable through its node id.
				if child.owned_tag_decl.id != '' && child.owned_tag_decl.id in c.system.records {
					key = child.owned_tag_decl.id
				}
			}
			c.system.record_typedefs[name] = key
			c.register_system_record_v_name(name)
			return
		}
		if qualified.starts_with('enum ') {
			c.register_system_typedef(name, 'int')
			return
		}
		underlying := if node.ast_type.desugared_qualified != ''
			&& !node.ast_type.desugared_qualified.starts_with('enum ') {
			node.ast_type.desugared_qualified
		} else {
			qualified
		}
		c.register_system_typedef(name, underlying)
		return
	}
	if node.kind_str == 'EnumDecl' {
		for child in node.inner {
			if child.kind_str == 'EnumConstantDecl' && child.name != '' {
				c.system.enum_constants[child.name] = true
				c.system.declaring_headers[child.name] = header
			}
		}
		if node.name != '' {
			c.register_system_typedef(node.name, 'int')
		}
		return
	}
	if node.kind_str in ['FunctionDecl', 'VarDecl'] && node.name != '' {
		c.system.declaring_headers[node.name] = header
	}
}

// Only names the base type conversion does not already know are resolved
// through their declarations (standard C typedefs keep their V mappings).
fn is_passthrough_converted_type(c_name string, v_name string) bool {
	return v_name == c_name || v_name == c_name.capitalize()
		|| v_name == c_name.trim_left('_').capitalize()
}

fn (mut c C2V) register_system_typedef(name string, underlying string) {
	if name in c.system.typedefs || name == underlying {
		return
	}
	if !is_passthrough_converted_type(name, convert_type(name).name) {
		return
	}
	c.system.typedefs[name] = underlying
}

fn (mut c C2V) register_system_record_v_name(c_name string) {
	v_name := convert_type(c_name).name
	if !is_passthrough_converted_type(c_name, v_name) {
		return
	}
	// `__sigaction` and `sigaction` share a V spelling; the exact C name wins.
	if existing := c.system.record_v_names[v_name] {
		if existing.len - existing.trim_left('_').len <= c_name.len - c_name.trim_left('_').len {
			return
		}
	}
	c.system.record_v_names[v_name] = c_name
}

fn (c &C2V) system_record_key(c_name string) ?string {
	if key := c.system.record_typedefs[c_name] {
		return key
	}
	if c_name in c.system.records {
		return c_name
	}
	return none
}

// system_record_struct describes the layout of a system record, as needed for
// its aggregate initializers.
fn (c &C2V) system_record_struct(c_name string) ?Struct {
	key := c.system_record_key(c_name)?
	record := c.system.records[key] or { return none }
	if !record.defined || record.fields.len == 0 {
		return none
	}
	mut result := Struct{}
	for field in record.fields {
		result.fields << if field.name in v_reserved_words { '@' + field.name } else { field.name }
		result.field_types << c.external_record_v_field_type(field.c_type)
	}
	return result
}

fn (c &C2V) is_system_record_name(c_name string) bool {
	return (c_name in c.system.record_typedefs || c_name in c.system.records)
		&& !is_builtin_c_type_name(c_name)
}

// C types such as FILE and va_list are already declared by V or by the base
// type conversion.
fn is_builtin_c_type_name(c_name string) bool {
	return convert_type(c_name).name.starts_with('C.')
}

fn (c &C2V) is_system_enum_constant(name string) bool {
	return name in c.system.enum_constants
}

fn is_c_identifier_start(ch u8) bool {
	return (ch >= `a` && ch <= `z`) || (ch >= `A` && ch <= `Z`) || ch == `_`
}

// resolve_system_typedefs replaces system typedef names in a C type with the
// types they stand for, e.g. `const GLubyte *` => `const unsigned char *`.
fn (c &C2V) resolve_system_typedefs(typ string) string {
	if c.system.typedefs.len == 0 {
		return typ
	}
	mut result := typ
	for _ in 0 .. 8 {
		next := c.substitute_system_typedef_tokens(result)
		if next == result {
			break
		}
		result = next
	}
	return result
}

fn (c &C2V) substitute_system_typedef_tokens(typ string) string {
	mut out := strings.new_builder(typ.len + 16)
	mut i := 0
	for i < typ.len {
		if !is_c_identifier_start(typ[i]) || (i > 0 && typ[i - 1] == `.`) {
			out.write_u8(typ[i])
			i++
			continue
		}
		start := i
		for i < typ.len && is_simple_identifier_char(typ[i]) {
			i++
		}
		token := typ[start..i]
		underlying := c.system.typedefs[token] or {
			out.write_string(token)
			continue
		}
		if fn_pointer := function_type_as_pointer(underlying) {
			// A function type typedef (`typedef R name(args);`) is used through
			// pointers: `name *` is `R (*)(args)`, and a parameter of function type
			// is adjusted to a pointer too.
			mut end := i
			mut stars := 0
			for end < typ.len && typ[end] in [` `, `*`] {
				if typ[end] == `*` {
					stars++
				}
				end++
			}
			extra := if stars > 1 { '*'.repeat(stars - 1) } else { '' }
			out.write_string(fn_pointer.replace('(*)', '(*${extra})'))
			if end > i && typ[end - 1] == ` ` {
				end--
			}
			i = end
			continue
		}
		if underlying.contains('(*)') {
			// A function pointer typedef is a declarator; apply the remaining
			// pointer layers inside it rather than appending them.
			prefix := typ[..start].trim_space()
			rest := typ[i..].replace('const', '').trim_space()
			if (prefix == '' || prefix == 'const') && rest.bytes().all(it == `*`) {
				return underlying.replace('(*)', '(*${rest})')
			}
			// As a whole parameter of another function type it is written as an
			// abstract declarator.
			before := prefix.trim_string_right('const').trim_space()
			mut end := i
			for end < typ.len && typ[end] in [` `, `*`] {
				end++
			}
			if before.len > 0 && before[before.len - 1] in [`(`, `,`] && end < typ.len
				&& typ[end] in [`,`, `)`] {
				stars := typ[i..end].replace(' ', '')
				out.write_string(underlying.replace('(*)', '(*${stars})'))
				i = end
				continue
			}
			out.write_string(token)
			continue
		}
		out.write_string(underlying)
	}
	return out.str()
}

// map_system_record_names spells records from system headers as V C types,
// e.g. `&SDL_Event` => `&C.SDL_Event` and `Stat` => `C.stat`.
fn (c &C2V) map_system_record_names(v_type string) string {
	if c.system.record_v_names.len == 0 {
		return v_type
	}
	mut out := strings.new_builder(v_type.len + 8)
	mut i := 0
	for i < v_type.len {
		if !is_c_identifier_start(v_type[i]) || (i > 0 && v_type[i - 1] == `.`) {
			out.write_u8(v_type[i])
			i++
			continue
		}
		start := i
		for i < v_type.len && is_simple_identifier_char(v_type[i]) {
			i++
		}
		token := v_type[start..i]
		if c_name := c.system.record_v_names[token] {
			if token !in c.known_types && token !in c.project_known_types {
				if c_name.starts_with('_') && out.len > 0 && out.last_n(1) == '&' {
					// A pointer to an implementation-private record without a typedef
					// name (e.g. Darwin's `pthread_t`) is an opaque handle. V would
					// define a `_`-prefixed C struct itself instead of using the
					// header's.
					out.go_back(1)
					out.write_string('voidptr')
					continue
				}
				out.write_string('C.${c_name}')
				continue
			}
		}
		out.write_string(token)
	}
	return out.str()
}

// used_c_symbols returns every `C.name` referenced by generated V source.
fn used_c_symbols(src string) map[string]bool {
	mut used := map[string]bool{}
	mut search_from := 0
	for {
		rel := src[search_from..].index('C.') or { break }
		start := search_from + rel
		search_from = start + 2
		if start > 0 && (is_simple_identifier_char(src[start - 1]) || src[start - 1] == `.`) {
			continue
		}
		mut end := start + 2
		for end < src.len && is_simple_identifier_char(src[end]) {
			end++
		}
		if end > start + 2 {
			used[src[start + 2..end]] = true
		}
	}
	return used
}

// system_entry_header walks up the include chain to the system header that
// project code included directly. Headers are designed to be included there.
fn (c &C2V) system_entry_header(header string) string {
	mut current := header
	for _ in 0 .. 64 {
		includer := c.system.included_from[current] or { break }
		if !line_is_builtin_header(includer) {
			break
		}
		current = includer
	}
	return current
}

fn system_include_search_dirs(additional_flags string) []string {
	null_device := if os.user_os() == 'windows' { 'nul' } else { '/dev/null' }
	res := os.execute('${os.quoted_path(clang_exe)} -x c++ -E -v ${additional_flags} ${null_device}')
	mut dirs := []string{}
	mut inside := false
	for line in res.output.split_into_lines() {
		if line.starts_with('#include <...> search starts here') {
			inside = true
			continue
		}
		if line.starts_with('End of search list') {
			break
		}
		if inside {
			dir := line.trim_space()
			if dir == '' || dir.ends_with('(framework directory)') {
				continue
			}
			real := os.real_path(dir)
			dirs << if real != '' { real } else { dir }
		}
	}
	dirs.sort(a.len > b.len)
	return dirs
}

fn include_directive_for_header(header string, search_dirs []string) string {
	for dir in search_dirs {
		if header.starts_with(dir + '/') {
			return '#include <${header[dir.len + 1..]}>'
		}
	}
	return '#include "${header}"'
}

// function_type_as_pointer spells the function type `R (args)` as the function
// pointer type `R (*)(args)`.
fn function_type_as_pointer(typ string) ?string {
	t := typ.trim_space()
	open := t.index_u8(`(`)
	if open <= 0 || !t.ends_with(')') || t[open..].starts_with('(*') || t[open..].starts_with('(^') {
		return none
	}
	return t[..open].trim_space() + ' (*)' + t[open..]
}

fn is_anonymous_c_type(c_type string) bool {
	return c_type.contains('(unnamed') || c_type.contains('(anonymous')
}

fn (c &C2V) external_record_v_field_type(c_type string) string {
	if is_anonymous_c_type(c_type) {
		return ''
	}
	mut v_type := c.convert_type(c_type).name
	if v_type == '' || !is_well_formed_v_type(v_type) {
		// The C header declares the field; V only needs the fields it accesses.
		return ''
	}
	return v_type
}

// is_well_formed_v_type reports whether `t` is a complete V type expression:
// `&`s and fixed array dimensions around a (C.)name or a `fn (args) ret` type.
fn is_well_formed_v_type(t string) bool {
	end := parse_v_type_end(t, 0)
	return end == t.len
}

// parse_v_type_end returns the index after the V type starting at `start`, or -1.
fn parse_v_type_end(t string, start int) int {
	mut i := start
	for i < t.len && t[i] == `&` {
		i++
	}
	for i < t.len && t[i] == `[` {
		close := t.index_after_(']', i)
		if close < 0 || !string_is_digits(t[i + 1..close]) {
			return -1
		}
		i = close + 1
	}
	if t[i..].starts_with('...') {
		i += 3
	}
	if t[i..].starts_with('fn (') {
		i += 4
		for i < t.len && t[i] != `)` {
			i = parse_v_type_end(t, i)
			if i < 0 {
				return -1
			}
			if t[i..].starts_with(', ') {
				i += 2
			} else if i < t.len && t[i] != `)` {
				return -1
			}
		}
		if i >= t.len {
			return -1
		}
		i++
		if t[i..].starts_with(' ') && i + 1 < t.len && t[i + 1] != `)` && t[i + 1] != `,` {
			return parse_v_type_end(t, i + 1)
		}
		return i
	}
	name_start := i
	for i < t.len && (is_simple_identifier_char(t[i]) || t[i] == `.`) {
		i++
	}
	if i == name_start || !is_c_identifier_start(t[name_start]) {
		return -1
	}
	return i
}

// external_surface_declarations generates the V declarations needed by `src`
// for system records and the #include directives of every system declaration
// it references.
fn (c &C2V) external_surface_declarations(src string, additional_flags string) string {
	used := used_c_symbols(src)
	if used.len == 0 {
		return ''
	}
	mut out := strings.new_builder(1024)
	mut headers := map[string]bool{}
	mut names := used.keys()
	names.sort()
	for name in names {
		if is_builtin_c_type_name(name) {
			// Declared by V's own C preamble.
			continue
		}
		// V's preamble declares only part of libc, so the declaring header is
		// included even for functions V also knows.
		if header := c.system.declaring_headers[name] {
			headers[c.system_entry_header(header)] = true
		}
	}
	mut header_list := headers.keys()
	header_list.sort()
	search_dirs := if header_list.len > 0 {
		system_include_search_dirs(additional_flags)
	} else {
		[]string{}
	}
	for header in header_list {
		out.writeln(include_directive_for_header(header, search_dirs))
	}
	if header_list.len > 0 {
		out.writeln('')
	}
	mut pending := names.filter(c.is_system_record_name(it))
	mut emitted := map[string]bool{}
	for pending.len > 0 {
		name := pending.pop()
		if name in emitted {
			continue
		}
		emitted[name] = true
		key := c.system_record_key(name) or { continue }
		record := c.system.records[key] or { SystemRecord{} }
		if name in c.system.record_typedefs {
			out.writeln('@[typedef]')
		}
		keyword := if record.is_union { 'union' } else { 'struct' }
		out.writeln(keyword + ' C.' + name + ' {')
		c.write_system_record_fields(mut out, record, name, mut pending, emitted)
		out.writeln('}')
		out.writeln('')
	}
	return out.str()
}

// write_system_record_fields declares the fields of a system record. A field of
// anonymous record type gets a C record type named after the field
// (`C.C2vSys_Tcl_HashEntry_key`). C has no name for it, so V code may only
// reach its members, which keep their C names.
fn (c &C2V) write_system_record_fields(mut out strings.Builder, record SystemRecord, v_owner string, mut pending []string, emitted map[string]bool) {
	if !record.defined || record.fields.len == 0 {
		return
	}
	mut anonymous_types := []string{}
	out.writeln('pub mut:')
	for field in record.fields {
		if field.name == '' || field.name[0].is_capital() {
			continue
		}
		mut field_type := c.external_record_v_field_type(field.c_type)
		if field.anon_key != '' {
			if field.anon_key in c.system.records {
				owner := if v_owner.starts_with('C.C2vSys_') {
					v_owner
				} else {
					'C.C2vSys_' + v_owner.trim_left('_')
				}
				field_type = '${owner}_${field.name}'
				anonymous_types << field_type
				anonymous_types << field.anon_key
			}
		}
		if field_type == '' {
			continue
		}
		field_name := if field.name in v_reserved_words { '@' + field.name } else { field.name }
		out.writeln('\t' + field_name + ' ' + field_type)
		for dependency, _ in used_c_symbols(field_type) {
			if dependency !in emitted && c.is_system_record_name(dependency) {
				pending << dependency
			}
		}
	}
	for i := 0; i < anonymous_types.len; i += 2 {
		v_name := anonymous_types[i]
		anonymous := c.system.records[anonymous_types[i + 1]] or { continue }
		out.writeln('}')
		out.writeln('')
		out.writeln((if anonymous.is_union { 'union ' } else { 'struct ' }) + v_name + ' {')
		c.write_system_record_fields(mut out, anonymous, v_name, mut pending, emitted)
	}
}
