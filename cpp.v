module main

import os

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
	return c.cpp_base_embed_path(receiver_type, owner, mut seen)
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
		// idEventFunc<T> has a T-independent layout. Emit its generic record once;
		// convert_type maps every specialization to this shared representation.
		if node.name == 'idEventFunc' {
			for child in node.inner {
				if child.kindof(.cxx_record_decl) && child.inner.any(it.kindof(.field_decl)) {
					c.cxx_record_decl(child)
					break
				}
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
		if base_embed == '' && receiver_expr.kindof(.implicit_cast_expr)
			&& receiver_expr.cast_kind.contains('DerivedToBase') && receiver_expr.inner.len > 0 {
			// An explicitly qualified inherited call can produce several nested
			// DerivedToBase casts. Resolve the path from the original `this` type,
			// not merely from the immediately nested (intermediate-base) cast.
			source_type := c.cpp_derived_cast_root_type(receiver_expr)
			if receiver_type != '' && receiver_type != source_type {
				mut seen := map[string]bool{}
				base_embed = c.cpp_base_embed_path(source_type, receiver_type, mut seen)
				if base_embed == '' && receiver_type !in c.cpp_abstract_types {
					base_embed = receiver_type
				}
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
			if remaining_args == 0 && op_token in ['const char *', 'char *']
				&& node_is_cpp_idstr_expr(receiver_expr) {
				c.gen_cpp_operator_receiver(receiver_expr)
				c.gen('.c_str()')
			} else if remaining_args == 0 && v_method.starts_with('op_conv_')
				&& is_cpp_winvar_value_wrapper_type(receiver_type) {
				// idWin* wrappers implement their implicit conversions by returning
				// the contained value. V has no implicit user-defined conversions, so
				// spell out that same field access at the conversion call site.
				c.gen_cpp_operator_receiver(receiver_expr)
				c.gen('.data')
				if receiver_type == 'IdWinStr' && op_token in ['const char *', 'char *'] {
					c.gen('.c_str()')
				}
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
			c.expr(receiver_expr)
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
					c.gen('.${method_v}(')
				}
			}
		}
		// Process remaining children as function arguments.
		// The first child was member_expr (the object+method), rest are arguments.
		callee_type := c.cpp_member_call_callee_type(member_expr)
		callee_params := function_type_params(callee_type)
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
		method_is_known_variadic := method_base in [
			'printf',
			'd_printf',
			'warning',
			'd_warning',
			'error',
			'add_chat_line',
		]
		mut arg_i := 0
		for {
			mut arg := node.try_get_next_child() or { break }
			// MaterializeTemporaryExpr wraps the actual argument expression
			if arg.kindof(.materialize_temporary_expr) {
				arg = arg.try_get_next_child() or { break }
			}
			if arg_i > 0 {
				c.gen(', ')
			}
			is_variadic_arg := (is_variadic && arg_i >= fixed_param_count)
				|| (method_is_known_variadic && arg_i > 0)
				|| call_is_cross_dir_fallback
			mut param_type := if arg_i < callee_params.len { callee_params[arg_i] } else { '' }
			if param_type == '' && arg_i == 0
				&& method_base in ['cmp', 'cmpn', 'icmp', 'icmpn', 'icmp_no_color', 'icmp_path',
					'icmpn_path', 'icmp_prefix_path'] {
				// Dependent function-template bodies can leave the selected idStr
				// member as a bound placeholder. These member overloads all take a
				// C string, so retain the concrete call-argument conversion.
				param_type = 'const char *'
			}
			base_pointer_target := if call_is_cross_dir_fallback {
				''
			} else {
				c.cpp_base_pointer_target_for_method_arg(receiver_type, method_base, arg_i, param_type)
			}
			if base_pointer_target != '' {
				c.gen_cpp_base_pointer_arg(arg, base_pointer_target)
			} else if (method_base in ['get_script_function', 'set_name', 'find_entity',
				'find_entity_def_dict', 'find_inventory_item', 'remove_inventory_item', 'set_model',
				'give_video']
				&& arg_i == 0) || (method_base == 'give_objective' && arg_i == 2)
				|| (method_base == 'damage' && arg_i == 3) {
				rendered := c.render_expr_to_string(arg)
				if array_source := cpp_array_decay_source(unsafe { &arg }) {
					if !array_source.kindof(.string_literal) {
						c.gen('unsafe { &i8(&')
						c.expr(array_source)
						c.gen('[0]) }')
					} else {
						c.gen(rendered)
					}
				} else if rendered.starts_with('&') {
					base := rendered[1..].trim_space()
					if c.rendered_expr_is_cpp_idstr_value(base) && !base.ends_with('.c_str()') {
						c.gen(base + '.c_str()')
					} else {
						c.gen(rendered)
					}
				} else if c.cpp_expr_is_idstr_value(arg, rendered)
					&& !rendered.ends_with('.c_str()') {
					c.gen(rendered + '.c_str()')
				} else {
					c.gen(rendered)
				}
			} else if method_base == 'project_decal' && arg_i == 5 {
				rendered := c.render_expr_to_string(arg)
				if rendered.starts_with('&') {
					base := rendered[1..].trim_space()
					if c.rendered_expr_is_cpp_idstr_value(base) && !base.ends_with('.c_str()') {
						c.gen(base + '.c_str()')
					} else {
						c.gen(rendered)
					}
				} else if (node_is_cpp_idstr_expr(arg) || c.rendered_expr_is_cpp_idstr_value(rendered))
					&& !rendered.ends_with('.c_str()') {
					c.gen(rendered + '.c_str()')
				} else {
					c.gen(rendered)
				}
			} else if method_base in ['load', 'add_body'] && ((method_base == 'load' && arg_i == 1)
				|| (method_base == 'add_body' && arg_i == 2)) {
				rendered := c.render_expr_to_string(arg)
				if (node_is_cpp_idstr_expr(arg) || c.rendered_expr_is_cpp_idstr_value(rendered))
					&& !rendered.ends_with('.c_str()') {
					c.gen(rendered + '.c_str()')
				} else {
					c.gen(rendered)
				}
			} else if receiver_type == 'IdAF' && method_base == 'load' && arg_i == 0 {
				rendered := c.render_expr_to_string(arg)
				if rendered == 'this' {
					c.gen('unsafe { &IdEntity(&this) }')
				} else {
					c.gen_call_arg(arg, param_type, is_variadic_arg)
				}
			} else if method_base in ['set_physics', 'restore_physics'] && arg_i == 0
				&& !call_is_cross_dir_fallback {
				v_param_type := c.prefix_external_type(c.convert_type(param_type).name)
				param_base := normalize_cpp_operator_type_name(v_param_type)
				if param_base in c.cpp_abstract_types && !v_param_type.starts_with('&') {
					c.gen_call_arg(arg, param_type, is_variadic_arg)
				} else {
					rendered := c.render_expr_to_string(arg)
					if cpp_rendered_is_nil_expr(rendered) {
						c.gen('unsafe { nil }')
					} else {
						c.gen('unsafe { &IdPhysics(' + rendered + ') }')
					}
				}
			} else {
				c.gen_call_arg(arg, param_type, is_variadic_arg)
			}
			arg_i++
		}
		if (is_variadic && arg_i == fixed_param_count)
			|| (method_is_known_variadic && arg_i == 1) {
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
		// Array init index - skip
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
		// Opaque value (used in binary conditional etc) - process inner
		if node.inner.len > 0 {
			c.expr(node.inner[0])
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
	if node.kindof(.implicit_cast_expr) && node.inner.len > 0 {
		if node.cast_kind == 'ArrayToPointerDecay' {
			c.gen('&')
			c.expr(node.inner[0])
			c.gen('[0]')
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
		c.gen('&this')
		return
	}
	c.expr(node)
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
		if !(expr.kindof(.implicit_cast_expr) && expr.inner.len > 0
			&& expr.cast_kind != 'ArrayToPointerDecay') {
			break
		}
		expr = expr.inner[0]
	}
	// Downcasts in recovered C++ ASTs are often only used for method dispatch
	// (`static_cast<idActor *>(focusEnt)->GetEyePosition()`).
	// Emitting value casts here (`IdActor(focus_ent)`) is invalid in V.
	// Preserve pointer semantics with an explicit unsafe pointer cast.
	if node.ast_type.qualified.contains('*') {
		mut ptr_type := c.convert_type(node.ast_type.qualified).name.trim_space()
		if ptr_type == '' {
			ptr_type = 'voidptr'
		}
		if !ptr_type.starts_with('&') && ptr_type != 'voidptr' {
			ptr_type = '&' + ptr_type
		}
		if node.kindof(.cxx_reinterpret_cast_expr) && node.cast_kind == 'IntegralToPointer' {
			c.gen('${ptr_type}(')
			c.expr(expr)
			c.gen(')')
			return
		}
		source_type := c.prefix_external_type(c.convert_type(node_effective_type_name(expr)).name)
		if c.is_v_abstract_interface_type(source_type) {
			if normalize_cpp_operator_type_name(source_type) == 'IdCamera'
				&& ptr_type == '&IdClass' {
				c.gen('(unsafe { &IdClass(&')
				c.expr(expr)
				c.gen('.c2v_base_id_entity().IdClass) })')
				return
			}
			// A C++ downcast from an abstract base pointer becomes a V interface
			// assertion. Pointer reinterpretation is rejected for interface values.
			c.gen('(')
			c.expr(expr)
			c.gen(' as ${ptr_type})')
			return
		}
		c.gen('(unsafe { ${ptr_type}(')
		// Preserve C++ pointer sources. In particular, V method receivers need an
		// address and fixed-array decay must point at the array's first element.
		c.gen_cxx_pointer_cast_source(expr)
		c.gen(') })')
		return
	}
	typ := c.convert_type(node.ast_type.qualified)
	if node.kindof(.cxx_functional_cast_expr) && node.cast_kind == 'ConstructorConversion'
		&& expr.kindof(.cxx_construct_expr) {
		c.expr(expr)
		return
	}
	if cpp_construct_is_opaque_default_literal(typ.name) {
		c.gen('${typ.name}{}')
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
fn cpp_construct_uses_positional_literal(type_name string) bool {
	base := normalize_cpp_operator_type_name(type_name)
	return base in ['IdAngles', 'IdPlane', 'IdRotation', 'IdVec2', 'IdVec3', 'IdVec4', 'IdVec5']
}

fn cpp_construct_is_opaque_default_literal(type_name string) bool {
	base := normalize_cpp_operator_type_name(type_name)
	return base != '' && !cpp_construct_uses_positional_literal(base) && base[0].is_capital()
}

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

fn is_cpp_winvar_value_wrapper_type(type_name string) bool {
	return normalize_cpp_operator_type_name(type_name) in [
		'IdWinBool',
		'IdWinFloat',
		'IdWinInt',
		'IdWinRectangle',
		'IdWinBackground',
		'IdWinStr',
		'IdWinVec2',
		'IdWinVec3',
		'IdWinVec4',
	]
}

fn cpp_winvar_conversion_receiver(node &Node) ?Node {
	if node.kindof(.cxx_member_call_expr) && node.inner.len > 0
		&& node.inner[0].kindof(.member_expr) {
		member := node.inner[0]
		if member.name.starts_with('operator')
			&& cpp_operator_to_v_method(member.name.trim_left('.')).starts_with('op_conv_')
			&& member.inner.len > 0 {
			receiver := member.inner[0]
			receiver_type := convert_type(node_effective_type_name(receiver)).name
			if is_cpp_winvar_value_wrapper_type(receiver_type) {
				return receiver
			}
		}
	}
	if node.inner.len == 1 && (node.kindof(.implicit_cast_expr) || node.kindof(.paren_expr)
		|| node.kindof(.materialize_temporary_expr) || node.kindof(.expr_with_cleanups)
		|| node.kindof(.cxx_bind_temporary_expr)) {
		return cpp_winvar_conversion_receiver(unsafe { &node.inner[0] })
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
	child_base := normalize_cpp_operator_type_name(child_type)
	base_type := c.convert_type(node_effective_type_name(base)).name.trim_space()
	base_type_name := normalize_cpp_operator_type_name(base_type)
	if expected_base == 'IdStr'
		&& (child_base in ['IdToken', 'IdPoolStr'] || base_type_name in ['IdToken', 'IdPoolStr']) {
		c.ensure_cpp_idstr_construct_helper()
		c.gen('c2v_construct_id_str(')
		c.expr(base)
		c.gen('.c_str())')
		return
	}
	if expected_base == 'IdStr' && base.kindof(.string_literal) {
		// idStr owns mutable storage in C++, but static type-table names only need
		// an immutable initial value. Keep the literal as stable data and leave
		// alloced at zero so a later mutation will allocate before writing.
		literal_text := base.value.to_str()
		literal_len := if literal_text.len >= 2 { literal_text.len - 2 } else { 0 }
		c.gen('IdStr{len: ${literal_len}, data: ')
		c.expr(base)
		c.gen('}')
		return
	}
	if expected_base == 'IdToken' && base.kindof(.string_literal) {
		literal_text := base.value.to_str()
		literal_len := if literal_text.len >= 2 { literal_text.len - 2 } else { 0 }
		c.gen('IdToken{IdStr: IdStr{len: ${literal_len}, data: ')
		c.expr(base)
		c.gen('}}')
		return
	}
	if !trimmed_expected_type.starts_with('&') && child_type.starts_with('&')
		&& expected_base !in v_primitive_type_names && normalize_cpp_operator_type_name(child_type) == expected_base {
		c.gen('unsafe { *')
		c.expr(child)
		c.gen(' }')
		return
	}
	cast_type := c.struct_init_cast_type(expected_type, *child)
	if cast_type != '' {
		c.gen('${cast_type}(')
		c.expr(child)
		c.gen(')')
		return
	}
	c.expr(child)
}

fn cpp_constructor_field_names(type_name string, arg_count int) []string {
	base := normalize_cpp_operator_type_name(type_name)
	if base == 'IdEventDef' && arg_count == 3 {
		return ['name', 'formatspec', 'return_type']
	}
	if base == 'IdTypeInfo' && arg_count == 7 {
		return ['classname', 'superclass', 'event_callbacks', 'create_instance', 'spawn', 'save',
			'restore']
	}
	// These constructors initialize fields in an order that differs from their
	// declaration order. Mapping them positionally corrupts the generated global
	// script type table (for example, `edef` was assigned to `name_field`).
	if base == 'IdTypeDef' && arg_count == 5 {
		return ['type_', 'def', 'name', 'size', 'aux_type']
	}
	if base == 'IdVarDef' && arg_count == 1 {
		return ['type_def']
	}
	if base == 'IdCVar' {
		return match arg_count {
			5 {
				['name', 'value', 'flags', 'description', 'value_completion']
			}
			6 {
				['name', 'value', 'flags', 'description', 'value_strings', 'value_completion']
			}
			7 {
				['name', 'value', 'flags', 'description', 'value_min', 'value_max', 'value_completion']
			}
			else {
				[]string{}
			}
		}
	}
	return []string{}
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

fn (mut c C2V) ensure_cpp_idstr_construct_helper() {
	helper_key := 'cpp_idstr_constructor_helper:${os.dir(c.outv)}'
	if helper_key in c.generated_declarations {
		return
	}
	c.generated_declarations[helper_key] = true
	c.local_type_declarations << 'fn c2v_construct_id_str(text &i8) IdStr {\n\tmut value := IdStr{}\n\tvalue.data = unsafe { nil }\n\tif text != unsafe { nil } {\n\t\tvalue.len = int(C.strlen(text))\n\t\tvalue.alloced = value.len + 1\n\t\tvalue.data = unsafe { &i8(C.malloc(usize(value.alloced))) }\n\t\tC.strcpy(value.data, text)\n\t}\n\treturn value\n}\n\n'
}

fn (mut c C2V) gen_cxx_construct_literal(type_name string, args []Node) {
	if normalize_cpp_operator_type_name(type_name) == 'IdMat4' && args.len == 2 {
		first_type := normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[0])).name)
		second_type := normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[1])).name)
		if first_type == 'IdMat3' && second_type == 'IdVec3' {
			helper_key := 'cpp_idmat4_mat3_vec3_constructor_helper:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'fn c2v_construct_id_mat4(axis IdMat3, origin IdVec3) IdMat4 {\n\t_ = axis\n\t_ = origin\n\treturn IdMat4{}\n}\n\n'
			}
			c.gen('c2v_construct_id_mat4(')
			c.gen_cxx_construct_value(unsafe { &args[0] }, 'IdMat3')
			c.gen(', ')
			c.gen_cxx_construct_value(unsafe { &args[1] }, 'IdVec3')
			c.gen(')')
			return
		}
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdVec5' && args.len == 2 {
		first_type := normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[0])).name)
		second_type := normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[1])).name)
		if first_type == 'IdVec3' && second_type == 'IdVec2' {
			helper_key := 'cpp_idvec5_vec3_vec2_constructor_helper:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'fn c2v_construct_id_vec5(point IdVec3, uv IdVec2) IdVec5 {\n\treturn IdVec5{x: point.x, y: point.y, z: point.z, s: uv.x, t: uv.y}\n}\n\n'
			}
			c.gen('c2v_construct_id_vec5(')
			c.gen_cxx_construct_value(unsafe { &args[0] }, 'IdVec3')
			c.gen(', ')
			c.gen_cxx_construct_value(unsafe { &args[1] }, 'IdVec2')
			c.gen(')')
			return
		}
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdBox' && args.len == 3 {
		first_type := normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[0])).name)
		second_type := normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[1])).name)
		third_type := normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[2])).name)
		if first_type == 'IdBounds' && second_type == 'IdVec3' && third_type == 'IdMat3' {
			helper_key := 'cpp_idbox_bounds_constructor_helper:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'fn c2v_construct_id_box(bounds IdBounds, origin IdVec3, axis IdMat3) IdBox {\n\t_ = bounds\n\treturn IdBox{center: origin, axis: axis}\n}\n\n'
			}
			c.gen('c2v_construct_id_box(')
			c.gen_cxx_construct_value(unsafe { &args[0] }, 'IdBounds')
			c.gen(', ')
			c.gen_cxx_construct_value(unsafe { &args[1] }, 'IdVec3')
			c.gen(', ')
			c.gen_cxx_construct_value(unsafe { &args[2] }, 'IdMat3')
			c.gen(')')
			return
		}
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdStr' && args.len == 1 {
		arg_type := c.convert_type(node_effective_type_name(args[0])).name.trim_space()
		if arg_type.starts_with('&i8')
			|| unwrap_cpp_operator_operand(unsafe { &args[0] }).kindof(.string_literal)
			|| cpp_array_decay_source(unsafe { &args[0] }) != none {
			c.ensure_cpp_idstr_construct_helper()
			c.gen('c2v_construct_id_str(')
			c.gen_call_arg(args[0], 'const char *', false)
			c.gen(')')
			return
		}
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdStr' && args.len == 3 {
		first_arg_type := c.convert_type(node_effective_type_name(args[0])).name.trim_space()
		if first_arg_type.starts_with('&i8') || cpp_array_decay_source(unsafe { &args[0] }) != none {
			helper_key := 'cpp_idstr_range_constructor_helper:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'fn c2v_construct_id_str_range(text &i8, start int, end int) IdStr {\n\ttext_len := int(C.strlen(text))\n\tmut safe_start := start\n\tmut safe_end := end\n\tif safe_start < 0 { safe_start = 0 }\n\tif safe_start > text_len { safe_start = text_len }\n\tif safe_end > text_len { safe_end = text_len }\n\tif safe_end < safe_start { safe_end = safe_start }\n\tcount := safe_end - safe_start\n\tmut value := IdStr{}\n\tvalue.len = count\n\tvalue.alloced = count + 1\n\tvalue.data = unsafe { &i8(C.malloc(usize(value.alloced))) }\n\tunsafe { C.memcpy(voidptr(value.data), voidptr(text + safe_start), usize(count)) }\n\tvalue.data[count] = `\\0`\n\treturn value\n}\n\n'
			}
			c.gen('c2v_construct_id_str_range(')
			c.gen_call_arg(args[0], 'const char *', false)
			c.gen(', ')
			c.gen_cxx_construct_value(unsafe { &args[1] }, 'int')
			c.gen(', ')
			c.gen_cxx_construct_value(unsafe { &args[2] }, 'int')
			c.gen(')')
			return
		}
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdCmdArgs' && args.len == 2 {
		// idCmdArgs(text, keepAsStrings) tokenizes the input in its constructor;
		// positional field initialization both loses that behavior and assigns the
		// pointer/bool arguments to the unrelated argc/argv storage fields.
		helper_key := 'cpp_idcmdargs_constructor_helper:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_construct_id_cmd_args(text &i8, keep_as_strings bool) IdCmdArgs {\n\tmut value := IdCmdArgs{}\n\tvalue.init2(text, keep_as_strings)\n\treturn value\n}\n\n'
		}
		c.gen('c2v_construct_id_cmd_args(')
		c.gen_cxx_construct_value(unsafe { &args[0] }, '&i8')
		c.gen(', ')
		c.gen_cxx_construct_value(unsafe { &args[1] }, 'bool')
		c.gen(')')
		return
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdTraceModel' && args.len == 1
		&& normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[0])).name) == 'IdBounds' {
		helper_key := 'cpp_idtracemodel_bounds_constructor_helper:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_construct_id_trace_model(bounds &IdBounds) IdTraceModel {\n\tmut value := IdTraceModel{}\n\tvalue.init_box()\n\tvalue.setup_box(bounds)\n\treturn value\n}\n\n'
		}
		c.gen('c2v_construct_id_trace_model(')
		c.gen_call_arg(args[0], 'const idBounds &', false)
		c.gen(')')
		return
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdTraceModel' && args.len == 2 {
		first_type :=
			normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[0])).name)
		second_type :=
			normalize_cpp_operator_type_name(c.convert_type(node_effective_type_name(args[1])).name)
		if first_type == 'IdBounds' && second_type == 'int' {
			helper_key := 'cpp_idtracemodel_cylinder_constructor_helper:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'fn c2v_construct_id_trace_model_cylinder(bounds &IdBounds, sides int) IdTraceModel {\n\tmut value := IdTraceModel{}\n\tvalue.setup_cylinder(bounds, sides)\n\treturn value\n}\n\n'
			}
			c.gen('c2v_construct_id_trace_model_cylinder(')
			c.gen_call_arg(args[0], 'const idBounds &', false)
			c.gen(', ')
			c.gen_call_arg(args[1], 'int', false)
			c.gen(')')
			return
		}
		if first_type == 'f32' && second_type == 'f32' {
			helper_key := 'cpp_idtracemodel_bone_constructor_helper:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'fn c2v_construct_id_trace_model_bone(length f32, width f32) IdTraceModel {\n\tmut value := IdTraceModel{}\n\tvalue.init_bone()\n\tvalue.setup_bone(length, width)\n\treturn value\n}\n\n'
			}
			c.gen('c2v_construct_id_trace_model_bone(')
			c.gen_call_arg(args[0], 'float', false)
			c.gen(', ')
			c.gen_call_arg(args[1], 'float', false)
			c.gen(')')
			return
		}
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdEventArg' && args.len == 1 {
		arg_v_type := c.convert_type(node_effective_type_name(args[0])).name
		arg_base := normalize_cpp_operator_type_name(arg_v_type)
		mut method_name := ''
		mut helper_param_type := ''
		mut cpp_param_type := ''
		if arg_base == 'int' {
			method_name = 'init1'
			helper_param_type = 'int'
			cpp_param_type = 'int'
		} else if arg_base == 'f32' {
			method_name = 'init12'
			helper_param_type = 'f32'
			cpp_param_type = 'float'
		} else if arg_base == 'IdVec3' {
			method_name = 'init13'
			helper_param_type = '&IdVec3'
			cpp_param_type = 'idVec3 &'
		} else if arg_base == 'IdStr' {
			method_name = 'init14'
			helper_param_type = '&IdStr'
			cpp_param_type = 'const idStr &'
		} else if arg_v_type == '&i8' {
			method_name = 'init15'
			helper_param_type = '&i8'
			cpp_param_type = 'const char *'
		} else if arg_base == 'IdEntity' {
			method_name = 'init16'
			helper_param_type = '&IdEntity'
			cpp_param_type = 'const idEntity *'
		} else if arg_base == 'Trace_s' {
			method_name = 'init17'
			helper_param_type = '&Trace_s'
			cpp_param_type = 'const trace_s *'
		}
		if method_name != '' {
			helper_name := 'c2v_construct_id_event_arg_${method_name}'
			helper_key := '${helper_name}:${os.dir(c.outv)}'
			if helper_key !in c.generated_declarations {
				c.generated_declarations[helper_key] = true
				c.local_type_declarations << 'fn ${helper_name}(data ${helper_param_type}) IdEventArg {\n\tmut value := IdEventArg{}\n\tvalue.${method_name}(data)\n\treturn value\n}\n\n'
			}
			c.gen('${helper_name}(')
			c.gen_call_arg(args[0], cpp_param_type, false)
			c.gen(')')
			return
		}
	}
	if normalize_cpp_operator_type_name(type_name) == 'IdBounds' && args.len == 1 {
		if layout := c.structs[type_name] {
			if layout.fields.len == 1 && layout.field_types.len == 1 {
				field_type := layout.field_types[0]
				array_len := cpp_fixed_array_length(field_type)
				element_type := cpp_fixed_array_element_type(field_type)
				if array_len == 2 && element_type != '' {
					helper_key := 'cpp_idbounds_point_constructor_helper:${os.dir(c.outv)}'
					if helper_key !in c.generated_declarations {
						c.generated_declarations[helper_key] = true
						field_name := layout.fields[0]
						c.local_type_declarations << 'fn c2v_construct_id_bounds_point(point ${element_type}) ${type_name} {\n\treturn ${type_name}{${field_name}: [point, point]!}\n}\n\n'
					}
					c.gen('c2v_construct_id_bounds_point(')
					c.gen_cxx_construct_value(unsafe { &args[0] }, element_type)
					c.gen(')')
					return
				}
			}
		}
	}
	mut field_names := cpp_constructor_field_names(type_name, args.len)
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

fn (c &C2V) cpp_base_pointer_target_for_method_arg(receiver_type string, method_base string, arg_i int, param_type string) string {
	if arg_i == 0
		&& method_base in ['set_body', 'bind_to_joint', 'bind_to_body', 'set_selected',
			'activate_targets', 'kill_box', 'damage_feedback', 'bind'] {
		return 'IdEntity'
	}
	if method_base == 'init' && arg_i == 0 && receiver_type.starts_with('IdIK_') {
		return 'IdEntity'
	}
	if method_base == 'radius_push' && arg_i == 3 {
		return 'IdEntity'
	}
	if method_base == 'radius_damage' && arg_i in [3, 4] {
		return 'IdEntity'
	}
	if method_base == 'apply_impulse' && arg_i == 0 {
		param_base := normalize_cpp_operator_type_name(c.convert_type(param_type).name)
		if param_base == 'IdEntity' {
			return 'IdEntity'
		}
	}
	if method_base == 'damage' && arg_i in [0, 1] {
		return 'IdEntity'
	}
	if method_base == 'create' && arg_i == 0 && receiver_type in ['IdProjectile', 'IdDebris'] {
		return 'IdEntity'
	}
	if method_base in ['event_teleport_player', 'event_teleport_stage'] && arg_i == 0 {
		return 'IdEntity'
	}
	if method_base == 'teleport' && arg_i == 2 {
		return 'IdEntity'
	}
	if method_base == 'set_camera' && arg_i == 0 {
		v_param_type := c.convert_type(param_type).name
		if c.is_v_abstract_interface_type(v_param_type) {
			// The first C++ pointer layer of an abstract class is already represented
			// by the V interface value. Let normal argument generation handle both a
			// concrete implementation and a typed interface nil.
			return ''
		}
		return 'IdCamera'
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
		c.gen('&${target_type}(')
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
	rendered := c.render_expr_to_string(arg)
	c.inside_unsafe = was_inside_unsafe
	if cpp_rendered_is_nil_expr(rendered) {
		c.gen(if was_inside_unsafe { 'nil' } else { 'unsafe { nil }' })
		return
	}
	if !was_inside_unsafe {
		c.gen('unsafe { ')
		c.inside_unsafe = true
	}
	if rendered.starts_with('&') || rendered.starts_with('unsafe { &') {
		c.gen('&${target_type}(')
		c.gen(rendered)
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
	constructor_key := cpp_constructor_signature_key(typ.name, node.ctor_type.qualified)
	if c.project_require_no_stubs && constructor_key != '' {
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
	} else if cpp_construct_is_opaque_default_literal(typ.name) && typ.name !in c.structs {
		c.gen('${typ.name}{}')
	} else if node.inner.len == 1 {
		child := node.inner[0]
		base_type := normalize_cpp_operator_type_name(typ.name)
		child_raw_type := c.convert_type(node_effective_type_name(child)).name.trim_space()
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
		c.gen_cxx_construct_literal(typ.name, node.inner)
	} else {
		c.gen_cxx_construct_literal(typ.name, node.inner)
	}
}

fn cpp_constructor_signature_key(type_name string, ctor_type string) string {
	base_type := normalize_cpp_operator_type_name(type_name)
	signature := collapse_ascii_whitespace(ctor_type)
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

fn (mut c C2V) gen_strict_cpp_constructor_helper_call(type_name string, init_name string, params []string, node &Node) {
	base_type := normalize_cpp_operator_type_name(type_name)
	helper_name := 'c2v_construct_' + filter_name(c_identifier_to_v_name('${base_type}_${init_name}'), true)
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
		c.local_type_declarations << 'fn ${helper_name}(${params.join(', ')}) ${base_type} {\n\tmut ${result_name} := ${base_type}{}\n\t${result_name}.${init_name}(${param_names.join(', ')})\n\treturn ${result_name}\n}\n\n'
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
	// Check if this is an array new (has a non-CXXConstructExpr child for size)
	if node.inner.len > 0 && !node.inner[0].kindof(.cxx_construct_expr) {
		// Array new: new int[n] => unsafe { &int(C.malloc(usize(size) * usize(sizeof(base_type)))) }
		// C++ permits any integral size expression. Normalize both factors to usize
		// so expressions such as `strlen(name) + 1` do not mix V's usize and int.
		c.gen('unsafe { &${base_type}(C.malloc(')
		c.gen('usize(')
		c.expr(node.inner[0])
		c.gen(') * usize(sizeof(${base_type})))) }')
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
	typ := c.convert_type(node.ast_type.qualified)
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
	name := node.name
	c.genln('CLASS ${name}')
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
	token = c_identifier_to_v_name(token)
	token = sanitize_type_token(token).to_lower()
	if token.starts_with('_') {
		token = 'n' + token
	}
	return token
}

fn cpp_static_method_function_v_name(class_name string, method_name string) string {
	class_token := sanitize_type_token(c_identifier_to_v_name(class_name)).to_lower()
	if class_token == '' {
		return method_name
	}
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
	// concrete V record so its translated base embedding and methods remain
	// available (for example idCurve_NonUniformBSpline<T>).
	// Keep avoiding the enormous standard-library template surface from headers,
	// but do not restrict concrete templates declared by the translated source to
	// Doom's `id*` naming convention. Local helpers such as `MyArray<T, N>` are
	// real project types and their typedefs otherwise point at missing V records.
	if (!node.name.starts_with('id') && node.location.file_index != 0)
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
	if node.name == 'idEventFunc' && outer_layout_exists {
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
	specialized := Node{
		...*node
		name: v_name
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
		// `idCurve_BSpline<type>`. Record the resolved specialization hierarchy as
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
		ret_type = ' ' + c.prefix_external_type(c.convert_type(ret_type).name)
	}
	c.genln('\t${method_name}(${params.join(', ')})${ret_type}')
}

fn (c &C2V) cpp_class_has_project_method_definition(class_name string) bool {
	needle := '|${class_name}.'
	return c.project_dir_method_defs.keys().any(it.contains(needle))
}

fn (c &C2V) cpp_class_has_known_derived_type(class_name string) bool {
	for bases in c.cpp_class_bases.values() {
		if class_name in bases {
			return true
		}
	}
	return false
}

fn (mut c C2V) cpp_record_is_abstract_interface(node &Node) bool {
	if node.inner.any((it.kindof(.cxx_method_decl) || it.kind_str == 'CXXMethodDecl')
		&& it.is_pure) {
		return true
	}
	// Some Doom public APIs are C++ interfaces without `= 0`: they contain no
	// state and declare their whole callable surface as virtual methods whose
	// implementations live in the game DLL (notably idGameEdit/idGameEditExt).
	// Model those as V interfaces as well so calls retain their typed results.
	has_fields := node.inner.any((it.kindof(.field_decl) || it.kind_str == 'FieldDecl')
		&& it.class_modifier != 'static')
	has_virtual_declaration := node.inner.any((it.kindof(.cxx_method_decl)
		|| it.kind_str == 'CXXMethodDecl') && it.is_virtual
		&& !it.has_child_of_kind(.compound_stmt)
		&& !has_direct_child_kind_str(it, 'CompoundStmt'))
	if has_fields || !has_virtual_declaration {
		return false
	}
	class_name := c.add_struct_name(mut c.types, node.name)
	has_abstract_base := c.cpp_class_bases[class_name].any(normalize_cpp_operator_type_name(c.resolve_type_alias(it)) in c.cpp_abstract_types)
	if has_abstract_base && c.cpp_class_has_project_method_definition(class_name) {
		// A stateless implementation of an abstract API is still a concrete record.
		// Doom's idSIMD_Generic is the base for optimized implementations, but it
		// directly implements idSIMDProcessor and is instantiated as a fallback.
		return false
	}
	// A stateless polymorphic base still needs interface lowering when its default
	// implementations are in the project (idFile). A leaf whose declared methods
	// are implemented by that same concrete class (idNetworkSystem and local Doom
	// service implementations) must remain a struct.
	return !c.cpp_class_has_project_method_definition(class_name)
		|| c.cpp_class_has_known_derived_type(class_name)
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
// declaration such as `extern idGameEdit *gameEdit` is lowered to the V
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
	// Reserve every overload name before emitting method bodies. Calls retain
	// Clang's referenced declaration id, so they can select the exact V suffix
	// even when the referenced overload is declared later in the class.
	for child in node.inner {
		if child.kindof(.cxx_method_decl) && !child.is_implicit && child.explicitly_defaulted == ''
			&& child.name != '' {
			method_base_name := method_base_name_from_cpp_name(child.name)
			if child.class_modifier == 'static' {
				c.register_cpp_static_method_decl_name(struct_v_name, method_base_name, child)
			} else {
				c.register_cpp_method_decl_name(struct_v_name, method_base_name, child)
			}
		}
	}
	is_abstract := c.cpp_record_is_abstract_interface(node)
	if is_abstract {
		c.cpp_abstract_types[struct_v_name] = true
	}
	for child in node.inner {
		if child.kindof(.var_decl) && child.class_modifier == 'static' {
			static_type := c.convert_type(node_effective_type_name(child))
			c.register_cpp_static_member_v_name(name, child.name, static_type.is_const, child.id)
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
	// can use aliases such as idCommon::FunctionPointer, as well as private helper
	// layouts/constants such as idMath::_flint and LOOKUP_BITS.
	for child in node.inner {
		if child.kindof(.typedef_decl) {
			c.typedef_decl(child)
		}
	}
	for child in node.inner {
		if child.kindof(.enum_decl) {
			mut enum_node := child
			c.enum_decl(mut enum_node)
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
	// Generate the interface or concrete struct fields.
	mut new_struct := Struct{}
	new_struct.fields << flattened_base_fields
	new_struct.field_types << flattened_base_field_types
	mut method_field_collisions := map[string]bool{}
	for child in node.inner {
		if child.kindof(.cxx_method_decl) && child.name != '' {
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
			filter_name(child.name, false).all_after_last('.').camel_to_snake().trim_left('_')
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
		if struct_v_name.starts_with('IdList_') && field_name == 'list'
			&& field_type.starts_with('&') {
			element_type := normalize_v_ptr_type(field_type)
			if element_type in c.cpp_abstract_types {
				// V cannot index a raw pointer to an interface descriptor. The save
				// rewrite lowers this idList specialization to managed []Interface
				// storage while retaining its C++ size/granularity surface.
				c.cpp_interface_idlist_elements[struct_v_name] = element_type
			}
		}
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
			c.genln('${record_keyword} ${struct_v_name} {')
			for base_name in base_embeds {
				// Preserve concrete single-inheritance surface via V embedding, so
				// derived instances can access inherited fields and methods.
				c.genln('\t${base_name}')
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
		for child in node.inner {
			if child.kindof(.cxx_method_decl) && !child.is_pure {
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
			} else if child.kindof(.cxx_method_decl) && !child.is_pure {
				c.cxx_method_decl(child)
			}
		}
		return
	}
	// Process constructors, destructors, and methods defined inline
	for child in node.inner {
		if child.kindof(.cxx_constructor_decl) {
			if child.is_implicit || child.explicitly_defaulted != '' {
				continue
			}
			// Skip implicit copy/move constructors generated by the compiler. An
			// ordinary out-of-class inline definition also has `previousDecl`, so that
			// metadata alone must not suppress real constructor bodies.
			if child.ast_type.qualified.contains('const ${name} &')
				|| child.ast_type.qualified.contains('${name} &&') {
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
		} else if child.kindof(.cxx_method_decl) {
			if child.is_implicit || child.explicitly_defaulted != '' {
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
	c.declared_local_vars.clear()
	c.declared_local_var_types.clear()
	c.local_decl_v_names.clear()
	c.for_init_vars.clear()
	c.conditional_mutable_locals = {}
	mut node := unsafe { _node }
	if node.is_implicit || node.explicitly_defaulted != '' {
		return
	}
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
	if !has_body && !c.should_emit_skeleton_body_for_node(node) {
		return
	}
	params := c.fn_params(mut node, false)
	str_args := params.join(', ')
	// Use 'init' for default constructors, 'init{N}' for parameterized constructors
	// to avoid V's duplicate method error (V doesn't support overloading).
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
	c.genln('fn (mut this ${receiver_type}) ${init_name}(${str_args}) {')
	if c.should_emit_skeleton_body_for_node(node) {
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

	collect_conditional_mutable_decl_refs(stmts, false, mut c.conditional_mutable_locals)
	c.st_block_no_start(mut stmts)
	c.genln('')
}

// CBattleAnimation::~CBattleAnimation()
fn (mut c C2V) destructor_decl(_node &Node) {
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
	mut dtor_name := 'free'
	if c.class_has_method_base(receiver_type, dtor_name)
		|| c.class_inherits_method_base(receiver_type, dtor_name) {
		dtor_name = 'dtor'
	}
	dtor_name = c.reserve_method_name(receiver_type, dtor_name)
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
// e.g. "_ZN11idMoveState4SaveE..." -> "idMoveState"
// e.g. "_ZNK4idAI4SaveE..." -> "idAI"
// e.g. "__ZN6idListIP5idStrE4SortE..." -> "idList<idStr *>"
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
	// `free` is a reserved special method in V and must have zero args.
	// Rename regular C++ methods named Free(...) to avoid parser errors.
	if name == 'free' {
		name = 'free_'
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

fn (c &C2V) cxx_method_body_mutates_receiver(node Node) bool {
	if (node.kindof(.binary_operator) || node.kindof(.compound_assign_operator))
		&& node.inner.len > 0
		&& node.opcode in ['=', '+=', '-=', '*=', '/=', '%=', '&=', '|=', '^=', '<<=', '>>='] {
		return cxx_lhs_mutates_receiver(node.inner[0])
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
	if node.kindof(.unary_operator) && node.opcode in ['++', '--'] && node.inner.len > 0 {
		return cxx_lhs_mutates_receiver(node.inner[0])
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
	if underlying := c.type_aliases[base_type] {
		if underlying.starts_with('fn (') {
			return pointer_prefix + underlying
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
	for node in c.tree.inner {
		c.collect_cpp_class_method_bases_from_node(&node)
	}
	// Constructor calls can precede their out-of-class definitions. Reserve the
	// exact signature/name mapping before rendering any function bodies so those
	// calls invoke the real translated initializer rather than a positional V
	// struct literal.
	for node in c.tree.inner {
		c.collect_cpp_constructor_signatures(node, '')
	}
}

fn (mut c C2V) collect_cpp_constructor_signatures(node Node, enclosing_class string) {
	mut class_name := enclosing_class
	if node.kindof(.cxx_record_decl) && node.name != '' {
		class_name = c.add_struct_name(mut c.types, node.name)
	}
	if node.kindof(.cxx_constructor_decl) && !node.is_implicit
		&& node.explicitly_defaulted == '' && node.has_child_of_kind(.compound_stmt) {
		mut receiver_type := class_name
		if receiver_type == '' && node.mangled_name != '' {
			receiver_type = c.add_struct_name(mut c.types, extract_class_from_mangled(node.mangled_name))
		}
		constructor_key := cpp_constructor_signature_key(receiver_type, node.ast_type.qualified)
		c_param_types := cpp_constructor_c_param_types(node.ast_type.qualified)
		is_copy_or_move := c_param_types.len == 1
			&& normalize_cpp_operator_type_name(c.convert_type(c_param_types[0]).name) == receiver_type
		if constructor_key != '' && !is_copy_or_move
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
	for child in node.inner {
		c.collect_cpp_constructor_signatures(child, class_name)
	}
}

fn (mut c C2V) collect_cpp_class_method_bases_from_node(node &Node) {
	if node.kindof(.cxx_record_decl) && node.name != '' {
		class_name := c.add_struct_name(mut c.types, node.name)
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
			for child in node.inner {
				if !child.kindof(.cxx_method_decl) || child.name == '' {
					continue
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
	for child in node.inner {
		c.collect_cpp_class_method_bases_from_node(&child)
	}
}

fn (c &C2V) is_cpp_static_method(node &Node) bool {
	if node.class_modifier == 'static' || node.mangled_name in c.cpp_static_method_symbols {
		return true
	}
	if node.mangled_name == '' {
		return false
	}
	for record in c.tree.inner {
		if !record.kindof(.cxx_record_decl) {
			continue
		}
		for declaration in record.inner {
			if declaration.kindof(.cxx_method_decl) && declaration.class_modifier == 'static'
				&& declaration.mangled_name == node.mangled_name {
				return true
			}
		}
	}
	return false
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
		// `idWinVar::Init(...)`, including when the derived class overrides Init.
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
	method_template := clone_cpp_operator_node(_node)
	c.declared_local_vars.clear()
	c.declared_local_var_types.clear()
	c.local_decl_v_names.clear()
	c.for_init_vars.clear()
	c.conditional_mutable_locals = {}
	mut node := unsafe { _node }
	c.current_fn_uses_va_arg = node_contains_kind(node, .va_arg_expr)
	is_static := c.is_cpp_static_method(node)
	name := node.name
	if node.is_implicit || node.explicitly_defaulted != '' {
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
		ret_type = ' ' + c.prefix_external_type(c.convert_type(ret_type).name)
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
			// such as idList<idStr>. Route it through the normal type converter
			// before reserving the receiver name; add_struct_name alone would keep
			// angle brackets and reject the otherwise valid V method.
			receiver_name := c.convert_type(extracted).name
			class_name = c.add_struct_name(mut c.types, receiver_name)
		}
	}
	if class_name == '' {
		return
	}
	if !is_valid_v_receiver_type_name(class_name) {
		return
	}
	has_body := node.has_child_of_kind(.compound_stmt)
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
	returns_nonconst_reference := node.ast_type.qualified.before('(').trim_space().ends_with('&')
	receiver_mut := if method_is_const
		|| (!returns_nonconst_reference && !c.cxx_method_body_mutates_receiver(node)) {
		''
	} else {
		'mut '
	}
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
	if is_static {
		c.genln('fn ${v_method_name}(${str_args})${ret_type} {')
	} else {
		c.genln('fn (${receiver_mut}this ${class_name}) ${v_method_name}(${str_args})${ret_type} {')
	}
	if emit_compat_stub || c.should_emit_skeleton_body_for_node(node) || !has_body {
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

	old_cur_fn_ret_type := c.cur_fn_ret_type
	c.cur_fn_ret_type = ret_type.trim_space()
	collect_conditional_mutable_decl_refs(stmts, false, mut c.conditional_mutable_locals)
	c.statements(mut stmts)
	c.cur_fn_ret_type = old_cur_fn_ret_type
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

fn cpp_operator_is_idstr_type(type_name string) bool {
	base := normalize_cpp_operator_type_name(type_name)
	return base in ['IdStr', 'IdToken', 'IdPoolStr']
}

fn cpp_operator_is_char_type(type_name string) bool {
	base := normalize_cpp_operator_type_name(type_name)
	return base in ['i8', 'u8']
}

fn (mut c C2V) try_gen_cpp_idstr_comparison(v_op string, lhs &Node, rhs &Node) bool {
	if v_op !in ['==', '!='] {
		return false
	}
	lhs_type := c.operator_node_v_type(lhs)
	rhs_type := c.operator_node_v_type(rhs)
	lhs_is_str := cpp_operator_is_idstr_type(lhs_type)
	rhs_is_str := cpp_operator_is_idstr_type(rhs_type)
	if !(lhs_is_str && (rhs_is_str || cpp_operator_is_char_type(rhs_type))) && !(rhs_is_str
		&& cpp_operator_is_char_type(lhs_type)) {
		return false
	}
	if lhs_is_str {
		c.gen_cpp_operator_receiver(lhs)
		c.gen('.cmp(')
		if rhs_is_str {
			c.gen_cpp_operator_receiver(rhs)
			c.gen('.c_str()')
		} else {
			c.expr(rhs)
		}
	} else {
		c.gen_cpp_operator_receiver(rhs)
		c.gen('.cmp(')
		c.expr(lhs)
	}
	c.gen(if v_op == '==' { ') == 0' } else { ') != 0' })
	return true
}

fn (mut c C2V) try_gen_cpp_idstr_plus_text(lhs &Node, rhs &Node) bool {
	lhs_type := c.convert_type(node_effective_type_name(*lhs)).name.trim_space()
	rhs_type := c.convert_type(node_effective_type_name(*rhs)).name.trim_space()
	lhs_is_idstr := normalize_cpp_operator_type_name(lhs_type) == 'IdStr'
	rhs_is_idstr := normalize_cpp_operator_type_name(rhs_type) == 'IdStr'
	if lhs_is_idstr && rhs_is_idstr {
		c.ensure_cpp_idstr_construct_helper()
		helper_key := 'cpp_idstr_plus_idstr_helper:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_idstr_plus_idstr(left IdStr, right IdStr) IdStr {\n\tmut result := c2v_construct_id_str(left.c_str())\n\tresult.op_plus_assign(&right)\n\treturn result\n}\n\n'
		}
		c.gen('c2v_idstr_plus_idstr(')
		c.gen_cxx_construct_value(lhs, 'IdStr')
		c.gen(', ')
		c.gen_cxx_construct_value(rhs, 'IdStr')
		c.gen(')')
		return true
	}
	if lhs_is_idstr && rhs_type.starts_with('&i8') {
		c.ensure_cpp_idstr_construct_helper()
		helper_key := 'cpp_idstr_plus_text_helper:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_idstr_plus_text(left IdStr, right &i8) IdStr {\n\tmut result := c2v_construct_id_str(left.c_str())\n\tresult.op_plus_assign2(right)\n\treturn result\n}\n\n'
		}
		c.gen('c2v_idstr_plus_text(')
		c.gen_cxx_construct_value(lhs, 'IdStr')
		c.gen(', ')
		c.gen_call_arg(*rhs, 'const char *', false)
		c.gen(')')
		return true
	}
	if lhs_is_idstr && cpp_operator_is_char_type(rhs_type) {
		c.ensure_cpp_idstr_construct_helper()
		helper_key := 'cpp_idstr_plus_char_helper:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_idstr_plus_char(left IdStr, right i8) IdStr {\n\tmut result := c2v_construct_id_str(left.c_str())\n\tresult.op_plus_assign4(right)\n\treturn result\n}\n\n'
		}
		c.gen('c2v_idstr_plus_char(')
		c.gen_cxx_construct_value(lhs, 'IdStr')
		c.gen(', i8(')
		c.expr(rhs)
		c.gen('))')
		return true
	}
	if lhs_type.starts_with('&i8') && rhs_is_idstr {
		c.ensure_cpp_idstr_construct_helper()
		helper_key := 'cpp_text_plus_idstr_helper:${os.dir(c.outv)}'
		if helper_key !in c.generated_declarations {
			c.generated_declarations[helper_key] = true
			c.local_type_declarations << 'fn c2v_text_plus_idstr(left &i8, right IdStr) IdStr {\n\tmut result := c2v_construct_id_str(left)\n\tresult.op_plus_assign(&right)\n\treturn result\n}\n\n'
		}
		c.gen('c2v_text_plus_idstr(')
		c.gen_call_arg(*lhs, 'const char *', false)
		c.gen(', ')
		c.gen_cxx_construct_value(rhs, 'IdStr')
		c.gen(')')
		return true
	}
	return false
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

fn (c &C2V) should_reverse_operator_method_for_binary(v_method string, lhs &Node, rhs &Node) bool {
	if v_method !in ['op_plus', 'op_mul'] {
		return false
	}
	lhs_type := c.operator_node_v_type(lhs)
	rhs_type := c.operator_node_v_type(rhs)
	if lhs_type == '' || rhs_type == '' {
		return false
	}
	return (is_cpp_operator_primitive_type(lhs_type) || is_cpp_operator_literal_operand(lhs))
		&& !is_cpp_operator_primitive_type(rhs_type) && !is_cpp_operator_literal_operand(rhs)
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

fn (c &C2V) should_reverse_free_operator_method_for_exact_overload(decl_ref_expr &Node, v_method string, lhs &Node, rhs &Node) bool {
	if decl_ref_expr.ref_declaration.kind != .function_decl || v_method !in ['op_plus', 'op_mul'] {
		return false
	}
	lhs_type := c.operator_node_v_type(lhs)
	rhs_type := c.operator_node_v_type(rhs)
	if lhs_type == '' || rhs_type == '' {
		return false
	}
	return c.exact_cpp_method_overload_for_argument(lhs_type, v_method, rhs_type) == ''
		&& c.exact_cpp_method_overload_for_argument(rhs_type, v_method, lhs_type) != ''
}

fn cpp_compound_operator_value_method(method_name string) string {
	return match method_name {
		'op_plus_assign' { 'op_plus' }
		'op_minus_assign' { 'op_minus' }
		'op_mul_assign' { 'op_mul' }
		'op_div_assign' { 'op_div' }
		else { '' }
	}
}

fn (c &C2V) cpp_operator_reference_local_type(node &Node) string {
	base := unwrap_cpp_operator_operand(node)
	if !base.kindof(.decl_ref_expr) {
		return ''
	}
	v_name := c.decl_ref_v_name(*base)
	return c.declared_local_var_types[v_name] or { '' }
}

fn (mut c C2V) gen_cpp_free_compound_assignment_lhs(lhs &Node) bool {
	if c.cpp_operator_reference_local_type(lhs).starts_with('&') {
		c.gen('unsafe { *')
		c.expr(lhs)
		c.gen(' = ')
		return true
	}
	c.expr(lhs)
	c.gen(' = ')
	return false
}

fn (mut c C2V) try_gen_cpp_free_compound_operator(decl_ref_expr &Node, method_name string, lhs &Node, rhs &Node) bool {
	if decl_ref_expr.ref_declaration.kind != .function_decl {
		return false
	}
	value_method := cpp_compound_operator_value_method(method_name)
	if value_method == '' {
		return false
	}
	lhs_type := c.operator_node_v_type(lhs)
	rhs_type := c.operator_node_v_type(rhs)
	if lhs_type == '' || rhs_type == '' {
		return false
	}
	lhs_value_method := c.exact_cpp_method_overload_for_argument(lhs_type, value_method, rhs_type)
	rhs_value_method := if value_method in ['op_plus', 'op_mul'] {
		c.exact_cpp_method_overload_for_argument(rhs_type, value_method, lhs_type)
	} else {
		''
	}
	if lhs_value_method == '' && rhs_value_method == '' {
		return false
	}
	mut lhs_assignment := clone_cpp_operator_node(lhs)
	mut lhs_receiver := clone_cpp_operator_node(lhs)
	mut lhs_arg := clone_cpp_operator_node(lhs)
	mut rhs_receiver := clone_cpp_operator_node(rhs)
	mut rhs_arg := clone_cpp_operator_node(rhs)
	close_unsafe := c.gen_cpp_free_compound_assignment_lhs(&lhs_assignment)
	if lhs_value_method != '' {
		param_type := c.exact_cpp_method_parameter_type(lhs_type, value_method, rhs_type)
		c.gen_cpp_operator_receiver(&lhs_receiver)
		c.gen('.${lhs_value_method}(')
		c.gen_call_arg(rhs_arg, param_type, false)
	} else {
		param_type := c.exact_cpp_method_parameter_type(rhs_type, value_method, lhs_type)
		c.gen_cpp_operator_receiver(&rhs_receiver)
		c.gen('.${rhs_value_method}(')
		c.gen_call_arg(lhs_arg, param_type, false)
	}
	c.gen(')')
	if close_unsafe {
		c.gen(' }')
	}
	return true
}

fn (mut c C2V) gen_cpp_operator_receiver(node &Node) {
	if is_cpp_dereferenced_this_expr(node) {
		c.gen('this')
		return
	}
	base := unwrap_cpp_operator_operand(node)
	if base.kindof(.decl_ref_expr) || base.kindof(.cxx_this_expr) {
		c.expr(node)
		return
	}
	c.gen('(')
	c.expr(node)
	c.gen(')')
}

fn is_cpp_dereferenced_this_expr(node &Node) bool {
	mut current := unwrap_cpp_operator_operand(node)
	if !current.kindof(.unary_operator) || current.opcode != '*' || current.inner.len == 0 {
		return false
	}
	current = unwrap_cpp_operator_operand(unsafe { &current.inner[0] })
	return current.kindof(.cxx_this_expr)
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
			if v_method != '' && !operand_is_primitive {
				c.gen_cpp_operator_receiver(operand)
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
			old_inside_unsafe := c.inside_unsafe
			if read_primitive_reference {
				if !old_inside_unsafe {
					c.gen('unsafe { ')
					c.inside_unsafe = true
				}
				c.gen('*(')
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
				&& decl_ref_expr.ref_declaration.id in c.cpp_method_decl_names
				&& c.should_use_operator_method_for_binary(method_base_name, lhs, rhs) {
				declaration_params := function_type_params(typ)
				param_type := if declaration_params.len > 0 {
					declaration_params.last()
				} else {
					''
				}
				c.gen_cpp_operator_receiver(lhs)
				c.gen('.${v_method}(')
				c.gen_call_arg(rhs, param_type, false)
				c.gen(')')
			} else if v_op == '=' {
				mut lhs_assign := lhs
				mut rhs_assign := rhs
				c.gen_simple_assign(mut lhs_assign, mut rhs_assign)
			} else if c.try_gen_cpp_idstr_comparison(v_op, lhs, rhs) {
			} else if v_op == '+' && c.try_gen_cpp_idstr_plus_text(lhs, rhs) {
			} else if c.try_gen_cpp_free_compound_operator(decl_ref_expr, method_base_name, lhs, rhs) {
			} else if method_base_name != ''
				&& (c.should_reverse_operator_method_for_binary(method_base_name, lhs, rhs)
					|| c.should_reverse_free_operator_method_for_exact_overload(decl_ref_expr, method_base_name, lhs, rhs)) {
				call_method := c.cpp_method_overload_for_argument(c.operator_node_v_type(rhs), method_base_name, c.operator_node_v_type(lhs))
				param_type := c.exact_cpp_method_parameter_type(c.operator_node_v_type(rhs), method_base_name, c.operator_node_v_type(lhs))
				c.gen_cpp_operator_receiver(rhs)
				c.gen('.${call_method}(')
				c.gen_call_arg(lhs, param_type, false)
				c.gen(')')
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
				c.gen_cpp_operator_receiver(lhs)
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
