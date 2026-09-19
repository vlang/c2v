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
	check_ct('int **', '&&int')
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
	assert types_are_equal(translator.resolve_type_alias('Glconfig_t'),
		translator.resolve_type_alias('Glconfig_s'))
	assert types_are_equal(translator.resolve_type_alias('C.PFNGLBINDPROGRAMARBPROC'),
		translator.resolve_type_alias('fn (u32, u32)'))
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
	assert c.v_abstract_interface_nil_literal('IdRenderModel') == 'IdRenderModel(unsafe { nil })'
	c.inside_unsafe = true
	assert c.v_abstract_interface_nil_literal('IdRenderModel') == 'IdRenderModel(nil)'
}

fn test_cpp_pointer_param_cast_avoids_nested_unsafe() {
	assert cpp_pointer_param_cast('trace', 'Trace_t', true, false) == 'unsafe { &Trace_t(&trace) }'
	assert cpp_pointer_param_cast('trace', 'Trace_t', true, true) == '&Trace_t(&trace)'
	assert should_cast_call_arg_to_pointer_param('&int', '&IdEventDef')
	assert !should_cast_call_arg_to_pointer_param('&IdEventDef', '&int')
}

fn test_cpp_winvar_value_wrappers_include_inherited_string_and_vector_forms() {
	for typ in ['IdWinBackground', 'IdWinStr', 'IdWinVec3', 'IdWinVec4'] {
		assert is_cpp_winvar_value_wrapper_type(typ)
	}
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

fn test_rewrite_cpp_interface_idlists() {
	source := 'struct IdList_ifacePtr {\n\tlist &Iface\n}\n\nfn (mut this IdList_ifacePtr) clear() {\n\tif this.list != unsafe { nil } {\n\t\tunsafe { free(this.list) }\n\t}\n\tthis.list = unsafe { nil }\n}\n\nfn (mut this IdList_ifacePtr) resize(newsize int) {\n\tthis.list = unsafe { &Iface(C.malloc(newsize * int(sizeof(Iface)))) }\n}\n'
	rewritten := rewrite_cpp_interface_idlists(source, {
		'IdList_ifacePtr': 'Iface'
	})
	assert rewritten.contains('\tlist []Iface')
	assert rewritten.contains('this.list = []Iface{}')
	assert rewritten.contains('mut resized := []Iface{len: newsize, init: Iface(unsafe { nil })}')
	assert !rewritten.contains('free(this.list)')
}

fn test_rewrite_cpp_interface_idlist_methods_without_local_layout() {
	source := 'fn (mut this IdList_ifacePtr) clear() {\n\tunsafe { free(this.list) }\n}\n\nfn (mut this IdList_ifacePtr) delete_contents(clear_2 bool) {\n\tfor i := 0; i < this.num_field; i++ {\n\t\tunsafe { free(this.list[i]) }\n\t}\n}\n'
	rewritten := rewrite_cpp_interface_idlists(source, {
		'IdList_ifacePtr': 'Iface'
	})
	assert rewritten.contains('this.list = []Iface{}')
	assert rewritten.contains('this.list[i] = Iface(unsafe { nil })')
	assert !rewritten.contains('free(this.list')
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

fn test_strict_sdl_version_abi_declarations() {
	assert 'SDL_GetVersion' in c_known_fn_names
	assert 'SDL_GetCurrentVideoDriver' in c_known_fn_names
	for c_name in ['isalpha', 'localtime_r', 'realloc', 'strftime', 'time', 'vfprintf', 'vprintf',
		'vsnprintf', 'vsprintf',
		'mach_absolute_time', 'strstr', 'stbi_load_from_memory', 'stbi_failure_reason',
		'stbi_image_free', 'stbi_write_png_to_func', 'stbi_write_bmp_to_func',
		'stbi_write_tga_to_func', 'stbi_write_jpg_to_func'] {
		assert c_name in c_known_fn_names
	}
	mut out := strings.new_builder(512)
	write_strict_cpp_compat_declarations(mut out)
	declarations := out.str()
	assert declarations.contains('struct C.tm {')
	assert declarations.contains('\ttm_hour int')
	assert declarations.contains('fn C.realloc(voidptr, usize) voidptr')
	assert declarations.contains('fn C.strstr(&i8, &i8) &i8')
	assert declarations.contains('fn C.localtime_r(&i64, &C.tm) &C.tm')
	assert declarations.contains('fn C.mach_absolute_time() u64')
	assert c_known_symbol_v_name('__darwin_fd_isset') == 'C.__darwin_fd_isset'
	assert declarations.contains('fn C.stbi_write_png_to_func(&Stbi_write_func, voidptr, int, int, int, voidptr, int) int')
	assert declarations.contains('fn C.stbi_write_bmp_to_func(&Stbi_write_func, voidptr, int, int, int, voidptr) int')
	assert declarations.contains('fn C.vsnprintf(&i8, int, &i8, C.va_list) int')
	assert declarations.contains('fn C.vfprintf(&C.FILE, &i8, C.va_list) int')
	assert declarations.contains('fn C.vprintf(&i8, C.va_list) int')
	assert declarations.contains('struct C.SDL_version {')
	assert declarations.contains('fn C.SDL_GetVersion(&C.SDL_version)')
	assert declarations.contains('fn C.SDL_GetCurrentVideoDriver() &i8')
	assert declarations.contains('fn builtin_va_start(arg0 &C.va_list, arg1 voidptr) {}')
	assert declarations.contains('fn builtin_va_end(arg0 &C.va_list) {}')
	assert declarations.contains('fn builtin_va_copy(arg0 &C.va_list, arg1 &C.va_list) {}')
	mut sdl_out := strings.new_builder(512)
	write_strict_sdl_event_declarations(mut sdl_out)
	sdl_declarations := sdl_out.str()
	assert sdl_declarations.contains('union C.SDL_Event {\npub mut:\n\t@type u32')
	mut posix_out := strings.new_builder(512)
	write_strict_posix_record_declarations(mut posix_out)
	posix_declarations := posix_out.str()
	assert posix_declarations.contains('#include <sys/select.h>')
	assert posix_declarations.contains('fn C.__darwin_fd_isset(int, &C.fd_set) int')
}

fn test_used_external_lowercase_global_retains_c_extern_declaration() {
	mut translator := C2V{
		is_cpp: true
		is_dir: true
	}
	translator.used_global.add('mach_task_self_')
	declaration := Node{
		kind_str: 'VarDecl'
		name: 'mach_task_self_'
		class_modifier: 'extern'
		ast_type: AstJsonType{
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
	for name in ['open', 'setvbuf', 'strerror', 'getuid', 'ioctl', 'realpath', 'sigaction',
		'sysconf'] {
		translator.register_external_c_function_decl(&Node{
			kind_str: 'FunctionDecl'
			name: name
			mangled_name: '_' + name
			ast_type: AstJsonType{
				qualified: 'int ()'
			}
		})
		assert name !in translator.external_c_fn_declarations
		assert filter_name(name, false) == 'C.${name}'
	}
}

fn test_external_function_prescan_desugars_callback_typedef_parameter() {
	mut translator := C2V{}
	translator.register_external_c_function_decl(&Node{
		kind_str: 'FunctionDecl'
		name: 'SDL_CreateThread'
		mangled_name: '_SDL_CreateThread'
		ast_type: AstJsonType{
			qualified: 'SDL_Thread *(SDL_ThreadFunction, const char *, void *)'
		}
		inner: [
			Node{
				kind_str: 'ParmVarDecl'
				ast_type: AstJsonType{
					qualified: 'SDL_ThreadFunction'
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
	assert translator.external_c_fn_declarations['SDL_CreateThread'] ==
		'fn C.SDL_CreateThread(fn (voidptr) int, &i8, voidptr) &C.SDL_Thread'
}

fn test_external_global_prescan_desugars_function_pointer_typedef() {
	mut translator := C2V{}
	translator.used_global.add('qglBindProgramARB')
	translator.collect_used_external_c_global_decls(&Node{
		kind_str: 'VarDecl'
		name: 'qglBindProgramARB'
		class_modifier: 'extern'
		ast_type: AstJsonType{
			qualified: 'PFNGLBINDPROGRAMARBPROC'
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
				name: 'idGameEdit'
				inner: [
					Node{
						kind_str: 'CXXMethodDecl'
						name: 'FindEntity'
						is_virtual: true
						ast_type: AstJsonType{
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
		kind_str: 'VarDecl'
		name: 'gameEdit'
		class_modifier: 'extern'
		ast_type: AstJsonType{
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
				name: 'idNetworkSystem'
				inner: [
					Node{
						kind_str: 'CXXMethodDecl'
						name: 'Send'
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

fn test_early_abstract_scan_keeps_implemented_polymorphic_base_as_interface() {
	mut translator := C2V{
		project_dir_method_defs: {
			'/tmp/out|IdFile.read': true
		}
	}
	root := Node{
		inner: [
			Node{
				kind_str: 'CXXRecordDecl'
				name: 'idFile'
				inner: [
					Node{
						kind_str: 'CXXMethodDecl'
						name: 'Read'
						is_virtual: true
					},
				]
			},
			Node{
				kind_str: 'CXXRecordDecl'
				name: 'idMemoryFile'
				bases: [
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
	assert wrap_final_rendered_expr('on_stack = true\n(voidptr(usize(15)))', '&Item') ==
		'on_stack = true\n&Item((voidptr(usize(15))))'
	assert wrap_final_rendered_expr('allocate(size)', '&Item') == '&Item(allocate(size))'
}

fn test_strict_global_fixed_arrays_do_not_store_result_literals() {
	source := '@[weak] __global sentinel = [-1]!\n@[weak] __global table = [\n\t[1, 2]!,\n\t[3, 4]!\n]!\n@[weak] __global matrix = Mat2{ rows: [Vec2{}, Vec2{}]! }\n'
	rewritten := replace_strict_global_array_result_suffixes(source)
	assert rewritten.contains('__global sentinel = [-1]\n')
	assert rewritten.contains('\t[1, 2]!,')
	assert rewritten.contains('\t[3, 4]!\n]\n')
	assert rewritten.contains('matrix = Mat2{ rows: [Vec2{}, Vec2{}]! }')
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
	sanitized := sanitize_translated_output(source, false, false, ['set_contents', 'unlink_clip'])
	assert sanitized.contains('mut __c2v_mut_recv_0 := list.op_index2(0).get_physics()')
	assert sanitized.contains('__c2v_mut_recv_0.set_contents(1)')
	assert !sanitized.contains('__c2v_mut_recv_0.get_physics().set_contents(1)')
	assert sanitized.contains('mut __c2v_mut_recv_1 := list.op_index2(0).get_physics()')
	assert sanitized.contains('__c2v_mut_recv_1.unlink_clip()')
}

fn test_multiple_mut_receivers_on_one_line_are_materialized() {
	source := 'fn update(mut item Item) int {\n\treturn consume(item.camera().base().get_areas(), item.camera().base().get_num_areas())\n\titem.entity().get_animator().set_frame(1)\n}\n'
	sanitized := sanitize_translated_output(source, false, false, ['get_areas', 'get_num_areas',
		'get_animator', 'set_frame'])
	assert sanitized.contains('mut __c2v_mut_recv_0 := item.camera().base()')
	assert sanitized.contains('mut __c2v_mut_recv_1 := item.camera().base()')
	assert sanitized.contains('consume(__c2v_mut_recv_1.get_areas(), __c2v_mut_recv_0.get_num_areas())')
	assert sanitized.contains('mut __c2v_mut_recv_2 := item.entity().get_animator()')
	assert sanitized.contains('__c2v_mut_recv_2.set_frame(1)')
}

fn test_indexed_mut_receiver_in_assignment_rhs_is_detected() {
	line := '__c2v_condition_1 := (this.children).op_index2(c).contains2(&(this.children).op_index2(c).draw_rect, this.gui.cursor_x(), this.gui.cursor_y())'
	receiver, tail, found := split_mut_receiver_call_expr(line, ['contains2'])
	assert found
	assert receiver == '(this.children).op_index2(c)'
	assert tail.starts_with('.contains2(')
	sanitized := sanitize_translated_output(line, false, false, []string{})
	assert sanitized.contains('mut __c2v_mut_recv_0 := (this.children).op_index2(c)')
	assert sanitized.contains('__c2v_condition_1 := __c2v_mut_recv_0.contains2(')
	compound := 'if ((this.children).op_index2(c).visible).data && (this.children).op_index2(c).contains2(&(this.children).op_index2(c).draw_rect, this.gui.cursor_x(), this.gui.cursor_y()) && !((this.children).op_index2(c).no_events).data {\n}\n'
	compound_sanitized := sanitize_translated_output(compound, false, false, []string{})
	assert compound_sanitized.contains('mut __c2v_mut_recv_0 := (this.children).op_index2(c)')
	assert compound_sanitized.contains('__c2v_condition_1 := __c2v_mut_recv_0.contains2('), compound_sanitized
}

fn test_doom_id_game_local_injection_does_not_skip_later_sanitizers() {
	source := 'struct IdGameLocal {\n\tvalue int\n}\n\nfn update(mut item Item) {\n\titem.get_entity().hide()\n}\n'
	sanitized := sanitize_translated_output(source, false, true, ['hide'])
	assert sanitized.contains('struct IdGameLocal {\n\tend_level &IdTarget_EndLevel\n\tmsec_precise int\n\tsuface_type_names [32]&i8')
	assert sanitized.contains('mut __c2v_mut_recv_0 := item.get_entity()')
	assert sanitized.contains('__c2v_mut_recv_0.hide()')
}

fn test_doom_compile_forms_use_canonical_engine_globals() {
	source := 'idLib_common.printf(c"x")\nidLib_sys.generate_mouse_move_event(0, 0)\nidLib_cvarSystem.get_c_var_bool(c"x")\nidLib_fileSystem.read_file(c"x", unsafe { nil }, unsafe { nil })\nret := if isDemoFnPtr != unsafe { nil } { isDemoFnPtr() } else { false }\ndelta.init(unsafe { if base != nil { &base.state } else { nil } })\ngameExport.game = game\nvalue := gameLocal.suface_type_names[0]\n'
	mut sanitized := strings.new_builder(source.len)
	for line in source.split_into_lines() {
		first_pass := sanitize_doom_generated_compile_forms(line, false)
		sanitized.writeln(sanitize_doom_generated_compile_forms(first_pass, false))
	}
	result := sanitized.str()
	assert result.contains('common.printf')
	assert result.contains('sys.generate_mouse_move_event')
	assert result.contains('cvarSystem.get_c_var_bool')
	assert result.contains('fileSystem.read_file')
	assert result.contains('isDemoFnPtr')
	assert !result.contains('C.C.')
	assert result.contains('unsafe { if base != nil { &base.state } else { nil } }')
	assert !result.contains('unsafe { if base != nil { &base.state } else { unsafe { nil } } }')
	assert result.contains('gameExport.game = &gameLocal')
	assert result.contains('id_game_local_suface_type_names[0]')
	mut compat := strings.new_builder(256)
	mut c := C2V{}
	c.write_cpp_compat_globals(mut compat)
	compatibility := compat.str()
	assert compatibility.contains('fn C.atan2f(f32, f32) f32')
	assert compatibility.contains('const id_math_m_deg_2_rad = m_deg2rad')
}

fn test_postformatted_doom_output_uses_direct_darwin_fd_set_check() {
	source := "fn darwin_check_fd_set(a int, b voidptr) int {\n\tif usize(&C.__darwin_check_fd_set_overflow) != usize(0) {\n\t\treturn C.__darwin_check_fd_set_overflow(a, b, 0)\n\t} else {\n\t\treturn 1\n\t}\n}\n"
	sanitized := sanitize_postformatted_doom_output(source, false)
	assert sanitized.contains('\treturn C.__darwin_check_fd_set_overflow(a, b, 0)')
	assert !sanitized.contains('usize(&C.__darwin_check_fd_set_overflow)')
	strict_sanitized := sanitize_translated_output(source, false, false, [])
	assert strict_sanitized.contains('\treturn C.__darwin_check_fd_set_overflow(a, b, 0)')
	assert !strict_sanitized.contains('usize(&C.__darwin_check_fd_set_overflow)')
}

fn test_doom_event_definition_arguments_are_typed() {
	line := 'if ent.IdClass.responds_to(&eV_Activate) { ent.IdClass.process_event2(&eV_Activate, arg) }'
	rewritten := rewrite_doom_event_def_call_args(line)
	assert rewritten.contains('.responds_to(unsafe { &IdEventDef(&eV_Activate) })')
	assert rewritten.contains('.process_event2(unsafe { &IdEventDef(&eV_Activate) }, arg)')
}

fn test_doom_event_fallback_constants_are_addressable_globals() {
	source := 'const eV_Activate = int(0)\nconst ordinary = int(1)\n'
	rewritten := rewrite_doom_event_fallback_constants(source)
	assert rewritten.contains('@[weak] __global eV_Activate = IdEventDef{}')
	assert rewritten.contains('const ordinary = int(1)')
}

fn test_doom_global_stub_signatures_match_scalar_calls() {
	source := 'fn mem_alloc(args ...voidptr) voidptr {\n\treturn voidptr(0)\n}\nfn mem_free(args ...voidptr) {}\nfn pack_color(args ...voidptr) Dword { return 0 }\n'
	rewritten := sanitize_doom_globals_stub_output(source)
	assert rewritten.contains('fn mem_alloc(arg0 int) voidptr {')
	assert rewritten.contains('fn mem_free(arg0 voidptr) {')
	assert rewritten.contains('fn pack_color(arg0 &IdVec4) Dword {')
}

fn test_final_doom_project_output_repairs_reconciled_names_and_receivers() {
	source := "if C.false {}\nvalue := rB_VELOCITY_EXPONENT_BITS\nvalue2 := rB_VELOCITY_MANTISSA_BITS\ncolor := idPlayer_colorBarTable[0]\nadd_render_gui(temp, &render_entity.gui[i], args_2)\n\t\t\tgameLocal.entities[i].IdClass.process_event(unsafe { &IdEventDef(&eV_Player_DisableWeapon) })\nfile.write_float_string(c'}\\n')\n"
	rewritten := sanitize_final_doom_project_output(source)
	assert rewritten.contains('if false {}')
	assert rewritten.contains('RB_VELOCITY_EXPONENT_BITS')
	assert rewritten.contains('RB_VELOCITY_MANTISSA_BITS')
	assert rewritten.contains('color_bar_table[0]')
	assert rewritten.contains('add_render_gui(temp, render_entity.gui[i], args_2)')
	assert rewritten.contains('mut __c2v_target_entity := gameLocal.entities[i]')
	assert rewritten.contains("file.write_float_string(c'}\\n', voidptr(0))")
}

fn test_doom_id_game_local_fields_do_not_skip_following_sanitizers() {
	source := 'struct IdGameLocal {\n\tvalue int\n}\n\nfn run(mut item Item) {\n\titem.get_entity().hide()\n}\n'
	sanitized := sanitize_translated_output(source, false, true, ['hide'])
	assert sanitized.contains('struct IdGameLocal {\n\tend_level &IdTarget_EndLevel\n\tmsec_precise int\n\tsuface_type_names [32]&i8')
	assert sanitized.contains('mut __c2v_mut_recv_0 := item.get_entity()')
	assert sanitized.contains('__c2v_mut_recv_0.hide()')
}

fn test_reference_returning_call_assignment_dereferences_final_result() {
	source := 'fn assign(mut list IdList, value IdVec3) {\n\tunsafe { list.op_index2(0).to_vec32() = value }\n\tlist.op_index2(0).get_render_entity().visible = true\n}\n'
	sanitized := sanitize_translated_output(source, false, false, [])
	assert sanitized.contains('mut __c2v_lhs_tmp_0 := list.op_index2(0).to_vec32()')
	assert sanitized.contains('unsafe { *__c2v_lhs_tmp_0 = value }')
	assert sanitized.contains('mut __c2v_lhs_tmp_1 := list.op_index2(0)')
	assert sanitized.contains('__c2v_lhs_tmp_1.get_render_entity().visible = true')
}

fn test_parenthesized_pointer_deref_assignment_materializes_balanced_operand() {
	source := 'fn restore(mut list IdList, saved State) {\n\tunsafe { *((list.op_index2(0)).current) = saved }\n}\n'
	sanitized := sanitize_translated_output(source, false, false, [])
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
	input := 'C.someGlobal + otherGlobal + prefixotherGlobal + C.someGlobalSuffix + value.otherGlobal'
	expected := 'some_global + other_global + prefixotherGlobal + C.someGlobalSuffix + value.other_global'
	assert replace_defined_global_refs_in_text(input, replacements) == expected
}

fn test_single_module_skeleton_cleanup() {
	source := '@[translated]\nmodule main\n\n// c2v skeleton dependency declarations\ntype Mode_t = int\nstruct Service {}\n\nstruct State {\n}\nstruct State {\n\tvalue int\n}\ninterface Service {\n\trun()\n}\nCLASS ignored_macro\nfn service() Service {\n\treturn Service{}\n}\n'
	without_dependencies := remove_skeleton_dependency_stubs(source)
	assert !without_dependencies.contains('c2v skeleton dependency declarations')
	without_empty_stubs := remove_duplicate_external_empty_struct_stubs(without_dependencies)
	assert without_empty_stubs.count('struct State {') == 1
	assert !without_empty_stubs.contains('struct Service {}')
	commented := comment_bare_cpp_class_markers(without_empty_stubs)
	assert commented.contains('// CLASS ignored_macro')
	rewritten := rewrite_skeleton_interface_default_returns(commented, {
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

fn test_comment_multiline_cpp_class_markers() {
	source := 'CLASS\nidCurve_Bezier\nCLASS idCurve_Spline\nstruct State {}\n'
	commented := comment_bare_cpp_class_markers(source)
	assert commented.contains('// CLASS\n// idCurve_Bezier')
	assert commented.contains('// CLASS idCurve_Spline')
	assert commented.contains('struct State {}')
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

fn test_nested_idblockalloc_records_do_not_get_allocator_methods() {
	mut translator := C2V{}
	methods := translator.collect_synthetic_template_stub_methods([
		'IdBlockAlloc_item_s_64',
		'IdBlockAlloc_item_s_64_Block_s',
		'IdBlockAlloc_item_s_64_Element_s_Source',
	], map[string]bool{})
	assert methods.contains('fn (this IdBlockAlloc_item_s_64) alloc()')
	assert !methods.contains('fn (this IdBlockAlloc_item_s_64_Block_s) alloc()')
	assert !methods.contains('fn (this IdBlockAlloc_item_s_64_Element_s_Source) alloc()')
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
		is_cpp: true
		files: [main_path]
		cur_file: main_path
	}
	mut tree := Node{
		kind: .translation_unit_decl
		kind_str: 'TranslationUnitDecl'
		inner: [
			Node{
				kind: .cxx_record_decl
				kind_str: 'CXXRecordDecl'
				location: NodeLocation{
					file: header_path
				}
				inner: [
					Node{
						kind: .cxx_method_decl
						kind_str: 'CXXMethodDecl'
						inner: [
							Node{
								kind: .compound_stmt
								kind_str: 'CompoundStmt'
							},
						]
					},
				]
			},
			Node{
				kind: .function_decl
				kind_str: 'FunctionDecl'
				inner: [
					Node{
						kind: .compound_stmt
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
		is_cpp: true
		is_dir: true
		project_generate_stubs: true
		project_require_no_stubs: false
		files: ['main.cpp', 'dependency.h']
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
	assert translator.skeleton_default_value('IdService') == 'IdService(unsafe { nil })'
}

fn test_cpp_constructor_signature_metadata() {
	assert cpp_constructor_signature_key('&IdPolynomial', 'void (  float,\tfloat )') == 'IdPolynomial|void ( float, float )'
	assert cpp_constructor_c_param_types('void (const idVec3 &, idList<int>, void (*)(int, float))') == [
		'const idVec3 &',
		'idList<int>',
		'void (*)(int, float)',
	]
	assert cpp_v_parameter_name('mut value &IdVec3') == 'value'
	assert cpp_v_parameter_name('count int') == 'count'
	assert cpp_static_member_v_name('idRegister', 'REGCOUNT', false) == 'id_register_regcount'
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
		kind: .while_stmt
		inner: [
			Node{
				kind: .integer_literal
				value: 1
			},
			Node{
				kind: .compound_stmt
			},
		]
	})
	assert !translator.is_unconditional_c_while(&Node{
		kind: .while_stmt
		inner: [
			Node{
				kind: .integer_literal
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
		kind: .default_stmt
		inner: [Node{
			kind: .case_stmt
			inner: [
				Node{
					kind: .integer_literal
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
		kind: .implicit_cast_expr
		inner: [Node{
			kind: .cxx_this_expr
		}]
	})
	assert !cpp_receiver_is_direct_this(Node{
		kind: .member_expr
		name: 'field'
		inner: [Node{
			kind: .cxx_this_expr
		}]
	})
}

fn test_typed_char_pointer_is_not_idstr() {
	translator := C2V{}
	node := Node{
		kind: .member_expr
		name: 'name'
		ast_type: AstJsonType{
			qualified: 'char *'
		}
	}
	assert !translator.cpp_expr_is_idstr_value(node, 'other.name')
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
	node := Node{
		kind: .function_decl
		name: 'SDL_GetWindowSize'
		mangled_name: '_SDL_GetWindowSize'
		ast_type: AstJsonType{
			qualified: 'void (SDL_Window *, int *, int *)'
		}
		inner: [
			Node{
				kind: .parm_var_decl
				ast_type: AstJsonType{
					qualified: 'SDL_Window *'
				}
			},
			Node{
				kind: .parm_var_decl
				ast_type: AstJsonType{
					qualified: 'int *'
				}
			},
			Node{
				kind: .parm_var_decl
				ast_type: AstJsonType{
					qualified: 'int *'
				}
			},
		]
	}
	assert is_c_linkage_function_decl(&node)
	cpp_node := Node{
		kind: .function_decl
		name: 'sprintf'
		mangled_name: '_Z7sprintfR5idStrPKcz'
	}
	assert !is_c_linkage_function_decl(&cpp_node)
	translator.register_external_c_function_decl(&node)
	assert translator.external_c_fn_declarations['SDL_GetWindowSize'] == 'fn C.SDL_GetWindowSize(&C.SDL_Window, &int, &int)'
	assert 'SDL_GetWindowSize' in translator.extern_fns
	assert convert_type('Uint32').name == 'u32'
	assert convert_type('SDL_Scancode').name == 'int'
	assert convert_type('SDL_Event').name == 'C.SDL_Event'
	assert convert_type('SDL_JoystickGUID').name == 'C.SDL_GUID'
	assert convert_type('ALsizei').name == 'int'
	assert convert_type('ALuint *').name == '&u32'
	assert convert_type('LPALGENEFFECTS').name == 'fn (int, &u32)'
	assert convert_type('LPALCRESETDEVICESOFT').name == 'fn (voidptr, &int) u8'
	assert convert_type('struct stat').name == 'C.stat'
	assert convert_type('int (* _Nonnull)(const void *, const void *)').name == 'fn (voidptr, voidptr) int'
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
		qualified: 'PFNGLCOMPRESSEDTEXIMAGE2DARBPROC'
		desugared_qualified: 'void (*)(GLenum, GLint, const void *)'
	}) == 'void (*)(GLenum, GLint, const void *)'
	assert c_style_cast_type_spelling(AstJsonType{
		qualified: 'time_t'
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
	receiver, tail, found := split_mut_receiver_call_expr('depth = (game_edit as IdGameEditExt).get_interpreter_call_stack_depth(interpreter)',
		['get_interpreter_call_stack_depth'])
	assert found
	assert receiver == '(game_edit as IdGameEditExt)'
	assert tail == '.get_interpreter_call_stack_depth(interpreter)'
}

fn test_stateless_abstract_implementation_remains_concrete() {
	mut translator := C2V{
		outv: '/tmp/c2v-test/output.v'
		cpp_abstract_types: {
			'IdSIMDProcessor': true
		}
		cpp_class_bases: {
			'IdSIMD_Generic': ['IdSIMDProcessor']
		}
		project_dir_method_defs: {
			'/tmp/c2v-test|IdSIMD_Generic.add': true
		}
	}
	record := Node{
		kind: .cxx_record_decl
		name: 'idSIMD_Generic'
		inner: [Node{
			kind: .cxx_method_decl
			name: 'Add'
			is_virtual: true
		}]
	}
	assert !translator.cpp_record_is_abstract_interface(&record)
}

fn test_concrete_template_alias_precedes_file_collision_alias() {
	translator := C2V{
		file_type_alias_names: {
			'Element_t': 'Element_t_tr_trisurf'
		}
		cpp_template_type_aliases: {
			'Element_t': 'IdBlockAlloc_srfTriangles_s_256_Element_s'
		}
	}
	assert translator.convert_type('Element_t').name == 'IdBlockAlloc_srfTriangles_s_256_Element_s'
	assert convert_type('__uint16_t').name == 'u16'
	assert convert_type('u_int32_t').name == 'u32'
	assert convert_type('clock_serv_t').name == 'u32'
	assert convert_type('struct ifaddrs').name == 'C.ifaddrs'
}

fn test_zero_initializer_accepts_uninitialized_array_filler_nodes() {
	assert is_zero_initializer_expr(Node{
		kind: .init_list_expr
		array_filler: [Node{
			kind_str: 'ImplicitValueInitExpr'
		}]
	})
	assert is_zero_initializer_expr(Node{
		kind: .init_list_expr
		inner: [Node{
			kind: .cxx_construct_expr
			ast_type: AstJsonType{
				qualified: 'timespec'
			}
			ctor_type: AstJsonType{
				qualified: 'void () throw()'
			}
		}]
	})
}
