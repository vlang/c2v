// This code handles C++ -> V translation
module main

fn (mut c C2V) cpp_top_level(mut node Node) bool {
	println('C++ top level')

	if node.kindof(.namespace_decl) {
		for child in node.inner {
			c.top_level(child)
		}
	} else if node.kindof(.cxx_constructor_decl) {
		c.constructor_decl(mut node)
	} else if node.kindof(.cxx_destructor_decl) {
	} else if node.kindof(.original) {
	} else if node.kindof(.using_decl) {
	} else if node.kindof(.using_shadow_decl) {
	} else if node.kindof(.class_template_decl) {
		c.class_template_decl(node)
	} else if node.kindof(.class_template_specialization_decl) {
	} else if node.kindof(.cxx_record_decl) {
	} else if node.kindof(.linkage_spec_decl) {
	} else if node.kindof(.using_directive_decl) {
	} else if node.kindof(.class_template_partial_specialization_decl) {
	} else if node.kindof(.function_template_decl) {
		c.fn_template_decl(mut node)
	} else if node.kindof(.cxx_method_decl) {
		c.cxx_method_decl(mut node)
	} else {
		return false
	}
	return true
}

fn (mut c C2V) cpp_expr(mut node Node) bool {
	vprintln('C++ expr check')
	vprintln(node.ast_type.str())
	// std::vector<int> a;    OR
	// User u(34);
	if node.kindof(.cxx_construct_expr) {
		c.genln('// cxx cons')
		typ := node.ast_type.qualified // get_val(-2)
		if typ.contains('<int>') {
			c.gen('int')
		}
	} else if node.kindof(.cxx_member_call_expr) {
		mut member_expr := node.try_get_next_child_of_kind(.member_expr) or {
			println(err)
			bad_node
		}

		method_name := member_expr.name // get_val(-2)
		child := member_expr.try_get_next_child() or {
			println(err)
			bad_node
		}
		c.expr(child)
		mut add_par := false
		match method_name {
			'.push_back' {
				c.gen(' << ')
			}
			'.size' {
				c.gen('.len')
			}
			else {
				add_par = true
				method := method_name.replace('->', '.')
				c.gen('${method}(')
			}
		}
		mut mat_tmp_expr := node.try_get_next_child() or {
			println(err)
			bad_node
		}
		if mat_tmp_expr.kindof(.materialize_temporary_expr) {
			expr := mat_tmp_expr.try_get_next_child() or {
				println(err)
				bad_node
			}
			c.expr(expr)
		}
		if add_par {
			c.gen(')')
		}
	}
	// operator call (std::cout << etc)
	else if node.kindof(.cxx_operator_call_expr) {
		c.operator_call(mut node)
	}
	// std::string s = "HI";
	else if node.kindof(.expr_with_cleanups) {
		vprintln('expr with cle')
		typ := node.ast_type.qualified // get_val(-1)
		vprintln('TYP=${typ}')
		if typ.contains('basic_string<') {
			// All this for a simple std::string = "hello";
			mut construct_expr := node.try_get_next_child_of_kind(.cxx_construct_expr) or {
				println(err)
				bad_node
			}

			mut mat_tmp_expr := construct_expr.try_get_next_child_of_kind(.materialize_temporary_expr) or {
				println(err)
				bad_node
			}

			mut cast_expr := mat_tmp_expr.try_get_next_child() or {
				println(err)
				bad_node
			}
			if !cast_expr.kindof(.implicit_cast_expr) {
				return true
			}
			mut bind_tmp_expr := cast_expr.try_get_next_child_of_kind(.cxx_bind_temporary_expr) or {
				println(err)
				bad_node
			}

			mut cast_expr2 := bind_tmp_expr.try_get_next_child_of_kind(.implicit_cast_expr) or {
				println(err)
				bad_node
			}

			mut construct_expr2 := cast_expr2.try_get_next_child_of_kind(.cxx_construct_expr) or {
				println(err)
				bad_node
			}

			mut cast_expr3 := construct_expr2.try_get_next_child_of_kind(.implicit_cast_expr) or {
				println(err)
				bad_node
			}

			str_lit := cast_expr3.try_get_next_child_of_kind(.string_literal) or {
				println(err)
				bad_node
			}

			c.gen(str_lit.value) // get_val(-1))
		}
	} else if node.kindof(.unresolved_lookup_expr) {
	} else if node.kindof(.cxx_try_stmt) {
	} else if node.kindof(.cxx_throw_expr) {
	} else if node.kindof(.cxx_dynamic_cast_expr) {
		v_type := convert_type(node.ast_type.qualified) // get_val(2))
		dtyp := v_type.name.replace('* ', '&')
		c.gen('${dtyp}( ')
		child := node.try_get_next_child() or {
			println(err)
			bad_node
		}
		c.expr(child)
		c.gen(')')
	} else if node.kindof(.cxx_reinterpret_cast_expr) {
	} else if node.kindof(.cxx_unresolved_construct_expr) {
	} else if node.kindof(.cxx_dependent_scope_member_expr) {
	} else if node.kindof(.cxx_this_expr) {
		c.gen('this')
	} else if node.kindof(.cxx_bool_literal_expr) {
		val := node.value // get_val(-1)
		c.gen(val)
	} else if node.kindof(.cxx_null_ptr_literal_expr) {
		c.gen('nullptr')
	} else if node.kindof(.cxx_functional_cast_expr) {
	} else if node.kindof(.cxx_delete_expr) {
	}
	// static_cast<int>(a)
	else if node.kindof(.cxx_static_cast_expr) {
		c.gen('(${node.ast_type.qualified})(')
		expr := node.try_get_next_child() or {
			println(err)
			bad_node
		}
		c.expr(expr)
		c.gen(')')
	} else if node.kindof(.materialize_temporary_expr) {
	} else if node.kindof(.cxx_temporary_object_expr) {
	} else if node.kindof(.decl_stmt) {
		// TODO WTF
	} else if node.kindof(.cxx_new_expr) {
	} else {
		return false
	}
	return true
}

fn (mut c C2V) fn_template_decl(mut node Node) {
	// build "<T, K>"
	mut types := '<'
	nr_types := node.count_children_of_kind(.template_type_parm_decl)
	for i := 0; i < nr_types; i++ {
		t := node.try_get_next_child_of_kind(.template_type_parm_decl) or {
			println(err)
			bad_node
		}

		types += t.ast_type.qualified // get_val(-1)
		if i != nr_types - 1 {
			types += ', '
		}
	}
	types = types + '>'
	// First child fn decl is with <T>
	mut children := node.find_children(.function_decl)
	for mut fn_node in children {
		c.fn_decl(mut fn_node, '') // types)
	}
}

fn (mut c C2V) class_template_decl(node &Node) {
	c.genln('CLASS ${node.name}')
}

// CBattleAnimation::CBattleAnimation()
fn (mut c C2V) constructor_decl(mut node Node) {
	v_typ := convert_type(node.ast_type.qualified)
	str_args := c.fn_params(mut node)
	c.genln('fn new_${node.name}(${str_args}) ${v_typ.name} {')
	// User::User() :  field1(val1), field2(val2)
	nr_ctor_inits := node.count_children_of_kind(.cxx_ctor_initializer)
	for i := 0; i < nr_ctor_inits; i++ {
		mut init := node.try_get_next_child_of_kind(.cxx_ctor_initializer) or {
			println(err)
			bad_node
		}

		expr := init.try_get_next_child() or {
			println(err)
			bad_node
		}
		c.expr(expr)
		c.genln('')
	}
	mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
		println(err)
		bad_node
	}

	c.st_block_no_start(mut stmts)
	c.genln('')
}

fn (mut c C2V) cxx_method_decl(mut node Node) {
	v_typ := convert_type(node.ast_type.qualified)
	str_args := c.fn_params(mut node)
	c.genln('fn (this typ) ${node.name}(${str_args}) ${v_typ.name} {')
	if node.has_child_of_kind(.overrides) {
		node.try_get_next_child_of_kind(.overrides) or {
			println(err)
			bad_node
		}
	}
	mut stmts := node.try_get_next_child_of_kind(.compound_stmt) or {
		println(err)
		bad_node
	}

	c.statements(mut stmts)
}

// std::cout << etc
fn (mut c C2V) operator_call(mut node Node) {
	mut cast_expr := node.try_get_next_child() or {
		println(err)
		bad_node
	}
	if !cast_expr.kindof(.implicit_cast_expr) {
		c.genln('OP@@')
		return
	}
	decl_ref_expr := cast_expr.try_get_next_child_of_kind(.decl_ref_expr) or {
		println(err)
		bad_node
	}

	typ := decl_ref_expr.ast_type.qualified // get_val(-1)
	op := decl_ref_expr.opcode // get_val(-2)
	mut add_par := false
	if op == 'operator<<' && typ.contains('basic_ostream') {
		c.gen('println(')
		add_par = true
	} else {
		// c.gen('op1 $op op2')
	}

	expr := node.try_get_next_child() or {
		println(err)
		bad_node
	}

	c.expr(expr)
	if add_par {
		c.gen(')')
	}
}

fn (mut c C2V) for_range(node &Node) {
	mut last_inner_node := node.inner.last()
	generate_for_loop(mut c, mut last_inner_node)
}

fn generate_for_loop(mut c C2V, mut body_content Node) {
	c.genln('for val in vals {')
	c.st_block_no_start(mut body_content)
}
