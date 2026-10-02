module main

import strings

// record_is_packed reports whether a record is declared with
// `__attribute__((packed))`, which V's `@[packed]` reproduces.
fn record_is_packed(node &Node) bool {
	return node.inner.any(it.kind_str == 'PackedAttr')
}

// warn_untranslated_record_packing reports a record laid out under
// `#pragma pack`, whose alignment Clang's JSON AST does not record.
fn (c &C2V) warn_untranslated_record_packing(node &Node, v_name string) {
	if !record_is_packed(node) && node.inner.any(it.kind_str == 'MaxFieldAlignmentAttr') {
		eprintln("c2v: warning: ${c.cur_file}:${node.location.line}: `#pragma pack` is not translated; `${v_name}` keeps V's default field alignment")
	}
}

fn (c &C2V) has_project_record_definition(node &Node) bool {
	if node.name == '' {
		return false
	}
	for id in c.record_decls_by_name[node.name] {
		declaration := c.callback_seen_ids[id] or { continue }
		if declaration.id == node.id || declaration.inner.len == 0 {
			continue
		}
		declaration_path := c.node_source_path(declaration)
		if declaration_path == ''
			|| !line_is_builtin_header(normalize_cpp_source_path(declaration_path)) {
			return true
		}
	}
	return false
}

fn (c &C2V) has_opaque_pointer_typedef(node &Node) bool {
	if node.id == '' {
		return false
	}
	return node.id in c.pointer_typedef_tag_ids
}

// resolve_type_alias resolves type alias chains to the underlying type.
// V doesn't allow type A = B where B is also a type alias.
fn (c &C2V) resolve_type_alias(type_name string) string {
	if type_name.starts_with('&') {
		return '&' + c.resolve_type_alias(type_name[1..])
	}
	if type_name.starts_with('[]') {
		return '[]' + c.resolve_type_alias(type_name[2..])
	}
	if type_name.starts_with('[') {
		idx := type_name.index(']') or { -1 }
		if idx >= 0 && idx + 1 < type_name.len {
			return type_name[..idx + 1] + c.resolve_type_alias(type_name[idx + 1..])
		}
	}
	if local_alias := c.file_type_alias_names[type_name] {
		return c.resolve_type_alias(local_alias)
	}
	if type_name.starts_with('C.') {
		unprefixed := type_name[2..]
		if unprefixed in c.type_aliases {
			return c.resolve_type_alias(unprefixed)
		}
	}
	// If this type is a known alias, resolve to its underlying type
	if underlying := c.type_aliases[type_name] {
		// Recursively resolve in case of chains
		return c.resolve_type_alias(underlying)
	}
	return type_name
}

// record_layout_signature identifies a C record layout by its fields' names
// and types.
fn record_layout_signature(node &Node) string {
	mut parts := []string{}
	for field in node.inner {
		if field.kind == .field_decl || field.kind_str == 'FieldDecl' {
			// An anonymous member type is spelled with its declaration location,
			// which differs between translation units that include the header.
			mut typ := field.ast_type.qualified
			key := anonymous_record_key(typ)
			if key != '' {
				typ = typ.replace(key, '')
			}
			parts << '${field.name}:${typ}'
		}
	}
	return parts.join(';')
}

fn record_decl_field_names(node &Node) []string {
	mut names := []string{}
	for field in node.inner {
		if !field.kindof(.field_decl) {
			continue
		}
		filtered := filter_name(field.name, false)
		names << if filtered.starts_with('C.') {
			filtered[2..] + '_'
		} else {
			filtered.uncapitalize()
		}
	}
	return names
}

// C++ record fields go through additional spelling normalization when their
// layout is stored in `c.structs`. Keep duplicate-layout detection on that same
// representation, otherwise ordinary header typedefs such as `frameData_t`
// look different in every translation unit (`memoryHighwater` versus
// `memory_highwater`) and are incorrectly made file-local.
fn cxx_record_decl_field_names(node &Node) []string {
	mut method_field_collisions := map[string]bool{}
	for child in node.inner {
		if is_cpp_method_like_decl(child) && child.name != '' {
			method_field_collisions[method_base_name_from_cpp_name(child.name)] = true
		}
	}
	mut names := []string{}
	for field in node.inner {
		if !field.kindof(.field_decl) {
			continue
		}
		// Keep in sync with the field names cxx_record_decl emits.
		raw_name := if field.name != '' {
			cpp_field_v_name(field.name)
		} else if anonymous_member := cpp_anonymous_member_name(field.ast_type.qualified) {
			anonymous_member
		} else {
			'_'
		}
		names << if raw_name in method_field_collisions {
			raw_name + '_field'
		} else {
			raw_name
		}
	}
	return names
}

// |-RecordDecl 0x7fd7c302c560 <a.c:3:1, line:5:1> line:3:8 struct User definition
fn (mut c C2V) record_decl(node &Node) {
	vprintln('record_decl("${node.name}")')
	// A bare C forward declaration denotes an external C ABI type. C++ opaque
	// project records are handled separately by cxx_record_decl.
	if node.kindof(.record_decl) && node.inner.len == 0 {
		return
	}
	mut c_name := node.name
	if c.forced_record_name != '' {
		// An anonymous member record named after its field (see
		// declare_anonymous_member_records).
		c_name = c.forced_record_name
		c.forced_record_name = ''
	}
	// Dont generate struct header if it was already generated by typedef
	// Confusing, but typedefs in C AST are really messy.
	// ...
	// If the struct has no name, then it's `typedef struct { ... } name`
	// AST: 1) RecordDecl struct definition 2) TypedefDecl struct name
	if c.tree.inner.len > c.node_i + 1 && c_name == node.name {
		next_node := c.tree.inner[c.node_i + 1]
		if next_node.kind == .typedef_decl && typedef_names_tag(&next_node, node) {
			if c.is_verbose {
				c.genln('// typedef struct')
			}
			c_name = next_node.name
		}
	}

	if c_name in builtin_type_names {
		return
	}
	if c.is_verbose {
		c.genln('// struct decl name="${c_name}"')
	}
	// Anonymous struct, most likely the next node is a vardecl with this anon struct type, so remember it
	if c_name == '' {
		c_name = 'AnonStruct_${node.location.line}'
		c.last_declared_type_name = c_name
	}

	// First pass: scan for anonymous enums and generate named enum types BEFORE the struct.
	// V doesn't support inline `enum {}` in struct fields like it does for struct/union.
	// We need to generate the enum as a separate named type.
	mut anon_enum_names := map[int]string{} // maps field index to generated enum name
	mut struct_v_name := c.add_struct_name(mut c.types, c_name)
	// Separate translation units may reuse an anonymous typedef name for private
	// records with different layouts. They are distinct C/C++ types, but a flat V
	// module cannot declare both under the same name. Qualify the later layout and
	// all following references in this source file with its file name.
	// (C also reuses record tags across translation units: function-local
	// `struct Cmd` tables with different fields.)
	if (node.name == '' || (!c.is_cpp && c.is_dir)) && struct_v_name in c.generated_declarations {
		if existing := c.structs[struct_v_name] {
			differs := if c.is_cpp {
				existing.fields != record_decl_field_names(node)
			} else {
				c.record_layouts[struct_v_name] or { '' } != record_layout_signature(node)
			}
			if differs {
				file_token :=
					sanitize_type_token(c.cur_file.all_after_last('/').all_before_last('.'))
				local_name := '${struct_v_name}_${file_token}'
				c.file_type_alias_names[struct_v_name] = local_name
				c_name = local_name
				struct_v_name = c.add_struct_name(mut c.types, c_name)
			}
		}
	}
	mut pending_enum := &Node(unsafe { nil })
	for i, field in node.inner {
		if field.kind == .enum_decl {
			pending_enum = unsafe { &node.inner[i] }
			continue
		}
		if field.kind == .field_decl && pending_enum != unsafe { nil } {
			// Check the raw type string (not converted) for anonymous enum detection
			if field.ast_type.qualified.contains('unnamed enum')
				|| field.ast_type.qualified.contains('anonymous enum') {
				// Generate a named enum for this anonymous enum
				field_name := filter_name(field.name, false)
				enum_name := c.generate_named_enum_for_anon(pending_enum, struct_v_name, field_name)
				anon_enum_names[i] = enum_name
			}
			pending_enum = unsafe { nil }
		}
	}

	// A named record defined inside another one (`struct A { union B {...} u; }`)
	// is a file scope type in C: declare it before the enclosing record.
	for field in node.inner {
		if is_named_nested_record(field) {
			old_node_i := c.node_i
			c.node_i = c.tree.inner.len
			c.record_decl(field)
			c.node_i = old_node_i
		}
	}
	if !c.is_cpp {
		c.declare_anonymous_member_records(node, struct_v_name)
	}
	if c_name !in ['struct', 'union'] {
		// prevent duplicate generations:
		if struct_v_name in c.generated_declarations {
			return
		}
		c.generated_declarations[struct_v_name] = true
		if node.tags.contains('union') {
			c.genln('union ${struct_v_name} { ')
		} else {
			if record_is_packed(node) {
				c.genln('@[packed]')
			}
			c.warn_untranslated_record_packing(node, struct_v_name)
			c.genln('struct ${struct_v_name} { ')
		}
	}
	mut new_struct := Struct{}
	// V field names start with a lowercase letter, so C fields such as `M` and `m`
	// would collide. The field declared lowercase in C keeps its name.
	mut taken_field_names := map[string]bool{}
	for field in node.inner {
		if field.kind == .field_decl && field.name != '' && !field.name[0].is_capital() {
			taken_field_names[filter_name(field.name, false)] = true
		}
	}
	// in V it's `field struct {...}`, but in C we get struct definition first, so save it and use it in the
	// next child
	mut anon_struct_definition := ''
	mut anon_enum_definition := ''
	for i, field in node.inner {
		c.gen_comment(field)
		if is_named_nested_record(field) || (field.kind == .record_decl
			&& c.anonymous_record_type_name(i, node) != '') {
			continue
		}
		// Handle anon structs and unions (unions appear as RecordDecl with tagUsed='union')
		if field.kind == .record_decl {
			is_union := field.tags.contains('union')
			anon_struct_definition = c.anon_struct_field_type(field, is_union)
			continue
		}
		if field.kind == .union_decl {
			anon_struct_definition = c.anon_struct_field_type(field, true)
			continue
		}
		// Handle anon enums - skip, already processed in first pass
		if field.kind == .enum_decl {
			continue
		}
		// There may be comments, skip them
		if field.kind != .field_decl {
			continue
		}
		raw_type := field.ast_type.qualified
		field_type := c.convert_record_field_type(raw_type, field.id)
		filtered := filter_name(field.name, false)
		// Don't uncapitalize if it's a C. prefixed name (builtin function)
		mut field_name := if renamed := c.c_field_v_names[field.id] {
			renamed
		} else if filtered.starts_with('C.') {
			filtered[2..] + '_'
		} else {
			filtered.uncapitalize()
		}
		if !c.is_cpp && field.name != '' && field.name[0].is_capital() {
			for (field_name in taken_field_names) {
				field_name += '_'
			}
			taken_field_names[field_name] = true
			if field_name != filtered.uncapitalize() && field.id != '' {
				c.c_field_v_names[field.id] = field_name
			}
		}
		mut field_type_name := field_type.name

		// Handle anon structs/unions, the anonymous type has just been defined above, use its definition
		// Check raw type string since convert_type may not preserve "unnamed" markers
		if anonymous_record_key(raw_type) in c.anonymous_record_names {
			// Declared as a named V record above.
		} else if (raw_type.contains('unnamed struct') || raw_type.contains('unnamed union')
			|| raw_type.contains('(unnamed at')
			|| raw_type.contains('anonymous struct')
			|| raw_type.contains('anonymous union')) && !raw_type.contains('unnamed enum')
			&& !raw_type.contains('anonymous enum') {
			field_type_name = anon_struct_definition
		}
		// Handle anon enums - use the pre-generated named enum type
		// Check raw type (field.ast_type.qualified) since convert_type converts unnamed enums to 'int'
		if field.ast_type.qualified.contains('unnamed enum')
			|| field.ast_type.qualified.contains('anonymous enum') {
			if i in anon_enum_names {
				field_type_name = anon_enum_names[i]
			} else {
				field_type_name = anon_enum_definition
			}
		}
		if field_type_name.contains('anonymous at') {
			continue
		}
		/*
		if field_type.name.contains('union') {
			continue // TODO
		}
		*/
		new_struct.fields << field_name
		mut final_field_type := c.prefix_external_type(field_type_name)
		if !c.is_cpp && final_field_type.starts_with('[]') {
			// A flexible array member (`T a[]`): V has no zero-length arrays, so it
			// is a one-element array indexed without bounds checks (see
			// collect_variable_size_fields). Its offset matches C's.
			final_field_type = '[1]' + final_field_type[2..]
		}
		if !c.is_cpp && c.pointer_array_to_owner(final_field_type) {
			c.voidptr_array_fields[field.id] = final_field_type.all_after_last(']')
			final_field_type = final_field_type.all_before_last(']') + ']voidptr'
		}
		new_struct.field_types << final_field_type
		c.genln('\t${field_name} ${final_field_type}')
	}
	c.structs[c_name] = new_struct
	c.structs[struct_v_name] = new_struct
	c.record_layouts[struct_v_name] = record_layout_signature(node)
	c.structs[c_name.capitalize()] = new_struct
	c.genln('}')
}

// declare_anonymous_member_records declares each anonymous record used by a
// member (`union { ... } u;`) as a top level V record named after the
// member (`FuncDef_u`). V's inline anonymous records cannot be named, so they
// could not be initialized, copied or pointed to.
fn (mut c C2V) declare_anonymous_member_records(node &Node, owner string) {
	mut taken_member_names := map[string]bool{}
	for field in node.inner {
		if field.kind == .field_decl && field.name != '' {
			taken_member_names[c_record_field_v_name(field.name)] = true
		}
	}
	for i, field in node.inner {
		if field.kind != .record_decl || field.name != '' || field.inner.len == 0 {
			continue
		}
		member := anonymous_record_member(i, node) or { continue }
		key := anonymous_record_key(member.ast_type.qualified)
		if key == '' {
			continue
		}
		mut member_name := if member.name == '' {
			// Give promoted anonymous members storage without flattening their
			// union layout. Clang represents access through this implicit field.
			'c2v_anonymous_${member.location.offset}'
		} else {
			// Keep the record-field spelling for builtin names such as `exit`.
			c_record_field_v_name(member.name)
		}
		if member.name == '' {
			// Macro-expanded declarations have no direct source offset. Reserve
			// explicit field names too, since C can use our synthetic prefix.
			base_name := member_name
			mut suffix := 1
			for (member_name in taken_member_names) {
				member_name = '${base_name}_${suffix}'
				suffix++
			}
			taken_member_names[member_name] = true
		}
		if member.name == '' && member.id != '' {
			c.c_field_v_names[member.id] = member_name
		}
		name := c.allocate_anonymous_member_type(field, owner, member, member_name)
		c.anonymous_record_names[key] = name
		for declarator in anonymous_record_members(i, node) {
			c.anonymous_record_member_types[declarator.id] = name
		}
		c.known_types[name] = true
		c.project_known_types[name] = true
		old_node_i := c.node_i
		c.node_i = c.tree.inner.len
		c.forced_record_name = name
		c.record_owner_stack << owner
		c.record_decl(field)
		c.record_owner_stack.delete_last()
		c.node_i = old_node_i
	}
}

fn (c &C2V) record_type_name_taken(name string) bool {
	return name in c.reserved_type_names || name in c.types || name in c.types.values()
		|| name in c.enums || name in c.enums.values() || name in c.type_aliases
		|| name in c.structs || name in c.generated_declarations
		|| name in c.known_types || name in c.project_known_types
}

fn (mut c C2V) allocate_anonymous_member_type(record &Node, owner string, member Node, member_name string) string {
	// Declaration IDs change per translation unit, and macro source locations
	// can repeat for different members. Reuse only this owner's matching member
	// and layout, so including a header twice keeps its generated types stable.
	member_identity := if member.name != '' { member.name } else { member_name }
	identity := '${owner}|${member_identity}|${record.tags}|${record_layout_signature(record)}'
	if name := c.anonymous_record_allocations[identity] {
		return name
	}
	base_name := '${owner}_${member_name}'
	mut name := base_name
	mut suffix := 1
	for c.record_type_name_taken(name) {
		name = '${base_name}_${suffix}'
		suffix++
	}
	c.anonymous_record_allocations[identity] = name
	return name
}

// pointer_array_to_owner reports whether `v_type` is a fixed array of pointers
// to a record that encloses the one being declared (`[62]&Bitvec` in a union
// member of Bitvec). V's C backend wrongly orders such arrays after their
// pointee, a false dependency cycle; they are stored as arrays of voidptr.
fn (c &C2V) pointer_array_to_owner(v_type string) bool {
	mut elem := v_type
	for elem.starts_with('[') {
		close := elem.index(']') or { return false }
		elem = elem[close + 1..]
	}
	return elem != v_type && elem.starts_with('&') && !elem.starts_with('&&')
		&& elem[1..] in c.record_owner_stack
}

// anonymous_record_member is the field declared with the anonymous
// record at `index` of `node`.
fn anonymous_record_member(index int, node &Node) ?Node {
	for j := index + 1; j < node.inner.len; j++ {
		next := node.inner[j]
		if next.kind == .field_decl {
			return next
		}
		if next.kind == .record_decl {
			return none
		}
	}
	return none
}

// A declaration can have several comma-separated fields, with different
// pointer or array declarators. Their types share a spelling and declaration
// start, but another macro-expanded record can share that spelling too.
fn anonymous_record_members(index int, node &Node) []Node {
	member := anonymous_record_member(index, node) or { return []Node{} }
	key := anonymous_record_key(member.ast_type.qualified)
	if key == '' {
		return []Node{}
	}
	mut members := []Node{}
	for j := index + 1; j < node.inner.len; j++ {
		next := node.inner[j]
		if next.kind == .record_decl {
			break
		}
		if next.kind != .field_decl {
			continue
		}
		// Clang omits repeated file paths, so compare source offsets rather
		// than the complete location objects.
		if anonymous_record_key(next.ast_type.qualified) != key
			|| next.range.begin.offset != member.range.begin.offset
			|| next.range.begin.spelling_file.offset != member.range.begin.spelling_file.offset
			|| next.range.begin.expansion_file.offset != member.range.begin.expansion_file.offset {
			break
		}
		members << next
	}
	return members
}

// anonymous_record_type_name is the V name given to the anonymous record at
// `index` of `node`, or ''.
fn (c &C2V) anonymous_record_type_name(index int, node &Node) string {
	member := anonymous_record_member(index, node) or { return '' }
	return c.anonymous_record_member_types[member.id] or { '' }
}

// anonymous_record_key extracts the declaration location that identifies an
// anonymous record in a Clang type spelling: `union (unnamed union at f.c:12:3)`
// and `union Outer::(unnamed at f.c:12:3)` both give `f.c:12:3`.
fn anonymous_record_key(type_name string) string {
	for marker in ['(unnamed ', '(anonymous '] {
		start := type_name.index(marker) or { continue }
		at := type_name.index_after_(' at ', start)
		close := type_name.index_after_(')', start)
		if at > start && close > at {
			return type_name[at + 4..close]
		}
	}
	return ''
}

// A field's declaration distinguishes anonymous records sharing a macro
// location. Substitute its name before conversion to retain the declarator.
fn (c &C2V) convert_record_field_type(typ string, field_id string) Type {
	if name := c.anonymous_record_member_types[field_id] {
		return c.convert_type(anonymous_record_type_with_name(typ, name))
	}
	return c.convert_type(typ)
}

// Give a Clang anonymous record a name while preserving its qualifiers and
// the pointer or array declarator following its source-location spelling.
fn anonymous_record_type_with_name(typ string, name string) string {
	for marker in ['(unnamed ', '(anonymous '] {
		open := typ.index(marker) or { continue }
		close := typ.index_after_(')', open)
		if close < 0 {
			return typ
		}
		// Drop the tag keyword and an enclosing `Outer::`, keeping qualifiers.
		qualifiers := typ[..open].split(' ').filter(it != '' && it !in ['struct', 'union']
			&& !it.ends_with('::'))
		return (qualifiers.join(' ') + ' ' + name + typ[close + 1..]).trim_space()
	}
	return typ
}

// is_named_nested_record reports whether a record member is the definition of a
// named record (C gives it file scope), rather than an anonymous inline type.
fn is_named_nested_record(node Node) bool {
	return node.kind == .record_decl && node.name != '' && node.inner.len > 0
}

fn (mut c C2V) anon_struct_field_type(node &Node, is_union bool) string {
	return c.anon_struct_field_type_at_depth(node, is_union, 1)
}

fn (mut c C2V) anon_struct_field_type_at_depth(node &Node, is_union bool, depth int) string {
	mut sb := strings.new_builder(50)
	if is_union {
		sb.write_string('union {\n')
	} else {
		sb.write_string('struct {\n')
	}
	mut max_field_name_len := 0
	for field in node.inner {
		if field.kind == .field_decl {
			field_name_len := filter_name(field.name, false).len
			if field_name_len > max_field_name_len {
				max_field_name_len = field_name_len
			}
		}
	}
	mut nested_anon_def := ''
	for field in node.inner {
		// Handle nested anonymous struct/union definitions
		if field.kind == .record_decl {
			nested_is_union := field.tags.contains('union')
			nested_anon_def = c.anon_struct_field_type_at_depth(field, nested_is_union, depth + 1)
			continue
		}
		if field.kind != .field_decl {
			continue
		}
		field_type := c.convert_type(field.ast_type.qualified)
		field_name := filter_name(field.name, false)
		mut field_type_name := field_type.name
		// Use nested anonymous definition if this field references one
		// Check raw type string since convert_type may convert unnamed types to voidptr
		raw_type := field.ast_type.qualified
		if raw_type.contains('unnamed struct') || raw_type.contains('unnamed union')
			|| raw_type.contains('(unnamed at') || raw_type.contains('anonymous struct')
			|| raw_type.contains('anonymous union') {
			field_type_name = nested_anon_def
		}
		// Apply external type prefix for types from headers
		field_type_name = c.prefix_external_type(field_type_name)
		padding := strings.repeat(` `, max_field_name_len - field_name.len + 1)
		sb.write_string('${strings.repeat(`\t`, depth + 1)}${field_name}${padding}${field_type_name}\n')
	}
	sb.write_string('${strings.repeat(`\t`, depth)}}')
	return sb.str()
}

fn (mut c C2V) anon_enum_field_type(node &Node) string {
	mut sb := strings.new_builder(50)
	sb.write_string('enum {\n')
	for i, child in node.inner {
		if child.kind != .enum_constant_decl {
			continue
		}
		c_name := filter_name(child.name, false)
		v_name := c_identifier_to_v_name(c_name)
		sb.write_string('${v_name}')
		// handle custom enum vals, e.g. `MF_SHOOTABLE = 4`
		if child.inner.len > 0 {
			mut const_expr := child.inner[0]
			if const_expr.kind == .constant_expr && const_expr.inner.len > 0 {
				// Try to get the literal value
				literal := const_expr.inner[0]
				if literal.kind == .integer_literal {
					sb.write_string(' = ${literal.value.to_str()}')
				}
			}
		}
		sb.write_string('\n')
		_ = i
	}
	sb.write_string('}')
	return sb.str()
}

// Generate a named enum type for an anonymous enum field in a struct.
// V doesn't support inline `enum {}` syntax in struct fields (unlike struct/union),
// so we generate a separate named enum type before the struct.
// Returns the generated enum type name.
fn (mut c C2V) generate_named_enum_for_anon(node &Node, struct_name string, field_name string) string {
	// Create enum name from struct name + field name, e.g. "With_anon_enum_Status"
	enum_name := '${struct_name}_${field_name.capitalize()}'

	// Generate the enum definition
	c.genln('enum ${enum_name} {')
	for child in node.inner {
		if child.kind != .enum_constant_decl {
			continue
		}
		c_name := filter_name(child.name, false)
		v_name := c_identifier_to_v_name(c_name)
		mut line := '\t${v_name}'
		// handle custom enum vals, e.g. `MF_SHOOTABLE = 4`
		if child.inner.len > 0 {
			mut const_expr := child.inner[0]
			if const_expr.kind == .constant_expr && const_expr.inner.len > 0 {
				// Try to get the literal value
				literal := const_expr.inner[0]
				if literal.kind == .integer_literal {
					line += ' = ${literal.value.to_str()}'
				}
			}
		}
		c.genln(line)
	}
	c.genln('}')
	c.genln('')

	// Register the generated enum so prefix_external_type recognizes it
	c.enums[enum_name] = enum_name
	return enum_name
}

// Typedef node goes after struct enum, but we need to parse it first, so that "type name { " is
// generated first

fn (mut c C2V) typedef_decl(node &Node) {
	mut typ := if node.ast_type.qualified.contains('<') && node.ast_type.desugared_qualified != '' {
		node.ast_type.desugared_qualified
	} else {
		node.ast_type.qualified
	}
	if typ.contains('::*') {
		// Member pointers are stored as raw function/field addresses.
		typ = 'void *'
	}
	original_typ := typ
	// just a single line typedef: (alias)
	// typedef sha1_context_t sha1_context_s ;
	// typedef after enum decl, just generate "enum NAME {" header
	mut c_alias_name := node.name // get_val(-2)
	source_alias_name := c_alias_name
	if c_alias_name.contains('et_context_t') {
		// TODO remove this
		return
	}
	if c_alias_name in builtin_type_names {
		return
	}

	if c_alias_name in c.enums {
		// Enum typedefs are handled by enum_decl.
		return
	}
	c_underlying := if node.ast_type.desugared_qualified != '' {
		node.ast_type.desugared_qualified
	} else {
		node.ast_type.qualified
	}
	if is_c_arithmetic_type_spelling(c_underlying) {
		c.arithmetic_typedef_c_types[convert_type(c_alias_name).name] = c_underlying.trim_space()
	}
	base_v_alias_name := c_alias_name.capitalize()
	if local_alias := c.file_type_alias_names[base_v_alias_name] {
		c_alias_name = local_alias
	}
	if base_v_alias_name !in c.file_declared_aliases {
		if existing_underlying := c.type_aliases[base_v_alias_name] {
			candidate_underlying := c.prefix_external_type(c.convert_type(typ).name)
			if c.resolve_type_alias(existing_underlying) != c.resolve_type_alias(candidate_underlying) {
				file_token :=
					sanitize_type_token(c.cur_file.all_after_last('/').all_before_last('.'))
				local_alias := '${base_v_alias_name}_${file_token}'
				c.file_type_alias_names[base_v_alias_name] = local_alias
				c_alias_name = local_alias
			}
		}
	}

	alias_has_concrete_decl := c_alias_name.capitalize() in c.generated_declarations
		|| 'cpp_struct:${c_alias_name.capitalize()}' in c.generated_declarations
	v_alias_name := c.add_struct_name(mut c.types, c_alias_name)
	typedef_key := 'typedef:${v_alias_name}'
	if typedef_key in c.generated_declarations {
		return
	}

	if typ.starts_with('struct ') && typ.ends_with(' *') {
		// Opaque pointer, for example: typedef struct TSTexture_t *TSTexture;
		c.generated_declarations[typedef_key] = true
		c.genln('type ${v_alias_name} = voidptr')
		return
	}

	if typ.trim_space().starts_with('__builtin_') {
		// A name for a compiler builtin type (`typedef __builtin_va_list
		// va_list;`): c2v translates the builtin type itself.
		return
	}
	// (A whole identifier: `typedef uint32_t uint32;` aliases another name.)
	if !contains_identifier_token(typ, source_alias_name) {
		if typ.contains('struct ') || typ.contains('class ') || typ.contains('union ') {
			if alias_has_concrete_decl {
				c.generated_declarations[typedef_key] = true
				return
			}
		}
		// Function pointer: int (*)(args)
		if typ.contains('(*)') {
			tt := c.convert_type(typ)
			typ = c.prefix_external_type(tt.name)
		} else if typ.count('(') > 2 {
			// Function type without pointer: int (args) - e.g., typedef int fn_name(args)
			// Note: don't require comma - single-argument functions like "void (void *)" have no comma
			// Skip types with nested function pointers (too complex to parse)
			c.genln('// TODO: complex function pointer typedef: ${c_alias_name}')
			return
		} else if typ.contains('(') && typ.contains(')') && !typ.starts_with('(') {
			// Parse function type: "int (arg1, arg2, ...)" -> "fn (arg1, arg2) int"
			// A pointer to this function type is itself a V function value.
			c.function_type_aliases[c_alias_name.capitalize()] = true
			ret_typ := c.convert_type(typ.all_before('(').trim_space())
			mut s := 'fn ('
			sargs := typ.find_between('(', ')')
			args := sargs.split(',')
			for i, arg in args {
				t := c.convert_type(arg.trim_space())
				s += c.prefix_external_type(t.name)
				if i < args.len - 1 {
					s += ', '
				}
			}
			if ret_typ.name == 'void' {
				typ = s + ')'
			} else {
				typ = '${s}) ${c.prefix_external_type(ret_typ.name)}'
			}
			typ = typ.replace('(void)', '()')
		} else {
			// Struct types have junk before spaces
			c_alias_name = c_alias_name.all_after(' ')
			tt := c.convert_type(typ)
			typ = c.prefix_external_type(tt.name)
		}
		if c_alias_name.starts_with('__') {
			// Skip internal stuff like __builtin_ms_va_list
			return
		}
		if typ in c.enums {
			return
		}

		mut cgen_alias := typ
		if cgen_alias.starts_with('_') {
			cgen_alias = trim_underscores(typ)
		}
		if typ !in ['int', 'i8', 'i16', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'f32', 'f64',
			'usize', 'isize', 'bool', 'void', 'voidptr'] && !typ.starts_with('fn (') {
			// TODO handle this better
			cgen_alias = cgen_alias.capitalize()
		}
		// Resolve type alias chains - V doesn't allow type A = B where B is an alias
		resolved_alias := c.resolve_type_alias(cgen_alias)
		prefixed_alias := c.prefix_external_type(resolved_alias)
		// A forward typedef may resolve through the tag-to-typedef map to its
		// own V spelling. The later record supplies that type; a self alias
		// would make recursive alias resolution overflow the stack.
		if prefixed_alias == v_alias_name {
			c.generated_declarations[typedef_key] = true
			return
		}
		// Store this alias mapping for future resolution
		c.type_aliases[c_alias_name.capitalize()] = prefixed_alias
		c.file_declared_aliases[c_alias_name.capitalize()] = true
		raw_layout_name :=
			original_typ.replace('struct ', '').replace('class ', '').replace('union ', '').trim_space()
		for layout_name in [raw_layout_name, raw_layout_name.capitalize(), prefixed_alias] {
			if layout := c.structs[layout_name] {
				c.structs[c_alias_name] = layout
				c.structs[c_alias_name.capitalize()] = layout
				break
			}
		}
		c.generated_declarations[typedef_key] = true
		c.genln('type ${c_alias_name.capitalize()} = ${prefixed_alias}') // typedef alias (SINGLE LINE)')
		return
	}
	if typ.contains('enum ') {
		// enums were alredy handled in enum_decl
		return
	} else if typ.contains('struct ') || typ.contains('class ') || typ.contains('union ') {
		alias_name := c_alias_name.capitalize()
		underlying := c.prefix_external_type(c.convert_type(typ).name)
		if alias_has_concrete_decl {
			// Concrete declaration with the same name already exists.
			// Skip conflicting typedef aliases like:
			//   struct Foo { ... }
			//   typedef struct Bar Foo;
			c.generated_declarations[typedef_key] = true
			return
		}
		if underlying != alias_name && c.convert_type(c_alias_name).name == underlying {
			// `typedef struct H {...} H;`: V spells both names `H_` (single capital
			// letters are reserved), so there is nothing to alias.
			c.generated_declarations[typedef_key] = true
			return
		}
		if underlying != alias_name {
			// Alias to a distinct tag type: keep it as a type alias.
			resolved_alias := c.resolve_type_alias(underlying)
			c.type_aliases[alias_name] = resolved_alias
			c.file_declared_aliases[alias_name] = true
			c.generated_declarations[typedef_key] = true
			c.genln('type ${alias_name} = ${resolved_alias}')
			return
		}
		// Self-typedef without an emitted concrete declaration in this TU.
		// Example: typedef struct foo foo; with no matching record emitted by c2v.
		// Skip when a real definition is known for this translation unit.
		if alias_name in c.known_types {
			return
		}
		decl_key := 'typedef_stub:${alias_name}'
		if decl_key in c.generated_declarations {
			return
		}
		c.generated_declarations[decl_key] = true
		if typ.contains('union ') {
			c.genln('union ${alias_name} {')
			c.genln('}')
		} else {
			c.genln('struct ${alias_name} {')
			c.genln('}')
		}
		c.generated_declarations[typedef_key] = true
		return
	}
}

// this calls typedef_decl() above
fn (mut c C2V) parse_next_typedef() bool {
	// Hack: typedef with the actual enum name is next, parse it and generate "enum NAME {" first
	/*
	XTODO
	next_line := c.lines[c.line_i + 1]
	if next_line.contains('TypedefDecl') {
		c.line_i++
		c.parse_next_node()
		return true
	}
	*/
	return false
}
