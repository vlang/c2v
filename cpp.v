module main

fn (mut c C2V) cpp_top_level(_node &Node) bool {
	println('C++ top level')
	mut node := unsafe { _node }
	if node.iss(.NamespaceDecl) {
		for child in node.inner {
			c.top_level(child)
		}
	} else if node.iss(.CXXConstructorDecl) {
		c.constructor_decl(node)
	} else if node.iss(.CXXDestructorDecl) {
		c.destructor_decl(node)
	} else if node.iss(.original) {
	} else if node.iss(.UsingDecl) {
	} else if node.iss(.UsingShadowDecl) {
	} else if node.iss(.ClassTemplateDecl) {
		c.class_template_decl(node)
	} else if node.iss(.ClassTemplateSpecializationDecl) {
	} else if node.iss(.CXXRecordDecl) {
	} else if node.iss(.LinkageSpecDecl) {
	} else if node.iss(.UsingDirectiveDecl) {
	} else if node.iss(.ClassTemplatePartialSpecializationDecl) {
	} else if node.iss(.FunctionTemplateDecl) {
		c.fn_template_decl(node)
	} else if node.iss(.CXXMethodDecl) {
		c.cxx_method_decl(node)
	} else {
		return false
	}
	return true
}

fn (mut c C2V) cpp_expr(_node &Node) bool {
	mut node := unsafe { _node }
	vprintln('C++ expr check')
	// println(node.vals)
	vprintln(node.typ.str())
	// std::vector<int> a;    OR
	// User u(34);
	if node.iss(.CXXConstructExpr) {
		// println(node.vals)
		// c.genln(node.vals.str())
		c.genln('// cxx cons')
		typ := node.typ.q // get_val(-2)
		if typ.contains('<int>') {
			c.gen('int')
		}
	} else if node.iss(.CXXMemberCallExpr) {
		// c.gen('[CXX MEMBER] ')
		mut member_expr := node.get(.MemberExpr)
		method_name := member_expr.name // get_val(-2)
		child := member_expr.get2()
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
		mut mat_tmp_expr := node.get2()
		if mat_tmp_expr.iss(.MaterializeTemporaryExpr) {
			expr := mat_tmp_expr.get2()
			c.expr(expr)
		}
		if add_par {
			c.gen(')')
		}
	}
	// operator call (std::cout << etc)
	else if node.iss(.CXXOperatorCallExpr) {
		c.operator_call(node)
	}
	// std::string s = "HI";
	else if node.iss(.ExprWithCleanups) {
		vprintln('expr with cle')
		typ := node.typ.q // get_val(-1)
		vprintln('TYP=$typ')
		if typ.contains('basic_string<') {
			// All this for a simple std::string = "hello";
			mut construct_expr := node.get(.CXXConstructExpr)
			mut mat_tmp_expr := construct_expr.get(.MaterializeTemporaryExpr)
			// cast_expr := mat_tmp_expr.get(ImplicitCastExpr)
			mut cast_expr := mat_tmp_expr.get2()
			if !cast_expr.iss(.ImplicitCastExpr) {
				return true
			}
			mut bind_tmp_expr := cast_expr.get(.CXXBindTemporaryExpr)
			mut cast_expr2 := bind_tmp_expr.get(.ImplicitCastExpr)
			mut construct_expr2 := cast_expr2.get(.CXXConstructExpr)
			mut cast_expr3 := construct_expr2.get(.ImplicitCastExpr)
			str_lit := cast_expr3.get(.StringLiteral)
			c.gen(str_lit.value) // get_val(-1))
		}
	} else if node.iss(.UnresolvedLookupExpr) {
	} else if node.iss(.CXXTryStmt) {
	} else if node.iss(.CXXThrowExpr) {
	} else if node.iss(.CXXDynamicCastExpr) {
		typ_ := convert_type(node.typ.q) // get_val(2))
		mut dtyp := typ_.name
		dtyp = dtyp.replace('* ', '&')
		c.gen('${dtyp}( ')
		child := node.get2()
		c.expr(child)
		c.gen(')')
	} else if node.iss(.CXXReinterpretCastExpr) {
	} else if node.iss(.CXXUnresolvedConstructExpr) {
	} else if node.iss(.CXXDependentScopeMemberExpr) {
	} else if node.iss(.CXXThisExpr) {
		c.gen('this')
	} else if node.iss(.CXXBoolLiteralExpr) {
		val := node.value // get_val(-1)
		c.gen(val)
	} else if node.iss(.CXXNullPtrLiteralExpr) {
		c.gen('nullptr')
	} else if node.iss(.CXXFunctionalCastExpr) {
	} else if node.iss(.CXXDeleteExpr) {
	}
	// static_cast<int>(a)
	else if node.iss(.CXXStaticCastExpr) {
		typ := node.typ.q // get_val(0)
		// v := node.vals.join(' ')
		c.gen('($typ)(')
		expr := node.get2()
		c.expr(expr)
		c.gen(')')
	} else if node.iss(.MaterializeTemporaryExpr) {
	} else if node.iss(.CXXTemporaryObjectExpr) {
	} else if node.iss(.DeclStmt) {
		// TODO WTF
	} else if node.iss(.CXXNewExpr) {
	} else {
		return false
	}
	return true
}

fn (mut c C2V) fn_template_decl(node &Node) {
	// name := node.get_val(- 1)
	// build "<T, K>"
	mut types := '<'
	nr_types := node.nr_children(.TemplateTypeParmDecl)
	for i := 0; i < nr_types; i++ {
		t := node.get(.TemplateTypeParmDecl)
		types += t.typ.q // get_val(-1)
		if i != nr_types - 1 {
			types += ', '
		}
	}
	types = types + '>'
	// First child fn decl is with <T>
	// fn_node := node.get(.FunctionDecl)
	mut children := node.find_children(.FunctionDecl)
	for mut fn_node in children {
		// fn_node2 := node.get(FunctionDecl)
		c.fn_decl(fn_node, '') // types)
	}
}

fn (mut c C2V) class_template_decl(node &Node) {
	// mut node := _node
	name := node.name // get_val(-1)
	c.genln('CLASS $name')
}

// CBattleAnimation::CBattleAnimation()
fn (mut c C2V) constructor_decl(_node &Node) {
	mut node := unsafe { _node }
	// nt := get_name_type(node)
	name := node.name
	typ := convert_type(node.typ.q)
	str_args := c.fn_params(node)
	c.genln('fn new_${name}($str_args) $typ.name {')
	// User::User() :  field1(val1), field2(val2)
	nr_ctor_inits := node.nr_children(.CXXCtorInitializer)
	for i := 0; i < nr_ctor_inits; i++ {
		mut init := node.get(.CXXCtorInitializer)
		expr := init.get2()
		c.expr(expr)
		c.genln('')
	}
	mut stmts := node.get(.CompoundStmt)
	c.st_block_no_start(stmts)
	c.genln('')
}

// CBattleAnimation::~CBattleAnimation()
fn (mut c C2V) destructor_decl(node &Node) {
}

fn (mut c C2V) cxx_method_decl(_node &Node) {
	mut node := unsafe { _node }
	name := node.name
	typ := convert_type(node.typ.q)
	str_args := c.fn_params(node)
	c.genln('fn (this typ) ${name}($str_args) $typ.name {')
	if node.has(.Overrides) {
		node.get(.Overrides)
	}
	mut stmts := node.get(.CompoundStmt)
	c.statements(stmts)
}

// std::cout << etc
fn (mut c C2V) operator_call(_node &Node) {
	mut node := unsafe { _node }
	// cast_expr := node.get(ImplicitCastExpr)
	mut cast_expr := node.get2()
	if !cast_expr.iss(.ImplicitCastExpr) {
		c.genln('OP@@')
		return
	}
	decl_ref_expr := cast_expr.get(.DeclRefExpr)
	// vprintln('\n CXX OPERATOR DRE')
	// vprintln(decl_ref_expr.vals)
	typ := decl_ref_expr.typ.q // get_val(-1)
	op := decl_ref_expr.opcode // get_val(-2)
	mut add_par := false
	if op == 'operator<<' && typ.contains('basic_ostream') {
		c.gen('println(')
		add_par = true
	} else {
		// c.gen('op1 $op op2')
	}
	// vprintln('op="$op"')
	// decl_ref_expr2 := node.get(DeclRefExpr)
	// expr := decl_ref_expr2.get2()
	// expr := node.get2()
	expr := node.get2()
	// vprintln('<< EXPR $expr.typ')
	// vprintln(expr.vals)
	c.expr(expr)
	if add_par {
		c.gen(')')
	}
}

fn (mut c C2V) for_range(node &Node) {
	// mut node := unsafe { _node }
	// decl := node.get(DeclStmt)
	mut stmt := node.inner.last()
	// decls := node.find_children(DeclStmt)
	// decl:=decls.last()
	// var_name :=  j
	c.genln('for val in vals {')
	c.st_block_no_start(stmt)
}
