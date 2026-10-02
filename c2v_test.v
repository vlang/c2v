module main

import strings
import json2
import os

fn check_ct(str_typ string, expected string) {
	t := convert_type(str_typ)
	assert t.name == expected
	if t.name != expected {
		println('!!!' + t.name)
	}
}

fn test_convert_type() {
	check_ct('FuncDef *[23]', '[23]&FuncDef')
	check_ct('void (*)(void *, void *)', 'fn (voidptr, voidptr)')
	check_ct('const char **', '&&u8')
	check_ct('byte [20]', '[20]u8')
	check_ct('byte *', '&u8')
	check_ct('byte *:byte *', '&u8')
	check_ct('short', 'i16')
	check_ct('signed char', 'i8')
	check_ct('int **', '&&i32')
	check_ct('void **', '&voidptr')
	check_ct('Widget * &', '&&Widget')
	check_ct('Widget *const &', '&Widget')
	check_ct('const idDrawVert (*)[3]', '&[3]IdDrawVert')
	check_ct('struct constraintFlags_s', 'ConstraintFlags_s')
	check_ct('const enum myEnum', 'MyEnum')
}

fn test_normalize_cpp_template_enum_arguments() {
	values := {
		'ev_boolean': i64(14)
	}
	assert normalize_cpp_template_enum_arguments('idScriptVariable<int, ev_boolean, int>', values) == 'idScriptVariable<int, 14, int>'
}

fn test_convert_template_type_resolves_scalar_typedef_argument() {
	mut translator := C2V{}
	translator.type_aliases['AasIndex_t'] = 'int'
	assert translator.normalize_cpp_template_alias_arguments('idList<aasIndex_t> &') == 'idList<int> &'
	assert translator.convert_type('idList<aasIndex_t> &').name == '&IdList_int'
}

fn test_global_type_comparison_resolves_project_typedefs() {
	mut translator := C2V{}
	translator.type_aliases['Glconfig_t'] = 'Glconfig_s'
	translator.type_aliases['PFNGLBINDPROGRAMARBPROC'] = 'fn (u32, u32)'
	assert translator.resolve_type_alias('Glconfig_t') == 'Glconfig_s'
	assert translator.resolve_type_alias('C.PFNGLBINDPROGRAMARBPROC') == 'fn (u32, u32)'
	assert types_are_equal(translator.resolve_type_alias('Glconfig_t'), translator.resolve_type_alias('Glconfig_s'))
	assert types_are_equal(translator.resolve_type_alias('C.PFNGLBINDPROGRAMARBPROC'), translator.resolve_type_alias('fn (u32, u32)'))
}

fn test_directory_implicit_numeric_cast_accepts_typedef_target() {
	mut translator := C2V{
		is_dir: true
	}
	translator.type_aliases['Dword'] = 'u32'
	cast := Node{
		kind:      .implicit_cast_expr
		cast_kind: 'IntegralCast'
		ast_type:  AstJsonType{
			qualified: 'dword'
		}
		inner:     [Node{
			kind:     .decl_ref_expr
			ast_type: AstJsonType{
				qualified: 'int'
			}
		}]
	}
	assert translator.implicit_numeric_cast_will_render(cast)
}

fn test_cpp_abstract_pointer_type_conversion() {
	mut c := C2V{
		cpp_abstract_types: {
			'IdRenderModel': true
		}
	}
	assert c.convert_type('idRenderModel *').name == 'IdRenderModel'
	assert c.convert_type('idRenderModel **').name == '&IdRenderModel'
	assert c.convert_type('idRenderModel *const &').name == 'IdRenderModel'
	assert c.convert_type('idRenderModel * &').name == '&IdRenderModel'
	assert c.is_v_abstract_interface_type('IdRenderModel')
	assert !c.is_v_abstract_interface_type('&IdRenderModel')
	assert c.v_abstract_interface_nil_literal('IdRenderModel') == 'c2v_nil_interface[IdRenderModel]()'
	c.inside_unsafe = true
	assert c.v_abstract_interface_nil_literal('IdRenderModel') == 'c2v_nil_interface[IdRenderModel]()'
	assert c.local_type_declarations.any(it.contains('fn c2v_interface_object[T](value T) voidptr'))
	assert c.local_type_declarations.any(it.contains('fn c2v_interface_is_nil[T](value T) bool'))
}

fn test_cpp_pointer_param_cast_avoids_nested_unsafe() {
	assert cpp_pointer_param_cast('trace', 'Trace_t', true, false) == 'unsafe { &Trace_t(&trace) }'
	assert cpp_pointer_param_cast('trace', 'Trace_t', true, true) == '&Trace_t(&trace)'
	assert should_cast_call_arg_to_pointer_param('&int', '&IdEventDef')
	assert !should_cast_call_arg_to_pointer_param('&IdEventDef', '&int')
}

fn test_sizeof_indexed_array_uses_type_operand() {
	assert sizeof_expr_needs_type_operand('buffers[0]')
	assert sizeof_expr_needs_type_operand('this.field')
	assert !sizeof_expr_needs_type_operand('buffer')
}

fn test_scan_cpp_abstract_type_names() {
	source := '
		class Forward;
		class ID_API AbstractBase {
		public:
			virtual int Read() const = 0;
		};
		struct Concrete {
			int value;
		};
		class Outer {
			class NestedAbstract {
				virtual void Touch() = 0;
			};
		};
		AbstractBase *Build(const struct ViewDef_s *view) {
			return 0;
		}
	'
	assert scan_cpp_abstract_type_names(source) == ['AbstractBase', 'NestedAbstract']
}

fn test_cpp_nested_template_alias_replacement_is_token_safe() {
	mut translator := C2V{}
	translator.cpp_template_type_aliases['Block'] = 'Container_int_Block'
	assert translator.convert_type('Block *').name == '&Container_int_Block'
	assert translator.convert_type('idDynamicBlock<int>').name == 'IdDynamicBlock_int'
}

fn test_function_type_params_preserves_nested_template_commas() {
	signature := 'Node *(Node<DynamicBlock<Vertex>, int> *, Node<DynamicBlock<Vertex>, int> *)'
	assert function_type_params(signature) == [
		'Node<DynamicBlock<Vertex>, int> *',
		'Node<DynamicBlock<Vertex>, int> *',
	]
}

fn test_strict_libc_compat_declarations_are_use_driven() {
	mut out := strings.new_builder(512)
	write_strict_cpp_compat_declarations(mut out, {
		'realloc':     true
		'localtime_r': true
	})
	declarations := out.str()
	assert declarations.contains('fn C.realloc(voidptr, usize) voidptr')
	assert declarations.contains('fn C.localtime_r(&i64, &C.tm) &C.tm')
	// builtin_alloca always allocates through malloc.
	assert declarations.contains('fn C.malloc(usize) voidptr')
	assert !declarations.contains('fn C.strstr(')
	assert !declarations.contains('struct C.tm {')
	assert declarations.contains('fn builtin_va_start(arg0 &C.va_list, arg1 voidptr) {}')
	assert declarations.contains('fn builtin_va_end(arg0 &C.va_list) {}')
	assert declarations.contains('fn builtin_va_copy(arg0 &C.va_list, arg1 &C.va_list) {}')
}

fn test_system_typedefs_resolve_through_their_declarations() {
	mut translator := C2V{
		is_cpp: true
	}
	translator.register_system_typedef('GLenum', 'unsigned int')
	translator.register_system_typedef('Callback', 'void (*)(int, GLenum *)')
	// Standard C typedefs keep the base conversion's mapping.
	translator.register_system_typedef('size_t', 'unsigned long')
	assert translator.convert_type('const GLenum *').name == '&u32'
	assert translator.convert_type('Callback').name == 'fn (i32, &u32)'
	assert translator.resolve_system_typedefs('Callback *') == 'void (**)(int, unsigned int *)'
	assert translator.convert_type('size_t').name == 'usize'
}

fn test_system_records_use_c_interop_names() {
	mut translator := C2V{
		is_cpp: true
	}
	translator.collect_system_declaration(Node{
		kind_str: 'RecordDecl'
		name:     'stat'
		inner:    [
			Node{
				kind_str: 'FieldDecl'
				name:     'st_mode'
				ast_type: AstJsonType{
					qualified: 'unsigned short'
				}
			},
		]
	}, '/usr/include/sys/stat.h')
	translator.collect_system_declaration(Node{
		kind_str: 'RecordDecl'
		id:       '0x1'
		tags:     'union'
		inner:    [
			Node{
				kind_str: 'FieldDecl'
				name:     'type'
				ast_type: AstJsonType{
					qualified: 'unsigned int'
				}
			},
			Node{
				kind_str: 'FieldDecl'
				name:     'info'
				ast_type: AstJsonType{
					qualified: 'struct stat *'
				}
			},
		]
	}, '/usr/include/events.h')
	translator.collect_system_declaration(Node{
		kind_str: 'TypedefDecl'
		name:     'Event'
		ast_type: AstJsonType{
			qualified: 'union Event'
		}
		inner:    [
			Node{
				kind_str:       'ElaboratedType'
				owned_tag_decl: OwnedTagDecl{
					id: '0x1'
				}
			},
		]
	}, '/usr/include/events.h')
	assert translator.convert_type('struct stat *').name == '&C.stat'
	assert translator.convert_type('Event').name == 'C.Event'
	// A project type with the same V name is not an external C type.
	translator.project_known_types['Stat'] = true
	assert translator.convert_type('stat').name == 'Stat'
	translator.project_known_types.delete('Stat')
	declarations := translator.external_surface_declarations('fn f(e &C.Event) {}', '')
	assert declarations.contains('@[typedef]\nunion C.Event {\npub mut:\n\t@type u32\n\tinfo &C.stat\n}')
	assert declarations.contains('struct C.stat {\npub mut:\n\tst_mode u16\n}')
}

fn test_used_c_symbols() {
	used := used_c_symbols('x := C.foo(C.BAR) + y.C.z + myC.q\n')
	assert 'foo' in used
	assert 'BAR' in used
	assert 'z' !in used
	assert 'q' !in used
}

fn test_used_external_lowercase_global_retains_c_extern_declaration() {
	mut translator := C2V{
		is_cpp: true
		is_dir: true
	}
	translator.used_global.add('mach_task_self_')
	// The system header's typedef supplies the global's C type.
	translator.register_system_typedef('mach_port_t', 'unsigned int')
	declaration := Node{
		kind_str:       'VarDecl'
		name:           'mach_task_self_'
		class_modifier: 'extern'
		ast_type:       AstJsonType{
			qualified: 'mach_port_t'
		}
	}
	translator.collect_used_external_c_global_decls(&declaration)
	assert translator.globals['mach_task_self_'].is_extern
	assert translator.globals['mach_task_self_'].typ == 'u32'
	assert translator.extern_global_v_name('mach_task_self_') == 'mach_task_self_'
	mut out := strings.new_builder(64)
	mut emitted := map[string]bool{}
	emit_c_extern_global_decl(mut out, 'mach_task_self_', 'u32', mut emitted)
	assert out.str() == '@[c_extern]\n__global mach_task_self_ u32\n'
}

fn test_external_global_prescan_does_not_downgrade_known_definition() {
	mut translator := C2V{}
	translator.register_global_symbol('cmdSystem', 'IdCmdSystem', false)
	translator.register_global_symbol('cmdSystem', 'C.IdCmdSystem', true)
	assert !translator.globals['cmdSystem'].is_extern
	assert translator.globals['cmdSystem'].typ == 'IdCmdSystem'

	translator.register_global_symbol('declManager', 'C.IdDeclManager', true)
	translator.register_global_symbol('declManager', 'IdDeclManager', false)
	assert !translator.globals['declManager'].is_extern
	assert translator.globals['declManager'].typ == 'IdDeclManager'
}

fn test_external_function_prescan_defers_to_v_runtime_c_declarations() {
	mut translator := C2V{}
	for name in ['open', 'setvbuf', 'strerror', 'getuid', 'realpath', 'sysconf'] {
		translator.register_external_c_function_decl(&Node{
			kind_str:     'FunctionDecl'
			name:         name
			mangled_name: '_' + name
			ast_type:     AstJsonType{
				qualified: 'int ()'
			}
		})
		assert name !in translator.external_c_fn_declarations
		assert filter_name(name, false) == 'C.${name}'
	}
	// Only V's `os` module declares these, and translated programs do not
	// import it.
	for name in ['ioctl', 'sigaction'] {
		translator.register_external_c_function_decl(&Node{
			kind_str:     'FunctionDecl'
			name:         name
			mangled_name: '_' + name
			ast_type:     AstJsonType{
				qualified: 'int ()'
			}
		})
		assert name in translator.external_c_fn_declarations
		assert filter_name(name, false) == 'C.${name}'
	}
}

fn test_external_function_prescan_desugars_callback_typedef_parameter() {
	mut translator := C2V{}
	translator.register_external_c_function_decl(&Node{
		kind_str:     'FunctionDecl'
		name:         'SDL_CreateThread'
		mangled_name: '_SDL_CreateThread'
		ast_type:     AstJsonType{
			qualified: 'SDL_Thread *(SDL_ThreadFunction, const char *, void *)'
		}
		inner:        [
			Node{
				kind_str: 'ParmVarDecl'
				ast_type: AstJsonType{
					qualified:           'SDL_ThreadFunction'
					desugared_qualified: 'int (*)(void *)'
				}
			},
			Node{
				kind_str: 'ParmVarDecl'
				ast_type: AstJsonType{
					qualified: 'const char *'
				}
			},
			Node{
				kind_str: 'ParmVarDecl'
				ast_type: AstJsonType{
					qualified: 'void *'
				}
			},
		]
	})
	assert translator.external_c_fn_declarations['SDL_CreateThread'] == 'fn C.SDL_CreateThread(fn (voidptr) i32, &i8, voidptr) &C.SDL_Thread'
}

fn test_external_global_prescan_desugars_function_pointer_typedef() {
	mut translator := C2V{}
	translator.used_global.add('qglBindProgramARB')
	translator.collect_used_external_c_global_decls(&Node{
		kind_str:       'VarDecl'
		name:           'qglBindProgramARB'
		class_modifier: 'extern'
		ast_type:       AstJsonType{
			qualified:           'PFNGLBINDPROGRAMARBPROC'
			desugared_qualified: 'void (*)(unsigned int, unsigned int)'
		}
	})
	assert translator.globals['qglBindProgramARB'].typ == 'fn (u32, u32)'
}

fn test_external_interface_pointer_global_uses_early_abstract_type_metadata() {
	mut translator := C2V{}
	root := Node{
		inner: [
			Node{
				kind_str: 'CXXRecordDecl'
				name:     'idGameEdit'
				inner:    [
					Node{
						kind_str:   'CXXMethodDecl'
						name:       'FindEntity'
						is_virtual: true
						is_pure:    true
						ast_type:   AstJsonType{
							qualified: 'idEntity *(const char *)'
						}
					},
				]
			},
		]
	}
	translator.collect_cpp_abstract_types_from_node(&root)
	assert 'IdGameEdit' in translator.cpp_abstract_types
	translator.used_global.add('gameEdit')
	translator.collect_used_external_c_global_decls(&Node{
		kind_str:       'VarDecl'
		name:           'gameEdit'
		class_modifier: 'extern'
		ast_type:       AstJsonType{
			qualified: 'idGameEdit *'
		}
	})
	assert translator.globals['gameEdit'].typ == 'IdGameEdit'
}

fn test_early_abstract_scan_keeps_implemented_leaf_service_concrete() {
	mut translator := C2V{
		project_dir_method_defs: {
			'/tmp/out|IdNetworkSystem.send': true
		}
	}
	root := Node{
		inner: [
			Node{
				kind_str: 'CXXRecordDecl'
				name:     'idNetworkSystem'
				inner:    [
					Node{
						kind_str:   'CXXMethodDecl'
						name:       'Send'
						is_virtual: true
					},
				]
			},
		]
	}
	translator.collect_cpp_class_hierarchy_from_node(&root)
	translator.collect_cpp_abstract_types_from_node(&root)
	assert 'IdNetworkSystem' !in translator.cpp_abstract_types
}

fn test_early_abstract_scan_keeps_pure_polymorphic_base_as_interface() {
	mut translator := C2V{
		project_dir_method_defs: {
			'/tmp/out|IdFile.read': true
		}
	}
	root := Node{
		inner: [
			Node{
				kind_str: 'CXXRecordDecl'
				name:     'idFile'
				inner:    [
					Node{
						kind_str:   'CXXMethodDecl'
						name:       'Read'
						is_virtual: true
						is_pure:    true
					},
				]
			},
			Node{
				kind_str: 'CXXRecordDecl'
				name:     'idMemoryFile'
				bases:    [
					CxxBaseSpecifier{
						ast_type: AstJsonType{
							qualified: 'idFile'
						}
					},
				]
			},
		]
	}
	translator.collect_cpp_class_hierarchy_from_node(&root)
	translator.collect_cpp_abstract_types_from_node(&root)
	assert 'IdFile' in translator.cpp_abstract_types
}

fn test_pointer_casted_conditional_wraps_each_final_branch_expression() {
	assert wrap_final_rendered_expr('on_stack = true\n(voidptr(usize(15)))', '&Item') == 'on_stack = true\n&Item((voidptr(usize(15))))'
	assert wrap_final_rendered_expr('allocate(size)', '&Item') == '&Item(allocate(size))'
}

fn test_strict_global_fixed_arrays_do_not_store_result_literals() {
	source := '@[weak] __global sentinel = [-1]!\n@[weak] __global table = [\n\t[1, 2]!,\n\t[3, 4]!\n]!\n@[weak] __global matrix = Mat2{ rows: [Vec2{}, Vec2{}]! }\n'
	rewritten := replace_strict_global_array_result_suffixes(source, map[string]bool{})
	assert rewritten.contains('__global sentinel = [-1]\n')
	assert rewritten.contains('\t[1, 2]!,')
	assert rewritten.contains('\t[3, 4]!\n]\n')
	assert rewritten.contains('matrix = Mat2{ rows: [Vec2{}, Vec2{}]! }')
	// Constant-initialized arrays stay static fixed arrays.
	kept := replace_strict_global_array_result_suffixes(source, {
		'sentinel': true
	})
	assert kept.contains('__global sentinel = [-1]!\n')
	assert kept.contains('\t[3, 4]!\n]\n')
}

fn test_clang_used_inline_function_metadata() {
	decoded := json2.decode[Node]('{"kind":"FunctionDecl","name":"NewFrame","isUsed":true}') or {
		assert false, err.msg()
		return
	}
	assert decoded.is_used
}

fn test_nested_mut_receiver_materializes_final_call_result() {
	source := 'fn update(mut list IdList) {\n\tlist.op_index2(0).get_physics().set_contents(1)\n\tlist.op_index2(0).get_physics().unlink_clip()\n}\n'
	sanitized := sanitize_translated_output(source, false, ['set_contents', 'unlink_clip'])
	assert sanitized.contains('mut __c2v_mut_recv_0 := list.op_index2(0).get_physics()')
	assert sanitized.contains('__c2v_mut_recv_0.set_contents(1)')
	assert !sanitized.contains('__c2v_mut_recv_0.get_physics().set_contents(1)')
	assert sanitized.contains('mut __c2v_mut_recv_1 := list.op_index2(0).get_physics()')
	assert sanitized.contains('__c2v_mut_recv_1.unlink_clip()')
}

fn test_multiple_mut_receivers_on_one_line_are_materialized() {
	source := 'fn update(mut item Item) int {\n\treturn consume(item.camera().base().get_areas(), item.camera().base().get_num_areas())\n\titem.entity().get_animator().set_frame(1)\n}\n'
	sanitized := sanitize_translated_output(source, false, ['get_areas', 'get_num_areas', 'get_animator',
		'set_frame'])
	assert sanitized.contains('mut __c2v_mut_recv_0 := item.camera().base()')
	assert sanitized.contains('mut __c2v_mut_recv_1 := item.camera().base()')
	assert sanitized.contains('consume(__c2v_mut_recv_1.get_areas(), __c2v_mut_recv_0.get_num_areas())')
	// `get_animator` changes its object too, so its receiver is bound first.
	assert sanitized.contains('mut __c2v_mut_recv_chain_2 := item.entity()')
	assert sanitized.contains('mut __c2v_mut_recv_2 := __c2v_mut_recv_chain_2.get_animator()')
	assert sanitized.contains('__c2v_mut_recv_2.set_frame(1)')
}

fn test_indexed_mut_receiver_in_assignment_rhs_is_detected() {
	line := '__c2v_condition_1 := (this.children).op_index2(c).contains2(&(this.children).op_index2(c).draw_rect, this.gui.cursor_x(), this.gui.cursor_y())'
	receiver, tail, found := split_mut_receiver_call_expr(line, ['contains2'])
	assert found
	assert receiver == '(this.children).op_index2(c)'
	assert tail.starts_with('.contains2(')
	sanitized := sanitize_translated_output(line, false, ['contains2'])
	assert sanitized.contains('mut __c2v_mut_recv_0 := (this.children).op_index2(c)')
	assert sanitized.contains('__c2v_condition_1 := __c2v_mut_recv_0.contains2(')
	compound := 'if ((this.children).op_index2(c).visible).data && (this.children).op_index2(c).contains2(&(this.children).op_index2(c).draw_rect, this.gui.cursor_x(), this.gui.cursor_y()) && !((this.children).op_index2(c).no_events).data {\n}\n'
	compound_sanitized := sanitize_translated_output(compound, false, ['contains2'])
	// After `&&` the receiver is only evaluated when the earlier terms hold.
	first_term := compound_sanitized.index('= ((this.children).op_index2(c).visible).data') or { -1 }
	bound_receiver := compound_sanitized.index('mut __c2v_mut_recv_cond_0 := (this.children).op_index2(c)') or {
		-1
	}
	assert first_term >= 0 && bound_receiver > first_term, compound_sanitized
	assert compound_sanitized.contains('__c2v_mut_recv_cond_0.contains2('), compound_sanitized
}

fn test_strict_cpp_backend_repairs_multiline_dereferences() {
	source := 'value := *(unsafe {\n\t*items.op_index2(i)\n})\n'
	rewritten := sanitize_strict_cpp_backend_output(source)
	assert rewritten.contains('value := unsafe {\n\t*items.op_index2(i)\n}')
}

fn test_reference_returning_call_assignment_dereferences_final_result() {
	source := 'fn assign(mut list IdList, value IdVec3) {\n\tunsafe { list.op_index2(0).to_vec32() = value }\n\tlist.op_index2(0).get_render_entity().visible = true\n}\n'
	sanitized := sanitize_translated_output(source, false, [])
	assert sanitized.contains('mut __c2v_lhs_tmp_0 := list.op_index2(0).to_vec32()')
	assert sanitized.contains('unsafe { *__c2v_lhs_tmp_0 = value }')
	assert sanitized.contains('mut __c2v_lhs_tmp_1 := list.op_index2(0)')
	assert sanitized.contains('__c2v_lhs_tmp_1.get_render_entity().visible = true')
}

fn test_parenthesized_pointer_deref_assignment_materializes_balanced_operand() {
	source := 'fn restore(mut list IdList, saved State) {\n\tunsafe { *((list.op_index2(0)).current) = saved }\n}\n'
	sanitized := sanitize_translated_output(source, false, [])
	assert sanitized.contains('mut __c2v_lhs_tmp_0 := (list.op_index2(0)).current')
	assert sanitized.contains('unsafe { *__c2v_lhs_tmp_0 = saved }')
	assert !sanitized.contains('__c2v_lhs_tmp_0.current)')
}

fn test_trim_underscore() {
	assert trim_underscores('__name') == 'name'
	assert trim_underscores('_name') == 'name'
}

fn test_replace_defined_global_refs_in_text_single_pass() {
	replacements := {
		'C.someGlobal': 'some_global'
		'otherGlobal':  'other_global'
	}
	input := "C.someGlobal + otherGlobal + prefixotherGlobal + C.someGlobalSuffix + value.otherGlobal + c'otherGlobal C.someGlobal' // otherGlobal\n/* C.someGlobal */ otherGlobal"
	expected := "some_global + other_global + prefixotherGlobal + C.someGlobalSuffix + value.other_global + c'otherGlobal C.someGlobal' // otherGlobal\n/* C.someGlobal */ other_global"
	assert replace_defined_global_refs_in_text(input, replacements) == expected
}

fn test_single_module_skeleton_cleanup() {
	source := '@[translated]\nmodule main\n\nstruct Service {}\nstruct State {\n}\nstruct State {\n\tvalue int\n}\ninterface Service {\n\trun()\n}\nfn service() Service {\n\treturn Service{}\n}\n'
	without_empty_stubs := remove_duplicate_external_empty_struct_stubs(source)
	assert without_empty_stubs.count('struct State {') == 1
	assert !without_empty_stubs.contains('struct Service {}')
	rewritten := rewrite_skeleton_interface_default_returns(without_empty_stubs, {
		'Service': true
	})
	assert rewritten.contains('return unsafe { Service(voidptr(0)) }')
}

fn test_single_module_cleanup_removes_cross_file_empty_struct_stubs() {
	real_source := 'interface Service {\n\trun()\n}\nstruct State {\n\tvalue int\n}\n'
	empty_source := 'struct Service {}\nstruct State {\n}\nstruct Opaque {}\n'
	mut real_decls := collect_nonempty_v_type_names(real_source)
	for name, _ in collect_nonempty_v_type_names(empty_source) {
		real_decls[name] = true
	}
	assert 'Service' in real_decls
	assert 'State' in real_decls
	assert 'Opaque' !in real_decls
	mut seen_empty := map[string]bool{}
	cleaned := remove_project_duplicate_empty_struct_stubs(empty_source, real_decls, mut seen_empty)
	assert !cleaned.contains('struct Service')
	assert !cleaned.contains('struct State')
	assert cleaned.contains('struct Opaque {}')
	duplicate := remove_project_duplicate_empty_struct_stubs('struct Opaque {}\n', real_decls, mut seen_empty)
	assert !duplicate.contains('struct Opaque')
}

fn test_rewrite_unknown_file_suffixed_type_refs() {
	source := '// allocator fields\nstruct Pool {\n\tblock &Block_s_Game_local\n}\ntype Alias_Game_local = Block_s\n'
	rewritten := rewrite_unknown_file_suffixed_type_refs(source, {
		'Pool':             true
		'Block_s':          true
		'Alias_Game_local': true
	}, 'Game_local')
	assert rewritten.contains('block &Block_s')
	assert rewritten.contains('type Alias_Game_local = Block_s')
}

fn test_filter_single_module_globals() {
	source := '@[translated]\nmodule main\n\nstruct Service {}\nstruct Duplicate {}\nstruct Duplicate {}\nfn helper() {}\nfn repeated() {}\nfn repeated(args ...voidptr) {}\nfn (this Wrapper) value(args ...voidptr) int { return 0 }\nconst local_value = 0\nconst fallback_value = 1\n@[weak] __global local_value int\n@[weak] __global fallback_value int\n@[weak] __global duplicate int\n@[weak] __global duplicate int\n@[weak] __global retained int\nfn main() {}\n'
	filtered := filter_single_module_globals(source, {
		'Service': true
	}, map[string]bool{}, {
		'helper': true
	}, {
		'Wrapper.value': true
	}, {
		'local_value': true
	})
	assert !filtered.contains('struct Service {}')
	assert filtered.count('struct Duplicate {}') == 1
	assert !filtered.contains('fn helper()')
	assert !filtered.contains('fn (this Wrapper) value')
	assert filtered.count('fn repeated') == 1
	assert !filtered.contains('__global local_value')
	assert !filtered.contains('__global fallback_value')
	assert filtered.count('__global duplicate') == 1
	assert filtered.contains('__global retained int')
}

fn test_filter_single_module_globals_removes_interface_methods() {
	source := 'module main\n\nfn (this Service) run() {\n}\n\nfn (this Record) run() {\n}\n'
	filtered := filter_single_module_globals(source, {
		'Service': true
		'Record':  true
	}, {
		'Service': true
	}, map[string]bool{}, map[string]bool{}, map[string]bool{})
	assert !filtered.contains('fn (this Service) run()')
	assert filtered.contains('fn (this Record) run()')
}

fn test_set_file_index_inherits_enclosing_cpp_header() {
	main_path := os.real_path('c2v.v')
	header_path := os.real_path('cpp.v')
	mut translator := C2V{
		is_cpp:   true
		files:    [main_path]
		cur_file: main_path
	}
	mut tree := Node{
		kind:     .translation_unit_decl
		kind_str: 'TranslationUnitDecl'
		inner:    [
			Node{
				kind:     .cxx_record_decl
				kind_str: 'CXXRecordDecl'
				location: NodeLocation{
					file: header_path
				}
				inner:    [
					Node{
						kind:     .cxx_method_decl
						kind_str: 'CXXMethodDecl'
						inner:    [
							Node{
								kind:     .compound_stmt
								kind_str: 'CompoundStmt'
							},
						]
					},
				]
			},
			Node{
				kind:     .function_decl
				kind_str: 'FunctionDecl'
				inner:    [
					Node{
						kind:     .compound_stmt
						kind_str: 'CompoundStmt'
					},
				]
			},
		]
	}
	translator.set_file_index(mut tree)
	assert tree.inner[0].location.file_index == 1
	assert tree.inner[0].inner[0].location.file_index == 1
	assert tree.inner[0].inner[0].inner[0].location.file_index == 1
	assert tree.inner[1].location.file_index == 0
	assert tree.inner[1].inner[0].location.file_index == 0
}

fn test_cpp_compatibility_skeletonizes_dependency_bodies_only() {
	translator := C2V{
		is_cpp:                   true
		is_dir:                   true
		project_generate_stubs:   true
		project_require_no_stubs: false
		files:                    ['main.cpp', 'dependency.h']
	}
	main_node := Node{
		location: NodeLocation{
			file_index: 0
		}
	}
	dependency_node := Node{
		location: NodeLocation{
			file_index: 1
		}
	}
	assert !translator.should_emit_skeleton_body_for_node(&main_node)
	assert translator.should_emit_skeleton_body_for_node(&dependency_node)
}

fn test_cpp_skeleton_default_for_interface_is_nil() {
	mut translator := C2V{
		cpp_abstract_types: {
			'IdService': true
		}
	}
	assert translator.skeleton_default_value('IdService') == 'c2v_nil_interface[IdService]()'
}

fn test_normalize_cpp_param_qualifiers() {
	assert normalize_cpp_param_qualifiers('void (const int, const deriveFunction_t, const void *)') == 'void (int, deriveFunction_t, const void *)'
	assert normalize_cpp_param_qualifiers('void (const int, deriveFunction_t, const void *)') == 'void (int, deriveFunction_t, const void *)'
	assert normalize_cpp_param_qualifiers('int (idVec3 *const, const idVec3 &) const') == 'int (idVec3 *, const idVec3 &) const'
	assert normalize_cpp_param_qualifiers('void (void (*)(const int), const float)') == 'void (void (*)(const int), float)'
	assert normalize_cpp_param_qualifiers('void ()') == 'void ()'
}

fn test_cpp_constructor_signature_metadata() {
	assert cpp_constructor_signature_key('&IdPolynomial', 'void (  float,\tfloat )') == 'IdPolynomial|void (float, float)'
	assert cpp_constructor_signature_key('IdODE_Euler', 'void (const int, const deriveFunction_t, const void *)') == cpp_constructor_signature_key('IdODE_Euler', 'void (const int, deriveFunction_t, const void *)')
	assert cpp_constructor_c_param_types('void (const idVec3 &, idList<int>, void (*)(int, float))') == [
		'const idVec3 &',
		'idList<int>',
		'void (*)(int, float)',
	]
	assert cpp_v_parameter_name('mut value &IdVec3') == 'value'
	assert cpp_v_parameter_name('count int') == 'count'
	mut translator := C2V{}
	assert translator.cpp_static_member_v_name('idRegister', 'REGCOUNT') == 'id_register_regcount'
	// Members spelled alike get distinct names, reused for later references.
	assert translator.cpp_static_member_v_name('idForceField', 'Type') == 'id_force_field_type'
	assert translator.cpp_static_member_v_name('idForce_Field', 'Type') == 'id_force_field_type2'
	assert translator.cpp_static_member_v_name('IdForce_Field', 'Type') == 'id_force_field_type2'
}

fn test_cpp_materialized_temporary_detection_ignores_outer_casts() {
	temporary := Node{
		kind:  .implicit_cast_expr
		inner: [Node{
			kind: .materialize_temporary_expr
		}]
	}
	lvalue := Node{
		kind:           .decl_ref_expr
		value_category: 'lvalue'
	}
	assert cpp_expr_is_materialized_temporary(temporary)
	assert !cpp_expr_is_materialized_temporary(lvalue)
}

fn test_function_type_params_with_callback_parameter() {
	assert function_type_params('idImage *(const char *, void (*)(idImage *))') == [
		'const char *',
		'void (*)(idImage *)',
	]
	assert function_type_params('void (*)(int, const char *)') == ['int', 'const char *']
}

fn test_unconditional_c_while_detection() {
	translator := C2V{}
	assert translator.is_unconditional_c_while(&Node{
		kind:  .while_stmt
		inner: [
			Node{
				kind:  .integer_literal
				value: 1
			},
			Node{
				kind: .compound_stmt
			},
		]
	})
	assert !translator.is_unconditional_c_while(&Node{
		kind:  .while_stmt
		inner: [
			Node{
				kind:  .integer_literal
				value: 0
			},
			Node{
				kind: .compound_stmt
			},
		]
	})
}

fn test_switch_labeled_return_does_not_fall_through() {
	assert !switch_statement_falls_through(Node{
		kind:  .default_stmt
		inner: [Node{
			kind:  .case_stmt
			inner: [
				Node{
					kind:  .integer_literal
					value: 1
				},
				Node{
					kind: .return_stmt
				},
			]
		}]
	})
}

fn test_cpp_receiver_direct_this_detection() {
	assert cpp_receiver_is_direct_this(Node{
		kind:  .implicit_cast_expr
		inner: [Node{
			kind: .cxx_this_expr
		}]
	})
	assert !cpp_receiver_is_direct_this(Node{
		kind:  .member_expr
		name:  'field'
		inner: [Node{
			kind: .cxx_this_expr
		}]
	})
}

fn test_cpp_record_field_names_match_emitted_layout_spelling() {
	node := Node{
		inner: [
			Node{
				kind: .field_decl
				name: 'memoryHighwater'
			},
			Node{
				kind: .field_decl
				name: 'Reset'
			},
			Node{
				kind: .cxx_method_decl
				name: 'Reset'
			},
		]
	}
	assert cxx_record_decl_field_names(&node) == ['memory_highwater', 'reset_field']
}

fn test_external_c_function_declaration_preserves_typed_abi() {
	mut translator := C2V{
		is_cpp: true
		is_dir: true
	}
	// An opaque record declared by a system header.
	translator.collect_system_declaration(Node{
		kind_str: 'CXXRecordDecl'
		name:     'SDL_Window'
	}, '/usr/local/include/SDL2/SDL_video.h')
	translator.collect_system_declaration(Node{
		kind_str: 'TypedefDecl'
		name:     'SDL_Window'
		ast_type: AstJsonType{
			qualified: 'struct SDL_Window'
		}
	}, '/usr/local/include/SDL2/SDL_video.h')
	node := Node{
		kind:         .function_decl
		name:         'SDL_GetWindowSize'
		mangled_name: '_SDL_GetWindowSize'
		ast_type:     AstJsonType{
			qualified: 'void (SDL_Window *, int *, int *)'
		}
		inner:        [
			Node{
				kind:     .parm_var_decl
				ast_type: AstJsonType{
					qualified: 'SDL_Window *'
				}
			},
			Node{
				kind:     .parm_var_decl
				ast_type: AstJsonType{
					qualified: 'int *'
				}
			},
			Node{
				kind:     .parm_var_decl
				ast_type: AstJsonType{
					qualified: 'int *'
				}
			},
		]
	}
	assert is_c_linkage_function_decl(&node)
	cpp_node := Node{
		kind:         .function_decl
		name:         'sprintf'
		mangled_name: '_Z7sprintfR5idStrPKcz'
	}
	assert !is_c_linkage_function_decl(&cpp_node)
	translator.register_external_c_function_decl(&node)
	assert translator.external_c_fn_declarations['SDL_GetWindowSize'] == 'fn C.SDL_GetWindowSize(&C.SDL_Window, &i32, &i32)'
	assert 'SDL_GetWindowSize' in translator.extern_fns
	assert convert_type('int (* _Nonnull)(const void *, const void *)').name == 'fn (voidptr, voidptr) i32'
}

fn test_configured_include_dirs_resolve_relative_project_paths() {
	project_folder := os.join_path(os.temp_dir(), 'c2v_include_dir_test')
	child := os.join_path(project_folder, 'child')
	os.mkdir_all(child) or { panic(err) }
	dirs := configured_include_dirs(child, '-I. -I.. -I ../missing -DVALUE=1')
	assert os.real_path(child) in dirs
	assert os.real_path(project_folder) in dirs
}

fn test_external_function_pointer_cast_uses_desugared_signature() {
	assert c_style_cast_type_spelling(AstJsonType{
		qualified:           'PFNGLCOMPRESSEDTEXIMAGE2DARBPROC'
		desugared_qualified: 'void (*)(GLenum, GLint, const void *)'
	}) == 'void (*)(GLenum, GLint, const void *)'
	assert c_style_cast_type_spelling(AstJsonType{
		qualified:           'time_t'
		desugared_qualified: 'long'
	}) == 'time_t'
}

fn test_function_pointer_cast_tokens_preserve_signature_structure() {
	assert function_pointer_cast_type_token('fn (voidptr) voidptr') != function_pointer_cast_type_token('fn (voidptr, voidptr)')
	assert function_pointer_cast_type_token('fn () u32') != function_pointer_cast_type_token('fn (u32)')
	assert function_pointer_cast_type_token('fn (u32, &u8)') != function_pointer_cast_type_token('fn (u32) &u8')
}

fn test_large_unsigned_integer_literals_need_explicit_v_casts() {
	assert integer_literal_needs_unsigned_cast('4278255360', 'u32')
	assert integer_literal_needs_unsigned_cast('2147483648', 'u64')
	assert !integer_literal_needs_unsigned_cast('2147483647', 'u32')
	assert !integer_literal_needs_unsigned_cast('4278255360', 'int')
}

fn test_mutable_interface_assertion_receiver_is_materialized() {
	receiver, tail, found := split_mut_receiver_call_expr('depth = (game_edit as IdGameEditExt).get_interpreter_call_stack_depth(interpreter)', [
		'get_interpreter_call_stack_depth',
	])
	assert found
	assert receiver == '(game_edit as IdGameEditExt)'
	assert tail == '.get_interpreter_call_stack_depth(interpreter)'
}

fn test_stateless_abstract_implementation_remains_concrete() {
	mut translator := C2V{
		outv:                    '/tmp/c2v-test/output.v'
		cpp_abstract_types:      {
			'IdSIMDProcessor': true
		}
		cpp_class_bases:         {
			'IdSIMD_Generic': ['IdSIMDProcessor']
		}
		project_dir_method_defs: {
			'/tmp/c2v-test|IdSIMD_Generic.add': true
		}
	}
	record := Node{
		kind:  .cxx_record_decl
		name:  'idSIMD_Generic'
		inner: [Node{
			kind:       .cxx_method_decl
			name:       'Add'
			is_virtual: true
		}]
	}
	assert !translator.cpp_record_is_abstract_interface(&record)
}

fn test_concrete_template_alias_precedes_file_collision_alias() {
	translator := C2V{
		file_type_alias_names:     {
			'Element_t': 'Element_t_tr_trisurf'
		}
		cpp_template_type_aliases: {
			'Element_t': 'IdBlockAlloc_srfTriangles_s_256_Element_s'
		}
	}
	assert translator.convert_type('Element_t').name == 'IdBlockAlloc_srfTriangles_s_256_Element_s'
	assert convert_type('__uint16_t').name == 'u16'
	assert convert_type('u_int32_t').name == 'u32'
}

fn test_zero_initializer_accepts_uninitialized_array_filler_nodes() {
	assert is_zero_initializer_expr(Node{
		kind:         .init_list_expr
		array_filler: [Node{
			kind_str: 'ImplicitValueInitExpr'
		}]
	})
	assert is_zero_initializer_expr(Node{
		kind:  .init_list_expr
		inner: [Node{
			kind:      .cxx_construct_expr
			ast_type:  AstJsonType{
				qualified: 'timespec'
			}
			ctor_type: AstJsonType{
				qualified: 'void () throw()'
			}
		}]
	})
}

fn test_function_pointer_typedef_parameters_resolve_to_declarators() {
	mut translator := C2V{
		is_cpp: true
	}
	translator.register_system_typedef('DEBUGPROC', 'void (*)(unsigned int, const char *)')
	translator.register_system_typedef('SETCALLBACK', 'void (*)(DEBUGPROC, const void *)')
	assert translator.convert_type('SETCALLBACK').name == 'fn (fn (u32, &i8), voidptr)'
}

fn test_address_of_c_global_call_chain_is_parenthesized() {
	// V reads `&C.game.player(` as a cast to the type `&C.game.player`.
	assert parenthesize_c_global_call_addresses('take(&C.game.player().origin)') == 'take(&(C.game.player().origin))'
	assert parenthesize_c_global_call_addresses("x := unsafe { &C.game.find(c')', 1).items[2].name }") == "x := unsafe { &(C.game.find(c')', 1).items[2].name) }"
	// Addresses of plain members, casts to C types and C types are left alone.
	for src in ['take(&C.game.origin.x)', 'p := &C.sockaddr(addr)', 'fn open(f &C.FILE) {',
		'a &&C.ready.load()', 'take(&C.table[i].name)'] {
		assert parenthesize_c_global_call_addresses(src) == src
	}
}

fn test_c_global_ending_a_for_header_is_parenthesized() {
	// V reads `for n > C.limit {` as the struct literal `C.limit{...}`.
	assert parenthesize_c_global_loop_operands('\tfor width > C.config.vid_width {\n\t\twidth >>= 1\n\t}\n') == '\tfor width > (C.config.vid_width) {\n\t\twidth >>= 1\n\t}\n'
	for src in ['for i := 0; i < C.count; i++ {', 'if width > C.config.vid_width {',
		'for C.config.vid_width > width {', 'for width > C.limit(1) {'] {
		assert parenthesize_c_global_loop_operands(src) == src
	}
}

fn test_returned_receiver_reference_is_wrapped_in_unsafe() {
	by_reference := 'fn (mut this Vec) op_assign(a &Vec) &Vec {\n\tthis.x = a.x\n\treturn this\n}\n'
	assert wrap_returned_receivers(by_reference) == by_reference.replace('return this',
		'return unsafe { this }')
	// A method returning its object by value copies it.
	by_value := 'fn (mut this Var) op_assign(other Var) Var {\n\treturn this\n}\n'
	assert wrap_returned_receivers(by_value) == by_value
}

fn test_issue_20_formatter_uses_platform_null_device() {
	path := os.join_path(os.temp_dir(), 'c2v generated source.v')
	prefix := 'v fmt -translated -w ${os.quoted_path(path)} > '
	assert translated_format_command(path, 'windows') == prefix + 'nul'
	assert translated_format_command(path, 'macos') == prefix + '/dev/null'
	assert translated_format_command(path, 'linux') == prefix + '/dev/null'
}

fn test_issue_39_save_formats_generated_wrapper() {
	root := os.join_path(os.temp_dir(), 'c2v_issue_39_${os.getpid()}')
	os.mkdir_all(root) or { panic(err) }
	defer { os.rmdir_all(root) or {} }
	path := os.join_path(root, 'wrapper.v')
	mut translator := C2V{
		is_wrapper: true
		outv:       path
		out_file:   os.create(path) or { panic(err) }
	}
	translator.genln('@[translated]')
	translator.genln('module example\n')
	translator.genln('fn C.example()\n')
	translator.genln('pub fn example()  { C.example() }')
	translator.save()
	source := os.read_file(path) or { panic(err) }
	assert source.contains('pub fn example() {')
}

fn test_file_qualified_anonymous_record_initializer() {
	mut translator := C2V{
		is_dir:                 true
		out:                    strings.new_builder(128)
		anonymous_record_names: {
			'/tmp/issue_190/b.c:1:15': 'AnonStruct_0_14'
		}
		file_type_alias_names:  {
			'AnonStruct_0_14': 'AnonStruct_0_14_b'
		}
		known_types:            {
			'AnonStruct_0_14_b': true
		}
		structs:                {
			'AnonStruct_0_14_b': Struct{
				fields:      ['y']
				field_types: ['i32']
			}
		}
	}
	mut initializer := Node{
		kind:     .init_list_expr
		ast_type: AstJsonType{
			qualified: 'struct (unnamed struct at /tmp/issue_190/b.c:1:15)'
		}
		inner:    [Node{
			kind:     .integer_literal
			ast_type: AstJsonType{ qualified: 'int' }
			value:    '7'
		}]
	}
	translator.init_list_expr(mut initializer)
	output := translator.out.str()
	assert output.starts_with('AnonStruct_0_14_b{')
	assert output.contains('y: 7')
}
