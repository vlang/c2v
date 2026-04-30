module main

import os

fn (mut c C2V) cpp_top_level(_node &Node) bool {
	vprintln('C++ top level')
	mut node := unsafe { _node }
	if node.kindof(.namespace_decl) {
		for child in node.inner {
			c.top_level(child)
		}
	} else if node.kindof(.cxx_constructor_decl) {
		// Top-level constructor declarations (without body) are frequently duplicated across TUs.
		if c.cur_class == '' && !node.has_child_of_kind(.compound_stmt) {
			return true
		}
		if c.cur_class == '' && !c.node_body_in_main_file(node) {
			return true
		}
		c.constructor_decl(node)
	} else if node.kindof(.cxx_destructor_decl) {
		// Top-level destructor declarations (without body) are frequently duplicated across TUs.
		if c.cur_class == '' && !node.has_child_of_kind(.compound_stmt) {
			return true
		}
		if c.cur_class == '' && !c.node_body_in_main_file(node) {
			return true
		}
		c.destructor_decl(node)
	} else if node.kindof(.original) {
	} else if node.kindof(.using_decl) {
	} else if node.kindof(.using_shadow_decl) {
	} else if node.kindof(.class_template_decl) {
		// Skip class templates from headers
		if node.location.file_index != 0 {
			return true
		}
		c.class_template_decl(node)
	} else if node.kindof(.class_template_specialization_decl) {
	} else if node.kindof(.cxx_record_decl) {
		// Keep C++ record declarations from headers, we need their field layouts.
		c.cxx_record_decl(node)
	} else if node.kindof(.linkage_spec_decl) {
	} else if node.kindof(.using_directive_decl) {
	} else if node.kindof(.class_template_partial_specialization_decl) {
	} else if node.kindof(.function_template_decl) {
		// Skip function templates from headers
		if node.location.file_index != 0 {
			return true
		}
		c.fn_template_decl(mut node)
	} else if node.kindof(.cxx_method_decl) {
		// Top-level method declarations without body should not emit stubs.
		if c.cur_class == '' && !node.has_child_of_kind(.compound_stmt) {
			return true
		}
		if c.cur_class == '' && !c.node_body_in_main_file(node) {
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
			typ := c.prefix_external_type(convert_type(node.ast_type.qualified).name)
			c.genln('type ${name.capitalize()} = ${typ}')
		}
	} else if node.kindof(.type_alias_template_decl) {
		// template<...> using X = Y; - skip (templates)
	} else if node.kindof(.var_template_decl) {
		// template variable - skip
	} else if node.kindof(.indirect_field_decl) {
		// indirect field (anonymous struct member access) - skip
	} else if node.kindof(.cxx_conversion_decl) {
		// conversion operator (operator int(), etc) - skip
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
		// Check for pointer-to-member call: (this->*fn_ptr)()
		first_child := node.try_get_next_child() or {
			vprintln(err.str())
			bad_node
		}
		mut is_ptm_call := false
		if first_child.kindof(.paren_expr) && first_child.inner.len > 0
			&& first_child.inner[0].kindof(.binary_operator)
			&& (first_child.inner[0].opcode == '->*' || first_child.inner[0].opcode == '.*') {
			is_ptm_call = true
			// Pointer-to-member call: (this->*cls->Spawn)()
			// Generate: cls.spawn() - call the function pointer member directly
			ptm_op := first_child.inner[0]
			if ptm_op.inner.len > 1 {
				c.expr(ptm_op.inner[1]) // the function pointer member expression
			}
		}
		mut member_expr := if is_ptm_call {
			bad_node
		} else if first_child.kindof(.member_expr) {
			first_child
		} else {
			bad_node
		}

		method_name := member_expr.name
		mut receiver_expr := bad_node
		if !is_ptm_call {
			receiver_expr = member_expr.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
		}
		mut add_par := false
		mut close_with_bracket := false
		if is_ptm_call {
			// Pointer-to-member call: function expression already generated
			add_par = true
			c.gen('(')
		} else if method_name.contains('operator') {
			// Member operator calls: obj.operator=(x), obj.operator[](i), ...
			mut raw_method := method_name.replace('->', '.').trim_space()
			if raw_method.starts_with('.') {
				raw_method = raw_method[1..]
			}
			v_method := cpp_operator_to_v_method(raw_method)
			op_token := raw_method.replace('operator', '').trim_space()
			remaining_args := node.inner.len - node.current_child_id
			receiver_is_primitive :=
				is_cpp_operator_primitive_type(c.operator_node_v_type(receiver_expr))
				|| is_cpp_operator_literal_operand(receiver_expr)
			if raw_method == 'operator()' {
				c.gen_cpp_operator_receiver(receiver_expr)
				add_par = true
				c.gen('(')
			} else if op_token == '[]' {
				c.gen_cpp_operator_receiver(receiver_expr)
				c.gen('[')
				close_with_bracket = true
			} else if v_method != '' && !v_method.starts_with('op_conv_') && !receiver_is_primitive {
				c.gen_cpp_operator_receiver(receiver_expr)
				add_par = true
				c.gen('.${v_method}(')
			} else if remaining_args == 1
				&& op_token in ['=', '+=', '-=', '*=', '/=', '%=', '==', '!=', '<', '>', '<=', '>=', '+', '-', '*', '/', '%', '&', '|', '^', '&&', '||', '<<', '>>', '<<=', '>>=', ','] {
				c.expr(receiver_expr)
				c.gen(' ${op_token} ')
			} else if remaining_args == 0 && op_token in ['-', '+', '!', '~', '*', '&'] {
				c.gen(op_token)
				c.expr(receiver_expr)
			} else {
				if v_method != '' && !v_method.starts_with('op_conv_') {
					c.gen_cpp_operator_receiver(receiver_expr)
					add_par = true
					c.gen('.${v_method}(')
				} else {
					c.expr(receiver_expr)
				}
				// Conversion operators (operator int, operator bool, ...) use the object as-is.
			}
		} else {
			c.expr(receiver_expr)
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
					mut method_v := method.trim_left('.').camel_to_snake().trim_left('_')
					if method_v == 'free' {
						method_v = 'free_'
					}
					c.gen('.${method_v}(')
				}
			}
		}
		// Process remaining children as function arguments.
		// The first child was member_expr (the object+method), rest are arguments.
		mut arg_i := 0
		for {
			mut arg := node.try_get_next_child() or { break }
			// Skip default argument expressions - they use C++ default values
			// which don't translate to V function calls
			if arg.kindof(.cxx_default_arg_expr) {
				continue
			}
			// MaterializeTemporaryExpr wraps the actual argument expression
			if arg.kindof(.materialize_temporary_expr) {
				arg = arg.try_get_next_child() or { break }
			}
			if arg_i > 0 {
				c.gen(', ')
			}
			c.expr(arg)
			arg_i++
		}
		if close_with_bracket {
			c.gen(']')
		} else if add_par {
			c.gen(')')
		}
	}
	// operator call (std::cout << etc)
	else if node.kindof(.cxx_operator_call_expr) {
		c.operator_call(node)
	}
	// ExprWithCleanups - wraps expressions that need temporary cleanup
	else if node.kindof(.expr_with_cleanups) {
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
		if node.name != '' {
			c.gen('.${node.name}')
		}
	} else if node.kindof(.cxx_try_stmt) {
	} else if node.kindof(.cxx_throw_expr) {
	} else if node.kindof(.cxx_dynamic_cast_expr) {
		c.cxx_cast_expr(node)
	} else if node.kindof(.cxx_reinterpret_cast_expr) {
		c.cxx_cast_expr(node)
	} else if node.kindof(.cxx_const_cast_expr) {
		c.cxx_const_cast_handler(node)
	} else if node.kindof(.cxx_unresolved_construct_expr) {
	} else if node.kindof(.cxx_dependent_scope_member_expr) {
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
	}
	// static_cast<int>(a)
	else if node.kindof(.cxx_static_cast_expr) {
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
		// Default arguments are resolved by clang, skip
	} else if node.kindof(.cxx_default_init_expr) {
		// Default member initializers are resolved by clang, skip
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
		// Template-dependent member access
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
		if node.name != '' {
			c.gen('.${node.name}')
		}
	} else if node.kindof(.array_init_loop_expr) {
		// Array copy initialization loop - skip (generated implicitly by compiler)
	} else if node.kindof(.array_init_index_expr) {
		// Array init index - skip
	} else if node.kindof(.type_trait_expr) {
		// C++ type trait (e.g. std::is_same) - output the boolean result
		c.gen(node.value.to_str())
	} else if node.kindof(.subst_non_type_template_parm_expr) {
		// Substituted non-type template parameter - process the inner expression
		if node.inner.len > 0 {
			c.expr(node.inner[0])
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
		// Opaque value (used in binary conditional etc) - process inner
		if node.inner.len > 0 {
			c.expr(node.inner[0])
		}
	} else if node.kindof(.cxx_unresolved_construct_expr) {
		// Unresolved construction expression
		typ := convert_type(node.ast_type.qualified)
		if node.inner.len > 0 {
			c.gen('${typ.name}(')
			for i, child in node.inner {
				if i > 0 {
					c.gen(', ')
				}
				c.expr(child)
			}
			c.gen(')')
		} else {
			c.gen('${typ.name}{}')
		}
	} else {
		return false
	}
	return true
}

// Unified handler for C++ cast expressions:
// static_cast, dynamic_cast, reinterpret_cast, const_cast, functional cast
fn (mut c C2V) cxx_cast_expr(_node &Node) {
	mut node := unsafe { _node }
	mut expr := node.try_get_next_child() or {
		vprintln(err.str())
		bad_node
	}
	// Skip through implicit casts to avoid double casting
	// (clang wraps the actual expression in ImplicitCastExpr for type conversion,
	// but we're already doing an explicit cast)
	for {
		if !(expr.kindof(.implicit_cast_expr) && expr.inner.len > 0) {
			break
		}
		expr = expr.inner[0]
	}
	// Downcasts in recovered C++ ASTs are often only used for method dispatch
	// (`static_cast<idActor *>(focusEnt)->GetEyePosition()`).
	// Emitting value casts here (`IdActor(focus_ent)`) is invalid in V.
	// Preserve pointer semantics with an explicit unsafe pointer cast.
	if node.kindof(.cxx_static_cast_expr) && node.cast_kind == 'BaseToDerived'
		&& node.ast_type.qualified.contains('*') {
		mut ptr_type := convert_type(node.ast_type.qualified).name.trim_space()
		if ptr_type == '' {
			ptr_type = 'voidptr'
		}
		if !ptr_type.starts_with('&') && ptr_type != 'voidptr' {
			ptr_type = '&' + ptr_type
		}
		c.gen('(unsafe { ${ptr_type}(')
		c.expr(expr)
		c.gen(') })')
		return
	}
	typ := convert_type(node.ast_type.qualified)
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
fn (mut c C2V) cxx_construct_expr(node &Node) {
	typ := convert_type(node.ast_type.qualified)
	if node.inner.len == 0 {
		// Default construction: Type{}
		c.gen('${typ.name}{}')
	} else if node.inner.len == 1 {
		child := node.inner[0]
		base_type := normalize_cpp_operator_type_name(typ.name)
		child_raw_type := convert_type(child.ast_type.qualified).name.trim_space()
		child_base_type := normalize_cpp_operator_type_name(child_raw_type)
		// Copy construction of translated C++ value types should not become
		// single-field struct literals (`Type{expr}`), which are invalid in V.
		if base_type != '' && child_base_type == base_type {
			if child_raw_type.starts_with('&') {
				c.gen('unsafe { *')
				c.expr(child)
				c.gen(' }')
			} else {
				c.expr(child)
			}
			return
		}
		c.gen('${typ.name}{')
		// Default argument expressions use the default value from the declaration.
		// Generate 0 as a placeholder since V struct literals need all fields.
		if child.kindof(.cxx_default_arg_expr) {
			c.gen('0')
		} else {
			c.expr(child)
		}
		c.gen('}')
	} else {
		c.gen('${typ.name}{')
		for i, child in node.inner {
			if i > 0 {
				c.gen(', ')
			}
			// Default argument expressions use the default value from the declaration.
			// Generate 0 as a placeholder since V struct literals need all fields.
			if child.kindof(.cxx_default_arg_expr) {
				c.gen('0')
			} else {
				c.expr(child)
			}
		}
		c.gen('}')
	}
}

// CXXNewExpr - new operator
// new Type() => &Type{}
// new Type[n] => allocate array
fn (mut c C2V) cxx_new_expr(node &Node) {
	typ := convert_type(node.ast_type.qualified)
	// new returns a pointer, so type is e.g. "&Point" or "&int"
	// We need the base type name without the leading &
	mut base_type := typ.name
	if base_type.starts_with('&') {
		base_type = base_type[1..]
	}
	// Check if this is an array new (has a non-CXXConstructExpr child for size)
	if node.inner.len > 0 && !node.inner[0].kindof(.cxx_construct_expr) {
		// Array new: new int[n] => unsafe { &int(C.malloc(size * int(sizeof(base_type)))) }
		c.gen('unsafe { &${base_type}(C.malloc(')
		c.expr(node.inner[0])
		c.gen(' * int(sizeof(${base_type})))) }')
	} else {
		// Object new: new Type() => &Type{}
		c.gen('&${base_type}{}')
	}
}

// CXXDeleteExpr - delete operator
// delete ptr => unsafe { free(ptr) }
fn (mut c C2V) cxx_delete_expr(_node &Node) {
	mut node := unsafe { _node }
	c.gen('unsafe { free(')
	expr := node.try_get_next_child() or {
		vprintln(err.str())
		bad_node
	}
	c.expr(expr)
	c.gen(') }')
}

// CXXScalarValueInitExpr - value initialization of scalar types
// int() => 0, float() => 0.0, bool() => false
fn (mut c C2V) cxx_scalar_value_init_expr(node &Node) {
	typ := convert_type(node.ast_type.qualified)
	zero_val := match typ.name {
		'i8', 'i16', 'int', 'i64', 'u8', 'u16', 'u32', 'u64', 'isize', 'usize' {
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
		c.fn_decl(mut fn_node, '') // types)
	}
}

fn (mut c C2V) class_template_decl(node &Node) {
	name := node.name
	c.genln('CLASS ${name}')
}

// CXXRecordDecl - C++ class/struct declaration
// Processes fields as struct and handles inline method/constructor/destructor declarations
fn (mut c C2V) cxx_record_decl(node &Node) {
	mut name := node.name
	if name == '' && c.tree.inner.len > c.node_i + 1 {
		next_node := c.tree.inner[c.node_i + 1]
		if next_node.kind == .typedef_decl && next_node.name != '' {
			name = next_node.name
		}
	}
	if name == '' {
		return
	}
	// Skip forward declarations (`class Foo;`). Emitting an empty struct here
	// blocks later full definitions (with fields) due declaration deduping.
	if node.inner.len == 0 {
		return
	}
	struct_v_name := c.add_struct_name(mut c.types, name)
	// Skip malformed template/specialized names until template lowering is handled.
	if struct_v_name.contains('<') || struct_v_name.contains('>') || struct_v_name.contains(' ')
		|| struct_v_name.contains('(') || struct_v_name.contains(')') || struct_v_name.contains(',') {
		return
	}
	old_class := c.cur_class
	c.cur_class = name
	defer {
		c.cur_class = old_class
	}
	mut base_embeds := []string{}
	mut seen_base_embeds := map[string]bool{}
	for base in node.bases {
		mut base_name := c.prefix_external_type(convert_type(base.ast_type.qualified).name).trim_space()
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
		base_embeds << base_name
	}
	// Generate struct with fields
	mut has_fields := base_embeds.len > 0
	for child in node.inner {
		if child.kindof(.field_decl) {
			has_fields = true
			break
		}
	}
	decl_key := 'cpp_struct:${struct_v_name}'
	if decl_key !in c.generated_declarations {
		c.generated_declarations[decl_key] = true
		c.genln('struct ${struct_v_name} {')
		for base_name in base_embeds {
			// Preserve single-inheritance surface via V embedding, so derived
			// instances can access base fields/methods (`this.base_field`, etc.).
			c.genln('\t${base_name}')
		}
		if has_fields {
			for child in node.inner {
				if child.kindof(.field_decl) {
					field_name := if child.name != '' {
						child.name.camel_to_snake()
					} else {
						'_'
					}
					field_typ := c.prefix_external_type(convert_type(child.ast_type.qualified).name)
					c.genln('\t${field_name} ${field_typ}')
				}
			}
		}
		c.genln('}')
		c.genln('')
	}
	// Skip builtin/toolchain headers, but keep project header inline members.
	// These inline bodies are needed for cross-directory semantic compilation.
	if c.is_cpp && node.location.file_index != 0 {
		record_path := c.node_source_path(node)
		if record_path != '' && line_is_builtin_header(record_path) {
			return
		}
	}
	// Process constructors, destructors, and methods defined inline
	for child in node.inner {
		if child.kindof(.cxx_constructor_decl) {
			// Skip implicit constructors (copy/move constructors generated by compiler)
			if child.previous_declaration != ''
				|| child.ast_type.qualified.contains('const ${name} &')
				|| child.ast_type.qualified.contains('${name} &&') {
				continue
			}
			// Skip constructors without a body
			if !child.has_child_of_kind(.compound_stmt) {
				continue
			}
			c.constructor_decl(child)
		} else if child.kindof(.cxx_destructor_decl) {
			if !child.has_child_of_kind(.compound_stmt) {
				continue
			}
			c.destructor_decl(child)
		} else if child.kindof(.cxx_method_decl) {
			c.cxx_method_decl(child)
		}
	}
}

// CBattleAnimation::CBattleAnimation()
fn (mut c C2V) constructor_decl(_node &Node) {
	c.declared_local_vars.clear()
	c.for_init_vars.clear()
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
	if c.should_skip_duplicate_cpp_member(node, receiver_type, 'ctor') {
		return
	}
	has_body := node.has_child_of_kind(.compound_stmt)
	if !has_body && !c.should_emit_skeleton_body() {
		return
	}
	params := c.fn_params(mut node)
	str_args := params.join(', ')
	// Use 'init' for default constructors, 'init{N}' for parameterized constructors
	// to avoid V's duplicate method error (V doesn't support overloading).
	mut init_name := if params.len == 0 { 'init' } else { 'init${params.len}' }
	if c.class_has_method_base(receiver_type, init_name) {
		init_name = if params.len == 0 { 'ctor' } else { 'ctor${params.len}' }
	}
	init_name = c.reserve_method_name(receiver_type, init_name)
	c.genln('fn (mut this ${receiver_type}) ${init_name}(${str_args}) {')
	if c.should_emit_skeleton_body() {
		c.genln('}')
		c.genln('')
		return
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

	c.st_block_no_start(mut stmts)
	c.genln('')
}

// CBattleAnimation::~CBattleAnimation()
fn (mut c C2V) destructor_decl(_node &Node) {
	c.declared_local_vars.clear()
	c.for_init_vars.clear()
	mut node := unsafe { _node }
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
	if !has_body && !c.should_emit_skeleton_body() {
		return
	}
	mut dtor_name := 'free'
	if c.class_has_method_base(receiver_type, dtor_name) {
		dtor_name = 'dtor'
	}
	dtor_name = c.reserve_method_name(receiver_type, dtor_name)
	c.genln('fn (mut this ${receiver_type}) ${dtor_name}() {')
	if c.should_emit_skeleton_body() {
		c.genln('}')
		c.genln('')
		return
	}
	mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
		// Destructor with no body
		c.genln('}')
		return
	}
	c.st_block_no_start(mut stmts)
	c.genln('')
}

// Extract class name from C++ mangled name (Itanium ABI)
// e.g. "_ZN11idMoveState4SaveE..." -> "idMoveState"
// e.g. "_ZNK4idAI4SaveE..." -> "idAI"
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
	// Read the first component: <len><name>
	mut len_str := ''
	for pos < mangled.len && mangled[pos] >= `0` && mangled[pos] <= `9` {
		len_str += mangled[pos..pos + 1]
		pos++
	}
	if len_str == '' {
		return ''
	}
	name_len := len_str.int()
	if pos + name_len > mangled.len {
		return ''
	}
	return mangled[pos..pos + name_len]
}

fn method_base_name_from_cpp_name(cpp_name string) string {
	if cpp_name.starts_with('operator') {
		return cpp_operator_to_v_method(cpp_name)
	}
	mut name := cpp_name.camel_to_snake()
	// `free` is a reserved special method in V and must have zero args.
	// Rename regular C++ methods named Free(...) to avoid parser errors.
	if name == 'free' {
		name = 'free_'
	}
	return name
}

fn cpp_member_symbol_key(node &Node, class_name string, member_hint string) string {
	if node.mangled_name != '' {
		return node.mangled_name
	}
	return '${class_name}.${member_hint}|${node.ast_type.qualified}'
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

fn (c &C2V) class_has_method_base(class_name string, base_name string) bool {
	if base_name == '' {
		return false
	}
	return '${class_name}.${base_name}' in c.class_method_bases
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
	if name == '' {
		return false
	}
	return !name.contains('<') && !name.contains('>') && !name.contains(' ') && !name.contains('(')
		&& !name.contains(')') && !name.contains(',')
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
	return ''
}

fn (c &C2V) node_body_in_main_file(node &Node) bool {
	for child in node.inner {
		if child.kindof(.compound_stmt) {
			body_path := c.node_source_path(child)
			if body_path != '' {
				return c.is_main_source_path(body_path)
			}
			break
		}
	}
	return node.location.file_index == 0
}

fn (mut c C2V) collect_cpp_class_method_bases() {
	c.class_method_bases.clear()
	for node in c.tree.inner {
		if !node.kindof(.cxx_record_decl) || node.name == '' {
			continue
		}
		class_name := c.add_struct_name(mut c.types, node.name)
		for child in node.inner {
			if !child.kindof(.cxx_method_decl) || child.name == '' {
				continue
			}
			base_name := method_base_name_from_cpp_name(child.name)
			if base_name == '' {
				continue
			}
			c.class_method_bases['${class_name}.${base_name}'] = true
		}
	}
}

fn (mut c C2V) cxx_method_decl(_node &Node) {
	c.declared_local_vars.clear()
	c.for_init_vars.clear()
	mut node := unsafe { _node }
	name := node.name
	// Skip operator methods that can't be represented in V
	if name.starts_with('operator') {
		v_op_name := cpp_operator_to_v_method(name)
		if v_op_name == '' {
			// Skip unsupported operators entirely
			return
		}
	}
	// node.ast_type.qualified is the function signature type, e.g. "int ()" or "void (int)"
	// Extract return type from function signature (everything before first '(')
	mut ret_type := node.ast_type.qualified.before('(').trim_space()
	if ret_type == 'void' {
		ret_type = ''
	} else {
		ret_type = ' ' + c.prefix_external_type(convert_type(ret_type).name)
	}
	mut class_name := if c.cur_class != '' {
		c.add_struct_name(mut c.types, c.cur_class)
	} else {
		''
	}
	if class_name == '' && node.mangled_name != '' {
		extracted := extract_class_from_mangled(node.mangled_name)
		if extracted != '' {
			class_name = c.add_struct_name(mut c.types, extracted)
		}
	}
	if class_name == '' {
		return
	}
	if !is_valid_v_receiver_type_name(class_name) {
		return
	}
	has_body := node.has_child_of_kind(.compound_stmt)
	if !has_body && !c.should_emit_skeleton_body() {
		return
	}
	params := c.fn_params(mut node)
	str_args := params.join(', ')
	mut v_method_name := method_base_name_from_cpp_name(name)
	if c.should_skip_duplicate_cpp_member(node, class_name, v_method_name) {
		return
	}
	v_method_name = c.reserve_method_name(class_name, v_method_name)
	if v_method_name == '' {
		return
	}
	receiver_mut := if node.ast_type.qualified.contains(') const') { '' } else { 'mut ' }
	c.genln('fn (${receiver_mut}this ${class_name}) ${v_method_name}(${str_args})${ret_type} {')
	if c.should_emit_skeleton_body() || !has_body {
		c.gen_skeleton_fn_body(ret_type.trim_space())
		return
	}
	if node.has_child_of_kind(.overrides) {
		node.try_get_next_child_of_kind(.overrides) or {
			vprintln(err.str())
			bad_node
		}
	}
	mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
		vprintln(err.str())
		bad_node
	}

	c.statements(mut stmts)
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
		else {
			if op_name.starts_with('operator ') {
				// Conversion operator like "operator int", "operator bool"
				'op_conv_' + op_name[9..].replace(' ', '_').to_lower()
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
	v_type := convert_type(node.ast_type.qualified).name
	return normalize_cpp_operator_type_name(v_type)
}

fn (c &C2V) should_use_operator_method_for_binary(v_method string, lhs &Node, rhs &Node) bool {
	if v_method == '' {
		return false
	}
	if is_cpp_operator_literal_operand(lhs) {
		return false
	}
	lhs_type := c.operator_node_v_type(lhs)
	rhs_type := c.operator_node_v_type(rhs)
	if lhs_type == '' || rhs_type == '' {
		return false
	}
	if is_cpp_operator_primitive_type(lhs_type) || is_cpp_operator_primitive_type(rhs_type) {
		return false
	}
	return lhs_type == rhs_type
}

fn (mut c C2V) gen_cpp_operator_receiver(node &Node) {
	c.gen('(')
	c.expr(node)
	c.gen(')')
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
		v_method := cpp_operator_to_v_method(op_name)
		if remaining == 1 && v_op in ['-', '+', '!', '~', '*', '&'] {
			// Unary operator: op expr
			c.gen(v_op)
			operand := node.try_get_next_child() or {
				vprintln(err.str())
				bad_node
			}
			c.expr(operand)
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
			if v_method != '' {
				c.gen_cpp_operator_receiver(lhs)
				c.gen('.${v_method}(')
				c.expr(rhs)
				c.gen(')')
			} else {
				c.expr(lhs)
				c.gen('[')
				c.expr(rhs)
				c.gen(']')
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
			} else if v_op == '=' {
				mut lhs_assign := lhs
				mut rhs_assign := rhs
				c.gen_simple_assign(mut lhs_assign, mut rhs_assign)
			} else if v_method != '' && c.should_use_operator_method_for_binary(v_method, lhs, rhs) {
				c.gen_cpp_operator_receiver(lhs)
				c.gen('.${v_method}(')
				c.expr(rhs)
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
