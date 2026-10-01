module main

import os
import strings
import hash.fnv1a

fn (mut c C2V) cpp_member_base_embed_name(receiver_type string, member_expr &Node) string {
	if receiver_type == '' || member_expr.referenced_member_decl == '' {
		return ''
	}
	declaration := c.callback_seen_ids[member_expr.referenced_member_decl] or { return '' }
	owner_raw := extract_class_from_mangled(declaration.mangled_name)
	if owner_raw == '' {
		return ''
	}
	owner := normalize_cpp_operator_type_name(c.convert_type(owner_raw).name)
	if owner == '' || owner == receiver_type {
		return ''
	}
	mut seen := map[string]bool{}
	path := c.cpp_base_embed_path(receiver_type, owner, mut seen)
	if path == '' {
		return ''
	}
	return if c.cpp_method_embed_path_needed(receiver_type, path, member_expr.name) {
		path
	} else {
		''
	}
}

// cpp_method_embed_path_needed reports whether a call of an inherited method
// must name the path to the embedded base declaring it. V's method promotion
// finds the method when no class on the way declares one of the same name,
// nor another base; the explicit path is then unnecessary (and V rejects it
// for a mutable method called on an indexed element).
fn (c &C2V) cpp_method_embed_path_needed(receiver_type string, path string, cpp_method_name string) bool {
	method_base := method_base_name_from_cpp_name(cpp_method_name.trim_left('.'))
	mut chain := [receiver_type]
	chain << path.split('.')
	for i := 0; i < chain.len - 1; i++ {
		class_name := chain[i]
		if c.class_has_method_base(class_name, method_base) {
			return true
		}
		for base in c.cpp_class_bases[class_name] {
			base_name := normalize_cpp_operator_type_name(base)
			mut base_seen := map[string]bool{}
			if base_name != chain[i + 1]
				&& c.class_or_base_has_method_base(base_name, method_base, mut base_seen) {
				return true
			}
		}
	}
	return false
}

fn (mut c C2V) cpp_abstract_default_decl_call_name(declaration_id string, cpp_method_name string,
	receiver_expr Node, receiver_type string, fallback string) string {
	if fallback == '' || !receiver_expr.kindof(.implicit_cast_expr)
		|| !receiver_expr.cast_kind.contains('DerivedToBase')
		|| !cpp_receiver_is_direct_this(receiver_expr) {
		return fallback
	}
	mut owner := receiver_type
	mut declaration_has_body := false
	if declaration := c.callback_seen_ids[declaration_id] {
		declaration_has_body = declaration.has_child_of_kind(.compound_stmt)
			|| has_direct_child_kind_str(declaration, 'CompoundStmt')
		owner_raw := extract_class_from_mangled(declaration.mangled_name)
		if owner_raw != '' {
			owner = normalize_cpp_operator_type_name(c.convert_type(owner_raw).name)
		}
	}
	method_base := method_base_name_from_cpp_name(cpp_method_name.trim_left('.'))
	method_key := '${owner}.${method_base}'
	if owner in c.cpp_abstract_types
		&& (declaration_has_body || method_key in c.cpp_method_body_bases
			|| c.method_defined_in_current_output_dir_from_sources(method_key)) {
		return 'c2v_default_${fallback}'
	}
	return fallback
}

fn (mut c C2V) cpp_abstract_default_call_name(member_expr &Node, receiver_expr Node,
	receiver_type string, fallback string) string {
	return c.cpp_abstract_default_decl_call_name(member_expr.referenced_member_decl, member_expr.name, receiver_expr, receiver_type, fallback)
}

fn cpp_abstract_base_accessor_name(base_type string) string {
	return 'c2v_base_${base_type.camel_to_snake().trim_left('_')}'
}

fn (mut c C2V) collect_cpp_concrete_bases_through_abstract(class_name string, mut seen map[string]bool, mut result []string) {
	resolved_class := normalize_cpp_operator_type_name(c.resolve_type_alias(class_name))
	if resolved_class == '' || resolved_class in seen {
		return
	}
	seen[resolved_class] = true
	for base in c.cpp_class_bases[resolved_class] {
		resolved_base := normalize_cpp_operator_type_name(c.resolve_type_alias(base))
		if resolved_base == '' {
			continue
		}
		if resolved_base in c.cpp_abstract_types {
			c.collect_cpp_concrete_bases_through_abstract(resolved_base, mut seen, mut result)
		} else if resolved_base !in result {
			result << resolved_base
		}
	}
}

fn (mut c C2V) cpp_concrete_bases_through_abstract(class_name string) []string {
	mut seen := map[string]bool{}
	mut result := []string{}
	c.collect_cpp_concrete_bases_through_abstract(class_name, mut seen, mut result)
	return result
}

fn (mut c C2V) cpp_base_embed_path(derived_type string, target_type string, mut seen map[string]bool) string {
	derived := normalize_cpp_operator_type_name(c.resolve_type_alias(derived_type))
	target := normalize_cpp_operator_type_name(c.resolve_type_alias(target_type))
	if derived == '' || target == '' || derived in seen {
		return ''
	}
	seen[derived] = true
	for base in c.cpp_class_bases[derived] {
		resolved_base := normalize_cpp_operator_type_name(c.resolve_type_alias(base))
		base_is_abstract := resolved_base in c.cpp_abstract_types
		if base == target || resolved_base == target {
			if base_is_abstract {
				// Abstract C++ bases have no embedded V field. Their pure virtual
				// surface is implemented directly by the concrete receiver.
				return ''
			}
			if derived in c.cpp_abstract_types {
				return cpp_abstract_base_accessor_name(resolved_base) + '()'
			}
			return base
		}
		nested := c.cpp_base_embed_path(resolved_base, target, mut seen)
		if nested != '' {
			if base_is_abstract {
				return nested
			}
			if derived in c.cpp_abstract_types {
				return cpp_abstract_base_accessor_name(resolved_base) + '().' + nested
			}
			return '${base}.${nested}'
		}
	}
	return ''
}

fn (mut c C2V) cpp_derived_cast_root_type(node Node) string {
	mut source := node
	for source.kindof(.implicit_cast_expr)
		&& source.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase'] && source.inner.len > 0 {
		source = source.inner[0]
	}
	return c.receiver_surface_type_name(source)
}

// cpp_helper_name names a generated helper after the types it serves. Snake
// case can merge distinct types (`idForceField`, `idForce_Field`), so each name
// is reserved for one set of types.
fn (mut c C2V) cpp_helper_name(prefix string, parts string) string {
	key := prefix + parts
	if name := c.cpp_helper_names[key] {
		return name
	}
	base := prefix + filter_name(c_identifier_to_v_name(parts), true)
	mut name := base
	mut n := 1
	for (name in c.cpp_helper_name_keys) {
		n++
		name = base + n.str()
	}
	c.cpp_helper_names[key] = name
	c.cpp_helper_name_keys[name] = key
	return name
}

// cpp_interface_conversion_helper returns a function converting a pointer to
// an abstract class to a pointer to an abstract base: V does not convert one
// interface value to another implicitly, and its `as` rejects a nil value.
fn (mut c C2V) cpp_interface_conversion_helper(source string, target string) string {
	c.ensure_cpp_interface_runtime_helpers()
	name := c.cpp_helper_name('c2v_interface_', '${source}_as_${target}')
	key := 'cpp_interface_conversion:${name}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << 'fn ${name}(value ${source}) ${target} {\n\tif c2v_interface_is_nil(value) {\n\t\treturn c2v_nil_interface[${target}]()\n\t}\n\treturn value as ${target}\n}\n\n'
	}
	return name
}

// cpp_interface_slot_operand recognizes `reinterpret_cast<Base *&>(pointer)`
// for an abstract `Base`: a reference to a pointer slot whose V
// representation (an interface value) differs from the pointer's.
fn (mut c C2V) cpp_interface_slot_operand(arg Node) ?(Node, string) {
	mut current := arg
	for current.inner.len == 1 && (current.kindof(.materialize_temporary_expr)
		|| current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind == 'NoOp')) {
		current = current.inner[0]
	}
	if !current.kindof(.cxx_reinterpret_cast_expr) || current.value_category != 'lvalue'
		|| current.inner.len != 1 {
		return none
	}
	slot_type := c.convert_type(current.ast_type.qualified).name
	operand := current.inner[0]
	operand_type := c.convert_type(node_effective_type_name(operand)).name
	if operand_type == slot_type {
		return none
	}
	// The slot or the pointer is an interface value; two record pointers share
	// a representation (see cpp_reinterpreted_pointer_slot).
	if !c.is_v_abstract_interface_type(slot_type) && !c.is_v_abstract_interface_type(operand_type) {
		return none
	}
	return operand, slot_type
}

// gen_cpp_interface_slots lowers a call statement passing such a slot: the
// callee writes an interface value into a temporary, which is then stored in
// the pointer. It emits the temporaries and returns them per argument with the
// statements that write them back.
fn (mut c C2V) gen_cpp_interface_slots(node &Node) (map[int]string, []string) {
	mut slots := map[int]string{}
	mut write_backs := []string{}
	if !c.out_line_empty || node.inner.len < 2 {
		return slots, write_backs
	}
	for i, arg in node.inner[1..] {
		operand, slot_type := c.cpp_interface_slot_operand(arg) or { continue }
		c.ensure_cpp_interface_runtime_helpers()
		slot := '__c2v_interface_slot_${c.cpp_interface_slot_count}'
		c.cpp_interface_slot_count++
		slot_is_interface := c.is_v_abstract_interface_type(slot_type)
		c.genln(if slot_is_interface {
			'mut ${slot} := c2v_nil_interface[${slot_type}]()'
		} else {
			'mut ${slot} := unsafe { ${slot_type}(nil) }'
		})
		target := c.render_expr_to_string(operand)
		target_type := c.convert_type(node_effective_type_name(operand)).name
		value := if !slot_is_interface {
			c.cpp_record_to_interface_helper(slot_type.trim_left('&'), target_type) + '(${slot})'
		} else if c.is_v_abstract_interface_type(target_type) {
			c.cpp_interface_conversion_helper(slot_type, target_type) + '(${slot})'
		} else {
			'unsafe { ${target_type}(c2v_interface_object(${slot})) }'
		}
		write_backs << '${target} = ${value}'
		slots[i] = slot
	}
	return slots, write_backs
}

// gen_cpp_interface_object_cast casts an abstract class pointer, a V
// interface value, to a pointer to a record the way C++'s static_cast does:
// it reinterprets the object the interface holds (the pinned V's run-time
// `iface as &T` assertion fails for pointer targets). In a method of the
// interface itself, `this` points to the interface value.
fn (mut c C2V) gen_cpp_interface_object_cast(expr Node, ptr_type string) {
	c.ensure_cpp_interface_runtime_helpers()
	// Helper calls keep `unsafe` blocks out of conditions such as `if (p != nil)`.
	c.gen('c2v_pointer_as[${ptr_type.trim_left('&')}](')
	if cpp_receiver_is_direct_this(expr) {
		// A cast of an interface pointer would unwrap its object in V's C backend.
		c.gen('c2v_interface_ref_object(voidptr(this))')
	} else {
		c.gen('c2v_interface_object(')
		c.expr(expr)
		c.gen(')')
	}
	c.gen(')')
}

// cpp_dynamic_cast_helper names the function a `dynamic_cast` from an abstract
// class pointer to a record pointer calls. It is generated once the whole
// program's class hierarchy is known: the cast succeeds for the record and the
// records derived from it.
fn (mut c C2V) cpp_dynamic_cast_helper(source string, target string) string {
	c.ensure_cpp_interface_runtime_helpers()
	name := c.cpp_helper_name('c2v_dynamic_cast_', '${source}_as_${target}')
	c.cpp_dynamic_casts[name] = CppVirtualMethod{
		class_name: source
		signature: target
	}
	return name
}

// cpp_address_to_interface_helper names the function converting an object
// address that was erased to an integer or `void *` back into the interface
// value of an abstract class: the object's class id selects the concrete V type.
// (A V interface value also records that type, which the address alone lacks.)
fn (mut c C2V) cpp_address_to_interface_helper(iface string) string {
	c.ensure_cpp_interface_runtime_helpers()
	name := c.cpp_helper_name('c2v_address_as_', iface)
	c.cpp_address_to_interface_casts[name] = iface
	return name
}

// cpp_record_to_interface_helper names the function converting a pointer to a
// polymorphic record into the interface value of an abstract class it may
// derive from: the object's class id selects the concrete V type.
fn (mut c C2V) cpp_record_to_interface_helper(record string, iface string) string {
	c.ensure_cpp_interface_runtime_helpers()
	name := c.cpp_helper_name('c2v_record_', '${record}_as_${iface}')
	c.cpp_record_to_interface_casts[name] = CppVirtualMethod{
		class_name: record
		signature: iface
	}
	return name
}

// cpp_dynamic_cast_helpers_source generates the requested dynamic casts and
// record-to-interface conversions.
fn (mut c C2V) cpp_dynamic_cast_helpers_source() string {
	mut out := strings.new_builder(1024)
	mut names := c.cpp_dynamic_casts.keys()
	names.sort()
	mut classes := c.cpp_class_bases.keys()
	classes.sort()
	for name in names {
		cast := c.cpp_dynamic_casts[name]
		source := cast.class_name
		target := cast.signature
		out.writeln('fn ' + name + '(value ' + source + ') &' + target + ' {')
		out.writeln('\tobject := c2v_interface_object(value)')
		out.writeln('\tif object == unsafe { nil } {')
		out.writeln('\t\treturn unsafe { nil }')
		out.writeln('\t}')
		mut candidates := [target]
		candidates << classes.filter(it != target)
		for class_name in candidates {
			if class_name in c.cpp_abstract_types {
				continue
			}
			mut seen := map[string]bool{}
			if class_name != target && !c.cpp_class_derives_from(class_name, target, mut seen) {
				continue
			}
			mut embed_seen := map[string]bool{}
			path := if class_name == target {
				''
			} else {
				c.cpp_base_embed_path(class_name, target, mut embed_seen)
			}
			if class_name != target && path == '' {
				continue
			}
			result := if path == '' {
				'c2v_pointer_as[' + target + '](object)'
			} else {
				'unsafe { &c2v_pointer_as[' + class_name + '](object).' + path + ' }'
			}
			out.writeln('\tif value is &' + class_name + ' {')
			out.writeln('\t\treturn ' + result)
			out.writeln('\t}')
		}
		out.writeln('\treturn unsafe { nil }')
		out.writeln('}')
		out.writeln('')
	}
	mut conversions := c.cpp_record_to_interface_casts.keys()
	conversions.sort()
	for name in conversions {
		conversion := c.cpp_record_to_interface_casts[name]
		record := conversion.class_name
		iface := conversion.signature
		out.writeln('fn ' + name + '(object &' + record + ') ' + iface + ' {')
		out.writeln('\tif object == unsafe { nil } {')
		out.writeln('\t\treturn c2v_nil_interface[' + iface + ']()')
		out.writeln('\t}')
		if c.is_cpp_polymorphic_struct(record) {
			mut arms := []string{}
			for class_name in classes {
				mut seen_iface := map[string]bool{}
				mut seen_record := map[string]bool{}
				if class_name in c.cpp_abstract_types
					|| !c.cpp_class_derives_from(class_name, iface, mut seen_iface)
					|| (class_name != record
						&& !c.cpp_class_derives_from(class_name, record, mut seen_record)) {
					continue
				}
				arms << '\t\t' + cpp_class_id(class_name).str() + ' { return ' + iface + '(unsafe { &' + class_name + '(voidptr(object)) }) }'
			}
			if arms.len > 0 {
				out.writeln('\tmatch object' + c.cpp_class_id_field_path(record) + ' {')
				for arm in arms {
					out.writeln(arm)
				}
				out.writeln('\t\telse {}')
				out.writeln('\t}')
			}
		}
		out.writeln('\treturn c2v_nil_interface[' + iface + ']()')
		out.writeln('}')
		out.writeln('')
	}
	mut deletes := c.cpp_interface_deletes.keys()
	deletes.sort()
	for name in deletes {
		iface := c.cpp_interface_deletes[name]
		out.writeln('fn ' + name + '(value ' + iface + ') {')
		out.writeln('\tobject := c2v_interface_object(value)')
		out.writeln('\tif object == unsafe { nil } {')
		out.writeln('\t\treturn')
		out.writeln('\t}')
		for class_name in classes {
			mut seen := map[string]bool{}
			if class_name in c.cpp_abstract_types || class_name !in c.cpp_destroy_types || !c.cpp_class_derives_from(class_name, iface, mut seen) {
				continue
			}
			out.writeln('\tif value is &' + class_name + ' {')
			out.writeln('\t\tmut record := c2v_pointer_as[' + class_name + '](object)')
			out.writeln('\t\trecord.c2v_destroy()')
			out.writeln('\t}')
		}
		out.writeln('\tc2v_cpp_free(object)')
		out.writeln('}')
		out.writeln('')
	}
	mut address_conversions := c.cpp_address_to_interface_casts.keys()
	address_conversions.sort()
	for name in address_conversions {
		iface := c.cpp_address_to_interface_casts[name]
		out.writeln('fn ' + name + '(value voidptr) ' + iface + ' {')
		out.writeln('\tif value == unsafe { nil } {')
		out.writeln('\t\treturn c2v_nil_interface[' + iface + ']()')
		out.writeln('\t}')
		for class_name in classes {
			mut seen := map[string]bool{}
			if class_name in c.cpp_abstract_types || !c.is_cpp_polymorphic_struct(class_name)
				|| !c.cpp_class_derives_from(class_name, iface, mut seen) {
				continue
			}
			object := 'unsafe { &' + class_name + '(value) }'
			out.writeln('\tif ' + object + c.cpp_class_id_field_path(class_name) + ' == ' + cpp_class_id(class_name).str() + ' {')
			out.writeln('\t\treturn ' + iface + '(' + object + ')')
			out.writeln('\t}')
		}
		out.writeln('\treturn c2v_abstract_pointer_cast[' + iface + '](value)')
		out.writeln('}')
		out.writeln('')
	}
	return out.str()
}

// cpp_cast_source_type is the V type of a cast operand. In the copy of an
// abstract base's method made for a derived record, `this` is that record,
// not the base interface its C++ type names.
fn (mut c C2V) cpp_cast_source_type(expr Node) string {
	if c.synthesizing_cpp_derived_method && c.cur_class != '' && cpp_receiver_is_direct_this(expr) {
		return '&' + c.cur_class
	}
	return c.prefix_external_type(c.convert_type(node_effective_type_name(expr)).name)
}

fn cpp_receiver_is_direct_this(node Node) bool {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
		current = current.inner[0]
	}
	return current.kindof(.cxx_this_expr)
}

fn (mut c C2V) cpp_top_level(_node &Node) bool {
	vprintln('C++ top level')
	mut node := unsafe { _node }
	if node.kindof(.namespace_decl) {
		for child in node.inner {
			c.top_level(child)
		}
	} else if node.kindof(.cxx_constructor_decl) {
		if node.is_implicit || node.explicitly_defaulted != '' {
			return true
		}
		// Top-level constructor declarations (without body) are frequently duplicated across TUs.
		if c.cur_class == '' && !node.has_child_of_kind(.compound_stmt) {
			return true
		}
		if c.cur_class == '' && !c.node_body_in_main_file(node) && !c.project_require_no_stubs
			&& node.mangled_name !in c.cpp_static_method_symbols {
			return true
		}
		c.constructor_decl(node)
	} else if node.kindof(.cxx_destructor_decl) {
		if node.is_implicit || node.explicitly_defaulted != '' {
			return true
		}
		// Top-level destructor declarations (without body) are frequently duplicated across TUs.
		if c.cur_class == '' && !node.has_child_of_kind(.compound_stmt) {
			return true
		}
		if c.cur_class == '' && !c.node_body_in_main_file(node) && !c.project_require_no_stubs {
			return true
		}
		c.destructor_decl(node)
	} else if node.kindof(.original) {
	} else if node.kindof(.using_decl) {
	} else if node.kindof(.using_shadow_decl) {
	} else if node.kindof(.class_template_decl) {
		// Clang attaches instantiated project templates to the template declaration.
		// Emit their concrete layouts/methods even when the template header itself is
		// an included dependency; translated fields use those monomorphized names.
		mut template_parameter_names := []string{}
		for child in node.inner {
			if child.kindof(.template_type_parm_decl) {
				template_parameter_names << ''
			} else if child.kindof(.non_type_template_parm_decl) {
				template_parameter_names << child.name
			}
		}
		for child in node.inner {
			if child.kindof(.class_template_specialization_decl) {
				c.cxx_template_specialization_decl(child, template_parameter_names)
			}
		}
		// Skip class templates from headers
		if node.location.file_index != 0 {
			return true
		}
		c.class_template_decl(node)
	} else if node.kindof(.class_template_specialization_decl) {
		c.cxx_template_specialization_decl(node, []string{})
	} else if node.kindof(.cxx_record_decl) {
		// Keep C++ record declarations from headers, we need their field layouts.
		c.cxx_record_decl(node)
	} else if node.kindof(.linkage_spec_decl) {
		for child in node.inner {
			c.top_level(child)
		}
	} else if node.kindof(.using_directive_decl) {
	} else if node.kindof(.class_template_partial_specialization_decl) {
	} else if node.kindof(.function_template_decl) {
		c.emit_cpp_function_template_specializations(node, '')
		// The specialization emitter handles both top-level functions and class
		// methods. Never emit the dependent primary body a second time.
	} else if node.kindof(.cxx_method_decl) {
		if node.is_implicit || node.explicitly_defaulted != '' {
			return true
		}
		// Top-level method declarations without body should not emit stubs.
		if c.cur_class == '' && !node.has_child_of_kind(.compound_stmt) {
			return true
		}
		c.cxx_method_decl(node)
	} else if node.kindof(.access_spec_decl) {
		// public/private/protected - no equivalent in V
	} else if node.kindof(.friend_decl) {
		// friend declarations - no equivalent in V
	} else if node.kindof(.empty_decl) {
		// empty declaration (e.g. stray semicolons)
	} else if node.kindof(.type_alias_decl) {
		// using X = Y; - generate V type alias
		name := node.name
		if name != '' {
			typ := c.prefix_external_type(c.convert_type(node.ast_type.qualified).name)
			c.genln('type ${name.capitalize()} = ${typ}')
		}
	} else if node.kindof(.type_alias_template_decl) {
		// template<...> using X = Y; - skip (templates)
	} else if node.kindof(.var_template_decl) {
		// template variable - skip
	} else if node.kindof(.indirect_field_decl) {
		// indirect field (anonymous struct member access) - skip
	} else if node.kindof(.cxx_conversion_decl) {
		if node.is_implicit || node.explicitly_defaulted != '' {
			return true
		}
		if c.cur_class == '' && !node.has_child_of_kind(.compound_stmt) {
			return true
		}
		c.cxx_method_decl(node)
	} else {
		return false
	}
	return true
}

fn (mut c C2V) cpp_expr(_node &Node) bool {
	mut node := unsafe { _node }
	vprintln('C++ expr check')
	vprintln(node.ast_type.str())
	// std::vector<int> a;    OR
	// User u(34);
	if node.kindof(.cxx_construct_expr) {
		c.cxx_construct_expr(node)
	} else if node.kindof(.cxx_member_call_expr) {
		interface_slots, slot_write_backs := c.gen_cpp_interface_slots(node)
		// Check for pointer-to-member call: (this->*fn_ptr)()
		first_child := node.try_get_next_child() or {
			vprintln(err.str())
			bad_node
		}
		mut is_ptm_call := false
		mut ptm_params := []string{}
		if first_child.kindof(.paren_expr) && first_child.inner.len > 0
			&& first_child.inner[0].kindof(.binary_operator)
			&& (first_child.inner[0].opcode == '->*' || first_child.inner[0].opcode == '.*') {
			// Pointer-to-member call `(object->*pointer)(args)`: the member pointer
			// holds a function taking the object first; see cpp_member_function_pointer_v_type.
			ptm_op := first_child.inner[0]
			if ptm_op.inner.len > 1 {
				is_ptm_call = true
				member_pointer := ptm_op.inner[1]
				pointer_type := if member_pointer.ast_type.desugared_qualified.contains('::*') {
					member_pointer.ast_type.desugared_qualified
				} else {
					member_pointer.ast_type.qualified
				}
				fn_type := c.cpp_member_function_pointer_v_type(pointer_type)
				_, ptm_params = cpp_member_function_pointer_signature(pointer_type)
				c.gen('${c.function_pointer_cast_helper_name(fn_type)}(voidptr(')
				c.expr(member_pointer)
				c.gen('))(voidptr(')
				if ptm_op.opcode == '.*' || ptm_op.inner[0].kindof(.cxx_this_expr) {
					c.gen('&')
				}
				c.expr(ptm_op.inner[0])
				c.gen(')')
			}
		}
		if !is_ptm_call && first_child.kindof(.member_expr) && first_child.name == 'operator='
			&& !c.is_translated_cpp_assignment_operator(first_child.referenced_member_decl)
			&& first_child.inner.len > 0 && node.inner.len == 2 {
			// A synthesized assignment operator assigns members through their
			// `operator=` even when that is trivial (untranslated): a plain copy.
			mut assign_lhs := first_child.inner[0]
			mut assign_rhs := node.inner[1]
			c.gen_simple_assign(mut assign_lhs, mut assign_rhs)
			return true
		}
		mut member_expr := if is_ptm_call {
			bad_node
		} else if first_child.kindof(.member_expr) {
			first_child
		} else {
			bad_node
		}

		method_name := member_expr.name
		member_method_base := method_base_name_from_cpp_name(method_name.trim_left('.'))
		member_method_v := c.cpp_method_decl_names[member_expr.referenced_member_decl] or {
			member_method_base
		}
		if member_expr.referenced_member_decl in c.cpp_nonconst_method_decls
			&& member_method_v != '' {
			// Header-only declarations still carry constness even when their method
			// bodies are emitted by another translation unit. Preserve that signal
			// for the mutable-receiver sanitizer in the current output file.
			c.cpp_mut_method_names[member_method_v] = true
		}
		mut receiver_expr := bad_node
		if !is_ptm_call {
			receiver_expr = member_expr.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
		}
		receiver_type := if is_ptm_call { '' } else { c.receiver_surface_type_name(receiver_expr) }
		mut base_embed := if is_ptm_call {
			''
		} else {
			c.cpp_member_base_embed_name(receiver_type, &member_expr)
		}
		if !is_ptm_call && cpp_receiver_is_direct_this(receiver_expr) && c.cur_class != '' {
			lexical_receiver := normalize_cpp_operator_type_name(c.convert_type(c.cur_class).name)
			lexical_embed := c.cpp_member_base_embed_name(lexical_receiver, &member_expr)
			if lexical_embed != '' {
				base_embed = lexical_embed
			}
		}
		mut base_cast := receiver_expr
		for base_cast.kindof(.implicit_cast_expr) && base_cast.cast_kind == 'NoOp'
			&& base_cast.inner.len == 1 {
			base_cast = base_cast.inner[0]
		}
		if base_embed == '' && base_cast.kindof(.implicit_cast_expr)
			&& base_cast.cast_kind.contains('DerivedToBase') && base_cast.inner.len > 0 {
			// An explicitly qualified inherited call can produce several nested
			// DerivedToBase casts. Resolve the path from the original `this` type,
			// not merely from the immediately nested (intermediate-base) cast.
			source_type := c.cpp_derived_cast_root_type(base_cast)
			if receiver_type != '' && receiver_type != source_type {
				mut seen := map[string]bool{}
				base_embed = c.cpp_base_embed_path(source_type, receiver_type, mut seen)
				if base_embed == '' && receiver_type !in c.cpp_abstract_types {
					base_embed = receiver_type
				}
				if base_embed != ''
					&& !c.cpp_method_embed_path_needed(source_type, base_embed, member_expr.name) {
					base_embed = ''
				}
			}
		}
		mut add_par := false
		mut close_with_bracket := false
		if is_ptm_call {
			// The callee and the object argument are already generated.
			add_par = true
		} else if method_name.contains('operator') {
			// Member operator calls: obj.operator=(x), obj.operator[](i), ...
			mut raw_method := method_name.replace('->', '.').trim_space()
			if raw_method.starts_with('.') {
				raw_method = raw_method[1..]
			}
			method_base_name := cpp_operator_to_v_method(raw_method)
			mut v_method := c.cpp_method_decl_names[member_expr.referenced_member_decl] or {
				method_base_name
			}
			v_method = c.cpp_abstract_default_call_name(&member_expr, receiver_expr, receiver_type, v_method)
			op_token := raw_method.replace('operator', '').trim_space()
			remaining_args := node.inner.len - node.current_child_id
			receiver_is_primitive :=
				is_cpp_operator_primitive_type(c.operator_node_v_type(receiver_expr))
					|| is_cpp_operator_literal_operand(receiver_expr)
			if remaining_args == 0 && v_method.starts_with('op_conv_') {
				c.gen_cpp_operator_receiver(receiver_expr)
				if base_embed != '' {
					c.gen('.${base_embed}')
				}
				c.gen('.${v_method}()')
			} else if raw_method == 'operator()' {
				c.gen_cpp_operator_receiver(receiver_expr)
				if base_embed != '' {
					c.gen('.${base_embed}')
				}
				add_par = true
				c.gen('(')
			} else if op_token == '[]' {
				c.gen_cpp_operator_receiver(receiver_expr)
				if base_embed != '' {
					c.gen('.${base_embed}')
				}
				c.gen('[')
				close_with_bracket = true
			} else if v_method != '' && !v_method.starts_with('op_conv_') && !receiver_is_primitive {
				c.gen_cpp_operator_receiver(receiver_expr)
				if base_embed != '' {
					c.gen('.${base_embed}')
				}
				add_par = true
				c.gen('.${v_method}(')
			} else if remaining_args == 1
				&& op_token in ['=', '+=', '-=', '*=', '/=', '%=', '==', '!=', '<', '>', '<=', '>=',
					'+', '-', '*', '/', '%', '&', '|', '^', '&&', '||', '<<', '>>', '<<=', '>>=',
					','] {
				c.expr(receiver_expr)
				c.gen(' ${op_token} ')
			} else if remaining_args == 0 && op_token in ['-', '+', '!', '~', '*', '&'] {
				c.gen(op_token)
				c.expr(receiver_expr)
			} else {
				if v_method != '' && !v_method.starts_with('op_conv_') {
					c.gen_cpp_operator_receiver(receiver_expr)
					if base_embed != '' {
						c.gen('.${base_embed}')
					}
					add_par = true
					c.gen('.${v_method}(')
				} else {
					c.expr(receiver_expr)
				}
				// Conversion operators (operator int, operator bool, ...) use the object as-is.
			}
		} else {
			old_receiver_cast_id := c.cpp_receiver_cast_id
			c.cpp_receiver_cast_id = cpp_receiver_cast_id(&receiver_expr)
			if c.gen_cpp_call_result_base_receiver(&receiver_expr, member_expr.referenced_member_decl, receiver_type) {
				base_embed = ''
			} else if pointer_call := cpp_dereferenced_call(receiver_expr) {
				c.expr(pointer_call)
			} else if !c.gen_cpp_call_result_field_receiver(&receiver_expr) {
				c.expr(receiver_expr)
			}
			c.cpp_receiver_cast_id = old_receiver_cast_id
			if base_embed != '' {
				c.gen('.${base_embed}')
			}
			match method_name {
				'.push_back' {
					c.gen(' << ')
				}
				'.size' {
					c.gen('.len')
				}
				else {
					add_par = true
					mut method := method_name.replace('->', '.')
					if !method.starts_with('.') {
						method = '.' + method
					}
					method_base_name := method_base_name_from_cpp_name(method.trim_left('.'))
					registered_method_v := c.cpp_method_decl_names[member_expr.referenced_member_decl] or {
						method_base_name
					}
					method_v := c.cpp_abstract_default_call_name(&member_expr, receiver_expr, receiver_type, registered_method_v)
					dispatch_v := c.cpp_virtual_dispatch_name(&member_expr, method_v)
					c.gen('.${if dispatch_v != '' { dispatch_v } else { method_v }}(')
				}
			}
		}
		// Process remaining children as function arguments.
		// The first child was member_expr (the object+method), rest are arguments.
		callee_type := c.cpp_member_call_callee_type(member_expr)
		callee_params := if is_ptm_call { ptm_params } else { function_type_params(callee_type) }
		is_variadic := callee_params.any(it == '...')
		fixed_param_count := callee_params.filter(it != '...').len
		method_base := method_base_name_from_cpp_name(method_name.trim_left('.'))
		method_key := if receiver_type != '' && method_base != '' {
			'${receiver_type}.${method_base}'
		} else {
			''
		}
		has_exact_typed_method := member_expr.referenced_member_decl in c.cpp_method_decl_names
		call_is_cross_dir_fallback := c.is_dir && c.project_generate_stubs && method_key != ''
			&& !has_exact_typed_method && !c.method_defined_in_current_output_dir(method_key)
		// Parameter types can name typedefs nested in the receiver's class template
		// specialization; resolve them in that class's scope.
		old_template_type_aliases := c.cpp_template_type_aliases.clone()
		if receiver_aliases := c.cpp_record_nested_type_aliases[normalize_cpp_operator_type_name(receiver_type)] {
			for alias, concrete in receiver_aliases {
				c.cpp_template_type_aliases[alias] = concrete
			}
		}
		defer {
			c.cpp_template_type_aliases = old_template_type_aliases.clone()
		}
		mut arg_i := 0
		for {
			mut arg := node.try_get_next_child() or { break }
			// MaterializeTemporaryExpr wraps the actual argument expression
			if arg.kindof(.materialize_temporary_expr) {
				arg = arg.try_get_next_child() or { break }
			}
			if arg_i > 0 || is_ptm_call {
				c.gen(', ')
			}
			is_variadic_arg := (is_variadic && arg_i >= fixed_param_count)
				|| call_is_cross_dir_fallback
			mut param_type := if arg_i < callee_params.len { callee_params[arg_i] } else { '' }
			base_pointer_target := if call_is_cross_dir_fallback {
				''
			} else {
				c.cpp_base_pointer_target_for_method_arg(arg, param_type)
			}
			if slot := interface_slots[arg_i] {
				c.gen('&${slot}')
			} else if cpp_reinterpreted_pointer_slot(arg) != none {
				c.gen_call_arg(arg, param_type, is_variadic_arg)
			} else if base_pointer_target != '' {
				c.gen_cpp_base_pointer_arg(arg, base_pointer_target)
			} else {
				c.gen_call_arg(arg, param_type, is_variadic_arg)
			}
			arg_i++
		}
		if is_variadic && arg_i == fixed_param_count {
			// The pinned V backend emits the fixed argument itself in place of an
			// empty variadic slice for interface calls. One harmless null word keeps
			// the generated slice ABI-correct for printf-style C++ methods.
			if arg_i > 0 {
				c.gen(', ')
			}
			c.gen('voidptr(0)')
		}
		if close_with_bracket {
			c.gen(']')
		} else if add_par {
			c.gen(')')
		}
		for write_back in slot_write_backs {
			c.genln('')
			c.gen(write_back)
		}
	} else if node.kindof(.cxx_operator_call_expr) {
		// operator call (std::cout << etc)
		c.operator_call(node)
	} else if node.kindof(.expr_with_cleanups) {
		// ExprWithCleanups - wraps expressions that need temporary cleanup
		vprintln('expr with cle')
		// Process the inner expression directly
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
	} else if node.kindof(.unresolved_lookup_expr) {
	} else if node.kindof(.unresolved_member_expr) {
		// Unresolved member access - try to output member name
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
		member_name := if node.name != '' { node.name } else { node.member }
		if member_name != '' {
			c.gen('.${method_base_name_from_cpp_name(member_name)}')
		}
	} else if node.kindof(.cxx_try_stmt) {
		// V has no C++ exception model. Preserve the ordinary try path; translated
		// allocation failures follow V's panic/allocator behavior, so catch clauses
		// cannot be represented as recoverable control flow here.
		if node.inner.len > 0 {
			mut try_body := node.inner[0]
			if try_body.kindof(.compound_stmt) {
				c.statements_flattened(mut try_body)
			} else {
				c.statement(mut try_body)
			}
		}
	} else if node.kindof(.cxx_throw_expr) {
	} else if node.kindof(.cxx_dynamic_cast_expr) {
		c.cxx_cast_expr(node)
	} else if node.kindof(.cxx_reinterpret_cast_expr) {
		c.cxx_cast_expr(node)
	} else if node.kindof(.cxx_const_cast_expr) {
		c.cxx_const_cast_handler(node)
	} else if node.kindof(.cxx_unresolved_construct_expr) {
		c.cxx_unresolved_construct_expr(node)
	} else if node.kindof(.cxx_dependent_scope_member_expr) {
		c.cxx_dependent_scope_member_expr(node)
	} else if node.kindof(.cxx_this_expr) {
		c.gen('this')
	} else if node.kindof(.cxx_bool_literal_expr) {
		c.gen(node.value.to_str())
	} else if node.kindof(.cxx_null_ptr_literal_expr) {
		if c.inside_unsafe {
			c.gen('nil')
		} else {
			c.gen('unsafe { nil }')
		}
	} else if node.kindof(.cxx_functional_cast_expr) {
		c.cxx_cast_expr(node)
	} else if node.kindof(.cxx_delete_expr) {
		c.cxx_delete_expr(node)
	} else if node.kindof(.cxx_static_cast_expr) {
		// static_cast<int>(a)
		c.cxx_cast_expr(node)
	} else if node.kindof(.materialize_temporary_expr) {
		// Materialized temporary - process the inner expression
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
	} else if node.kindof(.cxx_temporary_object_expr) {
		// Temporary object construction - treat like construct_expr
		c.cxx_construct_expr(node)
	} else if node.kindof(.decl_stmt) {
		// DeclStmt inside C++ expressions (e.g. condition variables)
	} else if node.kindof(.cxx_new_expr) {
		c.cxx_new_expr(node)
	} else if node.kindof(.cxx_scalar_value_init_expr) {
		c.cxx_scalar_value_init_expr(node)
	} else if node.kindof(.cxx_default_arg_expr) {
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		} else {
			typ := c.prefix_external_type(c.convert_type(node_effective_type_name(node)).name)
			c.gen(c.skeleton_default_value(typ))
		}
	} else if node.kindof(.cxx_default_init_expr) {
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		} else {
			typ := c.prefix_external_type(c.convert_type(node_effective_type_name(node)).name)
			c.gen(c.skeleton_default_value(typ))
		}
	} else if node.kindof(.cxx_bind_temporary_expr) {
		// Temporary binding, process the inner expression
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
	} else if node.kindof(.dependent_scope_decl_ref_expr) {
		// Template-dependent reference, output the name
		if node.name != '' {
			c.gen(node.name)
		}
	} else if node.kindof(.cxx_dependent_scope_member_expr) {
		c.cxx_dependent_scope_member_expr(node)
	} else if node.kindof(.array_init_loop_expr) {
		// Array copy initialization loop - skip (generated implicitly by compiler)
	} else if node.kindof(.array_init_index_expr) {
		c.gen(cpp_array_init_index_name(c.array_init_depth))
	} else if node.kindof(.type_trait_expr) {
		// C++ type trait (e.g. std::is_same) - output the boolean result
		c.gen(node.value.to_str())
	} else if node.kindof(.subst_non_type_template_parm_expr) {
		// Clang stores the original parameter first and the concrete replacement
		// last. Emit the replacement for an instantiated template.
		if node.inner.len > 0 {
			c.expr(node.inner[node.inner.len - 1])
		}
	} else if node.kindof(.pack_expansion_expr) {
		// Parameter pack expansion - process inner
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
	} else if node.kindof(.cxx_fold_expr) {
		// C++ fold expression - skip (template metaprogramming)
	} else if node.kindof(.cxx_typeid_expr) {
		// typeid() - output placeholder
		c.gen('0 /*typeid*/')
	} else if node.kindof(.cxx_noexcept_expr) {
		// noexcept() - output true/false
		c.gen('true')
	} else if node.kindof(.cxx_catch_stmt) {
		// catch block - skip
	} else if node.kindof(.opaque_value_expr) {
		// Opaque value (used in binary conditional etc) - process inner. The
		// source of an ArrayInitLoopExpr is evaluated in the enclosing loop.
		if node.inner.len > 0 {
			c.array_init_depth--
			c.expr(node.inner[0])
			c.array_init_depth++
		}
	} else if node.kindof(.cxx_unresolved_construct_expr) {
		c.cxx_unresolved_construct_expr(node)
	} else {
		return false
	}
	return true
}

fn (mut c C2V) cxx_dependent_scope_member_expr(node Node) {
	if node.inner.len > 0 {
		child := node.inner[0]
		if child.kindof(.recovery_expr) && child.inner.len > 0 {
			c.expr(child.inner[0])
		} else {
			c.expr(child)
		}
	}
	member_name := if node.name != '' { node.name } else { node.member }
	if member_name != '' {
		c.gen('.${method_base_name_from_cpp_name(member_name)}')
	}
}

fn (mut c C2V) cxx_unresolved_construct_expr(node Node) {
	typ := c.convert_type(node.ast_type.qualified)
	typ_name := c.prefix_external_type(typ.name)
	if node.inner.len > 0 {
		c.gen('${typ_name}{')
		for i, child in node.inner {
			if i > 0 {
				c.gen(', ')
			}
			c.expr(child)
		}
		c.gen('}')
	} else {
		c.gen('${typ_name}{}')
	}
}

fn (mut c C2V) gen_cxx_pointer_cast_source(node Node) {
	if c.collecting_pre_cond && node.kindof(.paren_expr) && node.inner.len > 0
		&& ((node.inner[0].kindof(.binary_operator) && node.inner[0].opcode == '=')
			|| node.inner[0].kindof(.compound_assign_operator)) {
		// Preserve the condition collector's assignment extraction. Recursing
		// directly into the child here would bypass the ParenExpr handler and leak
		// the assignment into the pointer comparison (`if ((p = next()) != nil)`).
		c.expr(node)
		return
	}
	if node.kindof(.implicit_cast_expr) && node.inner.len > 0 {
		if node.cast_kind == 'ArrayToPointerDecay' {
			old_inside_unsafe := c.inside_unsafe
			if !old_inside_unsafe {
				c.gen('unsafe { ')
				c.inside_unsafe = true
			}
			c.gen('&')
			c.expr(node.inner[0])
			c.gen('[0]')
			if !old_inside_unsafe {
				c.inside_unsafe = false
				c.gen(' }')
			}
		} else if node.cast_kind == 'LValueToRValue' && is_cpp_pointer_slot_call(node.inner[0]) {
			// Read the pointer out of its storage (see cpp_return_v_type).
			c.expr(node)
		} else {
			c.gen_cxx_pointer_cast_source(node.inner[0])
		}
		return
	}
	if node.kindof(.paren_expr) && node.inner.len > 0 {
		c.gen('(')
		c.gen_cxx_pointer_cast_source(node.inner[0])
		c.gen(')')
		return
	}
	if node.kindof(.binary_operator) && node.inner.len >= 2 && node.opcode in ['+', '-'] {
		c.gen_cxx_pointer_cast_source(node.inner[0])
		c.gen(' ${node.opcode} ')
		c.gen_cxx_pointer_cast_source(node.inner[1])
		return
	}
	if node.kindof(.cxx_this_expr) {
		c.gen(c.this_pointer())
		return
	}
	c.expr(node)
}

// Unified handler for C++ cast expressions:
// static_cast, dynamic_cast, reinterpret_cast, const_cast, functional cast
// cpp_pointer_upcast_base_path returns the path of the embedded base record
// that an upcast between the V pointer types addresses. Downcasts and unrelated
// casts have no embed path and stay pointer reinterpretations.
fn (mut c C2V) cpp_pointer_upcast_base_path(source_type string, ptr_type string) string {
	if !source_type.starts_with('&') || !ptr_type.starts_with('&') {
		return ''
	}
	source := normalize_cpp_operator_type_name(source_type)
	target := normalize_cpp_operator_type_name(ptr_type)
	if source == target {
		return ''
	}
	mut seen := map[string]bool{}
	return c.cpp_base_embed_path(source, target, mut seen)
}

// cpp_cast_is_pointer_upcast reports whether an explicit cast is emitted as the
// address of an embedded base record (see cxx_cast_expr).
fn (mut c C2V) cpp_cast_is_pointer_upcast(node &Node) bool {
	if !node.ast_type.qualified.contains('*') || node.inner.len == 0
		|| (node.kindof(.cxx_reinterpret_cast_expr) && node.cast_kind == 'IntegralToPointer') {
		return false
	}
	mut expr := unsafe { &node.inner[0] }
	for expr.kindof(.implicit_cast_expr) && expr.inner.len > 0
		&& expr.cast_kind != 'ArrayToPointerDecay' {
		expr = unsafe { &expr.inner[0] }
	}
	source_type := c.prefix_external_type(c.convert_type(node_effective_type_name(expr)).name)
	if c.is_v_abstract_interface_type(source_type) {
		return false
	}
	mut ptr_type := c.convert_type(node.ast_type.qualified).name.trim_space()
	if ptr_type != '' && !ptr_type.starts_with('&') && ptr_type != 'voidptr' {
		ptr_type = '&' + ptr_type
	}
	return c.cpp_pointer_upcast_base_path(source_type, ptr_type) != ''
}

// cpp_reinterpreted_object returns the lvalue a `reinterpret_cast<T &>` views
// as an object of another (non-pointer) type.
fn cpp_reinterpreted_object(node &Node) ?Node {
	mut current := unsafe { node }
	for current.inner.len == 1 && (current.kindof(.paren_expr)
		|| (current.kindof(.implicit_cast_expr) && current.cast_kind == 'NoOp')) {
		current = unsafe { &current.inner[0] }
	}
	// (A C-style cast is an lvalue only when it casts to a reference; `(int &)n`
	// of an `int` typedef is a NoOp cast.)
	if !((current.kindof(.cxx_reinterpret_cast_expr) && current.cast_kind == 'LValueBitCast')
		|| (current.kindof(.c_style_cast_expr) && current.cast_kind in ['LValueBitCast', 'NoOp']))
		|| current.value_category != 'lvalue' || current.inner.len != 1
		|| current.ast_type.qualified.trim_space().ends_with('*') {
		return none
	}
	return current.inner[0]
}

fn (mut c C2V) cxx_cast_expr(_node &Node) {
	mut node := unsafe { _node }
	mut expr := node.try_get_next_child() or {
		vprintln(err.str())
		bad_node
	}
	// Skip through implicit casts to avoid double casting
	// (clang wraps the actual expression in ImplicitCastExpr for type conversion,
	// but we're already doing an explicit cast)
	mut converts_floating := node.cast_kind == 'FloatingToIntegral'
	mut is_upcast := node.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase']
	for {
		if !(expr.kindof(.implicit_cast_expr) && expr.inner.len > 0
			&& expr.cast_kind != 'ArrayToPointerDecay') {
			break
		}
		if expr.cast_kind == 'LValueToRValue' && cpp_operator_call_returns_reference(expr.inner[0]) {
			// `static_cast<T *>(list[i])` reads the pointer that the translated
			// operator returns the address of: that read renders a dereference.
			break
		}
		if expr.cast_kind == 'FloatingToIntegral' {
			converts_floating = true
		}
		if expr.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase'] {
			is_upcast = true
		}
		expr = expr.inner[0]
	}
	if operand := cpp_reinterpreted_object(node) {
		// `reinterpret_cast<T &>(x)` is the object of type T stored at `x`.
		target_type := c.convert_type(node.ast_type.qualified).name
		if c.resolve_type_alias(target_type) in v_primitive_type_names
			|| c.is_known_enum_v_type(target_type) {
			c.gen('unsafe { *&${target_type}(voidptr(')
		} else {
			// (`&Record(x)` would be a value cast of `x` to the record.)
			c.ensure_cpp_interface_runtime_helpers()
			c.gen('unsafe { *c2v_pointer_as[${target_type}](voidptr(')
		}
		old_inside_unsafe := c.inside_unsafe
		c.inside_unsafe = true
		c.gen_address_in_cast(operand)
		c.inside_unsafe = old_inside_unsafe
		c.gen(')) }')
		return
	}
	// Downcasts in recovered C++ ASTs are often only used for method dispatch.
	// Emitting value casts here is invalid in V, so preserve pointer semantics.
	// Preserve pointer semantics with an explicit unsafe pointer cast.
	if node.ast_type.qualified.contains('*') {
		mut ptr_type := c.convert_type(node.ast_type.qualified).name.trim_space()
		if is_upcast && c.is_v_abstract_interface_type(ptr_type)
			&& !c.is_v_abstract_interface_type(c.cpp_cast_source_type(expr)) {
			// An upcast of a record pointer to an abstract base (a V interface
			// value), such as `dynamic_cast<Base *>(derived)`: box the pointer.
			c.gen('${ptr_type}(')
			c.expr(expr)
			c.gen(')')
			return
		}
		if ptr_type == '' {
			ptr_type = 'voidptr'
		}
		if !ptr_type.starts_with('&') && ptr_type != 'voidptr' {
			ptr_type = '&' + ptr_type
		}
		if node.kindof(.cxx_reinterpret_cast_expr) && node.cast_kind == 'IntegralToPointer' {
			// Parenthesized, as `&T(x).field` would take the address of the field.
			c.gen('(${ptr_type}(voidptr(')
			c.expr(expr)
			c.gen(')))')
			return
		}
		source_type := c.cpp_cast_source_type(expr)
		if c.is_v_abstract_interface_type(source_type) {
			target_type := normalize_cpp_operator_type_name(ptr_type)
			mut seen := map[string]bool{}
			base_path := c.cpp_base_embed_path(source_type, target_type, mut seen)
			if base_path != '' {
				c.gen('(unsafe { &${target_type}(&')
				c.expr(expr)
				c.gen('.${base_path}) })')
				return
			}
			if c.is_v_abstract_interface_type(target_type) {
				// A cast between abstract classes is a V interface assertion.
				c.gen('(')
				c.expr(expr)
				c.gen(' as ${ptr_type})')
			} else if node.kindof(.cxx_dynamic_cast_expr) {
				c.gen(c.cpp_dynamic_cast_helper(normalize_cpp_operator_type_name(source_type), target_type) + '(')
				c.expr(expr)
				c.gen(')')
			} else {
				c.gen_cpp_interface_object_cast(expr, ptr_type)
			}
			return
		}
		base_path := c.cpp_pointer_upcast_base_path(source_type, ptr_type)
		if base_path != '' {
			// A method receiver is addressed implicitly in V.
			is_receiver := node.id != '' && node.id == c.cpp_receiver_cast_id
			if !is_receiver {
				c.gen('&')
			}
			// `&object` upcasts address the base embedded in `object` itself.
			object := if expr.kindof(.unary_operator) && expr.opcode == '&' && expr.inner.len == 1 {
				expr.inner[0]
			} else {
				expr
			}
			c.gen_cpp_operator_receiver(object)
			c.gen('.${base_path}')
			return
		}
		if ptr_type.starts_with('&') && !ptr_type.starts_with('&&')
			&& c.is_v_abstract_interface_type(ptr_type[1..]) {
			// See c2v_pointer_as: casting to `&Interface` must not box the address.
			c.ensure_cpp_interface_runtime_helpers()
			c.gen('c2v_pointer_as[${ptr_type[1..]}](voidptr(')
			c.expr(expr)
			c.gen('))')
			return
		}
		c.gen('(unsafe { ${ptr_type}(')
		// Preserve C++ pointer sources. In particular, V method receivers need an
		// address and fixed-array decay must point at the array's first element.
		old_inside_unsafe := c.inside_unsafe
		c.inside_unsafe = true
		c.gen_cxx_pointer_cast_source(expr)
		c.inside_unsafe = old_inside_unsafe
		c.gen(') })')
		return
	}
	typ := c.convert_type(node.ast_type.qualified)
	if node.kindof(.cxx_functional_cast_expr) && node.cast_kind == 'ConstructorConversion' {
		// Non-trivial C++ temporaries are wrapped in CXXBindTemporaryExpr before
		// Clang exposes the actual constructor. Preserve that constructor and its
		// arguments instead of reducing an opaque record constructor to an
		// uninitialized value.
		mut constructor_expr := unsafe { &expr }
		for constructor_expr.inner.len == 1
			&& constructor_expr.kindof(.cxx_bind_temporary_expr) {
			constructor_expr = unsafe { &constructor_expr.inner[0] }
		}
		if constructor_expr.kindof(.cxx_construct_expr) {
			c.expr(constructor_expr)
			return
		}
	}
	if c.resolve_type_alias(typ.name) !in v_primitive_type_names && (node.cast_kind == 'NoOp' || expr.kindof(.init_list_expr)
		|| expr.kindof(.cxx_construct_expr) || expr.kindof(.cxx_temporary_object_expr)) {
		// `T{...}` and same-type casts already produce the record value. V has no
		// value casts between records, so the operand is the translation.
		c.expr(expr)
		return
	}
	is_enum := typ.name in c.enum_vals || c.is_known_enum_v_type(typ.name)
	if !is_enum && typ.name !in c.structs && c.resolve_type_alias(typ.name) !in v_primitive_type_names {
		c.gen('${typ.name}{}')
		return
	}
	float_via := if converts_floating {
		float_conversion_intermediate_type(c.resolve_type_alias(typ.name))
	} else {
		''
	}
	if float_via != '' {
		c.gen('${typ.name}(${float_via}(')
		c.expr(expr)
		c.gen('))')
		return
	}
	c.gen('${typ.name}(')
	c.expr(expr)
	c.gen(')')
}

// const_cast just removes const qualifier, which doesn't exist in V.
// Output the inner expression without any cast wrapper.
fn (mut c C2V) cxx_const_cast_handler(_node &Node) {
	mut node := unsafe { _node }
	mut expr := node.try_get_next_child() or {
		vprintln(err.str())
		bad_node
	}
	c.expr(expr)
}

// CXXConstructExpr - constructor call expression
// e.g. Point() or Point(1, 2)
fn cpp_fixed_array_length(type_name string) int {
	t := type_name.trim_space()
	if !t.starts_with('[') {
		return 0
	}
	close := t.index(']') or { return 0 }
	if close <= 1 {
		return 0
	}
	return t[1..close].int()
}

fn cpp_fixed_array_element_type(type_name string) string {
	t := type_name.trim_space()
	close := t.index(']') or { return '' }
	if close + 1 >= t.len {
		return ''
	}
	return t[close + 1..].trim_space()
}

fn cpp_raw_fixed_array_length(type_name string) int {
	open := type_name.last_index('[') or { return 0 }
	close_offset := type_name[open + 1..].index(']') or { return 0 }
	close := open + 1 + close_offset
	if close <= open + 1 {
		return 0
	}
	return type_name[open + 1..close].trim_space().int()
}

fn cpp_array_decay_source(node &Node) ?Node {
	if node.kindof(.implicit_cast_expr) && node.cast_kind == 'ArrayToPointerDecay'
		&& node.inner.len > 0 {
		if node.inner[0].kindof(.conditional_operator) {
			return none
		}
		return node.inner[0]
	}
	if node.kindof(.subst_non_type_template_parm_expr) && node.inner.len > 0 {
		// A pointer-valued non-type template argument retains its concrete array
		// decay as the final child. Let an enclosing subscript address the original
		// fixed array directly instead of embedding an unsafe pointer block in a
		// C-style for-loop condition.
		return cpp_array_decay_source(unsafe { &node.inner[node.inner.len - 1] })
	}
	is_explicit_cast := node.kindof(.c_style_cast_expr) || node.kindof(.cxx_functional_cast_expr)
		|| node.kindof(.cxx_static_cast_expr) || node.kindof(.cxx_const_cast_expr)
		|| node.kindof(.cxx_reinterpret_cast_expr) || node.kindof(.cxx_dynamic_cast_expr)
	if is_explicit_cast && !node.ast_type.qualified.trim_space().ends_with('*') {
		// `(intptr_t) array` deliberately changes the decayed pointer into an
		// integer. Do not let pointer-arithmetic lowering tunnel through that cast.
		return none
	}
	if node.inner.len == 1 && (node.kindof(.implicit_cast_expr) || node.kindof(.paren_expr)
		|| node.kindof(.materialize_temporary_expr)
		|| node.kindof(.expr_with_cleanups) || node.kindof(.cxx_bind_temporary_expr)
		|| node.kindof(.c_style_cast_expr) || node.kindof(.cxx_functional_cast_expr)
		|| node.kindof(.cxx_static_cast_expr) || node.kindof(.cxx_const_cast_expr)
		|| node.kindof(.cxx_reinterpret_cast_expr)
		|| node.kindof(.cxx_dynamic_cast_expr)) {
		return cpp_array_decay_source(unsafe { &node.inner[0] })
	}
	return none
}

fn cpp_derived_to_base_source(node &Node) ?Node {
	if node.kindof(.implicit_cast_expr)
		&& node.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase'] && node.inner.len > 0 {
		return node.inner[0]
	}
	if node.inner.len == 1 && (node.kindof(.implicit_cast_expr) || node.kindof(.paren_expr)
		|| node.kindof(.materialize_temporary_expr)
		|| node.kindof(.expr_with_cleanups) || node.kindof(.cxx_bind_temporary_expr)) {
		return cpp_derived_to_base_source(unsafe { &node.inner[0] })
	}
	return none
}

fn cpp_reference_operator_source(node &Node) ?Node {
	if cpp_operator_call_returns_reference(*node) {
		return *node
	}
	if node.kindof(.implicit_cast_expr) && node.cast_kind == 'LValueToRValue' && node.inner.len == 1
		&& cpp_operator_call_returns_reference(node.inner[0]) {
		return node.inner[0]
	}
	if node.kindof(.unary_operator) && node.opcode == '*' && node.inner.len == 1 {
		return cpp_reference_operator_source(unsafe { &node.inner[0] })
	}
	if node.inner.len == 1 && (node.kindof(.implicit_cast_expr) || node.kindof(.paren_expr)
		|| node.kindof(.materialize_temporary_expr)
		|| node.kindof(.expr_with_cleanups) || node.kindof(.cxx_bind_temporary_expr)) {
		return cpp_reference_operator_source(unsafe { &node.inner[0] })
	}
	return none
}

fn cpp_function_decl_ref_source(node &Node) ?Node {
	if node.kindof(.decl_ref_expr)
		&& node.ref_declaration.kind in [.function_decl, .function_template_decl] {
		return *node
	}
	if node.inner.len == 1 && (node.kindof(.implicit_cast_expr) || node.kindof(.paren_expr)
		|| node.kindof(.c_style_cast_expr) || node.kindof(.cxx_static_cast_expr)
		|| node.kindof(.cxx_reinterpret_cast_expr)
		|| node.kindof(.cxx_const_cast_expr)
		|| node.kindof(.cxx_functional_cast_expr)
		|| node.kindof(.cxx_default_arg_expr)
		|| (node.kindof(.unary_operator) && node.opcode in ['&', '*'])) {
		return cpp_function_decl_ref_source(unsafe { &node.inner[0] })
	}
	return none
}

fn (mut c C2V) gen_cxx_construct_value(child &Node, expected_type string) {
	mut child_type := c.convert_type(node_effective_type_name(child)).name.trim_space()
	base := unwrap_cpp_operator_operand(child)
	if base.kindof(.decl_ref_expr) {
		v_name := c.decl_ref_v_name(*base)
		if declared_type := c.declared_local_var_types[v_name] {
			child_type = declared_type
		}
	}
	trimmed_expected_type := expected_type.trim_space()
	if trimmed_expected_type.starts_with('&') {
		if array_source := cpp_array_decay_source(child) {
			// V c-string literals already have pointer type. Fixed C/C++ arrays need
			// an explicit pointer to their first element, preserving any pointer cast.
			if !array_source.kindof(.string_literal) {
				was_inside_unsafe := c.inside_unsafe
				if !was_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('${trimmed_expected_type}(&')
				c.expr(array_source)
				c.gen('[0])')
				if !was_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
				return
			}
		}
	}
	expected_base := normalize_cpp_operator_type_name(expected_type)
	if !trimmed_expected_type.starts_with('&') && child_type.starts_with('&')
		&& expected_base !in v_primitive_type_names && normalize_cpp_operator_type_name(child_type) == expected_base {
		c.gen('unsafe { *')
		c.expr(child)
		c.gen(' }')
		return
	}
	cast_type := c.struct_init_cast_type(expected_type, *child, false)
	if cast_type != '' {
		c.gen('${cast_type}(')
		c.expr(child)
		c.gen(')')
		return
	}
	c.expr(child)
}

fn (mut c C2V) try_gen_cxx_fixed_array_construct_literal(type_name string, layout Struct, args []Node) bool {
	if layout.fields.len != 1 || layout.field_types.len != 1 {
		return false
	}
	field_type := layout.field_types[0]
	array_len := cpp_fixed_array_length(field_type)
	element_type := cpp_fixed_array_element_type(field_type)
	if array_len <= 0 || element_type == '' {
		return false
	}
	element_layout := c.structs[element_type] or { Struct{} }
	members_per_element := element_layout.fields.len
	direct_elements := args.len == array_len
	flattened_elements := members_per_element > 0 && args.len == array_len * members_per_element
	if !direct_elements && !flattened_elements {
		return false
	}
	c.gen('${type_name}{${layout.fields[0]}: [')
	for element_i := 0; element_i < array_len; element_i++ {
		if element_i > 0 {
			c.gen(', ')
		}
		if direct_elements {
			c.gen_cxx_construct_value(unsafe { &args[element_i] }, element_type)
			continue
		}
		c.gen('${element_type}{')
		for member_i := 0; member_i < members_per_element; member_i++ {
			if member_i > 0 {
				c.gen(', ')
			}
			c.gen('${element_layout.fields[member_i]}: ')
			arg_i := element_i * members_per_element + member_i
			c.gen_cxx_construct_value(unsafe { &args[arg_i] }, element_layout.field_types[member_i])
		}
		c.gen('}')
	}
	c.gen(']!}')
	return true
}

fn (mut c C2V) gen_cxx_construct_literal(type_name string, args []Node) {
	mut field_names := []string{}
	mut field_types := []string{}
	if layout := c.structs[type_name] {
		if c.try_gen_cxx_fixed_array_construct_literal(type_name, layout, args) {
			return
		}
		if field_names.len == 0 && layout.fields.len > args.len {
			field_names = layout.fields[..args.len].clone()
		}
		if field_names.len == args.len {
			for field_name_i, field_name in field_names {
				mut resolved_field_name := field_name
				mut field_i := layout.fields.index(resolved_field_name)
				for suffix in ['_', '_field'] {
					if field_i >= 0 {
						break
					}
					candidate := field_name + suffix
					field_i = layout.fields.index(candidate)
					if field_i >= 0 {
						resolved_field_name = candidate
					}
				}
				field_names[field_name_i] = resolved_field_name
				field_types << if field_i >= 0 && field_i < layout.field_types.len {
					layout.field_types[field_i]
				} else {
					''
				}
			}
		}
	}
	c.gen('${type_name}{')
	for i, child in args {
		if i > 0 {
			c.gen(', ')
		}
		if field_names.len == args.len {
			c.gen('${field_names[i]}: ')
		}
		// Default argument expressions use the default value from the declaration.
		// Generate a typed nil for pointer/function defaults; scalar defaults use 0.
		if child.kindof(.cxx_default_arg_expr) {
			expected_type := if i < field_types.len { field_types[i] } else { '' }
			expanded_type := c.expand_cpp_function_alias_type(expected_type)
			if expected_type.starts_with('&') || expanded_type.starts_with('fn (') {
				c.gen('unsafe { nil }')
			} else {
				c.gen('0')
			}
		} else {
			expected_type := if i < field_types.len { field_types[i] } else { '' }
			c.gen_cxx_construct_value(unsafe { &child }, expected_type)
		}
	}
	c.gen('}')
}

fn (mut c C2V) cpp_base_pointer_target_for_method_arg(arg Node, param_type string) string {
	v_param_type := c.prefix_external_type(c.convert_type(param_type).name)
	if !v_param_type.starts_with('&') {
		return ''
	}
	target_type := normalize_cpp_operator_type_name(v_param_type)
	if target_type == '' || target_type in v_primitive_type_names
		|| c.is_v_abstract_interface_type(target_type) {
		return ''
	}
	source_type := normalize_cpp_operator_type_name(c.prefix_external_type(c.convert_type(node_effective_type_name(arg)).name))
	if source_type == '' || source_type == target_type {
		return ''
	}
	mut seen := map[string]bool{}
	if c.cpp_class_derives_from(source_type, target_type, mut seen) {
		return target_type
	}
	return ''
}

fn cpp_rendered_is_nil_expr(rendered string) bool {
	trimmed := rendered.trim_space()
	return trimmed == 'nil' || trimmed == 'unsafe { nil }' || trimmed == '&unsafe { nil }'
}

fn (mut c C2V) gen_cpp_base_pointer_arg(arg Node, target_type string) {
	if reference_source := cpp_reference_operator_source(&arg) {
		was_inside_unsafe := c.inside_unsafe
		if !was_inside_unsafe {
			c.gen('unsafe { ')
			c.inside_unsafe = true
		}
		// An operator returning a mutable `T *&` returns the V address of the
		// pointer (`T *const &` returns the pointer itself).
		reads_pointer_slot := reference_source.ast_type.qualified.trim_space().ends_with('*')
		c.gen('&${target_type}(' + if reads_pointer_slot { '*' } else { '' })
		c.expr(reference_source)
		c.gen(')')
		if !was_inside_unsafe {
			c.inside_unsafe = false
			c.gen(' }')
		}
		return
	}
	// The rendered expression will be placed inside an unsafe pointer cast. Render
	// it with that context active so nil/dereference subexpressions do not create
	// nested `unsafe` blocks (notably in conditional pointer expressions).
	was_inside_unsafe := c.inside_unsafe
	c.inside_unsafe = true
	// The converted pointer is a value: a call returning a pointer by reference
	// (`list[i]`) returns a V pointer to it, which is read.
	old_deref := c.deref_reference_call_values
	c.deref_reference_call_values = true
	rendered := c.render_expr_to_string(arg)
	c.deref_reference_call_values = old_deref
	c.inside_unsafe = was_inside_unsafe
	if cpp_rendered_is_nil_expr(rendered) {
		c.gen(if was_inside_unsafe { 'nil' } else { 'unsafe { nil }' })
		return
	}
	if !was_inside_unsafe {
		c.gen('unsafe { ')
		c.inside_unsafe = true
	}
	source_v_type := c.prefix_external_type(c.convert_type(node_effective_type_name(arg)).name)
	// C++ pointer and reference expressions are already V pointers. Taking their
	// address again turns a derived-to-base conversion into a pointer-to-pointer
	// cast (for example a derived pointer became an address of its base field), leaving
	// long-lived fields pointing at a temporary stack slot.
	// (A C++ reference variable is a V pointer as well, and so is `this` in a
	// method with a `this &T` receiver.)
	if rendered.starts_with('&') || rendered.starts_with('unsafe { &')
		|| (source_v_type.starts_with('&') && (!arg.kindof(.cxx_this_expr) || c.cur_receiver_is_ref))
		|| c.cpp_expr_uses_reference_storage(arg) {
		c.gen('&${target_type}(')
		c.gen(rendered)
		c.gen(')')
	} else if c.is_heap_promotable_local(arg) {
		// (See gen_address_in_cast.)
		c.gen('&${target_type}(')
		c.gen_address_in_cast(arg)
		c.gen(')')
	} else if cpp_expr_is_addressable_lvalue(arg) || rendered_arg_is_addressable_lvalue(rendered) {
		c.gen('&${target_type}(&')
		c.gen(rendered)
		c.gen(')')
	} else {
		c.gen('&${target_type}(')
		c.gen(rendered)
		c.gen(')')
	}
	if !was_inside_unsafe {
		c.inside_unsafe = false
		c.gen(' }')
	}
}

// is_cpp_elided_copy reports whether Clang elides a copy/move construction:
// from a temporary (`elidable`), or of a named return value that is constructed
// directly in the return slot (NRVO).
fn (c &C2V) is_cpp_elided_copy(node &Node) bool {
	// A user-declared copy constructor makes the copy observable in the V
	// translation, where values are copied bitwise: an object pointing into
	// itself (e.g. at an inline buffer) must be copy-constructed at its
	// destination instead.
	if c.cpp_has_user_copy_constructor(c.convert_type(node_effective_type_name(node)).name) {
		return false
	}
	if node.is_elidable {
		return true
	}
	mut source := unsafe { &node.inner[0] }
	for source.inner.len == 1 && (source.kindof(.implicit_cast_expr) || source.kindof(.paren_expr)) {
		source = unsafe { &source.inner[0] }
	}
	return source.kindof(.decl_ref_expr) && source.ref_declaration.id in c.cpp_nrvo_vars
		&& c.inside_return_stmt
}

fn (mut c C2V) cxx_construct_expr(node &Node) {
	raw_type := node_effective_type_name(node)
	// Clang gives a local anonymous C++ record an implicit CXXConstructExpr. Its
	// source type is only `(unnamed union at file:line:column)`, while the
	// immediately preceding RecordDecl has already been hoisted under a stable V
	// name. Reuse that name instead of degrading the constructor to `voidptr{}`.
	typ := if (raw_type.contains('unnamed struct') || raw_type.contains('unnamed union')
		|| raw_type.contains('anonymous struct') || raw_type.contains('anonymous union'))
		&& c.last_declared_type_name != '' {
		c.convert_type(c.last_declared_type_name)
	} else {
		c.convert_type(raw_type)
	}
	if node.inner.len == 1 && c.is_cpp_elided_copy(node) {
		// C++ elides this copy: the object is its source, and no copy
		// constructor runs.
		c.expr(node.inner[0])
		return
	}
	constructor_key := cpp_constructor_signature_key(typ.name, node.ctor_type.qualified)
	if constructor_key != '' {
		// A user-declared constructor defines the object's state; run its
		// translated body rather than guessing a field mapping from arguments.
		if init_name := c.cpp_constructor_signature_names[constructor_key] {
			params := c.cpp_constructor_signature_params[constructor_key] or { []string{} }
			if params.len == node.inner.len {
				c.gen_strict_cpp_constructor_helper_call(typ.name, init_name, params, node)
				return
			}
		}
	}
	if node.inner.len == 0 {
		// Default construction: Type{}
		c.gen('${typ.name}{}')
	} else if typ.name !in c.structs && c.resolve_type_alias(typ.name) !in v_primitive_type_names {
		c.gen('${typ.name}{}')
	} else if node.inner.len == 1 {
		child := node.inner[0]
		base_type := normalize_cpp_operator_type_name(typ.name)
		mut child_raw_type := c.convert_type(node_effective_type_name(child)).name.trim_space()
		child_ref := unwrap_cpp_operator_operand(&child)
		if child_ref.kindof(.decl_ref_expr) {
			// A C++ reference variable has its referent's expression type, but its
			// V declaration is a pointer.
			if declared_type := c.declared_local_var_types[c.decl_ref_v_name(*child_ref)] {
				child_raw_type = declared_type
			}
		}
		child_base_type := normalize_cpp_operator_type_name(child_raw_type)
		// The selected constructor identifies a copy/move even when the argument
		// is spelled through a typedef of the record.
		ctor_params := cpp_constructor_c_param_types(node.ctor_type.qualified)
		is_copy_or_move_ctor := ctor_params.len == 1 && ctor_params[0].trim_space().ends_with('&')
			&& c.resolve_type_alias(normalize_cpp_operator_type_name(c.convert_type(ctor_params[0]).name)) == c.resolve_type_alias(base_type)
		// Copy construction of translated C++ value types should not become
		// single-field struct literals (`Type{expr}`), which are invalid in V.
		if base_type != '' && (child_base_type == base_type || is_copy_or_move_ctor
			|| c.resolve_type_alias(child_base_type) == c.resolve_type_alias(base_type)) {
			// A call returning a reference returns a V pointer to the copied object.
			copies_returned_reference := c.is_cpp && cpp_call_expr_returns_reference_value(child)
				&& !is_cpp_pointer_slot_call(child)
			if child_raw_type.starts_with('&') || copies_returned_reference {
				c.gen('unsafe { *')
				c.expr(child)
				c.gen(' }')
			} else {
				c.expr(child)
			}
			return
		}
		c.gen_cxx_construct_literal(typ.name, node.inner)
	} else {
		c.gen_cxx_construct_literal(typ.name, node.inner)
	}
}

// normalize_cpp_param_qualifiers drops the top-level `const` of each parameter
// of a function type (`void (const int, T *const)` -> `void (int, T *)`), which
// C++ ignores: a declaration and its definition can differ in it.
fn normalize_cpp_param_qualifiers(function_type string) string {
	typ := collapse_ascii_whitespace(function_type)
	close := typ.last_index(')') or { return typ }
	mut depth := 0
	mut open := -1
	for i := close; i >= 0; i-- {
		if typ[i] == `)` {
			depth++
		} else if typ[i] == `(` {
			depth--
			if depth == 0 {
				open = i
				break
			}
		}
	}
	if open < 0 {
		return typ
	}
	mut params := []string{}
	mut start := open + 1
	depth = 0
	for i := open + 1; i <= close; i++ {
		ch := typ[i]
		if ch == `(` || ch == `<` || ch == `[` {
			depth++
		} else if (ch == `)` || ch == `>` || ch == `]`) && i < close {
			depth--
		}
		if (ch == `,` && depth == 0) || i == close {
			mut param := typ[start..i].trim_space()
			if param.starts_with('const ') && !param.contains('*') && !param.contains('&')
				&& !param.contains('(') {
				param = param['const '.len..]
			} else if (param.ends_with(' const') || param.ends_with('*const'))
				&& param.contains('*') && !param.contains('(') {
				param = param[..param.len - 'const'.len].trim_space()
			}
			params << param
			start = i + 1
		}
	}
	return typ[..open + 1] + params.join(', ') + typ[close..]
}

fn cpp_constructor_signature_key(type_name string, ctor_type string) string {
	base_type := normalize_cpp_operator_type_name(type_name)
	signature := normalize_cpp_param_qualifiers(ctor_type)
	if base_type == '' || signature == '' {
		return ''
	}
	return '${base_type}|${signature}'
}

fn cpp_v_parameter_name(param string) string {
	parts := param.fields()
	if parts.len == 0 {
		return ''
	}
	if parts[0] == 'mut' && parts.len > 1 {
		return parts[1]
	}
	return parts[0]
}

fn cpp_constructor_c_param_types(ctor_type string) []string {
	open := ctor_type.index('(') or { return []string{} }
	mut depth := 0
	mut close := -1
	for i := open; i < ctor_type.len; i++ {
		if ctor_type[i] == `(` {
			depth++
		} else if ctor_type[i] == `)` {
			depth--
			if depth == 0 {
				close = i
				break
			}
		}
	}
	if close <= open + 1 {
		return []string{}
	}
	contents := ctor_type[open + 1..close].trim_space()
	if contents == '' || contents == 'void' {
		return []string{}
	}
	mut result := []string{}
	mut start := 0
	mut angle_depth := 0
	mut paren_depth := 0
	for i, ch in contents {
		match ch {
			`<` { angle_depth++ }
			`>` { angle_depth-- }
			`(` { paren_depth++ }
			`)` { paren_depth-- }
			`,` {
				if angle_depth == 0 && paren_depth == 0 {
					result << contents[start..i].trim_space()
					start = i + 1
				}
			}
			else {}
		}
	}
	result << contents[start..].trim_space()
	return result
}

// cpp_has_user_copy_constructor reports whether a translated class declares a
// copy constructor (`T(const T &)`).
fn (c &C2V) cpp_has_user_copy_constructor(type_name string) bool {
	base_type := normalize_cpp_operator_type_name(type_name)
	if base_type == '' {
		return false
	}
	prefix := base_type + '|'
	for key, _ in c.cpp_constructor_signature_names {
		if !key.starts_with(prefix) {
			continue
		}
		params := cpp_constructor_c_param_types(key[prefix.len..])
		if params.len == 1 && params[0].trim_space().ends_with('&')
			&& !params[0].trim_space().ends_with('&&')
			&& c.resolve_type_alias(normalize_cpp_operator_type_name(c.convert_type(params[0]).name)) == c.resolve_type_alias(base_type) {
			return true
		}
	}
	return false
}

// cpp_record_is_plain_value reports whether a record, with its bases and
// members, holds nothing but arithmetic values: no pointer, reference or
// function that could aim at the object itself, no virtual methods, and no
// copy constructor or destructor of its own. C++ copies such an object
// bitwise, so it has no identity: it can be constructed anywhere and moved.
fn (c &C2V) cpp_record_is_plain_value(type_name string, depth int) bool {
	if depth > 16 {
		return false
	}
	mut typ := c.resolve_type_alias(type_name.trim_space())
	for cpp_fixed_array_length(typ) > 0 {
		typ = c.resolve_type_alias(cpp_fixed_array_element_type(typ))
	}
	if typ in ['voidptr', 'string', 'none'] {
		return false
	}
	if typ in v_primitive_type_names || c.is_known_enum_v_type(typ) {
		return true
	}
	record := c.structs[typ] or { return false }
	if typ in c.cpp_abstract_types || c.cpp_class_virtual_sigs[typ].len > 0
		|| c.cpp_has_user_copy_constructor(typ) || c.cpp_record_declares_destructor_body(typ) {
		return false
	}
	for base in c.cpp_class_bases[typ] {
		if !c.cpp_record_is_plain_value(base, depth + 1) {
			return false
		}
	}
	for field_type in record.field_types {
		if !c.cpp_record_is_plain_value(field_type, depth + 1) {
			return false
		}
	}
	return true
}

// cpp_user_constructor_init_name returns the V method of the user-declared
// constructor that a construction expression runs, if any.
fn (mut c C2V) cpp_user_constructor_init_name(node &Node) ?string {
	if !node.kindof(.cxx_construct_expr) || c.is_cpp_elided_copy_safe(node) {
		return none
	}
	typ := c.convert_type(node_effective_type_name(node))
	constructor_key := cpp_constructor_signature_key(typ.name, node.ctor_type.qualified)
	if constructor_key == '' {
		return none
	}
	init_name := c.cpp_constructor_signature_names[constructor_key] or { return none }
	params := c.cpp_constructor_signature_params[constructor_key] or { []string{} }
	if params.len != node.inner.len {
		return none
	}
	return init_name
}

// cpp_static_local_is_constructed reports whether a function-level static object
// (or array of objects) runs a constructor. Like C++, it is then constructed in
// place, once, on first use.
fn (mut c C2V) cpp_static_local_is_constructed(var_decl &Node) bool {
	if !c.is_cpp || var_decl.inner.len == 0 {
		return false
	}
	construction := unwrap_cpp_reference_binding(var_decl.inner[0])
	if !construction.kindof(.cxx_construct_expr) {
		return false
	}
	return c.cpp_array_element_constructor(&construction) != none
		|| c.cpp_user_constructor_init_name(&construction) != none
}

fn (c &C2V) is_cpp_elided_copy_safe(node &Node) bool {
	return node.inner.len == 1 && c.is_cpp_elided_copy(node)
}

// cpp_array_element_constructor returns the V constructor Clang runs on every
// element of a fixed array of objects (`T values[N];`), and the array depth.
fn (mut c C2V) cpp_array_element_constructor(construct &Node) ?(string, int) {
	if !construct.kindof(.cxx_construct_expr) {
		return none
	}
	mut element_type := c.convert_type(node_effective_type_name(construct)).name
	mut array_depth := 0
	for cpp_fixed_array_length(element_type) > 0 {
		element_type = cpp_fixed_array_element_type(element_type)
		array_depth++
	}
	if array_depth == 0 {
		return none
	}
	key := cpp_constructor_signature_key(element_type, construct.ctor_type.qualified)
	init_name := c.cpp_constructor_signature_names[key] or { return none }
	params := c.cpp_constructor_signature_params[key] or { []string{} }
	if params.len != construct.inner.len {
		return none
	}
	return init_name, array_depth
}

// gen_cpp_array_element_constructors constructs every element of a fixed array
// of objects in place, as C++ does. V only zero-fills the array. Returns false
// when the elements have no constructor to run.
fn (mut c C2V) gen_cpp_array_element_constructors(target string, construct &Node) bool {
	init_name, array_depth := c.cpp_array_element_constructor(construct) or { return false }
	mut element_expr := target
	for depth in 0 .. array_depth {
		element_name := '__c2v_ctor_element_${depth}'
		c.genln('for mut ${element_name} in ${element_expr} {')
		element_expr = element_name
	}
	c.gen_cpp_constructor_call_on(element_expr, init_name, construct)
	c.genln('')
	for _ in 0 .. array_depth {
		c.genln('}')
	}
	return true
}

// gen_cpp_constructor_call_on runs a constructor on existing storage, like C++
// does (`target.initN(args)`), rather than copying a constructed value there.
fn (mut c C2V) gen_cpp_constructor_call_on(target string, init_name string, node &Node) {
	c.gen('${target}.${init_name}(')
	c_param_types := cpp_constructor_c_param_types(node.ctor_type.qualified)
	for i, arg in node.inner {
		if i > 0 {
			c.gen(', ')
		}
		if i < c_param_types.len {
			c.gen_call_arg(arg, c_param_types[i], false)
		} else {
			c.expr(arg)
		}
	}
	c.gen(')')
}

fn cpp_array_init_index_name(depth int) string {
	return '__c2v_array_init_index_${depth}'
}

// gen_cpp_array_member_copy translates the ArrayInitLoopExpr that copies an
// array member in a synthesized copy/move constructor: records with a
// translated constructor are copied element by element through it, all other
// arrays are copied as a whole.
fn (mut c C2V) gen_cpp_array_member_copy(target string, node &Node) {
	mut element := unsafe { node }
	mut depth := 0
	for element.kindof(.array_init_loop_expr) && element.inner.len == 2 {
		element = unsafe { &element.inner[1] }
		depth++
	}
	construction := unwrap_cpp_reference_binding(*element)
	init_name := c.cpp_user_constructor_init_name(&construction) or {
		if node.inner.len > 0 {
			c.gen('\t${target} = ')
			c.expr(node.inner[0])
			c.genln('')
		}
		return
	}
	mut element_target := target
	for i in 0 .. depth {
		index_name := cpp_array_init_index_name(i)
		c.genln('${'\t'.repeat(i + 1)}for ${index_name} in 0 .. ${element_target}.len {')
		element_target += '[${index_name}]'
	}
	saved_depth := c.array_init_depth
	c.array_init_depth = depth - 1
	c.gen('\t'.repeat(depth + 1))
	c.gen_cpp_constructor_call_on(element_target, init_name, &construction)
	c.genln('')
	c.array_init_depth = saved_depth
	for i := depth - 1; i >= 0; i-- {
		c.genln('${'\t'.repeat(i + 1)}}')
	}
}

fn (mut c C2V) gen_strict_cpp_constructor_helper_call(type_name string, init_name string, params []string, node &Node) {
	base_type := normalize_cpp_operator_type_name(type_name)
	helper_name := c.cpp_helper_name('c2v_construct_', '${base_type}_${init_name}')
	helper_key := 'strict_cpp_constructor:${helper_name}:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		mut param_names := []string{cap: params.len}
		for param in params {
			param_names << cpp_v_parameter_name(param)
		}
		mut result_name := 'c2v_ctor_value'
		for param_names.contains(result_name) {
			result_name += '_result'
		}
		// The temporary is returned by value. An object that may hold its own
		// address is constructed in storage that outlives the call, which its
		// copy keeps pointing into; a plain value is built on the stack.
		storage, result := if c.cpp_record_is_plain_value(base_type, 0) {
			'${base_type}{}', result_name
		} else {
			'&${base_type}{}', 'unsafe { *${result_name} }'
		}
		c.local_type_declarations << 'fn ${helper_name}(${params.join(', ')}) ${base_type} {\n\tmut ${result_name} := ${storage}\n\t${result_name}.${init_name}(${param_names.join(', ')})\n\treturn ${result}\n}\n\n'
	}
	c.gen('${helper_name}(')
	c_param_types := cpp_constructor_c_param_types(node.ctor_type.qualified)
	for i, arg in node.inner {
		if i > 0 {
			c.gen(', ')
		}
		if i < c_param_types.len {
			c.gen_call_arg(arg, c_param_types[i], false)
		} else {
			c.expr(arg)
		}
	}
	c.gen(')')
}

// cpp_heap_alloc returns a call allocating zeroed storage for `count` values
// of `type_name`, as `new` does. C++ heap objects are managed manually and are
// often referenced only from other manually managed memory, which a garbage
// collector does not scan, so the storage is never collected but is scanned.
fn (mut c C2V) cpp_heap_alloc(type_name string, count string) string {
	helper_key := 'cpp_heap_alloc:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << 'fn c2v_cpp_alloc(count usize, size usize) voidptr {\n\tbytes := count * size\n\tmemory := unsafe { malloc_uncollectable(isize(if bytes == 0 { 1 } else { bytes })) }\n\tunsafe { C.memset(memory, 0, bytes) }\n\treturn memory\n}\n\n'
	}
	return 'unsafe { &${type_name}(c2v_cpp_alloc(${count}, usize(sizeof(${type_name})))) }'
}

// gen_cpp_heap_alloc emits cpp_heap_alloc for a count given by an expression.
fn (mut c C2V) gen_cpp_heap_alloc(type_name string, count &Node) {
	c.cpp_heap_alloc(type_name, '')
	c.gen('unsafe { &${type_name}(c2v_cpp_alloc(usize(')
	c.expr(count)
	c.gen('), usize(sizeof(${type_name})))) }')
}

// gen_cpp_new_array_constructor_call allocates `new T[count]` and runs the
// default constructor `init_name` on each element in place.
fn (mut c C2V) gen_cpp_new_array_constructor_call(type_name string, init_name string, count &Node) {
	base_type := normalize_cpp_operator_type_name(type_name)
	helper_name := c.cpp_helper_name('c2v_new_array_', '${base_type}_${init_name}')
	helper_key := 'cpp_new_array_constructor:${helper_name}:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		allocation := c.cpp_heap_alloc(base_type, 'count')
		c.local_type_declarations << 'fn ${helper_name}(count usize) &${base_type} {\n\tmut values := ${allocation}\n\tfor i in 0 .. count {\n\t\tunsafe { values[i].${init_name}() }\n\t}\n\treturn values\n}\n\n'
	}
	c.gen('${helper_name}(usize(')
	c.expr(count)
	c.gen('))')
}

fn (mut c C2V) gen_cpp_new_constructor_helper_call(type_name string, init_name string, params []string, node &Node) {
	base_type := normalize_cpp_operator_type_name(type_name)
	helper_name := c.cpp_helper_name('c2v_new_', '${base_type}_${init_name}')
	helper_key := 'cpp_new_constructor:${helper_name}:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		mut param_names := []string{cap: params.len}
		for param in params {
			param_names << cpp_v_parameter_name(param)
		}
		allocation := c.cpp_heap_alloc(base_type, '1')
		c.local_type_declarations << 'fn ${helper_name}(${params.join(', ')}) &${base_type} {\n\tmut value := ${allocation}\n\tvalue.${init_name}(${param_names.join(', ')})\n\treturn value\n}\n\n'
	}
	c.gen('${helper_name}(')
	c_param_types := cpp_constructor_c_param_types(node.ctor_type.qualified)
	for i, arg in node.inner {
		if i > 0 {
			c.gen(', ')
		}
		if i < c_param_types.len {
			c.gen_call_arg(arg, c_param_types[i], false)
		} else {
			c.expr(arg)
		}
	}
	c.gen(')')
}

// CXXNewExpr - new operator
// new Type() => &Type{}
// new Type[n] => allocate array
fn (mut c C2V) cxx_new_expr(node &Node) {
	typ := c.convert_type(node.ast_type.qualified)
	// new returns a pointer, so type is e.g. "&Point" or "&int"
	// We need the base type name without the leading &
	mut base_type := typ.name
	if base_type.starts_with('&') {
		base_type = base_type[1..]
	}
	if node.inner.len > 0 && node.inner[0].kindof(.cxx_construct_expr) {
		constructor := unsafe { &node.inner[0] }
		constructor_key := cpp_constructor_signature_key(base_type, constructor.ctor_type.qualified)
		if constructor_key != '' {
			if init_name := c.cpp_constructor_signature_names[constructor_key] {
				params := c.cpp_constructor_signature_params[constructor_key] or { []string{} }
				if params.len == constructor.inner.len {
					c.gen_cpp_new_constructor_helper_call(base_type, init_name, params, constructor)
					return
				}
			}
		}
		if constructor.inner.len > 0 {
			// Zeroed storage cannot stand in for a constructor that takes arguments.
			eprintln('c2v: warning: ${c.cur_file}:${node.location.line}: no translated constructor for `new ${base_type}` (${constructor.ctor_type.qualified})')
		}
	}
	// Check if this is an array new (has a non-CXXConstructExpr child for size)
	if node.inner.len > 0 && !node.inner[0].kindof(.cxx_construct_expr) {
		// Array new: new int[n] => unsafe { &int(c2v_cpp_alloc(usize(n), usize(sizeof(int)))) }
		// C++ permits any integral size expression. Normalize both factors to usize
		// so expressions such as `strlen(name) + 1` do not mix V's usize and int.
		if c.is_v_abstract_interface_type(base_type) {
			// An array of abstract-class pointers holds V interface values.
			c.ensure_cpp_interface_runtime_helpers()
			c.cpp_heap_alloc(base_type, '')
			c.gen('c2v_pointer_as[${base_type}](c2v_cpp_alloc(usize(')
			c.expr(node.inner[0])
			c.gen('), usize(sizeof(${base_type}))))')
			return
		}
		// C++ default-constructs every element of `new T[n]`. Run a user-declared
		// default constructor on each element in place; otherwise start from zeroed
		// storage, a valid state for members that are pointers or counts.
		if node.inner.len > 1 && node.inner[1].kindof(.cxx_construct_expr)
			&& node.inner[1].inner.len == 0 {
			element_ctor := unsafe { &node.inner[1] }
			constructor_key := cpp_constructor_signature_key(base_type, element_ctor.ctor_type.qualified)
			if init_name := c.cpp_constructor_signature_names[constructor_key] {
				c.gen_cpp_new_array_constructor_call(base_type, init_name, &node.inner[0])
				return
			}
		}
		c.gen_cpp_heap_alloc(base_type, &node.inner[0])
	} else {
		c.gen(c.cpp_heap_alloc(base_type, '1'))
	}
}

// CXXDeleteExpr - delete operator
// delete ptr => c2v_cpp_free(ptr)
fn (mut c C2V) cxx_delete_expr(_node &Node) {
	mut node := unsafe { _node }
	expr := node.try_get_next_child() or {
		vprintln(err.str())
		bad_node
	}
	expr_type := c.convert_type(node_effective_type_name(expr)).name
	pointee := expr_type.trim_left('&')
	// A pointer to an abstract class is a V interface value; a pointer to such
	// pointers (`delete[]` of `new Base *[n]`) is a V pointer to them.
	is_abstract_pointer := c.is_v_abstract_interface_type(expr_type)
	if pointee in c.cpp_destroy_types && !node.is_array {
		// `delete p` destroys the object, then releases its storage.
		c.gen(c.cpp_delete_helper(pointee) + '(')
		c.expr(expr)
		c.gen(')')
		return
	}
	if is_abstract_pointer && !node.is_array {
		// A pointer to an abstract class is a V interface value: destroy the
		// object's dynamic class, then free the object.
		c.gen(c.cpp_interface_delete_helper(pointee) + '(')
		c.expr(expr)
		c.gen(')')
		return
	}
	c.gen(c.cpp_free_helper() + '(')
	if is_abstract_pointer {
		// A pointer to an abstract class is a V interface value: free the object.
		c.ensure_cpp_interface_runtime_helpers()
		c.gen('c2v_interface_object(')
		c.expr(expr)
		c.gen(')')
	} else {
		c.expr(expr)
	}
	c.gen(')')
}

// cpp_free_helper names the function releasing memory of `c2v_cpp_alloc`.
// That memory is uncollectable, and V's `free` leaves Boehm GC memory to the
// collector (it does nothing): it must be released with `GC_FREE`.
fn (mut c C2V) cpp_free_helper() string {
	helper_key := 'c2v_cpp_free:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << 'fn c2v_cpp_free(memory voidptr) {\n\t\$if gcboehm ? {\n\t\tC.GC_FREE(memory)\n\t} \$else {\n\t\tunsafe { free(memory) }\n\t}\n}\n\n'
	}
	return 'c2v_cpp_free'
}

// cpp_interface_delete_helper names the function a `delete` of an abstract class
// pointer calls. It is generated once the whole program's classes are known:
// the V interface value's concrete type selects the destructor to run.
fn (mut c C2V) cpp_interface_delete_helper(iface string) string {
	c.ensure_cpp_interface_runtime_helpers()
	c.cpp_free_helper()
	name := c.cpp_helper_name('c2v_delete_', iface)
	c.cpp_interface_deletes[name] = iface
	return name
}

// cpp_delete_helper names the function a `delete` of a record pointer calls: a
// virtual destructor destroys the object's dynamic class.
fn (mut c C2V) cpp_delete_helper(class_name string) string {
	name := c.cpp_helper_name('c2v_delete_', class_name)
	key := 'cpp_delete_helper:${name}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		destroy := if '~' in c.cpp_class_virtual_sigs[class_name] && c.is_cpp_polymorphic_struct(class_name) {
			c.cpp_virtual_dispatchers['${class_name}|~'] = CppVirtualMethod{
				class_name: class_name
				signature: 'c2v_virtual_destroy'
			}
			'c2v_virtual_destroy'
		} else {
			'c2v_destroy'
		}
		free_helper := c.cpp_free_helper()
		c.local_type_declarations << 'fn ${name}(value &${class_name}) {\n\tif value == unsafe { nil } {\n\t\treturn\n\t}\n\tmut object := unsafe { value }\n\tobject.${destroy}()\n\t${free_helper}(value)\n}\n\n'
	}
	return name
}

// CXXScalarValueInitExpr - value initialization of scalar types
// int() => 0, float() => 0.0, bool() => false
fn (mut c C2V) cxx_scalar_value_init_expr(node &Node) {
	typ := c.convert_type(node.ast_type.qualified)
	zero_val := match typ.name {
		'i8', 'i16', 'int', 'i32', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize' {
			'0'
		}
		'f32', 'f64' {
			'0.0'
		}
		'bool' {
			'false'
		}
		else {
			'${typ.name}{}'
		}
	}

	c.gen(zero_val)
}

fn (mut c C2V) fn_template_decl(mut node Node) {
	// build "<T, K>"
	mut types := '<'
	nr_types := node.count_children_of_kind(.template_type_parm_decl)
	for i := 0; i < nr_types; i++ {
		t := node.try_get_next_child_of_kind(.template_type_parm_decl) or {
			vprintln(err.str())
			bad_node
		}

		types += t.ast_type.qualified
		if i != nr_types - 1 {
			types += ', '
		}
	}
	types = types + '>'
	mut children := node.find_children(.function_decl)
	for mut fn_node in children {
		// The primary C++ function-template body still contains dependent types.
		// Emit only concrete instantiations, which Clang marks with TemplateArgument
		// children; calls will reference those exact specializations.
		if !fn_node.has_child_of_kind(.template_argument) {
			continue
		}
		c.fn_decl(mut fn_node, '') // types)
	}
}

fn (mut c C2V) class_template_decl(node &Node) {
	// A primary class template has no V representation of its own. Its concrete
	// instantiations are emitted from ClassTemplateSpecializationDecl nodes.
	_ = node
}

// CXXRecordDecl - C++ class/struct declaration
// Processes fields as struct and handles inline method/constructor/destructor declarations
fn (mut c C2V) cxx_record_decl(node &Node) {
	c.cxx_record_decl_with_template_methods(node, false)
}

fn cpp_template_specialization_args(node &Node) []string {
	mut args := []string{}
	for child in node.inner {
		if !child.kindof(.template_argument) {
			continue
		}
		mut arg := child.ast_type.qualified.trim_space()
		if child.template_argument_decl.name != '' {
			arg = child.template_argument_decl.name
		}
		if arg == '' {
			arg = child.value.to_str().trim_space()
		}
		if arg == '' && child.inner.len > 0 {
			arg = child.inner[0].ast_type.qualified.trim_space()
			if arg == '' {
				arg = child.inner[0].value.to_str().trim_space()
			}
		}
		if arg == '' {
			return []string{}
		}
		args << arg
	}
	return args
}

fn cpp_template_argument_name_token(arg string) string {
	mut token := arg.trim_space()
	if token.starts_with('-') {
		token = 'neg_' + token[1..]
	}
	// Keep `f<T>`, `f<T *>` and `f<T &>` distinct.
	token = token.replace('*', ' ptr ').replace('&', ' ref ').trim_space()
	token = c_identifier_to_v_name(token)
	token = sanitize_type_token(token).to_lower()
	if token.starts_with('_') {
		token = 'n' + token
	}
	return token
}

fn cpp_static_method_function_v_name(class_name string, method_name string) string {
	if class_name == '' {
		return method_name
	}
	class_token := sanitize_type_token(c_identifier_to_v_name(class_name)).to_lower()
	return '${class_token}_${method_name}'
}

fn (mut c C2V) register_cpp_static_method_decl_name(class_name string, base_name string, node &Node) string {
	if class_name == '' || base_name == '' {
		return base_name
	}
	for declaration_id in [node.id, node.previous_declaration] {
		if declaration_id != '' {
			if exact_name := c.cpp_method_decl_names[declaration_id] {
				for linked_id in [node.id, node.previous_declaration] {
					if linked_id != '' {
						c.cpp_method_decl_names[linked_id] = exact_name
					}
				}
				return exact_name
			}
		}
	}
	key := cpp_method_signature_key(class_name, base_name, node)
	mut v_name := c.cpp_method_signature_v_names[key]
	if v_name == '' {
		static_base_name := cpp_static_method_function_v_name(class_name, base_name)
		if n := c.emitted_top_level_name_counts[static_base_name] {
			next_n := n + 1
			c.emitted_top_level_name_counts[static_base_name] = next_n
			v_name = '${static_base_name}${next_n}'
		} else {
			c.emitted_top_level_name_counts[static_base_name] = 1
			v_name = static_base_name
		}
		c.cpp_method_signature_v_names[key] = v_name
	}
	for declaration_id in [node.id, node.previous_declaration] {
		if declaration_id != '' {
			c.cpp_method_decl_names[declaration_id] = v_name
		}
	}
	return v_name
}

fn cpp_function_template_specialization_v_name(node &Node, class_name string) string {
	args := cpp_template_specialization_args(node)
	if args.len == 0 {
		return ''
	}
	base_name := method_base_name_from_cpp_name(node.name)
	if base_name == '' {
		return ''
	}
	specialized_name := base_name + '_' + args.map(cpp_template_argument_name_token(it)).join('_')
	return cpp_static_method_function_v_name(class_name, specialized_name)
}

fn (mut c C2V) emit_cpp_function_template_specializations(node &Node, class_name string) {
	old_class := c.cur_class
	if class_name != '' {
		c.cur_class = class_name
	}
	defer {
		c.cur_class = old_class
	}
	for child in node.inner {
		if (!child.kindof(.cxx_method_decl) && !child.kindof(.function_decl))
			|| !child.has_child_of_kind(.template_argument)
			|| !child.has_child_of_kind(.compound_stmt) {
			continue
		}
		mut owner_name := class_name
		if child.kindof(.cxx_method_decl) && owner_name == '' && child.mangled_name != '' {
			owner_name = extract_class_from_mangled(child.mangled_name)
		}
		v_name := cpp_function_template_specialization_v_name(child, owner_name)
		if v_name == '' {
			continue
		}
		for declaration_id in [child.id, child.previous_declaration] {
			if declaration_id != '' {
				if child.kindof(.cxx_method_decl) {
					c.cpp_method_decl_names[declaration_id] = v_name
				} else {
					c.cpp_function_decl_names[declaration_id] = v_name
				}
			}
		}
		if child.kindof(.cxx_method_decl) {
			c.cxx_method_decl(child)
		} else {
			mut specialization := child
			c.fn_decl(mut specialization, '')
		}
	}
}

fn (mut c C2V) cxx_template_specialization_decl(node &Node, template_parameter_names []string) {
	// A specialization can add behavior without adding fields. It still needs a
	// concrete V record so its translated base embedding and methods remain.
	// Keep avoiding the enormous standard-library template surface from headers,
	// but retain concrete templates declared anywhere inside the translated tree.
	node_path := c.node_source_path(node)
	if (node_path != '' && !c.is_project_source_path(node_path))
		|| (!node.inner.any(it.kindof(.field_decl)) && node.bases.len == 0) {
		return
	}
	args := cpp_template_specialization_args(node)
	if args.len == 0 {
		return
	}
	raw_name := '${node.name}<${args.join(', ')}>'
	if raw_name == '' {
		return
	}
	v_name := convert_type(raw_name).name
	if !is_valid_v_receiver_type_name(v_name) {
		return
	}
	outer_layout_exists := 'cpp_struct:${v_name}' in c.generated_declarations
	if outer_layout_exists && !node.inner.any(it.kindof(.field_decl)) && node.bases.len == 0 {
		return
	}
	has_nested_records := node.inner.any(it.kindof(.cxx_record_decl) && it.name != node.name)
	mut has_complete_nested_record := false
	for nested in node.inner {
		if nested.kindof(.cxx_record_decl) && nested.name != node.name
			&& nested.inner.any(it.kindof(.field_decl)) {
			has_complete_nested_record = true
			break
		}
	}
	if has_nested_records && !has_complete_nested_record && !outer_layout_exists {
		return
	}
	// Typedefs nested in a class template (`typedef int cmp_t(const type *, ...)`)
	// differ per instantiation, so each specialization declares its own.
	mut specialized_inner := node.inner.clone()
	for i, child in specialized_inner {
		if child.kindof(.typedef_decl) && child.name != '' {
			specialized_inner[i] = Node{
				...child
				name: '${v_name}_${child.name}'
			}
		}
	}
	specialized := Node{
		...*node
		name: v_name
		inner: specialized_inner
	}
	old_template_values := c.cpp_template_values.clone()
	old_template_type_aliases := c.cpp_template_type_aliases.clone()
	defer {
		c.cpp_template_values = old_template_values.clone()
		c.cpp_template_type_aliases = old_template_type_aliases.clone()
	}
	for i, parameter_name in template_parameter_names {
		if parameter_name != '' && i < args.len {
			c.cpp_template_values[parameter_name] = args[i]
		}
	}
	mut nested_aliases := map[string]string{}
	for child in node.inner {
		if child.kindof(.typedef_decl) && child.name != '' {
			nested_aliases[convert_type(child.name).name] = '${v_name}_${child.name}'.capitalize()
		}
	}
	for alias, concrete in nested_aliases {
		c.cpp_template_type_aliases[alias] = concrete
	}
	if nested_aliases.len > 0 {
		c.cpp_record_nested_type_aliases[v_name] = nested_aliases.clone()
	}
	for child in node.inner {
		if !child.kindof(.cxx_record_decl) || child.name == node.name {
			continue
		}
		concrete_nested_name := '${v_name}_${sanitize_type_token(child.name).capitalize()}'
		c.cpp_template_type_aliases[convert_type(child.name).name] = concrete_nested_name
		for alias in node.inner {
			if alias.kindof(.typedef_decl) && alias.ast_type.qualified.contains(child.name) {
				c.cpp_template_type_aliases[convert_type(alias.name).name] = concrete_nested_name
			}
		}
	}
	for child in node.inner {
		if !child.kindof(.cxx_record_decl) || child.name == node.name
			|| !child.inner.any(it.kindof(.field_decl)) {
			continue
		}
		concrete_nested_name := '${v_name}_${sanitize_type_token(child.name).capitalize()}'
		specialized_nested := Node{
			...child
			name: concrete_nested_name
		}
		c.cxx_record_decl_with_template_methods(&specialized_nested, true)
	}
	mut concrete_bases := []string{}
	for base in node.bases {
		base_name := normalize_cpp_operator_type_name(c.convert_type(base.ast_type.qualified).name)
		if base_name != '' && base_name !in concrete_bases {
			concrete_bases << base_name
		}
	}
	if concrete_bases.len > 0 {
		// The initial hierarchy scan sees dependent spellings such as
		// a specialized derived template. Record the resolved specialization hierarchy as
		// well so qualified inherited calls walk every embedded V base.
		c.cpp_class_bases[v_name] = concrete_bases
	}
	c.cxx_record_decl_with_template_methods(&specialized, true)
}

fn (mut c C2V) emit_cpp_pure_interface_method(child Node) {
	mut method := child
	c.declared_local_vars.clear()
	c.declared_local_var_types.clear()
	c.local_decl_v_names.clear()
	c.for_init_vars.clear()
	mut params := c.fn_params(mut method, false)
	params = c.expand_cpp_function_alias_params(params)
	if child.ast_type.qualified.contains('...') {
		params << 'c2v_variadic_args ...voidptr'
	}
	method_name := c.cpp_method_decl_names[child.id] or {
		method_base_name_from_cpp_name(child.name)
	}
	mut ret_type := child.ast_type.qualified.before('(').trim_space()
	if ret_type == 'void' {
		ret_type = ''
	} else {
		ret_type = ' ' + c.cpp_return_v_type(ret_type)
	}
	c.genln('\t${method_name}(${params.join(', ')})${ret_type}')
}

// cpp_record_is_abstract_interface reports whether a record becomes a V
// interface: an abstract class, which declares pure virtual methods. Other
// polymorphic records are V structs whose virtual calls dispatch on a class id.
// (The textual scan of the project's headers finds the same classes, so a
// translation unit that sees only a forward declaration agrees.)
fn (mut c C2V) cpp_record_is_abstract_interface(node &Node) bool {
	return node.inner.any((it.kindof(.cxx_method_decl) || it.kind_str == 'CXXMethodDecl')
		&& it.is_pure)
}

fn (mut c C2V) collect_cpp_class_hierarchy_from_node(node &Node) {
	if (node.kindof(.cxx_record_decl) || node.kind_str == 'CXXRecordDecl') && node.name != '' {
		class_name := c.add_struct_name(mut c.types, node.name)
		if is_valid_v_receiver_type_name(class_name) {
			mut base_names := c.cpp_class_bases[class_name].clone()
			for base in node.bases {
				base_name := normalize_cpp_operator_type_name(c.convert_type(base.ast_type.qualified).name)
				if base_name != '' && base_name !in base_names {
					base_names << base_name
				}
			}
			if base_names.len > 0 {
				c.cpp_class_bases[class_name] = base_names
			}
		}
	}
	for child in node.inner {
		c.collect_cpp_class_hierarchy_from_node(&child)
	}
}

// External globals are collected from the unfiltered Clang AST before the
// regular record pass. Discover interface records at the same point so a
// external declaration using an abstract pointer is lowered to the V
// interface value rather than a pointer to it.
fn (mut c C2V) collect_cpp_abstract_types_from_node(node &Node) {
	if (node.kindof(.cxx_record_decl) || node.kind_str == 'CXXRecordDecl') && node.name != ''
		&& c.cpp_record_is_abstract_interface(node) {
		name := c.add_struct_name(mut c.types, node.name)
		if is_valid_v_receiver_type_name(name) {
			c.cpp_abstract_types[name] = true
		}
	}
	for child in node.inner {
		c.collect_cpp_abstract_types_from_node(&child)
	}
}

fn cpp_interface_signature_method(node &Node, is_interface bool) bool {
	return node.kindof(.cxx_method_decl) && node.name != ''
		&& (node.is_pure || (is_interface && node.is_virtual))
}

fn (mut c C2V) cxx_record_decl_with_template_methods(node &Node, emit_header_methods bool) {
	mut name := node.name
	if name == '' {
		name = c.typedef_name_for_tag_id(node.id)
	}
	is_top_level_record := c.node_i >= 0 && c.node_i < c.tree.inner.len
		&& c.tree.inner[c.node_i].id == node.id
	if name == '' && is_top_level_record && c.tree.inner.len > c.node_i + 1 {
		next_node := c.tree.inner[c.node_i + 1]
		if next_node.kind == .typedef_decl && next_node.name != ''
			&& node_contains_owned_tag_id(&next_node, node.id) {
			name = next_node.name
		}
	}
	if name == '' {
		name = 'AnonStruct_${node.location.line}'
		c.last_declared_type_name = name
	}
	// Preserve records that remain opaque throughout the project headers. If a
	// full definition exists later, defer to it so declaration deduping cannot
	// hide its fields.
	if node.inner.len == 0 {
		if node.name == '' || c.has_project_record_definition(node)
			|| c.has_opaque_pointer_typedef(node) {
			return
		}
		struct_v_name := c.add_struct_name(mut c.types, name)
		if !is_valid_v_receiver_type_name(struct_v_name) {
			return
		}
		decl_key := 'cpp_struct:${struct_v_name}'
		if decl_key in c.generated_declarations {
			return
		}
		c.generated_declarations[decl_key] = true
		c.cpp_opaque_record_files[struct_v_name] = c.outv
		c.structs[name] = Struct{}
		c.structs[struct_v_name] = Struct{}
		c.genln('struct ${struct_v_name} {')
		c.genln('}')
		c.genln('')
		return
	}
	mut struct_v_name := c.add_struct_name(mut c.types, name)
	if node.name == '' && 'cpp_struct:${struct_v_name}' in c.generated_declarations {
		if existing := c.structs[struct_v_name] {
			if existing.fields != cxx_record_decl_field_names(node) {
				file_token :=
					sanitize_type_token(c.cur_file.all_after_last('/').all_before_last('.'))
				local_name := '${struct_v_name}_${file_token}'
				c.file_type_alias_names[struct_v_name] = local_name
				name = local_name
				struct_v_name = c.add_struct_name(mut c.types, name)
			}
		}
	}
	// Skip malformed template/specialized names until template lowering is handled.
	if !is_valid_v_receiver_type_name(struct_v_name) {
		return
	}
	c.register_cpp_record_method_names(struct_v_name, node)
	c.register_cpp_record_constructor_names(struct_v_name, node)
	is_abstract := c.cpp_record_is_abstract_interface(node)
	if is_abstract {
		c.cpp_abstract_types[struct_v_name] = true
	}
	for child in node.inner {
		if child.kindof(.var_decl) && child.class_modifier == 'static' {
			static_type := c.convert_type(node_effective_type_name(child))
			c.register_cpp_static_member_v_name(name, child.name, child.id)
			if static_type.is_const && child.inner.any(!it.kindof(.visibility_attr)
				&& !it.kindof(.full_comment) && !it.kindof(.record_decl)
				&& !it.kindof(.cxx_record_decl) && !it.kindof(.enum_decl)
				&& !it.kindof(.typedef_decl)) {
				mut static_decl := child
				c.global_var_decl(mut static_decl)
			}
		}
	}
	// Typedefs, enums, and records nested inside ordinary classes are module-level
	// types in V. Emit them before the owner so its fields and method signatures
	// can use owner-qualified aliases, as well as private helper layouts/constants.
	for child in node.inner {
		if child.kindof(.typedef_decl) {
			c.typedef_decl(child)
		}
	}
	for child in node.inner {
		if child.kindof(.enum_decl) {
			mut enum_node := child
			old_enum_owner := c.nested_enum_owner
			c.nested_enum_owner = node.name
			c.enum_decl(mut enum_node)
			c.nested_enum_owner = old_enum_owner
		}
	}
	for child in node.inner {
		if child.kindof(.cxx_record_decl) && child.name != name
			&& child.inner.any(it.kindof(.field_decl)) {
			c.cxx_record_decl_with_template_methods(child, false)
		}
	}
	old_class := c.cur_class
	c.cur_class = name
	defer {
		c.cur_class = old_class
	}
	mut base_embeds := []string{}
	mut flattened_base_fields := []string{}
	mut flattened_base_field_types := []string{}
	mut inherited_abstract_concrete_bases := []string{}
	mut inherited_abstract_interfaces := []string{}
	mut seen_base_embeds := map[string]bool{}
	for base in node.bases {
		mut base_name :=
			c.prefix_external_type(c.convert_type(base.ast_type.qualified).name).trim_space()
		if base_name.starts_with('&') {
			base_name = base_name[1..].trim_space()
		}
		if !is_valid_v_receiver_type_name(base_name) || base_name == struct_v_name {
			continue
		}
		if base_name in seen_base_embeds {
			continue
		}
		seen_base_embeds[base_name] = true
		if base_name in c.cpp_abstract_types {
			if base_name !in inherited_abstract_interfaces {
				inherited_abstract_interfaces << base_name
			}
			for concrete_base in c.cpp_concrete_bases_through_abstract(base_name) {
				if concrete_base !in seen_base_embeds {
					seen_base_embeds[concrete_base] = true
					base_embeds << concrete_base
				}
				if concrete_base !in inherited_abstract_concrete_bases {
					inherited_abstract_concrete_bases << concrete_base
				}
			}
			if base_struct := c.structs[base_name] {
				for i, field_name in base_struct.fields {
					flattened_base_fields << field_name
					flattened_base_field_types << base_struct.field_types[i]
				}
			}
		} else {
			base_embeds << base_name
		}
	}
	if base_embeds.len > 0 {
		c.cpp_first_embedded_base[struct_v_name] = base_embeds[0]
	}
	// Generate the interface or concrete struct fields.
	mut new_struct := Struct{}
	new_struct.fields << flattened_base_fields
	new_struct.field_types << flattened_base_field_types
	mut method_field_collisions := map[string]bool{}
	for child in node.inner {
		if is_cpp_method_like_decl(child) && child.name != '' {
			method_field_collisions[method_base_name_from_cpp_name(child.name)] = true
		}
	}
	mut pending_anonymous_field_type := ''
	for child in node.inner {
		if child.kindof(.cxx_record_decl) && child.name == ''
			&& child.inner.any(it.kindof(.field_decl)) {
			pending_anonymous_field_type = 'AnonStruct_${child.location.line}'
			continue
		}
		if !child.kindof(.field_decl) {
			continue
		}
		raw_field_name := if child.name != '' {
			cpp_field_v_name(child.name)
		} else if anonymous_member := cpp_anonymous_member_name(child.ast_type.qualified) {
			anonymous_member
		} else {
			'_'
		}
		field_name := if raw_field_name in method_field_collisions {
			raw_field_name + '_field'
		} else {
			raw_field_name
		}
		// Clang emits template specializations using canonical arguments, so use
		// the desugared spelling for explicit template fields. Preserve ordinary
		// typedefs (notably member-function-pointer aliases), whose V declaration
		// carries semantics that their desugared C++ spelling cannot represent.
		field_source_type := if child.ast_type.qualified.contains('<') {
			node_effective_type_name(child)
		} else {
			child.ast_type.qualified
		}
		mut field_type := c.prefix_external_type(c.convert_type(field_source_type).name)
		if pending_anonymous_field_type != '' && (field_source_type.contains('unnamed struct')
			|| field_source_type.contains('unnamed union')
			|| field_source_type.contains('anonymous struct')
			|| field_source_type.contains('anonymous union')) {
			array_len := cpp_raw_fixed_array_length(field_source_type)
			field_type = if array_len > 0 {
				'[${array_len}]${pending_anonymous_field_type}'
			} else {
				pending_anonymous_field_type
			}
		}
		pending_anonymous_field_type = ''
		c.cpp_field_v_names['${struct_v_name}.${raw_field_name}'] = field_name
		new_struct.fields << field_name
		new_struct.field_types << field_type
	}
	c.structs[name] = new_struct
	c.structs[struct_v_name] = new_struct
	c.structs[name.capitalize()] = new_struct
	decl_key := 'cpp_struct:${struct_v_name}'
	if opaque_file := c.cpp_opaque_record_files[struct_v_name] {
		// Directory translation can encounter a forward-only header in an early
		// translation unit and the complete class in a later one. V permits only a
		// single declaration, so remove the earlier empty placeholder before
		// emitting the authoritative layout here.
		if opaque_file != '' && opaque_file != c.outv && os.exists(opaque_file) {
			source := os.read_file(opaque_file) or { '' }
			empty_decl := 'struct ${struct_v_name} {\n}\n\n'
			if source.contains(empty_decl) {
				os.write_file(opaque_file, source.replace(empty_decl, '')) or {
					c.verror('cannot replace opaque record ${struct_v_name} in ${opaque_file}: ${err}')
				}
			}
		}
		c.generated_declarations.delete(decl_key)
		c.cpp_opaque_record_files.delete(struct_v_name)
	}
	if decl_key !in c.generated_declarations {
		c.generated_declarations[decl_key] = true
		if is_abstract {
			c.genln('interface ${struct_v_name} {')
			for abstract_base in inherited_abstract_interfaces {
				c.genln('\t${abstract_base}')
			}
			for concrete_base in c.cpp_concrete_bases_through_abstract(struct_v_name) {
				c.genln('\t${cpp_abstract_base_accessor_name(concrete_base)}() &${concrete_base}')
			}
			for child in node.inner {
				if cpp_interface_signature_method(child, is_abstract)
					&& child.ast_type.qualified.contains(') const') {
					c.emit_cpp_pure_interface_method(child)
				}
			}
			has_mut_methods := node.inner.any(cpp_interface_signature_method(it, is_abstract)
				&& !it.ast_type.qualified.contains(') const'))
			if new_struct.fields.len > 0 || has_mut_methods {
				c.genln('mut:')
			}
			if new_struct.fields.len > 0 {
				for i, field_name in new_struct.fields {
					c.genln('\t${field_name} ${new_struct.field_types[i]}')
				}
			}
			for child in node.inner {
				if !cpp_interface_signature_method(child, is_abstract)
					|| child.ast_type.qualified.contains(') const') {
					continue
				}
				c.emit_cpp_pure_interface_method(child)
			}
		} else {
			record_keyword := if node.tags == 'union' { 'union' } else { 'struct' }
			if record_keyword == 'struct' && record_is_packed(node) {
				c.genln('@[packed]')
			}
			c.warn_untranslated_record_packing(node, struct_v_name)
			c.genln('${record_keyword} ${struct_v_name} {')
			for base_name in base_embeds {
				// Preserve concrete single-inheritance surface via V embedding, so
				// derived instances can access inherited fields and methods.
				c.genln('\t${base_name}')
			}
			if record_keyword == 'struct' && c.cpp_class_needs_class_id_field(struct_v_name) {
				// The dynamic class of the object, in place of a vtable pointer.
				c.genln('\tc2v_class u32')
			}
			if flattened_base_fields.len > 0 {
				// Abstract-base fields are exposed under the interface's `mut:`
				// section, so concrete implementations must expose their flattened
				// copies as mutable too for V interface conformance.
				c.genln('mut:')
			}
			for i, field_name in new_struct.fields {
				c.genln('\t${field_name} ${new_struct.field_types[i]}')
			}
		}
		c.genln('}')
		c.genln('')
		if !is_abstract {
			for concrete_base in inherited_abstract_concrete_bases {
				accessor := cpp_abstract_base_accessor_name(concrete_base)
				c.genln('fn (this &${struct_v_name}) ${accessor}() &${concrete_base} {')
				c.genln('\treturn unsafe { &${concrete_base}(&this.${concrete_base}) }')
				c.genln('}')
				c.genln('')
			}
			if node.tags != 'union' {
				c.gen_cpp_complete_destructor(struct_v_name, node, base_embeds, new_struct)
			}
		}
	}
	if is_abstract {
		for child in node.inner {
			if child.kindof(.function_template_decl) {
				c.emit_cpp_function_template_specializations(child, struct_v_name)
			}
		}
		// Non-pure inline virtual/default methods remain callable as extension
		// methods on the V interface value. Pure methods are interface signatures.
		// Constructors and destructors are too: derived records run them on
		// themselves through the interface.
		for child in node.inner {
			if child.kindof(.cxx_constructor_decl) {
				if !child.is_implicit && child.explicitly_defaulted == ''
					&& child.has_child_of_kind(.compound_stmt) {
					c.constructor_decl(child)
				}
			} else if child.kindof(.cxx_destructor_decl) {
				if child.has_child_of_kind(.compound_stmt) {
					c.destructor_decl(child)
				}
			} else if is_cpp_method_like_decl(child) && !child.is_pure {
				c.cxx_method_decl(child)
			}
		}
		return
	}
	for child in node.inner {
		if child.kindof(.function_template_decl) {
			c.emit_cpp_function_template_specializations(child, struct_v_name)
		}
	}
	// Keep included header fields/types, but do not emit full inline method bodies
	// for dependencies when fallback stubs are allowed. Strict projects need one
	// real definition; emitted_cpp_members deduplicates it across translation units.
	if c.is_cpp && node.location.file_index != 0 && !emit_header_methods
		&& !c.project_require_no_stubs {
		for child in node.inner {
			if child.kindof(.cxx_constructor_decl) {
				c.constructor_decl(child)
			} else if child.kindof(.cxx_destructor_decl) {
				c.destructor_decl(child)
			} else if is_cpp_method_like_decl(child) && !child.is_pure {
				c.cxx_method_decl(child)
			}
		}
		return
	}
	// Process constructors, destructors, and methods defined inline
	for child in node.inner {
		if child.kindof(.cxx_constructor_decl) {
			if (child.is_implicit || child.explicitly_defaulted != '')
				&& !c.is_cpp_nontrivial_default_constructor(struct_v_name, child) {
				continue
			}
			// Skip constructors without a body
			if !child.has_child_of_kind(.compound_stmt) {
				continue
			}
			if !emit_header_methods && !c.project_require_no_stubs
				&& !c.node_body_explicitly_in_main_file(child) {
				continue
			}
			c.constructor_decl(child)
		} else if child.kindof(.cxx_destructor_decl) {
			if child.is_implicit || child.explicitly_defaulted != '' {
				continue
			}
			if !child.has_child_of_kind(.compound_stmt) {
				continue
			}
			if !emit_header_methods && !c.project_require_no_stubs
				&& !c.node_body_explicitly_in_main_file(child) {
				continue
			}
			c.destructor_decl(child)
		} else if is_cpp_method_like_decl(child) {
			if (child.is_implicit || child.explicitly_defaulted != '')
				&& !c.is_cpp_nontrivial_implicit_assignment(&child) {
				continue
			}
			if !emit_header_methods && !c.project_require_no_stubs
				&& !c.node_body_explicitly_in_main_file(child) {
				continue
			}
			c.cxx_method_decl(child)
		}
	}
}

// CBattleAnimation::CBattleAnimation()
fn (mut c C2V) constructor_decl(_node &Node) {
	// The constructors of an abstract class (a V interface) are called by the
	// constructors of derived records, used or not in this translation unit.
	abstract_class := c.cur_class != '' && c.cur_class in c.cpp_abstract_types
	if !abstract_class && c.is_unused_inline_member(_node) {
		return
	}
	c.declared_local_vars.clear()
	c.declared_local_var_types.clear()
	c.local_decl_v_names.clear()
	c.for_init_vars.clear()
	c.conditional_mutable_locals = {}
	mut node := unsafe { _node }
	mut name := if c.cur_class != '' { c.cur_class } else { node.name }
	if name == '' && node.mangled_name != '' {
		name = extract_class_from_mangled(node.mangled_name)
	}
	if name == '' {
		return
	}
	receiver_type := c.add_struct_name(mut c.types, name)
	if !is_valid_v_receiver_type_name(receiver_type) {
		return
	}
	if (node.is_implicit || node.explicitly_defaulted != '')
		&& !c.is_cpp_nontrivial_default_constructor(receiver_type, node) {
		return
	}
	if c.should_skip_duplicate_cpp_member(node, receiver_type, 'ctor') {
		return
	}
	has_body := node.has_child_of_kind(.compound_stmt)
	if !has_body && !c.should_emit_skeleton_body_for_node(node) {
		return
	}
	params := c.fn_params(mut node, false)
	str_args := params.join(', ')
	init_name := c.register_cpp_constructor_name(receiver_type, node, params)
	c.genln('fn (mut this ${receiver_type}) ${init_name}(${str_args}) {')
	if c.should_emit_skeleton_body_for_node(node) {
		c.genln('}')
		c.genln('')
		return
	}
	// C++ constructs base class subobjects first (explicitly initialized or not),
	// then members.
	for initializer in node.inner {
		if !initializer.kindof(.cxx_ctor_initializer) || initializer.base_init.qualified == ''
			|| initializer.inner.len == 0 {
			continue
		}
		construction := unwrap_cpp_reference_binding(initializer.inner[0])
		base_type := normalize_cpp_operator_type_name(c.convert_type(initializer.base_init.qualified).name)
		if c.is_v_abstract_interface_type(base_type) {
			// An abstract base is a V interface. The record holds its fields, and
			// its constructor, a method of the interface, runs on the record
			// through the interface.
			if c.is_v_abstract_interface_type(receiver_type) {
				continue
			}
			if cpp_constructor_signature_key(base_type, construction.ctor_type.qualified) in c.cpp_implicit_constructor_keys {
				// An implicit constructor of an abstract base constructs its own
				// bases, which the record embeds.
				for abstract_base in c.cpp_class_bases[base_type] {
					if c.is_v_abstract_interface_type(abstract_base) {
						continue
					}
					default_key := cpp_constructor_signature_key(abstract_base, 'void ()')
					default_init := c.cpp_constructor_signature_names[default_key] or { continue }
					// Records implementing an abstract class embed its concrete bases.
					c.genln('\tthis.${abstract_base}.${default_init}()')
				}
				continue
			}
			if base_init_name := c.cpp_user_constructor_init_name(&construction) {
				c.genln('\t{')
				c.genln('\t\tmut c2v_base := ${base_type}(&this)')
				c.gen('\t\t')
				c.gen_cpp_constructor_call_on('c2v_base', base_init_name, &construction)
				c.genln('')
				c.genln('\t}')
			}
			continue
		}
		mut seen := map[string]bool{}
		base_path := c.cpp_base_embed_path(receiver_type, base_type, mut seen)
		if base_path == '' {
			continue
		}
		if base_init_name := c.cpp_user_constructor_init_name(&construction) {
			c.gen('\t')
			c.gen_cpp_constructor_call_on('this.${base_path}', base_init_name, &construction)
			c.genln('')
		}
	}
	if c.is_cpp_polymorphic_struct(receiver_type) {
		// Like C++'s vtable pointer, the class id is set once the bases are
		// constructed, so calls in the constructor run this class's overrides.
		c.genln('\tthis${c.cpp_class_id_field_path(receiver_type)} = ${cpp_class_id(receiver_type)}')
	}
	for initializer in node.inner {
		if !initializer.kindof(.cxx_ctor_initializer) || initializer.any_init.name == ''
			|| initializer.any_init.kind != .field_decl || initializer.inner.len == 0 {
			continue
		}
		raw_field_name := cpp_field_v_name(initializer.any_init.name)
		field_name := c.cpp_field_v_names['${receiver_type}.${raw_field_name}'] or {
			raw_field_name
		}
		value := unsafe { &initializer.inner[0] }
		if value.kindof(.array_init_loop_expr) {
			c.gen_cpp_array_member_copy('this.${field_name}', value)
			continue
		}
		if value.kindof(.cxx_construct_expr) {
			if initializer.any_init.ast_type.qualified.count('[') > 0 {
				// Clang materializes construction for every element of a fixed-array
				// member. A trivially constructible element needs no explicit V
				// assignment: the containing record already supplies its zero-value
				// storage. (Assigning the element value to the whole array passes V's
				// checker but produces an illegal C array assignment in the backend.)
				c.gen_cpp_array_element_constructors('this.${field_name}', value)
				continue
			}
			field_type := c.convert_type(node_effective_type_name(value)).name
			field_constructor_key := cpp_constructor_signature_key(field_type, value.ctor_type.qualified)
			if field_init_name := c.cpp_constructor_signature_names[field_constructor_key] {
				field_params := c.cpp_constructor_signature_params[field_constructor_key] or {
					[]string{}
				}
				if field_params.len == value.inner.len {
					c.gen('\t')
					c.gen_cpp_constructor_call_on('this.${field_name}', field_init_name, value)
					c.genln('')
					continue
				}
			}
		}
		c.gen('\tthis.${field_name} = ')
		if initializer.any_init.ast_type.qualified.trim_space().ends_with('&') {
			// A reference member binds to the object: a primitive reference
			// parameter is already its address, another lvalue gives its own.
			if reference_name := c.cpp_primitive_reference_v_name(value) {
				c.genln(reference_name)
				continue
			}
			field_v_type := c.convert_type(initializer.any_init.ast_type.qualified).name
			if c.is_primitive_reference_v_type(field_v_type) && value.value_category == 'lvalue' {
				c.gen('unsafe { &')
				c.expr(value)
				c.genln(' }')
				continue
			}
		}
		c.expr(value)
		c.genln('')
	}
	// Skip C++ constructor initializer list entries (base class inits, member inits).
	// In V, struct fields are zero-initialized by default and base classes don't exist.
	nr_ctor_inits := node.count_children_of_kind(.cxx_ctor_initializer)
	for _ in 0 .. nr_ctor_inits {
		_ = node.try_get_next_child_of_kind(.cxx_ctor_initializer) or {
			vprintln(err.str())
			bad_node
		}
	}
	mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
		vprintln(err.str())
		bad_node
	}

	collect_conditional_mutable_decl_refs(stmts, false, mut c.conditional_mutable_locals)
	c.st_block_no_start(mut stmts)
	c.genln('')
}

// CBattleAnimation::~CBattleAnimation()
fn (mut c C2V) destructor_decl(_node &Node) {
	// The destructor of an abstract class (a V interface) is called by every
	// derived record's `c2v_destroy`, used or not in this translation unit.
	abstract_class := c.cur_class != '' && c.cur_class in c.cpp_abstract_types
	if !abstract_class && c.is_unused_inline_member(_node) {
		return
	}
	c.declared_local_vars.clear()
	c.declared_local_var_types.clear()
	c.local_decl_v_names.clear()
	c.for_init_vars.clear()
	c.conditional_mutable_locals = {}
	mut node := unsafe { _node }
	if node.is_implicit || node.explicitly_defaulted != '' {
		return
	}
	mut type_name := if c.cur_class != '' {
		c.cur_class
	} else {
		// e.g. "~Counter" -> "Counter"
		node.name.trim_left('~')
	}
	if type_name == '' && node.mangled_name != '' {
		type_name = extract_class_from_mangled(node.mangled_name)
	}
	if type_name == '' {
		return
	}
	receiver_type := c.add_struct_name(mut c.types, type_name)
	if !is_valid_v_receiver_type_name(receiver_type) {
		return
	}
	if c.should_skip_duplicate_cpp_member(node, receiver_type, 'dtor') {
		return
	}
	has_body := node.has_child_of_kind(.compound_stmt)
	if !has_body && !c.should_emit_skeleton_body_for_node(node) {
		return
	}
	dtor_name := c.cpp_destructor_body_name(receiver_type)
	c.genln('fn (mut this ${receiver_type}) ${dtor_name}() {')
	if c.should_emit_skeleton_body_for_node(node) {
		c.genln('}')
		c.genln('')
		return
	}
	mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
		// Destructor with no body
		c.genln('}')
		return
	}
	collect_conditional_mutable_decl_refs(stmts, false, mut c.conditional_mutable_locals)
	c.st_block_no_start(mut stmts)
	c.genln('')
}

// cpp_destructor_body_name names the V method holding a destructor's body,
// once per class: the class definition and an out-of-line destructor can be
// translated in different units.
fn (mut c C2V) cpp_destructor_body_name(class_name string) string {
	if name := c.cpp_destructor_body_names[class_name] {
		return name
	}
	mut name := 'free'
	// (V gives interfaces a `free` method of their own.)
	if class_name in c.cpp_abstract_types || c.class_has_method_base(class_name, name)
		|| c.class_inherits_method_base(class_name, name) {
		name = 'dtor'
	}
	name = c.reserve_method_name(class_name, name)
	c.cpp_destructor_body_names[class_name] = name
	return name
}

// cpp_record_declares_destructor_body reports whether a class declares a
// destructor of its own (defined in some translation unit).
fn (c &C2V) cpp_record_declares_destructor_body(class_name string) bool {
	return class_name in c.cpp_classes_with_destructor_body
}

// gen_cpp_complete_destructor emits `c2v_destroy()`, which destroys an object
// like C++ does: the destructor body, then the members in reverse order of
// declaration, then the bases in reverse order. Records with nothing to
// destroy get none.
fn (mut c C2V) gen_cpp_complete_destructor(class_name string, node &Node, base_embeds []string, record Struct) {
	has_body := node.inner.any(it.kindof(.cxx_destructor_decl) && !it.is_implicit
		&& it.explicitly_defaulted == '')
	mut members := []string{}
	for i := record.fields.len - 1; i >= 0; i-- {
		mut element_type := record.field_types[i]
		mut depth := 0
		for cpp_fixed_array_length(element_type) > 0 {
			element_type = cpp_fixed_array_element_type(element_type)
			depth++
		}
		if element_type !in c.cpp_destroy_types {
			continue
		}
		mut target := 'this.${record.fields[i]}'
		mut call := ''
		for level in 0 .. depth {
			element := '__c2v_destroy_element_${level}'
			call += '\t'.repeat(level + 1) + 'for mut ${element} in ${target} {\n'
			target = element
		}
		call += '\t'.repeat(depth + 1) + '${target}.c2v_destroy()\n'
		for level := depth - 1; level >= 0; level-- {
			call += '\t'.repeat(level + 1) + '}\n'
		}
		members << call
	}
	mut bases := []string{}
	for i := base_embeds.len - 1; i >= 0; i-- {
		if base_embeds[i] in c.cpp_destroy_types {
			bases << '\tthis.${base_embeds[i]}.c2v_destroy()\n'
		}
	}
	// The destructor of an abstract base, a method of its V interface, runs on
	// the record through the interface.
	for i := node.bases.len - 1; i >= 0; i-- {
		base_type := normalize_cpp_operator_type_name(c.convert_type(node.bases[i].ast_type.qualified).name)
		if !c.is_v_abstract_interface_type(base_type) || !c.cpp_record_declares_destructor_body(base_type) {
			continue
		}
		bases << '\t{\n\t\tmut c2v_base := ${base_type}(&this)\n\t\tc2v_base.${c.cpp_destructor_body_name(base_type)}()\n\t}\n'
	}
	// A virtual destructor destroys the object's dynamic class, whose own
	// destructor has to exist to be selected.
	virtual_destructor := '~' in c.cpp_class_virtual_sigs[class_name]
	if !has_body && members.len == 0 && bases.len == 0 && !virtual_destructor {
		return
	}
	c.cpp_destroy_types[class_name] = true
	c.gen('fn (mut this ${class_name}) c2v_destroy() {\n')
	if c.is_cpp_polymorphic_struct(class_name) {
		// Like C++, the destructor runs this class's overrides of virtual methods.
		c.gen('\tthis${c.cpp_class_id_field_path(class_name)} = ${cpp_class_id(class_name)}\n')
		c.cpp_virtual_impls['${class_name}|~'] = CppVirtualImpl{
			v_name: 'c2v_destroy'
			receiver_mut: true
		}
	}
	if has_body {
		c.gen('\tthis.${c.cpp_destructor_body_name(class_name)}()\n')
	}
	for member in members {
		c.gen(member)
	}
	for base in bases {
		c.gen(base)
	}
	c.genln('}')
	c.genln('')
}

fn parse_itanium_source_name(mangled string, start int) (string, int) {
	mut pos := start
	mut name_len := 0
	mut has_length := false
	for pos < mangled.len && mangled[pos] >= `0` && mangled[pos] <= `9` {
		has_length = true
		name_len = name_len * 10 + int(mangled[pos] - `0`)
		pos++
	}
	if !has_length || name_len <= 0 || pos + name_len > mangled.len {
		return '', start
	}
	mut name := mangled[pos..pos + name_len]
	pos += name_len
	if pos >= mangled.len || mangled[pos] != `I` {
		return name, pos
	}
	pos++
	mut args := []string{}
	for pos < mangled.len && mangled[pos] != `E` {
		arg, next_pos := parse_itanium_type(mangled, pos)
		if arg == '' || next_pos <= pos {
			return '', start
		}
		args << arg
		pos = next_pos
	}
	if pos >= mangled.len || mangled[pos] != `E` {
		return '', start
	}
	pos++
	name += '<${args.join(', ')}>'
	return name, pos
}

fn parse_itanium_type(mangled string, start int) (string, int) {
	if start >= mangled.len {
		return '', start
	}
	mut pos := start
	// CV qualifiers do not affect the concrete V receiver name.
	for pos < mangled.len && mangled[pos] in [`K`, `V`, `r`] {
		pos++
	}
	if pos >= mangled.len {
		return '', start
	}
	if mangled[pos] in [`P`, `R`, `O`] {
		modifier := mangled[pos]
		inner, next_pos := parse_itanium_type(mangled, pos + 1)
		if inner == '' {
			return '', start
		}
		suffix := if modifier == `P` { ' *' } else { ' &' }
		return inner + suffix, next_pos
	}
	builtin := match mangled[pos] {
		`b` { 'bool' }
		`c` { 'char' }
		`a` { 'signed char' }
		`h` { 'unsigned char' }
		`s` { 'short' }
		`t` { 'unsigned short' }
		`i` { 'int' }
		`j` { 'unsigned int' }
		`l` { 'long' }
		`m` { 'unsigned long' }
		`x` { 'long long' }
		`y` { 'unsigned long long' }
		`f` { 'float' }
		`d` { 'double' }
		else { '' }
	}
	if builtin != '' {
		return builtin, pos + 1
	}
	if mangled[pos] >= `0` && mangled[pos] <= `9` {
		return parse_itanium_source_name(mangled, pos)
	}
	return '', start
}

// Extract the receiver type from a C++ Itanium ABI mangled name.
// Handles ordinary, const-qualified, and template-specialized receivers.
fn extract_class_from_mangled(mangled string) string {
	// Skip prefix: _ZN or _ZNK
	mut pos := 0
	if mangled.starts_with('__ZNK') {
		pos = 5
	} else if mangled.starts_with('__ZN') {
		pos = 4
	} else if mangled.starts_with('_ZNK') {
		pos = 4
	} else if mangled.starts_with('_ZN') {
		pos = 3
	} else {
		return ''
	}
	receiver, _ := parse_itanium_source_name(mangled, pos)
	return receiver
}

fn method_base_name_from_cpp_name(cpp_name string) string {
	if cpp_name.starts_with('operator') {
		return cpp_operator_to_v_method(cpp_name)
	}
	mut name := cpp_method_identifier_to_snake(cpp_name)
	// `free` and `str` are special methods in V (`free()` takes no arguments,
	// `str()` returns a V string): rename C++ methods named Free(...) or Str().
	if name in ['free', 'str'] {
		name += '_'
	}
	if name in v_keywords {
		name += '_'
	}
	return name
}

fn cpp_method_identifier_to_snake(name string) string {
	mut out := ''
	for i := 0; i < name.len; i++ {
		ch := name[i]
		if ch == `_` {
			if out != '' && !out.ends_with('_') {
				out += '_'
			}
			continue
		}
		if !is_ascii_alnum(ch) {
			continue
		}
		if is_ascii_upper(ch) && out != '' && !out.ends_with('_') {
			prev := name[i - 1]
			next := if i + 1 < name.len { name[i + 1] } else { u8(0) }
			if is_ascii_lower(prev) || is_ascii_digit(prev)
				|| (is_ascii_upper(prev) && is_ascii_lower(next)
					&& !is_trailing_acronym_plural(name, i)) {
				out += '_'
			}
		}
		out += name[i..i + 1].to_lower()
	}
	return out.trim('_')
}

fn is_trailing_acronym_plural(name string, i int) bool {
	return i > 0 && i + 2 == name.len && is_ascii_upper(name[i - 1]) && name[i + 1] == `s`
}

fn is_ascii_upper(ch u8) bool {
	return ch >= `A` && ch <= `Z`
}

fn is_ascii_lower(ch u8) bool {
	return ch >= `a` && ch <= `z`
}

fn is_ascii_digit(ch u8) bool {
	return ch >= `0` && ch <= `9`
}

fn is_ascii_alnum(ch u8) bool {
	return is_ascii_upper(ch) || is_ascii_lower(ch) || is_ascii_digit(ch)
}

fn cpp_member_symbol_key(node &Node, class_name string, member_hint string) string {
	if node.mangled_name != '' {
		mangled_owner := normalize_cpp_operator_type_name(extract_class_from_mangled(node.mangled_name))
		if mangled_owner == '' || mangled_owner == class_name {
			return node.mangled_name
		}
	}
	return '${class_name}.${member_hint}|${node.ast_type.qualified}'
}

// C++ emits an inline member function (defined in its class, or declared
// `inline`) only where it is odr-used or needed by a vtable. A definition that no
// translation unit uses may call functions that exist nowhere in the program,
// so it is not translated either.
fn (c &C2V) is_unused_inline_member(node &Node) bool {
	is_inline := node.is_inline || node.parent_decl_context_id == ''
	return c.is_dir && c.project_require_no_stubs && is_inline && !node.is_used
		&& !node.is_virtual && !node.is_pure && node.has_child_of_kind(.compound_stmt)
}

fn (mut c C2V) should_skip_duplicate_cpp_member(node &Node, class_name string, member_hint string) bool {
	key := cpp_member_symbol_key(node, class_name, member_hint)
	if key == '' {
		return false
	}
	if key in c.emitted_cpp_members {
		return true
	}
	c.emitted_cpp_members[key] = true
	return false
}

fn (mut c C2V) should_skip_duplicate_cpp_rendered_method(class_name string, method_name string, params string, is_static bool) bool {
	kind := if is_static { 'static' } else { 'instance' }
	key := 'rendered:${class_name}.${method_name}(${params})|${kind}'
	if key in c.emitted_cpp_members {
		return true
	}
	c.emitted_cpp_members[key] = true
	return false
}

fn (mut c C2V) reserve_method_name(class_name string, base_name string) string {
	if base_name == '' {
		return ''
	}
	method_key := '${class_name}.${base_name}'
	if method_key in c.declared_methods {
		c.declared_methods[method_key]++
		return '${base_name}${c.declared_methods[method_key]}'
	}
	c.declared_methods[method_key] = 1
	return base_name
}

fn cpp_method_signature_key(class_name string, base_name string, node &Node) string {
	qualified_type := if node.ast_type.desugared_qualified != '' {
		node.ast_type.desugared_qualified
	} else {
		node.ast_type.qualified
	}
	return '${class_name}.${base_name}|${qualified_type}'
}

fn (mut c C2V) register_cpp_method_decl_name(class_name string, base_name string, node &Node) string {
	if class_name == '' || base_name == '' {
		return base_name
	}
	if !c.synthesizing_cpp_derived_method {
		if exact_name := c.cpp_method_decl_names[node.id] {
			if node.previous_declaration != '' {
				c.cpp_method_decl_names[node.previous_declaration] = exact_name
			}
			return exact_name
		}
		if node.previous_declaration != '' {
			if exact_name := c.cpp_method_decl_names[node.previous_declaration] {
				if node.id != '' {
					c.cpp_method_decl_names[node.id] = exact_name
				}
				return exact_name
			}
		}
	}
	key := cpp_method_signature_key(class_name, base_name, node)
	mut v_name := c.cpp_method_signature_v_names[key]
	if v_name == '' {
		v_name = c.reserve_method_name(class_name, base_name)
		c.cpp_method_signature_v_names[key] = v_name
	}
	if !c.synthesizing_cpp_derived_method {
		for declaration_id in [node.id, node.previous_declaration] {
			if declaration_id != '' {
				c.cpp_method_decl_names[declaration_id] = v_name
				for redeclaration_id in c.cpp_method_redeclarations[declaration_id] {
					c.cpp_method_decl_names[redeclaration_id] = v_name
				}
			}
		}
	}
	return v_name
}

fn (c &C2V) class_has_method_base(class_name string, base_name string) bool {
	if base_name == '' {
		return false
	}
	return '${class_name}.${base_name}' in c.class_method_bases
}

fn (c &C2V) class_or_base_has_method_base(class_name string, base_name string, mut seen map[string]bool) bool {
	if class_name == '' || class_name in seen {
		return false
	}
	seen[class_name] = true
	if c.class_has_method_base(class_name, base_name) {
		return true
	}
	for parent in c.cpp_class_bases[class_name] {
		if c.class_or_base_has_method_base(parent, base_name, mut seen) {
			return true
		}
	}
	return false
}

fn (c &C2V) class_inherits_method_base(class_name string, base_name string) bool {
	mut seen := map[string]bool{}
	for parent in c.cpp_class_bases[class_name] {
		if c.class_or_base_has_method_base(parent, base_name, mut seen) {
			return true
		}
	}
	return false
}

fn (mut c C2V) cpp_class_derives_from(class_name string, target string, mut seen map[string]bool) bool {
	if class_name == '' || class_name in seen {
		return false
	}
	seen[class_name] = true
	for parent in c.cpp_class_bases[class_name] {
		resolved_parent := normalize_cpp_operator_type_name(c.resolve_type_alias(parent))
		if resolved_parent == target
			|| c.cpp_class_derives_from(resolved_parent, target, mut seen) {
			return true
		}
	}
	return false
}

fn node_contains_kind(node Node, kind NodeKind) bool {
	if node.kindof(kind) {
		return true
	}
	for child in node.inner {
		if node_contains_kind(child, kind) {
			return true
		}
	}
	for child in node.array_filler {
		if node_contains_kind(child, kind) {
			return true
		}
	}
	return false
}

fn cxx_lhs_mutates_receiver(node Node) bool {
	mut current := node
	for current.inner.len > 0
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
		current = current.inner[0]
	}
	if is_cpp_dereferenced_this_expr(&current) {
		return true
	}
	return node_contains_kind(current, .member_expr)
}

// register_cpp_record_method_names reserves every overload name of a record
// before its method bodies are emitted. Calls retain Clang's referenced
// declaration id, so they can select the exact V suffix even when the
// referenced overload is declared later in the class.
fn (mut c C2V) register_cpp_record_method_names(struct_v_name string, node &Node) {
	for child in node.inner {
		if is_cpp_method_like_decl(child) && ((!child.is_implicit && child.explicitly_defaulted == '')
			|| c.is_cpp_nontrivial_implicit_assignment(&child)) && child.name != '' {
			method_base_name := method_base_name_from_cpp_name(child.name)
			if child.class_modifier == 'static' {
				c.register_cpp_static_method_decl_name(struct_v_name, method_base_name, child)
			} else {
				c.register_cpp_method_decl_name(struct_v_name, method_base_name, child)
			}
		}
	}
}

// register_cpp_record_constructor_names names the compiler-defined
// constructors of a record before its methods are emitted: methods defined in
// the class can construct copies of it, while Clang appends these
// constructors to the class. A local class is declared inside a function, so
// the function's parameter and local state is preserved.
fn (mut c C2V) register_cpp_record_constructor_names(struct_v_name string, node &Node) {
	saved_vars := c.declared_local_vars.copy()
	saved_var_types := c.declared_local_var_types.clone()
	saved_decl_names := c.local_decl_v_names.clone()
	saved_copied_fn_id := c.copied_params_fn_id
	saved_copied_params := c.copied_pointer_params.clone()
	saved_param_copies := c.param_local_copies.clone()
	defer {
		c.declared_local_vars = saved_vars
		c.declared_local_var_types = saved_var_types.clone()
		c.local_decl_v_names = saved_decl_names.clone()
		c.copied_params_fn_id = saved_copied_fn_id
		c.copied_pointer_params = saved_copied_params.clone()
		c.param_local_copies = saved_param_copies.clone()
	}
	for child in node.inner {
		if child.kindof(.cxx_constructor_decl)
			&& (child.is_implicit || child.explicitly_defaulted != '')
			&& c.is_cpp_nontrivial_default_constructor(struct_v_name, &child) {
			c.declared_local_vars.clear()
			c.declared_local_var_types.clear()
			c.local_decl_v_names.clear()
			mut constructor := child
			constructor.current_child_id = 0
			params := c.fn_params(mut constructor, false)
			c.register_cpp_constructor_name(struct_v_name, &child, params)
			c.cpp_implicit_constructor_keys[cpp_constructor_signature_key(struct_v_name, child.ast_type.qualified)] = true
		}
	}
}

// register_cpp_constructor_name names the V method of a constructor: 'init' for
// a default constructor, 'init{N}' for one with N parameters, as V has no
// overloading.
fn (mut c C2V) register_cpp_constructor_name(receiver_type string, node &Node, params []string) string {
	constructor_key := cpp_constructor_signature_key(receiver_type, node.ast_type.qualified)
	mut init_name := c.cpp_constructor_signature_names[constructor_key] or { '' }
	if init_name == '' {
		init_name = if params.len == 0 { 'init' } else { 'init${params.len}' }
		if c.class_has_method_base(receiver_type, init_name)
			|| c.class_inherits_method_base(receiver_type, init_name) {
			init_name = if params.len == 0 { 'ctor' } else { 'ctor${params.len}' }
		}
		init_name = c.reserve_method_name(receiver_type, init_name)
		if constructor_key != '' {
			c.cpp_constructor_signature_names[constructor_key] = init_name
		}
	}
	if constructor_key != '' && constructor_key !in c.cpp_constructor_signature_params {
		c.cpp_constructor_signature_params[constructor_key] = params.clone()
	}
	return init_name
}

// ensure_cpp_assignment_operator_registered registers the method names of the
// record declaring an `operator=` that a call refers to before that record is
// emitted, e.g. from a template instantiated for a record declared later.
fn (mut c C2V) ensure_cpp_assignment_operator_registered(decl_id string) {
	if decl_id == '' || decl_id in c.cpp_method_decl_names {
		return
	}
	declaring := c.cpp_assignment_operator_records[decl_id] or { return }
	if declaring.class_name in c.cpp_registering_records {
		return
	}
	c.cpp_registering_records[declaring.class_name] = true
	c.register_cpp_record_method_names(declaring.class_name, &declaring.record)
	c.cpp_registering_records.delete(declaring.class_name)
}

fn (mut c C2V) is_translated_cpp_assignment_operator(decl_id string) bool {
	c.ensure_cpp_assignment_operator_registered(decl_id)
	return decl_id in c.cpp_method_decl_names
}

// is_cpp_nontrivial_implicit_assignment reports whether a compiler-defined copy
// or move assignment operator assigns a base or member through an `operator=`
// that is itself translated (user-declared or non-trivial), which a bitwise V
// copy would skip (e.g. two objects then sharing one heap buffer). Clang
// synthesizes its body, even for trivial ones, when it is used.
fn (mut c C2V) is_cpp_nontrivial_implicit_assignment(node &Node) bool {
	if !is_cpp_method_like_decl(node) || node.name != 'operator='
		|| (!node.is_implicit && node.explicitly_defaulted == '') || !node.is_used {
		return false
	}
	for child in node.inner {
		if child.kindof(.compound_stmt) {
			return c.calls_translated_assignment(&child)
		}
	}
	return false
}

fn (mut c C2V) calls_translated_assignment(node &Node) bool {
	if node.kindof(.cxx_member_call_expr) && node.inner.len > 0 && node.inner[0].kindof(.member_expr)
		&& node.inner[0].name == 'operator='
		&& c.is_translated_cpp_assignment_operator(node.inner[0].referenced_member_decl) {
		return true
	}
	if node.kindof(.decl_ref_expr) && node.ref_declaration.name == 'operator='
		&& c.is_translated_cpp_assignment_operator(node.ref_declaration.id) {
		return true
	}
	for child in node.inner {
		if c.calls_translated_assignment(&child) {
			return true
		}
	}
	return false
}

// is_cpp_nontrivial_default_constructor reports whether a compiler-defined
// constructor (implicit or `= default`: default, copy or move) constructs bases
// or members with their constructors, so the translation must run it too.
// Clang synthesizes its body when it is used.
fn (c &C2V) is_cpp_nontrivial_default_constructor(class_name string, node &Node) bool {
	if !node.is_used || !node.has_child_of_kind(.compound_stmt) {
		return false
	}
	if c.is_cpp_polymorphic_struct(class_name) {
		// It sets the class id of the object, like C++ sets its vtable pointer.
		return true
	}
	for initializer in node.inner {
		if !initializer.kindof(.cxx_ctor_initializer) || initializer.inner.len == 0 {
			continue
		}
		construction := unwrap_cpp_reference_binding(initializer.inner[0])
		if !construction.kindof(.cxx_construct_expr) {
			continue
		}
		mut constructed_type := c.convert_type(node_effective_type_name(construction)).name
		for cpp_fixed_array_length(constructed_type) > 0 {
			constructed_type = cpp_fixed_array_element_type(constructed_type)
		}
		key := cpp_constructor_signature_key(constructed_type, construction.ctor_type.qualified)
		if key != '' && key in c.cpp_constructor_signature_names {
			return true
		}
	}
	return false
}

// is_cpp_receiver_bound_to_mutable_reference reports whether a call argument is
// a non-const lvalue of the receiver used without conversion: Clang binds only
// such arguments to non-const reference parameters, which the callee may mutate.
// By-value and const reference parameters apply a copy or a const conversion.
fn is_cpp_receiver_bound_to_mutable_reference(arg Node) bool {
	mut current := arg
	for current.inner.len == 1 && current.kindof(.paren_expr) {
		current = current.inner[0]
	}
	typ := current.ast_type.qualified.trim_space()
	return current.kindof(.member_expr) && current.value_category == 'lvalue'
		&& !typ.starts_with('const ') && !typ.ends_with('const')
		&& node_contains_kind(current, .cxx_this_expr)
}

fn (c &C2V) cxx_method_body_mutates_receiver(node Node) bool {
	if (node.kindof(.binary_operator) || node.kindof(.compound_assign_operator))
		&& node.inner.len > 0
		&& node.opcode in ['=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>=']
		&& cxx_lhs_mutates_receiver(node.inner[0]) {
		return true
	}
	if node.kindof(.cxx_operator_call_expr) && node.inner.len > 1 {
		method_ref := node.inner[0]
		mut method_decl_id := ''
		if method_ref.inner.len > 0 {
			method_decl_id = method_ref.inner[0].ref_declaration.id
		}
		method_name := c.cpp_method_decl_names[method_decl_id] or { '' }
		receiver := node.inner[1]
		if is_cpp_dereferenced_this_expr(unsafe { &receiver })
			|| ((method_name in c.cpp_mut_method_names
				|| method_decl_id in c.cpp_nonconst_method_decls)
				&& node_contains_kind(receiver, .cxx_this_expr)) {
			return true
		}
	}
	if node.kindof(.cxx_member_call_expr) && node.inner.len > 0
		&& node.inner[0].kindof(.member_expr) {
		member := node.inner[0]
		method_name := c.cpp_method_decl_names[member.referenced_member_decl] or { '' }
		callee_may_mutate := method_name in c.cpp_mut_method_names
			|| member.referenced_member_decl in c.cpp_nonconst_method_decls
		if callee_may_mutate && member.inner.len > 0
			&& node_contains_kind(member.inner[0], .cxx_this_expr) {
			return true
		}
	}
	if node.kindof(.unary_operator) && node.opcode in ['++', '--'] && node.inner.len > 0
		&& cxx_lhs_mutates_receiver(node.inner[0]) {
		return true
	}
	first_arg := if node.kindof(.cxx_operator_call_expr) {
		2
	} else if node.kindof(.call_expr) || node.kindof(.cxx_member_call_expr) {
		1
	} else {
		node.inner.len
	}
	for i := first_arg; i < node.inner.len; i++ {
		if is_cpp_receiver_bound_to_mutable_reference(node.inner[i]) {
			return true
		}
	}
	if node.kindof(.binary_operator) && node.opcode in ['->*', '.*'] && node.inner.len > 0
		&& node_contains_kind(node.inner[0], .cxx_this_expr) {
		// A call through a member pointer may run any non-const method on `this`.
		return true
	}
	for child in node.inner {
		if c.cxx_method_body_mutates_receiver(child) {
			return true
		}
	}
	for child in node.array_filler {
		if c.cxx_method_body_mutates_receiver(child) {
			return true
		}
	}
	return false
}

fn normalize_cpp_source_path(path string) string {
	if path == '' {
		return ''
	}
	real := os.real_path(path)
	if real != '' {
		return real
	}
	return path
}

fn is_valid_v_receiver_type_name(name string) bool {
	return is_valid_stub_type_name(name)
}

fn (c &C2V) is_main_source_path(path string) bool {
	if path == '' || c.files.len == 0 {
		return false
	}
	return normalize_cpp_source_path(path) == normalize_cpp_source_path(c.files[0])
}

fn (c &C2V) node_source_path(node &Node) string {
	candidates := [
		node.location.file,
		node.range.begin.file,
		node.range.end.file,
		node.location.spelling_file.path,
		node.range.begin.spelling_file.path,
		node.range.end.spelling_file.path,
		node.range.begin.expansion_file.path,
		node.range.end.expansion_file.path,
	]
	for p in candidates {
		if p != '' {
			return p
		}
	}
	if node.location.source_file.path != '' {
		included_from := normalize_cpp_source_path(node.location.source_file.path)
		if line_is_builtin_header(included_from) {
			return included_from
		}
	}
	if node.location.file_index >= 0 && node.location.file_index < c.files.len {
		return c.files[node.location.file_index]
	}
	return ''
}

fn (c &C2V) node_body_source_path(node &Node) string {
	for child in node.inner {
		if child.kindof(.compound_stmt) {
			return c.node_source_path(child)
		}
	}
	return ''
}

fn (c &C2V) node_body_explicitly_in_main_file(node &Node) bool {
	body_path := c.node_body_source_path(node)
	if body_path == '' {
		// Clang often omits a path on CompoundStmt nodes for methods defined
		// inline inside a class in the main .cpp file. set_file_index() still
		// attributes the enclosing method correctly, so use that attribution
		// instead of discarding valid overrides in directory mode.
		return node.location.file_index == 0
	}
	return c.is_main_source_path(body_path)
}

fn (c &C2V) expand_cpp_function_alias_type(v_type string) string {
	mut base_type := v_type.trim_space()
	mut pointer_prefix := ''
	for base_type.starts_with('&') {
		pointer_prefix += '&'
		base_type = base_type[1..].trim_space()
	}
	// V spells a pointer to a function value `&fn (...)` like the function
	// value itself, so only a function alias without pointer layers expands.
	if pointer_prefix != '' {
		return v_type
	}
	if underlying := c.type_aliases[base_type] {
		if underlying.starts_with('fn (') {
			return underlying
		}
	}
	return v_type
}

fn (c &C2V) expand_cpp_function_alias_params(params []string) []string {
	mut expanded := []string{cap: params.len}
	for param in params {
		space_index := param.index(' ') or { -1 }
		if space_index < 0 {
			expanded << param
			continue
		}
		param_name := param[..space_index]
		param_type := param[space_index + 1..]
		expanded << '${param_name} ${c.expand_cpp_function_alias_type(param_type)}'
	}
	return expanded
}

fn (c &C2V) node_body_in_main_file(node &Node) bool {
	body_path := c.node_body_source_path(node)
	if body_path != '' {
		return c.is_main_source_path(body_path)
	}
	return node.location.file_index == 0
}

fn (mut c C2V) collect_cpp_class_method_bases() {
	if !c.is_dir {
		c.class_method_bases.clear()
		c.cpp_class_bases.clear()
	}
	c.note_cpp_anonymous_record_typedefs(c.tree.inner)
	for node in c.tree.inner {
		c.collect_cpp_class_method_bases_from_node(&node)
	}
	// Constructor calls can precede their out-of-class definitions. Reserve the
	// exact signature/name mapping before rendering any function bodies so those
	// calls invoke the real translated initializer rather than a positional V
	// struct literal.
	for node in c.tree.inner {
		c.collect_cpp_constructor_signatures(node, '')
		c.collect_cpp_free_function_signatures(node)
	}
}

// Overloads are keyed by their canonical signature: the same function can be
// spelled through different typedefs in different declarations.
fn cpp_function_signature_key(name string, typ AstJsonType) string {
	signature := if typ.desugared_qualified != '' { typ.desugared_qualified } else { typ.qualified }
	return '${name}|${collapse_ascii_whitespace(signature)}'
}

// Clang models conversion operators (`operator T()`) as a CXXMethodDecl subclass.
fn is_cpp_method_like_decl(node &Node) bool {
	return node.kindof(.cxx_method_decl) || node.kindof(.cxx_conversion_decl)
}

fn cpp_free_function_base_name(name string) string {
	if name.starts_with('operator') {
		operator_name := cpp_operator_to_v_method(name)
		if operator_name != '' {
			return 'cpp_free_${operator_name}'
		}
	}
	// C++-linkage functions are project symbols even when they overload a C
	// library name such as `sprintf`.
	v_name := filter_name(c_identifier_to_v_name(name), true).camel_to_snake()
	// V calls module functions named `init`/`cleanup` implicitly.
	return if v_name in v_reserved_fn_names { 'c_' + v_name } else { v_name }
}

fn (mut c C2V) collect_cpp_free_function_signatures(node Node) {
	if node.kindof(.function_decl) && node.name != '' && node.has_child_of_kind(.template_argument) {
		// Every translation unit must spell a function template instantiation the
		// same way as the unit that emits it, regardless of local overload order.
		v_name := cpp_function_template_specialization_v_name(&node, '')
		if v_name != '' {
			for declaration_id in [node.id, node.previous_declaration] {
				if declaration_id != '' {
					c.cpp_function_decl_names[declaration_id] = v_name
				}
			}
		}
	} else if node.kindof(.function_decl) && node.name != '' && !is_c_linkage_function_decl(&node) {
		base_name := cpp_free_function_base_name(node.name)
		if base_name != '' {
			signature_key := cpp_function_signature_key(node.name, node.ast_type)
			// A redeclaration can spell the same parameter types through different
			// typedefs; Clang's redeclaration chain identifies it as the same function.
			mut v_name := c.cpp_function_decl_names[node.previous_declaration] or { '' }
			if v_name == '' {
				v_name = c.cpp_function_signature_v_names[signature_key] or { '' }
			}
			if v_name == '' {
				mut overload_names := map[string]bool{}
				for existing_signature, existing_name in c.cpp_function_signature_v_names {
					if existing_signature.starts_with(node.name + '|') {
						overload_names[existing_name] = true
					}
				}
				overload_index := overload_names.len + 1
				v_name = if overload_index == 1 {
					base_name
				} else {
					'${base_name}_${overload_index}'
				}
				// A function must not share its V name with a global (`R_OrderIndexes`
				// and `r_orderIndexes` both become `r_order_indexes`).
				if c.global_uses_v_name(v_name) {
					v_name += '_fn'
				}
			}
			if signature_key !in c.cpp_function_signature_v_names {
				c.cpp_function_signature_v_names[signature_key] = v_name
			}
			for declaration_id in [node.id, node.previous_declaration] {
				if declaration_id != '' {
					c.cpp_function_decl_names[declaration_id] = v_name
				}
			}
		}
	}
	for child in node.inner {
		c.collect_cpp_free_function_signatures(child)
	}
}

fn (mut c C2V) collect_cpp_constructor_signatures(node Node, enclosing_class string) {
	mut class_name := enclosing_class
	record_name := if node.name != '' {
		node.name
	} else {
		c.cpp_anonymous_record_typedef_names[node.id] or { '' }
	}
	if node.kindof(.cxx_record_decl) && record_name != '' {
		class_name = c.add_struct_name(mut c.types, record_name)
	}
	if node.kindof(.cxx_constructor_decl) && !node.is_implicit
		&& node.explicitly_defaulted == '' {
		mut receiver_type := class_name
		if receiver_type == '' && node.mangled_name != '' {
			receiver_type = c.add_struct_name(mut c.types, extract_class_from_mangled(node.mangled_name))
		}
		constructor_key := cpp_constructor_signature_key(receiver_type, node.ast_type.qualified)
		c_param_types := cpp_constructor_c_param_types(node.ast_type.qualified)
		// A copy constructor may be defined in another translation unit than the
		// copies (`new T(other)`), so it is named up front too.
		is_move := c_param_types.len == 1 && c_param_types[0].trim_space().ends_with('&&')
			&& normalize_cpp_operator_type_name(c.convert_type(c_param_types[0]).name) == receiver_type
		if constructor_key != '' && !is_move && !node.explicitly_deleted
			&& constructor_key !in c.cpp_constructor_signature_names {
			c.declared_local_vars.clear()
			c.declared_local_var_types.clear()
			c.local_decl_v_names.clear()
			mut constructor := node
			constructor.current_child_id = 0
			params := c.fn_params(mut constructor, false)
			mut init_name := if params.len == 0 { 'init' } else { 'init${params.len}' }
			if c.class_has_method_base(receiver_type, init_name)
				|| c.class_inherits_method_base(receiver_type, init_name) {
				init_name = if params.len == 0 { 'ctor' } else { 'ctor${params.len}' }
			}
			init_name = c.reserve_method_name(receiver_type, init_name)
			c.cpp_constructor_signature_names[constructor_key] = init_name
			c.cpp_constructor_signature_params[constructor_key] = params.clone()
		}
	}
	// A template instantiated before a record can default-construct it (e.g.
	// `new T[n]`), so name its compiler-defined default constructor up front.
	if node.kindof(.cxx_constructor_decl) && (node.is_implicit || node.explicitly_defaulted != '')
		&& class_name != '' && cpp_constructor_c_param_types(node.ast_type.qualified).len == 0
		&& c.is_cpp_nontrivial_default_constructor(class_name, &node) {
		c.register_cpp_constructor_name(class_name, &node, []string{})
	}
	for child in node.inner {
		c.collect_cpp_constructor_signatures(child, class_name)
	}
}

// cpp_field_owner finds the class that declares a field: the class itself or
// one of its bases.
fn (c &C2V) cpp_field_owner(class_name string, field string, mut seen map[string]bool) string {
	if class_name == '' || class_name in seen {
		return ''
	}
	seen[class_name] = true
	if '${class_name}.${field}' in c.cpp_field_v_names {
		return class_name
	}
	for base in c.cpp_class_bases[class_name] {
		owner := c.cpp_field_owner(normalize_cpp_operator_type_name(base), field, mut seen)
		if owner != '' {
			return owner
		}
	}
	return ''
}

// cpp_anonymous_member_name names the unnamed member through which C++
// accesses the fields of an anonymous struct or union, after the source
// position in its type (`union (unnamed union at File.h:167:3)`).
fn cpp_anonymous_member_name(type_name string) ?string {
	if !(type_name.contains('(unnamed ') || type_name.contains('(anonymous ')) {
		return none
	}
	position := type_name.trim_right(')').split(':')
	if position.len < 3 {
		return none
	}
	line := position[position.len - 2]
	column := position[position.len - 1]
	if !line.is_int() || !column.is_int() {
		return none
	}
	return 'anon_${line}_${column}'
}

// cpp_field_v_name names a C++ member field like member accesses do: an
// all-uppercase name (`AI_DEST_UNREACHABLE`) is lowercased, not split per letter.
fn cpp_field_v_name(name string) string {
	if is_all_upper_identifier(name) {
		return filter_name(name.to_lower(), false).all_after_last('.').trim_left('_')
	}
	return filter_name(name, false).all_after_last('.').camel_to_snake().trim_left('_')
}

struct CppDeclaringRecord {
	class_name string
	record     Node
}

struct CppVirtualMethod {
	class_name string
	signature  string
}

struct CppVirtualImpl {
	v_name       string
	params       string
	ret_type     string
	receiver_mut bool
}

// cpp_virtual_signature identifies an overridable method by its name,
// parameter types and qualifiers; an override may return a covariant type.
fn cpp_virtual_signature(node &Node) string {
	typ := normalize_cpp_param_qualifiers(if node.ast_type.desugared_qualified != '' {
		node.ast_type.desugared_qualified
	} else {
		node.ast_type.qualified
	})
	params_end := typ.last_index(')') or { return node.name + '|' + typ }
	mut depth := 0
	for i := params_end; i >= 0; i-- {
		if typ[i] == `)` {
			depth++
		} else if typ[i] == `(` {
			depth--
			if depth == 0 {
				return node.name + '|' + typ[i..]
			}
		}
	}
	return node.name + '|' + typ
}

// collect_cpp_virtual_methods records the virtual methods of a record: those
// declared `virtual` and those overriding a virtual method of a base, which
// Clang does not mark.
fn (mut c C2V) collect_cpp_virtual_methods(class_name string, node &Node, base_names []string) {
	mut inherited := map[string]bool{}
	for base_name in base_names {
		for signature, _ in c.cpp_class_virtual_sigs[base_name] {
			inherited[signature] = true
		}
	}
	mut signatures := inherited.clone()
	for child in node.inner {
		if child.kindof(.cxx_destructor_decl) && child.is_virtual {
			// A virtual destructor destroys the object's dynamic class.
			signatures['~'] = true
		}
		if !is_cpp_method_like_decl(child) || child.name == '' || child.class_modifier == 'static' {
			continue
		}
		signature := cpp_virtual_signature(child)
		if !child.is_virtual && signature !in inherited {
			continue
		}
		signatures[signature] = true
		for declaration_id in [child.id, child.previous_declaration] {
			if declaration_id != '' {
				c.cpp_virtual_method_decls[declaration_id] = CppVirtualMethod{
					class_name: class_name
					signature: signature
				}
			}
		}
	}
	if signatures.len > 0 {
		c.cpp_class_virtual_sigs[class_name] = signatures.clone()
	}
}

// A polymorphic record that is a V struct (not an interface) dispatches its
// virtual methods through a class id, which mirrors the C++ vtable pointer.
fn (c &C2V) is_cpp_polymorphic_struct(class_name string) bool {
	return class_name !in c.cpp_abstract_types && c.cpp_class_virtual_sigs[class_name].len > 0
}

// The class id lives in the polymorphic root, reached through first bases,
// which share the address of the object.
fn (c &C2V) cpp_class_needs_class_id_field(class_name string) bool {
	return c.is_cpp_polymorphic_struct(class_name)
		&& !c.is_cpp_polymorphic_struct(c.cpp_first_embedded_base[class_name] or { '' })
}

fn (c &C2V) cpp_class_id_field_path(class_name string) string {
	mut path := ''
	mut current := class_name
	for {
		base := c.cpp_first_embedded_base[current] or { break }
		if !c.is_cpp_polymorphic_struct(base) {
			break
		}
		path += '.' + base
		current = base
	}
	return path + '.c2v_class'
}

fn cpp_class_id(class_name string) u32 {
	return fnv1a.sum32_string(class_name)
}

fn (c &C2V) cpp_virtual_dispatch_enabled() bool {
	return c.is_cpp && (!c.is_dir || c.project_single_module)
}

fn source_begin_offset(begin Begin) int {
	if begin.offset != 0 {
		return begin.offset
	}
	if begin.spelling_file.offset != 0 {
		return begin.spelling_file.offset
	}
	return begin.expansion_file.offset
}

// A qualified call (`Base::method()`) names the implementation it runs; its
// member expression starts at the qualifier, before its (implicit) object.
fn cpp_member_expr_is_qualified(member_expr &Node) bool {
	if member_expr.inner.len == 0 {
		return false
	}
	if source_begin_offset(member_expr.range.begin) < source_begin_offset(member_expr.inner[0].range.begin) {
		// `Base::method` on the implicit `this`.
		return true
	}
	// `object.Base::method`: Clang does not record the qualifier, which occupies
	// the source between the object and the member name (on the same line, past
	// the `.`/`->`).
	object_end := member_expr.inner[0].range.end
	member := member_expr.range.end
	if object_end.offset == 0 || member.offset == 0 || object_end.col == 0 || member.col == 0 {
		return false
	}
	gap := member.offset - (object_end.offset + object_end.tok_len)
	same_line := member.col - object_end.col == member.offset - object_end.offset
	operator_len := if member_expr.is_arrow { 2 } else { 1 }
	return same_line && gap >= operator_len + 3
}

// cpp_virtual_dispatch_name returns the dispatcher that a call of a virtual
// method uses instead of calling the method of the static type directly.
fn (mut c C2V) cpp_virtual_dispatch_name(member_expr &Node, v_method string) string {
	if !c.cpp_virtual_dispatch_enabled() || v_method == '' {
		return ''
	}
	method := c.cpp_virtual_method_decls[member_expr.referenced_member_decl] or { return '' }
	if cpp_member_expr_is_qualified(member_expr) {
		return ''
	}
	mut dispatch_class := method.class_name
	if !c.is_cpp_polymorphic_struct(dispatch_class) {
		// A virtual method of an abstract class (a V interface) called on a record,
		// e.g. by a method of the abstract class run on the record, dispatches over
		// the record's class and the classes derived from it.
		receiver_class := c.cpp_member_object_class(member_expr)
		if receiver_class == '' || !c.is_cpp_polymorphic_struct(receiver_class) {
			return ''
		}
		dispatch_class = receiver_class
	}
	name := 'c2v_virtual_${v_method}'
	c.cpp_virtual_dispatchers['${dispatch_class}|${method.signature}'] = CppVirtualMethod{
		class_name: dispatch_class
		signature: name
	}
	return name
}

// cpp_member_object_class is the V record type of the object a member
// expression accesses: `this` in a method copied from an abstract base to a
// derived record is that record.
fn (mut c C2V) cpp_member_object_class(member_expr &Node) string {
	if member_expr.inner.len == 0 {
		return ''
	}
	object := member_expr.inner[0]
	if c.synthesizing_cpp_derived_method && c.cur_class != '' && cpp_receiver_is_direct_this(object) {
		return c.cur_class
	}
	return normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(object)).name)
}

// record_cpp_virtual_impl remembers a translated virtual method, which the
// dispatchers of its bases call for objects of its class.
fn (mut c C2V) record_cpp_virtual_impl(class_name string, node &Node, impl CppVirtualImpl) {
	if !c.is_cpp_polymorphic_struct(class_name) {
		return
	}
	method := c.cpp_virtual_method_decls[node.id] or {
		c.cpp_virtual_method_decls[node.previous_declaration] or { return }
	}
	c.cpp_virtual_impls['${class_name}|${method.signature}'] = impl
}

fn (mut c C2V) record_cpp_virtual_declaration(class_name string, node &Node, declaration CppVirtualImpl) {
	if !c.is_cpp_polymorphic_struct(class_name) {
		return
	}
	method := c.cpp_virtual_method_decls[node.id] or {
		c.cpp_virtual_method_decls[node.previous_declaration] or { return }
	}
	key := '${class_name}|${method.signature}'
	if key !in c.cpp_virtual_declarations {
		c.cpp_virtual_declarations[key] = declaration
	}
}

fn cpp_v_call_arguments(params string) string {
	if params.trim_space() == '' {
		return ''
	}
	mut args := []string{}
	mut depth := 0
	mut start := 0
	for i := 0; i <= params.len; i++ {
		if i < params.len {
			if params[i] == `(` || params[i] == `[` {
				depth++
			} else if params[i] == `)` || params[i] == `]` {
				depth--
			}
			if params[i] != `,` || depth != 0 {
				continue
			}
		}
		param := params[start..i].trim_space()
		start = i + 1
		name := param.trim_string_left('mut ').all_before(' ')
		args << if param.contains('...') {
			'...' + name
		} else if param.starts_with('mut ') {
			'mut ' + name
		} else {
			name
		}
	}
	return args.join(', ')
}

// cpp_virtual_dispatchers_source generates the dispatchers requested by calls.
// Each selects the final override for the dynamic class of the object among
// the classes derived through first bases, which share the object's address.
fn (c &C2V) cpp_virtual_dispatchers_source() string {
	mut derived_classes := map[string][]string{}
	for class_name, base in c.cpp_first_embedded_base {
		derived_classes[base] << class_name
	}
	mut out := strings.new_builder(4096)
	mut keys := c.cpp_virtual_dispatchers.keys()
	keys.sort()
	for key in keys {
		dispatcher := c.cpp_virtual_dispatchers[key]
		class_name := dispatcher.class_name
		signature := key.all_after('|')
		// Map every derived class to the class whose override it runs.
		mut impl_classes := map[string][]string{}
		mut pending := [class_name]
		mut provider := map[string]string{}
		provider[class_name] = class_name
		for pending.len > 0 {
			current := pending.pop()
			for derived in derived_classes[current] {
				provider[derived] = if '${derived}|${signature}' in c.cpp_virtual_impls {
					derived
				} else {
					provider[current]
				}
				if provider[derived] != class_name {
					impl_classes[provider[derived]] << derived
				}
				pending << derived
			}
		}
		mut impl_names := impl_classes.keys()
		impl_names.sort()
		// A virtual method declared but not defined in the class takes the
		// signature of an override; the class itself never runs it.
		has_base_impl := '${class_name}|${signature}' in c.cpp_virtual_impls
		base_impl := c.cpp_virtual_impls['${class_name}|${signature}'] or {
			if impl_names.len > 0 {
				c.cpp_virtual_impls['${impl_names[0]}|${signature}']
			} else {
				c.cpp_virtual_declarations['${class_name}|${signature}'] or { continue }
			}
		}
		args := cpp_v_call_arguments(base_impl.params)
		ret := if base_impl.ret_type == '' { '' } else { ' ${base_impl.ret_type}' }
		out.writeln('fn (this &' + class_name + ') ' + dispatcher.signature + '(' + base_impl.params + ')' + ret + ' {')
		if impl_classes.len > 0 {
			out.writeln('\tmatch this' + c.cpp_class_id_field_path(class_name) + ' {')
			for impl_class in impl_names {
				impl := c.cpp_virtual_impls['${impl_class}|${signature}']
				ids := impl_classes[impl_class].map('${cpp_class_id(it)}').join(', ')
				out.writeln('\t\t' + ids + ' {')
				out.writeln(cpp_virtual_dispatch_call('\t\t\t', impl_class, impl, args, base_impl.ret_type))
				out.writeln('\t\t}')
			}
			out.writeln('\t\telse {}')
			out.writeln('\t}')
		}
		if has_base_impl {
			out.writeln(cpp_virtual_dispatch_call('\t', class_name, base_impl, args, base_impl.ret_type))
		} else {
			out.writeln("\tpanic('c2v: " + class_name + ' does not define ' + signature.all_before('|') + "')")
		}
		out.writeln('}')
		out.writeln('')
	}
	return out.str()
}

fn cpp_virtual_dispatch_call(indent string, class_name string, impl CppVirtualImpl, args string, ret_type string) string {
	mutability := if impl.receiver_mut { 'mut ' } else { '' }
	mut call := 'c2v_target.${impl.v_name}(${args})'
	if impl.ret_type != ret_type && ret_type.starts_with('&') {
		// A covariant override returns a pointer to a derived class.
		call = 'unsafe { ${ret_type}(voidptr(${call})) }'
	}
	return '${indent}${mutability}c2v_target := unsafe { &${class_name}(voidptr(this)) }\n' + if ret_type == '' {
		'${indent}${call}\n${indent}return'
	} else {
		'${indent}return ${call}'
	}
}

fn (mut c C2V) collect_cpp_class_method_bases_from_node(node &Node) {
	// A call after a method's out-of-line definition refers to the definition.
	if is_cpp_method_like_decl(node) && node.id != '' && node.previous_declaration != '' {
		if method := c.cpp_virtual_method_decls[node.previous_declaration] {
			c.cpp_virtual_method_decls[node.id] = method
		}
		// A call can reference an out-of-line definition that is translated after
		// the call (e.g. a template instantiated earlier in the translation unit).
		c.cpp_method_redeclarations[node.previous_declaration] << node.id
		if record := c.cpp_assignment_operator_records[node.previous_declaration] {
			c.cpp_assignment_operator_records[node.id] = record
		}
	}
	record_name := if node.name != '' {
		node.name
	} else {
		c.cpp_anonymous_record_typedef_names[node.id] or { '' }
	}
	if node.kindof(.cxx_record_decl) && record_name != '' {
		class_name := c.add_struct_name(mut c.types, record_name)
		if is_valid_v_receiver_type_name(class_name) {
			is_abstract := c.cpp_record_is_abstract_interface(node)
			if is_abstract {
				c.cpp_abstract_types[class_name] = true
			}
			mut base_names := c.cpp_class_bases[class_name].clone()
			for base in node.bases {
				base_name :=
					normalize_cpp_operator_type_name(c.convert_type(base.ast_type.qualified).name)
				if base_name != '' && base_name !in base_names {
					base_names << base_name
				}
			}
			if base_names.len > 0 {
				c.cpp_class_bases[class_name] = base_names
			}
			if node.inner.any(it.kindof(.cxx_destructor_decl) && !it.is_implicit
				&& it.explicitly_defaulted == '') {
				c.cpp_classes_with_destructor_body[class_name] = true
			}
			if node.inner.len > 0 {
				c.collect_cpp_virtual_methods(class_name, node, base_names)
			}
			for child in node.inner {
				if !is_cpp_method_like_decl(child) || child.name == '' {
					continue
				}
				if child.name == 'operator=' {
					for declaration_id in [child.id, child.previous_declaration] {
						if declaration_id != '' {
							c.cpp_assignment_operator_records[declaration_id] = CppDeclaringRecord{
								class_name: class_name
								record: *node
							}
						}
					}
				}
				if child.class_modifier != 'static' && !child.ast_type.qualified.contains(') const') {
					for declaration_id in [child.id, child.previous_declaration] {
						if declaration_id != '' {
							c.cpp_nonconst_method_decls[declaration_id] = true
						}
					}
				}
				base_name := method_base_name_from_cpp_name(child.name)
				if base_name == '' {
					continue
				}
				if child.has_child_of_kind(.compound_stmt)
					|| has_direct_child_kind_str(child, 'CompoundStmt') {
					c.cpp_method_body_bases['${class_name}.${base_name}'] = true
				}
				if c.is_dir && c.project_generate_stubs && !c.project_require_no_stubs
					&& c.outv != '' && !child.is_implicit && child.explicitly_defaulted == '' {
					c.project_emitted_method_defs['${os.dir(c.outv)}|${class_name}.${base_name}'] = true
				}
				if (child.is_pure || (is_abstract && child.is_virtual))
					&& !child.ast_type.qualified.contains(') const') {
					// Non-const interface methods are emitted in the interface's `mut:`
					// section. Register their translated names even when a repeated
					// header declaration gives a call site a different Clang id.
					c.cpp_mut_method_names[base_name] = true
				}
				if child.is_pure || (is_abstract && child.is_virtual) {
					c.cpp_pure_method_bases['${class_name}.${base_name}'] = true
				}
				c.class_method_bases['${class_name}.${base_name}'] = true
				if child.class_modifier == 'static' && child.mangled_name != '' {
					c.cpp_static_method_symbols[child.mangled_name] = true
				}
			}
		}
	}
	c.note_cpp_anonymous_record_typedefs(node.inner)
	for child in node.inner {
		c.collect_cpp_class_method_bases_from_node(&child)
	}
}

// note_cpp_anonymous_record_typedefs records the names of anonymous records
// named by the typedef that follows them (`typedef struct { ... } Name;`).
fn (mut c C2V) note_cpp_anonymous_record_typedefs(nodes []Node) {
	for i := 0; i + 1 < nodes.len; i++ {
		record := nodes[i]
		next := nodes[i + 1]
		if record.kindof(.cxx_record_decl) && record.name == '' && record.id != ''
			&& next.kind == .typedef_decl && next.name != ''
			&& node_contains_owned_tag_id(&next, record.id) {
			c.cpp_anonymous_record_typedef_names[record.id] = next.name
		}
	}
}

fn (c &C2V) is_cpp_static_method(node &Node) bool {
	if node.class_modifier == 'static' || node.mangled_name in c.cpp_static_method_symbols {
		return true
	}
	return node.mangled_name != '' && node.mangled_name in c.cpp_record_static_methods
}

fn (mut c C2V) synthesize_cpp_abstract_default_method(method_template &Node, class_name string,
	is_static bool) {
	if !c.project_require_no_stubs || is_static || class_name !in c.cpp_abstract_types {
		return
	}
	mut derived_names := c.cpp_class_bases.keys()
	derived_names.sort()
	for derived_name in derived_names {
		if derived_name in c.cpp_abstract_types {
			continue
		}
		mut seen := map[string]bool{}
		if !c.cpp_class_derives_from(derived_name, class_name, mut seen) {
			continue
		}
		mut derived_method := clone_cpp_operator_node(method_template)
		old_class := c.cur_class
		old_synthesizing := c.synthesizing_cpp_derived_method
		old_default_synthesizing := c.synthesizing_cpp_default_method
		c.cur_class = derived_name
		// This is a synthesized V implementation, not the original C++ symbol.
		// Reserve its name on the derived receiver without reusing or changing the
		// base declaration's Clang identity.
		c.synthesizing_cpp_derived_method = true
		// Keep a separately named copy for explicitly qualified calls such as
		// an explicitly qualified base call, including when the derived class overrides it.
		c.synthesizing_cpp_default_method = true
		c.cxx_method_decl(&derived_method)
		// A derived class without an override also needs the ordinary method name in
		// order to implement the V interface and preserve virtual dispatch.
		method_base := method_base_name_from_cpp_name(method_template.name)
		if '${derived_name}.${method_base}' !in c.class_method_bases {
			mut inherited_method := clone_cpp_operator_node(method_template)
			c.synthesizing_cpp_default_method = false
			c.cxx_method_decl(&inherited_method)
		}
		c.synthesizing_cpp_default_method = old_default_synthesizing
		c.synthesizing_cpp_derived_method = old_synthesizing
		c.cur_class = old_class
	}
}

fn (mut c C2V) cxx_method_decl(_node &Node) {
	if c.is_unused_inline_member(_node) {
		return
	}
	method_template := clone_cpp_operator_node(_node)
	c.declared_local_vars.clear()
	c.declared_local_var_types.clear()
	c.local_decl_v_names.clear()
	c.for_init_vars.clear()
	c.conditional_mutable_locals = {}
	mut node := unsafe { _node }
	is_static := c.is_cpp_static_method(node)
	name := node.name
	if (node.is_implicit || node.explicitly_defaulted != '')
		&& !c.is_cpp_nontrivial_implicit_assignment(node) {
		return
	}
	// Skip operator methods that can't be represented in V
	if name.starts_with('operator') {
		v_op_name := cpp_operator_to_v_method(name)
		if v_op_name == '' {
			if c.project_require_no_stubs && c.node_body_in_main_file(node) {
				c.verror('unsupported C++ operator ${name} in strict translation of ${c.cur_file}')
			}
			return
		}
	}
	// node.ast_type.qualified is the function signature type, e.g. "int ()" or "void (int)"
	// Extract return type from function signature (everything before first '(')
	mut ret_type := node.ast_type.qualified.before('(').trim_space()
	if ret_type == 'void' {
		ret_type = ''
	} else {
		ret_type = ' ' + c.cpp_return_v_type(ret_type)
	}
	mut class_name := if c.cur_class != '' {
		c.add_struct_name(mut c.types, c.cur_class)
	} else {
		''
	}
	if class_name == '' && node.mangled_name != '' {
		extracted := extract_class_from_mangled(node.mangled_name)
		if extracted != '' {
			// The Itanium receiver may be a concrete template specialization,
			// such as a container specialization. Route it through the normal type converter
			// before reserving the receiver name; add_struct_name alone would keep
			// angle brackets and reject the otherwise valid V method.
			receiver_name := c.convert_type(extracted).name
			class_name = c.add_struct_name(mut c.types, receiver_name)
		}
	}
	// The class's nested types are in scope in an out-of-line method too.
	old_nested_enum_scope := c.nested_enum_method_scope
	c.nested_enum_method_scope = if c.cur_class != '' {
		c.cur_class
	} else {
		extract_class_from_mangled(node.mangled_name)
	}
	defer {
		c.nested_enum_method_scope = old_nested_enum_scope
	}
	if class_name == '' {
		return
	}
	if !is_valid_v_receiver_type_name(class_name) {
		return
	}
	// Out-of-line members (e.g. an explicit `template<> void List<int>::Sort(cmp_t *)`)
	// name the class's nested typedefs, which are specialized per instantiation.
	old_template_type_aliases := c.cpp_template_type_aliases.clone()
	if nested_aliases := c.cpp_record_nested_type_aliases[class_name] {
		for alias, concrete in nested_aliases {
			c.cpp_template_type_aliases[alias] = concrete
		}
	}
	defer {
		c.cpp_template_type_aliases = old_template_type_aliases.clone()
	}
	has_body := node.has_child_of_kind(.compound_stmt)
	c.prepare_copied_pointer_params(node)
	mut params := c.fn_params(mut node, false)
	params = c.expand_cpp_function_alias_params(params)
	is_variadic := node.ast_type.qualified.contains('...')
	mut str_args := params.join(', ')
	if is_variadic {
		c.declared_local_vars.add('c2v_variadic_args')
		c.declared_local_var_types['c2v_variadic_args'] = '[]voidptr'
	}
	method_base_name := method_base_name_from_cpp_name(name)
	method_key := '${class_name}.${method_base_name}'
	emit_compat_stub := c.is_dir && c.is_cpp && c.project_generate_stubs
		&& !c.project_require_no_stubs
		&& (!c.method_defined_in_current_output_dir_from_sources(method_key)
			|| !c.node_body_in_main_file(node))
	if !is_static {
		// A dispatcher needs the signature even when no implementation is
		// translated (e.g. one defined by a separately built library).
		declared_params := if is_variadic {
			(if str_args != '' { str_args + ', ' } else { '' }) + 'c2v_variadic_args ...voidptr'
		} else {
			str_args
		}
		c.record_cpp_virtual_declaration(class_name, node, CppVirtualImpl{
			params: declared_params
			ret_type: ret_type.trim_space()
		})
	}
	if !has_body && !emit_compat_stub && !c.should_emit_skeleton_body_for_node(node) {
		return
	}
	mut v_method_name := if is_static {
		c.register_cpp_static_method_decl_name(class_name, method_base_name, node)
	} else {
		c.register_cpp_method_decl_name(class_name, method_base_name, node)
	}
	if c.synthesizing_cpp_default_method && v_method_name != '' {
		v_method_name = 'c2v_default_${v_method_name}'
	}
	if c.should_skip_duplicate_cpp_member(node, class_name, v_method_name) {
		c.synthesize_cpp_abstract_default_method(&method_template, class_name, is_static)
		return
	}
	if c.should_skip_duplicate_cpp_rendered_method(class_name, v_method_name, str_args, is_static) {
		c.synthesize_cpp_abstract_default_method(&method_template, class_name, is_static)
		return
	}
	if v_method_name == '' {
		return
	}
	if !c.synthesizing_cpp_derived_method && has_body && !is_static
		&& method_key in c.cpp_pure_method_bases && class_name in c.cpp_abstract_types {
		v_method_name = 'c2v_default_${v_method_name}'
	}
	method_is_const := node.ast_type.qualified.contains(') const')
	// A C++ method receives its object's address (`this`). V passes a receiver
	// that is neither `mut` nor a reference by value: the method would see a
	// copy, with another address (comparisons of `this`, pointers into the
	// object, calls that pass `this` on), without changes made through `mutable`
	// members, and without the dynamic class that virtual calls dispatch on.
	// So a method that changes its object takes a `mut` receiver and every other
	// method a reference: V also accepts a call result as such a receiver,
	// unlike a `mut` receiver.
	body_mutates_receiver := c.cxx_method_body_mutates_receiver(node)
	receiver_mut := if !method_is_const && body_mutates_receiver {
		'mut '
	} else {
		''
	}
	receiver_is_ref := receiver_mut == '' && !is_static
	receiver_type_prefix := if receiver_is_ref { '&' } else { '' }
	if receiver_mut == 'mut ' {
		c.cpp_mut_method_names[v_method_name] = true
	}
	if is_variadic {
		if str_args != '' {
			str_args += ', c2v_variadic_args ...voidptr'
		} else {
			str_args = 'c2v_variadic_args ...voidptr'
		}
	}
	if !is_static && has_body {
		c.record_cpp_virtual_impl(class_name, node, CppVirtualImpl{
			v_name: v_method_name
			params: str_args
			ret_type: ret_type.trim_space()
			receiver_mut: receiver_mut != ''
		})
	}
	if is_static {
		c.genln('fn ${v_method_name}(${str_args})${ret_type} {')
	} else {
		c.genln('fn (${receiver_mut}this ${receiver_type_prefix}${class_name}) ${v_method_name}(${str_args})${ret_type} {')
	}
	c.gen_param_local_copies()
	if emit_compat_stub || c.should_emit_skeleton_body_for_node(node) || !has_body {
		c.gen_skeleton_fn_body(ret_type.trim_space())
		return
	}
	if node.has_child_of_kind(.overrides) {
		_ = node.try_get_next_child_of_kind(.overrides) or {
			vprintln(err.str())
			bad_node
		}
	}
	mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
		vprintln(err.str())
		bad_node
	}

	old_cur_fn_ret_type := c.cur_fn_ret_type
	old_receiver_is_ref := c.cur_receiver_is_ref
	old_current_fn_v_name := c.current_fn_v_name
	old_static_local_vars := c.static_local_vars.clone()
	old_address_taken_locals := c.address_taken_locals.clone()
	c.cur_fn_ret_type = ret_type.trim_space()
	c.cur_receiver_is_ref = receiver_is_ref
	// Static locals of a method become globals named after the method.
	c.current_fn_v_name = '${c_identifier_to_v_name(class_name)}_${v_method_name}'
	c.static_local_vars = {}
	c.address_taken_locals = {}
	collect_address_taken_decl_refs(stmts, mut c.address_taken_locals)
	collect_conditional_mutable_decl_refs(stmts, false, mut c.conditional_mutable_locals)
	c.gc_thread_entry_body = c.is_gc_thread_entry(node)
	c.statements(mut stmts)
	c.cur_fn_ret_type = old_cur_fn_ret_type
	c.cur_receiver_is_ref = old_receiver_is_ref
	c.current_fn_v_name = old_current_fn_v_name
	c.static_local_vars = old_static_local_vars.clone()
	c.address_taken_locals = old_address_taken_locals.clone()
	c.synthesize_cpp_abstract_default_method(&method_template, class_name, is_static)
}

// Convert C++ operator name to valid V method name
fn cpp_operator_to_v_method(op_name string) string {
	return match op_name {
		'operator=' {
			'op_assign'
		}
		'operator==' {
			'op_eq'
		}
		'operator!=' {
			'op_ne'
		}
		'operator<' {
			'op_lt'
		}
		'operator>' {
			'op_gt'
		}
		'operator<=' {
			'op_le'
		}
		'operator>=' {
			'op_ge'
		}
		'operator+' {
			'op_plus'
		}
		'operator-' {
			'op_minus'
		}
		'operator*' {
			'op_mul'
		}
		'operator/' {
			'op_div'
		}
		'operator%' {
			'op_mod'
		}
		'operator+=' {
			'op_plus_assign'
		}
		'operator-=' {
			'op_minus_assign'
		}
		'operator*=' {
			'op_mul_assign'
		}
		'operator/=' {
			'op_div_assign'
		}
		'operator[]' {
			'op_index'
		}
		'operator()' {
			'op_call'
		}
		'operator new' {
			'op_new'
		}
		'operator delete' {
			'op_delete'
		}
		'operator<<' {
			'op_lshift'
		}
		'operator>>' {
			'op_rshift'
		}
		'operator&' {
			'op_and'
		}
		'operator|' {
			'op_or'
		}
		'operator^' {
			'op_xor'
		}
		'operator~' {
			'op_not'
		}
		'operator!' {
			'op_bang'
		}
		'operator&&' {
			'op_land'
		}
		'operator||' {
			'op_lor'
		}
		'operator<<=' {
			'op_lshift_assign'
		}
		'operator>>=' {
			'op_rshift_assign'
		}
		'operator&=' {
			'op_and_assign'
		}
		'operator|=' {
			'op_or_assign'
		}
		'operator^=' {
			'op_xor_assign'
		}
		'operator++' {
			'op_inc'
		}
		'operator--' {
			'op_dec'
		}
		'operator->' {
			'op_arrow'
		}
		'operator->*' {
			'op_arrow_star'
		}
		'operator,' {
			'op_comma'
		}
		'operator new[]' {
			'op_new_array'
		}
		'operator delete[]' {
			'op_delete_array'
		}
		else {
			if op_name.starts_with('operator ') {
				// Encode punctuation as words so conversions to pointers/references remain
				// distinct while still producing valid V identifiers.
				conversion_token := op_name[9..].replace('::', '_').replace('&&', '_rref_').replace('&', '_ref_').replace('*', '_ptr_')
				'op_conv_' + sanitize_type_token(conversion_token).to_lower()
			} else {
				''
			}
		}
	}
}

fn normalize_cpp_operator_type_name(type_name string) string {
	mut t := type_name.trim_space()
	for t.starts_with('&') {
		t = t[1..].trim_space()
	}
	for t.starts_with('[]') {
		t = t[2..].trim_space()
	}
	if t.starts_with('[') && t.contains(']') {
		t = t.all_after(']').trim_space()
	}
	return t
}

fn is_cpp_operator_primitive_type(type_name string) bool {
	base := normalize_cpp_operator_type_name(type_name)
	return base == '' || base == 'voidptr' || base in v_primitive_type_names
}

fn unwrap_cpp_operator_operand(node &Node) &Node {
	mut n := unsafe { node }
	for {
		if n.inner.len == 0 {
			break
		}
		if n.kindof(.implicit_cast_expr) || n.kindof(.paren_expr)
			|| n.kindof(.materialize_temporary_expr) || n.kindof(.expr_with_cleanups)
			|| n.kindof(.cxx_bind_temporary_expr) || n.kindof(.cxx_functional_cast_expr)
			|| n.kindof(.cxx_static_cast_expr) || n.kindof(.cxx_const_cast_expr)
			|| n.kindof(.cxx_reinterpret_cast_expr) || n.kindof(.cxx_dynamic_cast_expr)
			|| n.kindof(.c_style_cast_expr) {
			n = unsafe { &n.inner[0] }
			continue
		}
		break
	}
	return n
}

fn clone_cpp_operator_node(node &Node) Node {
	mut cloned := *node
	cloned.current_child_id = 0
	cloned.inner = []Node{cap: node.inner.len}
	for child in node.inner {
		cloned.inner << clone_cpp_operator_node(&child)
	}
	cloned.array_filler = []Node{cap: node.array_filler.len}
	for child in node.array_filler {
		cloned.array_filler << clone_cpp_operator_node(&child)
	}
	return cloned
}

fn is_cpp_operator_literal_operand(node &Node) bool {
	mut base := unwrap_cpp_operator_operand(node)
	if base.kindof(.unary_operator) && base.inner.len > 0 && base.opcode in ['+', '-'] {
		base = unwrap_cpp_operator_operand(unsafe { &base.inner[0] })
	}
	return base.kindof(.integer_literal) || base.kindof(.floating_literal)
		|| base.kindof(.cxx_bool_literal_expr) || base.kindof(.character_literal)
		|| base.kindof(.string_literal) || base.kindof(.cxx_null_ptr_literal_expr)
}

fn (c &C2V) operator_node_v_type(node &Node) string {
	v_type := c.convert_type(node.ast_type.qualified).name
	return normalize_cpp_operator_type_name(v_type)
}

fn (mut c C2V) try_gen_cpp_selected_free_unary_operator(decl_ref_expr &Node, operand &Node) bool {
	if decl_ref_expr.ref_declaration.kind != .function_decl {
		return false
	}
	function_name := c.cpp_function_decl_names[decl_ref_expr.ref_declaration.id] or {
		return false
	}
	params := function_type_params(decl_ref_expr.ref_declaration.ast_type.qualified)
	if params.len != 1 {
		return false
	}
	c.gen('${function_name}(')
	c.gen_call_arg(*operand, params[0], false)
	c.gen(')')
	return true
}

fn (mut c C2V) try_gen_cpp_selected_free_binary_operator(decl_ref_expr &Node, lhs &Node, rhs &Node) bool {
	if decl_ref_expr.ref_declaration.kind != .function_decl {
		return false
	}
	function_name := c.cpp_function_decl_names[decl_ref_expr.ref_declaration.id] or {
		return false
	}
	params := function_type_params(decl_ref_expr.ref_declaration.ast_type.qualified)
	if params.len != 2 {
		return false
	}
	c.gen('${function_name}(')
	c.gen_call_arg(*lhs, params[0], false)
	c.gen(', ')
	c.gen_call_arg(*rhs, params[1], false)
	c.gen(')')
	return true
}

fn (c &C2V) should_use_operator_method_for_binary(v_method string, lhs &Node, rhs &Node) bool {
	if v_method == '' {
		return false
	}
	lhs_type := c.operator_node_v_type(lhs)
	rhs_type := c.operator_node_v_type(rhs)
	if lhs_type == '' || rhs_type == '' {
		return false
	}
	return !is_cpp_operator_primitive_type(lhs_type) && !is_cpp_operator_literal_operand(lhs)
}

fn (c &C2V) exact_cpp_method_overload_for_argument(receiver_type string, method_base string, argument_type string) string {
	receiver := normalize_cpp_operator_type_name(c.resolve_type_alias(receiver_type))
	argument := normalize_cpp_operator_type_name(c.resolve_type_alias(argument_type))
	if receiver == '' || method_base == '' || argument == '' {
		return ''
	}
	prefix := '${receiver}.${method_base}|'
	for signature_key, v_name in c.cpp_method_signature_v_names {
		if !signature_key.starts_with(prefix) {
			continue
		}
		params := function_type_params(signature_key[prefix.len..])
		if params.len != 1 {
			continue
		}
		param_type := normalize_cpp_operator_type_name(c.resolve_type_alias(c.convert_type(params[0]).name))
		if param_type == argument {
			return v_name
		}
	}
	return ''
}

fn (c &C2V) exact_cpp_method_parameter_type(receiver_type string, method_base string, argument_type string) string {
	receiver := normalize_cpp_operator_type_name(c.resolve_type_alias(receiver_type))
	argument := normalize_cpp_operator_type_name(c.resolve_type_alias(argument_type))
	if receiver == '' || method_base == '' || argument == '' {
		return ''
	}
	prefix := '${receiver}.${method_base}|'
	for signature_key, _ in c.cpp_method_signature_v_names {
		if !signature_key.starts_with(prefix) {
			continue
		}
		params := function_type_params(signature_key[prefix.len..])
		if params.len != 1 {
			continue
		}
		param_type := normalize_cpp_operator_type_name(c.resolve_type_alias(c.convert_type(params[0]).name))
		if param_type == argument {
			return params[0]
		}
	}
	return ''
}

fn (c &C2V) cpp_method_overload_for_argument(receiver_type string, method_base string, argument_type string) string {
	v_name := c.exact_cpp_method_overload_for_argument(receiver_type, method_base, argument_type)
	if v_name != '' {
		return v_name
	}
	return method_base
}

// gen_cpp_call_result_field_receiver emits a method receiver that is a record
// member reached from a call returning a reference or a pointer, such as
// `list[i].origin` in `list[i].origin.Normalize()`, through generated field
// accessors. The pinned V passes any other receiver expression rooted at a
// call as the address of a copy: writes to it are lost and pointers into it
// dangle.
fn (mut c C2V) gen_cpp_call_result_field_receiver(receiver &Node) bool {
	text := c.cpp_call_rooted_receiver_text(receiver) or { return false }
	c.gen(text)
	return true
}

// cpp_call_rooted_receiver_text renders a record reached from a call returning
// a reference or a pointer through fields and array elements, such as
// `GetHolder()->items[i].origin`, with generated accessors (see
// gen_cpp_call_result_field_receiver).
fn (mut c C2V) cpp_call_rooted_receiver_text(receiver &Node) ?string {
	object := unwrap_cpp_noop_casts(*receiver)
	if object.kindof(.array_subscript_expr) {
		return c.cpp_call_result_subscript_text(&object)
	}
	if object.kindof(.member_expr) {
		return c.cpp_call_result_field_text(&object)
	}
	return none
}

fn (mut c C2V) cpp_call_result_field_text(receiver &Node) ?string {
	mut segments := []Node{}
	mut current := unwrap_cpp_noop_casts(*receiver)
	for current.kindof(.member_expr) && current.inner.len == 1 {
		if current.referenced_member_decl in c.cpp_static_member_decl_names {
			return none
		}
		segments << current
		current = unwrap_cpp_noop_casts(current.inner[0])
	}
	if segments.len == 0 {
		return none
	}
	root := current
	mut root_text := ''
	if is_cpp_call_node(root) {
		// A call returning a record by value is a temporary: a copy is faithful.
		if root.value_category != 'lvalue' && !segments.last().is_arrow {
			return none
		}
	} else if root.kindof(.array_subscript_expr) {
		root_text = c.cpp_call_result_subscript_text(&root)?
	} else if pointer_call := cpp_dereferenced_call(root) {
		root_text = c.render_expr_to_string(pointer_call)
	} else {
		return none
	}
	receiver_type := c.convert_type(node_effective_type_name(segments[0])).name
	if !c.is_v_object_type(receiver_type) || receiver_type.starts_with('[')
		|| c.is_v_abstract_interface_type(receiver_type) {
		return none
	}
	rendered := c.render_expr_to_string(receiver)
	rendered_root := c.render_expr_to_string(root)
	if rendered.contains('\n') || rendered_root.contains('\n') || root_text.contains('\n')
		|| !rendered.starts_with(rendered_root) {
		return none
	}
	names := rendered[rendered_root.len..].split('.')
	if names.len != segments.len + 1 || names[0] != ''
		|| names[1..].any(it == '' || !it.bytes().all(it.is_alnum() || it == `_`)) {
		return none
	}
	mut out := if root_text != '' { root_text } else { rendered_root }
	for i := segments.len - 1; i >= 0; i-- {
		name := names[segments.len - i]
		field_type := c.prefix_external_type(c.convert_type(node_effective_type_name(segments[i])).name)
		owner := if i == segments.len - 1 { root } else { segments[i + 1] }
		owner_type := c.convert_type(node_effective_type_name(owner)).name.trim_left('&')
		if c.is_v_object_type(field_type) && !field_type.starts_with('[')
			&& !c.is_v_abstract_interface_type(field_type) && c.is_v_object_type(owner_type)
			&& !owner_type.starts_with('[') && !c.is_v_abstract_interface_type(owner_type)
			&& is_valid_v_receiver_type_name(owner_type) {
			out += '.' + c.cpp_field_accessor(owner_type, name, field_type) + '()'
		} else {
			out += '.' + name
		}
	}
	return out
}

fn (mut c C2V) cpp_call_result_subscript_text(element &Node) ?string {
	if text := c.cpp_call_result_element_text(element) {
		return text
	}
	return c.cpp_call_result_pointer_element_text(element)
}

// cpp_call_result_pointer_element_text renders an element that a pointer
// reached from a call points at, such as `list.Ptr()[i]`, as its address
// computed by a helper: V passes the element itself as the address of a copy.
fn (mut c C2V) cpp_call_result_pointer_element_text(element &Node) ?string {
	subscript := unwrap_cpp_noop_casts(*element)
	if !subscript.kindof(.array_subscript_expr) || subscript.inner.len != 2 {
		return none
	}
	mut base := subscript.inner[0]
	for base.inner.len == 1 && (base.kindof(.paren_expr) || (base.kindof(.implicit_cast_expr)
		&& base.cast_kind in ['LValueToRValue', 'NoOp'])) {
		base = base.inner[0]
	}
	if !(is_cpp_call_node(base) || cpp_lvalue_is_rooted_at_call(base))
		|| !c.convert_type(node_effective_type_name(base)).name.starts_with('&') {
		return none
	}
	element_type := c.receiver_surface_type_name(*element)
	if !c.is_v_object_type(element_type) || element_type.starts_with('[')
		|| c.is_v_abstract_interface_type(element_type) {
		return none
	}
	rendered_base := c.render_expr_to_string(subscript.inner[0])
	rendered_index := c.render_expr_to_string(subscript.inner[1])
	if rendered_base == '' || rendered_index == '' || rendered_base.contains('\n')
		|| rendered_index.contains('\n') {
		return none
	}
	helper_key := 'c2v_offset:${os.dir(c.outv)}'
	if helper_key !in c.generated_declarations {
		c.generated_declarations[helper_key] = true
		c.local_type_declarations << 'fn c2v_offset[T](pointer &T, index int) &T {\n\treturn unsafe { pointer + index }\n}\n\n'
	}
	return 'c2v_offset(${rendered_base}, int(${rendered_index}))'
}

// cpp_call_result_element_text renders an element of an array field of a
// record reached from a call, such as `GetHolder()->items[i]`, with a
// generated element accessor: `get_holder().c2v_elem_items(i)`.
fn (mut c C2V) cpp_call_result_element_text(element &Node) ?string {
	mut indices := []Node{}
	mut current := unwrap_cpp_noop_casts(*element)
	for current.kindof(.array_subscript_expr) && current.inner.len == 2 {
		indices.prepend(current.inner[1])
		current = current.inner[0]
		for current.inner.len == 1 && (current.kindof(.paren_expr)
			|| (current.kindof(.implicit_cast_expr)
				&& current.cast_kind in ['ArrayToPointerDecay', 'NoOp'])) {
			current = current.inner[0]
		}
	}
	if indices.len == 0 || !current.kindof(.member_expr) || current.inner.len != 1
		|| current.referenced_member_decl in c.cpp_static_member_decl_names
		|| !node_effective_type_name(current).contains('[') {
		return none
	}
	field := current
	owner := unwrap_cpp_noop_casts(field.inner[0])
	mut owner_text := ''
	if is_cpp_call_node(owner) {
		// A call returning a record by value is a temporary: a copy is faithful.
		if owner.value_category != 'lvalue' && !field.is_arrow {
			return none
		}
		owner_text = c.render_expr_to_string(owner)
	} else if pointer_call := cpp_dereferenced_call(owner) {
		owner_text = c.render_expr_to_string(pointer_call)
	} else {
		owner_text = c.cpp_call_rooted_receiver_text(&owner)?
	}
	element_type := c.receiver_surface_type_name(*element)
	owner_type := c.receiver_surface_type_name(owner)
	if !c.is_v_object_type(element_type) || element_type.starts_with('[')
		|| c.is_v_abstract_interface_type(element_type) || !c.is_v_object_type(owner_type)
		|| owner_type.starts_with('[') || c.is_v_abstract_interface_type(owner_type)
		|| !is_valid_v_receiver_type_name(owner_type) {
		return none
	}
	name := c.render_expr_to_string(field).all_after_last('.')
	if name == '' || !name.bytes().all(it.is_alnum() || it == `_`) || owner_text.contains('\n') {
		return none
	}
	mut args := []string{}
	for index in indices {
		rendered := c.render_expr_to_string(index)
		if rendered == '' || rendered.contains('\n') {
			return none
		}
		args << 'int(${rendered})'
	}
	return owner_text + '.' + c.cpp_element_accessor(owner_type, name, indices.len, element_type) + '(' + args.join(', ') + ')'
}

// cpp_element_accessor names a generated method returning the address of an
// element of an array field (see cpp_call_result_element_text).
fn (mut c C2V) cpp_element_accessor(owner_type string, field string, dimensions int, element_type string) string {
	name := 'c2v_elem_${field}'
	key := 'cpp_element_accessor:${owner_type}.${field}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		params := []string{len: dimensions, init: 'i${index} int'}.join(', ')
		indexing := []string{len: dimensions, init: '[i${index}]'}.join('')
		c.local_type_declarations << 'fn (this &${owner_type}) ${name}(${params}) &${element_type} {\n\treturn unsafe { &this.${field}${indexing} }\n}\n\n'
	}
	return name
}

// gen_cpp_call_result_base_receiver emits the receiver of an inherited method
// (or operator) called on an object that a call returns, such as
// `GetEntity()->Show()`, through a generated accessor of the embedded base
// declaring the method: `get_entity().c2v_embed_id_entity().show()`. V
// promotes the method to the embedded base, but passes the address of a copy
// of just that base when the object is a call result.
fn (mut c C2V) gen_cpp_call_result_base_receiver(receiver &Node, method_decl_id string, receiver_type string) bool {
	mut object := unwrap_cpp_noop_casts(*receiver)
	if !object.kindof(.implicit_cast_expr)
		|| object.cast_kind !in ['DerivedToBase', 'UncheckedDerivedToBase'] {
		return false
	}
	for object.inner.len == 1 && (object.kindof(.paren_expr) || (object.kindof(.implicit_cast_expr)
		&& object.cast_kind in ['NoOp', 'DerivedToBase', 'UncheckedDerivedToBase'])) {
		object = object.inner[0]
	}
	// `(*GetEntity())[i]`: the call returns the address of the object.
	mut pointer_call := Node{}
	if object.kindof(.unary_operator) {
		pointer_call = cpp_dereferenced_call(object) or { return false }
	}
	is_call := is_cpp_call_node(object)
	if !is_call && !object.kindof(.member_expr) && !object.kindof(.array_subscript_expr)
		&& pointer_call.inner.len == 0 {
		return false
	}
	// A call returning a record by value is a temporary: a copy is faithful.
	if is_call && object.value_category != 'lvalue'
		&& !c.convert_type(node_effective_type_name(object)).name.starts_with('&') {
		return false
	}
	declaration := c.callback_seen_ids[method_decl_id] or { return false }
	owner_raw := extract_class_from_mangled(declaration.mangled_name)
	mut owner := if owner_raw == '' {
		''
	} else {
		normalize_cpp_operator_type_name(c.convert_type(owner_raw).name)
	}
	if owner == '' || owner in c.cpp_abstract_types {
		// Methods of abstract bases are translated for the records deriving
		// from them.
		owner = receiver_type
	}
	source := c.receiver_surface_type_name(object)
	if owner == '' || source == '' || source == owner || !c.is_v_object_type(source)
		|| source.starts_with('[') || c.is_v_abstract_interface_type(source)
		|| !is_valid_v_receiver_type_name(source) {
		return false
	}
	mut seen := map[string]bool{}
	path := c.cpp_base_embed_path(source, owner, mut seen)
	if path == '' || !path.bytes().all(it.is_alnum() || it == `_` || it == `.`) {
		return false
	}
	if pointer_call.inner.len > 0 {
		c.expr(pointer_call)
	} else if is_call {
		c.expr(object)
	} else if !c.gen_cpp_call_result_field_receiver(&object) {
		return false
	}
	c.gen('.' + c.cpp_base_accessor(source, path, owner) + '()')
	return true
}

// cpp_dereferenced_call returns the call in a receiver such as
// `(*GetEntity())`, which designates the object that the call returns the
// address of: V would pass the address of a copy of the dereferenced object.
fn cpp_dereferenced_call(node Node) ?Node {
	object := unwrap_cpp_noop_casts(node)
	if !object.kindof(.unary_operator) || object.opcode != '*' || object.inner.len != 1
		|| object.ast_type.qualified.trim_space().ends_with('*') {
		// (`(*pointers())->m()` receives the pointer that the call points at.)
		return none
	}
	call := unwrap_cpp_noop_casts(object.inner[0])
	if !is_cpp_call_node(call) {
		return none
	}
	return call
}

fn is_cpp_call_node(node Node) bool {
	return node.kindof(.call_expr) || node.kindof(.cxx_member_call_expr)
		|| node.kindof(.cxx_operator_call_expr)
}

// gen_cpp_operator_method_receiver emits the receiver of a call of the
// translated operator method `method_decl_id`.
fn (mut c C2V) gen_cpp_operator_method_receiver(receiver &Node, method_decl_id string) {
	if !c.gen_cpp_call_result_base_receiver(receiver, method_decl_id, c.receiver_surface_type_name(*receiver)) {
		c.gen_cpp_operator_receiver(receiver)
	}
}

// cpp_base_accessor names a generated method returning the address of the
// base record embedded in a record along `path` (see
// gen_cpp_call_result_base_receiver).
fn (mut c C2V) cpp_base_accessor(owner_type string, path string, base_type string) string {
	name := 'c2v_embed_' + path.split('.').map(it.camel_to_snake().trim_left('_')).join('__')
	key := 'cpp_base_accessor:${owner_type}.${path}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << 'fn (this &${owner_type}) ${name}() &${base_type} {\n\treturn unsafe { &this.${path} }\n}\n\n'
	}
	return name
}

// cpp_field_accessor names a generated method returning the address of a
// record field (see gen_cpp_call_result_field_receiver).
fn (mut c C2V) cpp_field_accessor(owner_type string, field string, field_type string) string {
	name := 'c2v_field_${field}'
	key := 'cpp_field_accessor:${owner_type}.${field}:${os.dir(c.outv)}'
	if key !in c.generated_declarations {
		c.generated_declarations[key] = true
		c.local_type_declarations << 'fn (this &${owner_type}) ${name}() &${field_type} {\n\treturn unsafe { &this.${field} }\n}\n\n'
	}
	return name
}

fn unwrap_cpp_noop_casts(node Node) Node {
	mut current := node
	for current.inner.len == 1 && ((current.kindof(.implicit_cast_expr)
		&& current.cast_kind == 'NoOp') || current.kindof(.paren_expr)) {
		current = current.inner[0]
	}
	return current
}

fn (mut c C2V) gen_cpp_operator_receiver(node &Node) {
	old_receiver_cast_id := c.cpp_receiver_cast_id
	c.cpp_receiver_cast_id = cpp_receiver_cast_id(node)
	defer {
		c.cpp_receiver_cast_id = old_receiver_cast_id
	}
	if is_cpp_object_this_expr(node) {
		c.gen('this')
		return
	}
	if c.gen_cpp_call_result_field_receiver(node) {
		return
	}
	if pointer_call := cpp_dereferenced_call(*node) {
		c.expr(pointer_call)
		return
	}
	base := unwrap_cpp_operator_operand(node)
	if base.kindof(.unary_operator) && base.opcode == '*' && base.inner.len == 1 {
		// `*static_cast<Base *>(derived)` receives through the base record
		// embedded in `derived`, which V can pass as a `mut` receiver.
		cast_id := cpp_receiver_cast_id(&base.inner[0])
		if cast_id != '' {
			mut cast := unsafe { &base.inner[0] }
			for cast.id != cast_id && cast.inner.len == 1 {
				cast = unsafe { &cast.inner[0] }
			}
			if c.cpp_cast_is_pointer_upcast(cast) {
				c.cpp_receiver_cast_id = cast_id
				c.expr(cast)
				return
			}
		}
	}
	if base.kindof(.decl_ref_expr) || base.kindof(.cxx_this_expr) {
		c.expr(node)
		return
	}
	// Member accesses and calls are V postfix expressions and need no grouping.
	// Avoiding a leading `(` matters: V continues `x.field` on the previous
	// line into a method call when the next statement starts with `(`.
	mut outer := unsafe { node }
	for outer.inner.len == 1 && (outer.kindof(.materialize_temporary_expr)
		|| outer.kindof(.expr_with_cleanups) || outer.kindof(.cxx_bind_temporary_expr)
		|| (outer.kindof(.implicit_cast_expr) && outer.cast_kind in ['LValueToRValue', 'NoOp'])) {
		outer = unsafe { &outer.inner[0] }
	}
	// An implicit conversion to a base class renders as a member access too.
	if outer.kindof(.member_expr) || outer.kindof(.call_expr) || outer.kindof(.cxx_member_call_expr)
		|| (outer.kindof(.implicit_cast_expr)
			&& outer.cast_kind in ['DerivedToBase', 'UncheckedDerivedToBase']) {
		c.expr(node)
		return
	}
	c.gen('(')
	c.expr(node)
	c.gen(')')
}

// cpp_receiver_cast_id returns the id of the explicit cast that is itself a
// method receiver (seen through implicit casts and parentheses), if any.
fn cpp_receiver_cast_id(node &Node) string {
	mut current := unsafe { node }
	for current.inner.len == 1 && (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)) {
		current = unsafe { &current.inner[0] }
	}
	if current.kindof(.cxx_static_cast_expr) || current.kindof(.c_style_cast_expr) {
		return current.id
	}
	return ''
}

fn is_cpp_dereferenced_this_expr(node &Node) bool {
	mut current := unwrap_cpp_operator_operand(node)
	if !current.kindof(.unary_operator) || current.opcode != '*' || current.inner.len == 0 {
		return false
	}
	current = unwrap_cpp_operator_operand(unsafe { &current.inner[0] })
	return current.kindof(.cxx_this_expr)
}

// is_cpp_object_this_expr reports whether an expression is `*this` itself, not
// `*this` converted to a base class (`*static_cast<Base *>(this)`), which
// designates the embedded base object.
fn is_cpp_object_this_expr(node &Node) bool {
	if !is_cpp_dereferenced_this_expr(node) {
		return false
	}
	mut current := unsafe { node }
	for current.inner.len == 1 && !(current.kindof(.unary_operator) && current.opcode == '*') {
		if !is_cpp_type_preserving_wrapper(current) {
			return false
		}
		current = unsafe { &current.inner[0] }
	}
	current = unsafe { &current.inner[0] }
	for current.inner.len == 1 && !current.kindof(.cxx_this_expr) {
		if !is_cpp_type_preserving_wrapper(current) {
			return false
		}
		current = unsafe { &current.inner[0] }
	}
	return current.kindof(.cxx_this_expr)
}

fn is_cpp_type_preserving_wrapper(node &Node) bool {
	if node.kindof(.paren_expr) || node.kindof(.materialize_temporary_expr)
		|| node.kindof(.expr_with_cleanups) || node.kindof(.cxx_bind_temporary_expr) {
		return true
	}
	return (node.kindof(.implicit_cast_expr) || node.kindof(.cxx_static_cast_expr)
		|| node.kindof(.cxx_const_cast_expr) || node.kindof(.c_style_cast_expr))
		&& node.cast_kind in ['NoOp', 'LValueToRValue']
}

// Check if a node is a chained CXXOperatorCallExpr with operator=
// Unwraps ImplicitCastExpr wrappers to find the inner CXXOperatorCallExpr
fn is_cxx_assign_op(node &Node) bool {
	mut n := unsafe { node }
	// Unwrap ImplicitCastExpr
	for {
		if !(n.kindof(.implicit_cast_expr) && n.inner.len > 0) {
			break
		}
		n = unsafe { &n.inner[0] }
	}
	if !n.kindof(.cxx_operator_call_expr) {
		return false
	}
	if n.inner.len < 1 {
		return false
	}
	first := n.inner[0]
	if !first.kindof(.implicit_cast_expr) || first.inner.len == 0 {
		return false
	}
	ref := first.inner[0]
	if !ref.kindof(.decl_ref_expr) {
		return false
	}
	ref_name := if ref.name != '' { ref.name } else { ref.ref_declaration.name }
	return ref_name == 'operator='
}

fn cpp_assignment_expr_parts(node Node) (Node, Node, bool) {
	mut current := node
	for current.inner.len == 1
		&& (current.kindof(.implicit_cast_expr) || current.kindof(.paren_expr)
			|| current.kindof(.materialize_temporary_expr) || current.kindof(.expr_with_cleanups)
			|| current.kindof(.cxx_bind_temporary_expr) || current.kindof(.cxx_construct_expr)) {
		current = current.inner[0]
	}
	if !current.kindof(.cxx_operator_call_expr) || current.inner.len < 3
		|| !is_cxx_assign_op(&current) {
		return Node{}, Node{}, false
	}
	return current.inner[1], current.inner[2], true
}

// CXXOperatorCallExpr - C++ operator overload calls
// Handles: operator=, operator<<, operator==, operator+, etc.
fn (mut c C2V) operator_call(_node &Node) {
	mut node := unsafe { _node }
	mut cast_expr := node.try_get_next_child() or {
		vprintln(err.str())
		bad_node
	}
	if !cast_expr.kindof(.implicit_cast_expr) {
		// Non-ImplicitCastExpr: may be a direct DeclRefExpr to operator
		c.expr(cast_expr)
		return
	}
	decl_ref_expr := cast_expr.try_get_next_child_of_kind(.decl_ref_expr) or {
		vprintln(err.str())
		bad_node
	}

	typ := decl_ref_expr.ast_type.qualified
	op_name := if decl_ref_expr.name != '' {
		decl_ref_expr.name
	} else {
		decl_ref_expr.ref_declaration.name
	}
	mut add_par := false
	if op_name == 'operator<<' && typ.contains('basic_ostream') {
		c.gen('println(')
		add_par = true
		// Process the expression being printed
		expr := node.try_get_next_child() or {
			vprintln(err.str())
			bad_node
		}
		c.expr(expr)
	} else if op_name in ['operator=', 'operator+=', 'operator-=', 'operator*=', 'operator/=',
		'operator==', 'operator!=', 'operator<', 'operator>', 'operator<=', 'operator>=', 'operator+',
		'operator-', 'operator*', 'operator/', 'operator%', 'operator[]', 'operator&', 'operator|',
		'operator^', 'operator&&', 'operator||', 'operator!', 'operator~'] {
		// Determine if unary or binary based on remaining children count
		// After consuming the operator function (first child), remaining = inner.len - 1
		remaining := node.inner.len - node.current_child_id
		v_op := op_name.replace('operator', '').trim_space()
		method_base_name := cpp_operator_to_v_method(op_name)
		v_method := c.cpp_method_decl_names[decl_ref_expr.ref_declaration.id] or {
			method_base_name
		}
		if remaining == 1 && v_op in ['-', '+', '!', '~', '*', '&'] {
			// Unary operator: op expr
			operand := node.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
			operand_is_primitive := is_cpp_operator_primitive_type(c.operator_node_v_type(operand))
				|| is_cpp_operator_literal_operand(operand)
			if c.try_gen_cpp_selected_free_unary_operator(decl_ref_expr, operand) {
			} else if v_method != '' && !operand_is_primitive {
				c.gen_cpp_operator_method_receiver(operand, decl_ref_expr.ref_declaration.id)
				c.gen('.${v_method}()')
			} else {
				c.gen(v_op)
				c.expr(operand)
			}
		} else if v_op == '[]' {
			// Subscript operator: prefer `lhs.op_index(rhs)` for translated C++ types.
			lhs := node.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
			rhs := node.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
			read_primitive_reference := c.cpp_operator_call_returns_primitive_reference(*node)
				&& !c.inside_cpp_reference_lvalue
			// Only this call's result is kept as a reference; operands are read.
			old_reference_lvalue := c.inside_cpp_reference_lvalue
			c.inside_cpp_reference_lvalue = false
			defer {
				c.inside_cpp_reference_lvalue = old_reference_lvalue
			}
			old_inside_unsafe := c.inside_unsafe
			if read_primitive_reference {
				if !old_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('*(')
			}
			if v_method != '' {
				c.gen_cpp_operator_method_receiver(lhs, decl_ref_expr.ref_declaration.id)
				c.gen('.${v_method}(')
				c.expr(rhs)
				c.gen(')')
			} else {
				c.expr(lhs)
				c.gen('[')
				c.expr(rhs)
				c.gen(']')
			}
			if read_primitive_reference {
				c.gen(')')
				if !old_inside_unsafe {
					c.inside_unsafe = false
					c.gen(' }')
				}
			}
		} else {
			// Binary operator: LHS op RHS
			lhs := node.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
			rhs := node.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
			// Handle chained operator= (a = b = c): split into separate assignments
			if v_op == '=' && is_cxx_assign_op(rhs) {
				// Unwrap ImplicitCastExpr to find the inner CXXOperatorCallExpr
				mut inner_assign := unsafe { rhs }
				for {
					if !(inner_assign.kindof(.implicit_cast_expr) && inner_assign.inner.len > 0) {
						break
					}
					inner_assign = unsafe { &inner_assign.inner[0] }
				}
				// Output inner assignment first, then outer
				c.expr(inner_assign)
				c.genln('')
				c.expr(lhs)
				c.gen(' = ')
				// The inner assignment's LHS is child[1] (after operator ref)
				if inner_assign.inner.len > 1 {
					c.expr(inner_assign.inner[1])
				}
			} else if v_op == '=' && v_method != ''
				&& c.is_translated_cpp_assignment_operator(decl_ref_expr.ref_declaration.id)
				&& c.should_use_operator_method_for_binary(method_base_name, lhs, rhs) {
				declaration_params := function_type_params(typ)
				param_type := if declaration_params.len > 0 {
					declaration_params.last()
				} else {
					''
				}
				c.gen_cpp_operator_method_receiver(lhs, decl_ref_expr.ref_declaration.id)
				c.gen('.${v_method}(')
				c.gen_call_arg(rhs, param_type, false)
				c.gen(')')
			} else if v_op == '=' {
				mut lhs_assign := lhs
				mut rhs_assign := rhs
				c.gen_simple_assign(mut lhs_assign, mut rhs_assign)
			} else if c.try_gen_cpp_selected_free_binary_operator(decl_ref_expr, lhs, rhs) {
			} else if method_base_name != ''
				&& c.should_use_operator_method_for_binary(method_base_name, lhs, rhs) {
				resolved_method := c.cpp_method_overload_for_argument(c.operator_node_v_type(lhs), method_base_name, c.operator_node_v_type(rhs))
				mut call_method := if decl_ref_expr.ref_declaration.id in c.cpp_method_decl_names {
					// Clang has already selected the exact overload for this call. Prefer
					// that declaration over type-only lookup, which cannot distinguish
					// `char` from `char *` after C++ references become V pointers.
					v_method
				} else if resolved_method != method_base_name {
					resolved_method
				} else {
					v_method
				}
				call_method = c.cpp_abstract_default_decl_call_name(decl_ref_expr.ref_declaration.id, op_name, lhs, c.operator_node_v_type(lhs), call_method)
				mut param_type := c.exact_cpp_method_parameter_type(c.operator_node_v_type(lhs), method_base_name, c.operator_node_v_type(rhs))
				declaration_params := function_type_params(typ)
				if decl_ref_expr.ref_declaration.id in c.cpp_method_decl_names
					&& declaration_params.len > 0 {
					// The selected declaration is authoritative. Type-only overload lookup
					// cannot distinguish `char` from `char *` after V type conversion.
					param_type = declaration_params.last()
				} else if param_type == '' {
					// A derived operand selects an overload declared for its base, so an
					// exact argument-type lookup cannot find the parameter. The selected
					// operator declaration still carries the authoritative parameter type.
					if declaration_params.len > 0 {
						param_type = declaration_params.last()
					}
				}
				c.gen_cpp_operator_method_receiver(lhs, decl_ref_expr.ref_declaration.id)
				c.gen('.${call_method}(')
				if c.is_dir && c.project_generate_stubs
					&& decl_ref_expr.ref_declaration.id !in c.cpp_method_decl_names {
					c.gen_call_arg(rhs, '', true)
				} else {
					c.gen_call_arg(rhs, param_type, false)
				}
				c.gen(')')
			} else {
				c.expr(lhs)
				c.gen(' ${v_op} ')
				c.expr(rhs)
			}
		}
	} else {
		// Unknown operator - process children as expressions
		for node.inner.len > node.current_child_id {
			expr := node.try_get_next_child() or { break }
			c.expr(expr)
		}
	}
	if add_par {
		c.gen(')')
	}
}

// CXXForRangeStmt - range-based for loop
// for (int x : arr) { ... } => for x in arr { ... }
// AST children:
// [0] null
// [1] DeclStmt __range1 (contains ref to container)
// [2-5] internal iterator machinery
// [6] DeclStmt with loop variable
// [last] CompoundStmt body
fn (mut c C2V) for_range(node &Node) {
	c.continue_labels << ''
	defer {
		c.continue_labels.delete_last()
	}
	mut loop_var := 'val'
	mut container := 'vals'

	// Extract loop variable name from child 6
	if node.inner.len > 6 {
		decl_stmt := node.inner[6]
		if decl_stmt.inner.len > 0 {
			loop_var = decl_stmt.inner[0].name.camel_to_snake()
			if loop_var == '' {
				loop_var = 'val'
			}
		}
	}
	// Extract container name from child 1 (__range1 DeclStmt -> VarDecl -> DeclRefExpr)
	if node.inner.len > 1 {
		range_decl := node.inner[1]
		if range_decl.inner.len > 0 && range_decl.inner[0].inner.len > 0 {
			ref := range_decl.inner[0].inner[0]
			if ref.kindof(.decl_ref_expr) {
				container = ref.ref_declaration.name.camel_to_snake()
				if container == '' {
					container = 'vals'
				}
			}
		}
	}
	mut stmt := node.inner.last()
	c.genln('for ${loop_var} in ${container} {')
	c.st_block_no_start(mut stmt)
}
