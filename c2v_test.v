module main

import strings
import json2

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
	check_ct('struct constraintFlags_s', 'ConstraintFlags_s')
	check_ct('const enum myEnum', 'MyEnum')
}

fn test_normalize_cpp_template_enum_arguments() {
	values := {
		'ev_boolean': i64(14)
	}
	assert normalize_cpp_template_enum_arguments('idScriptVariable<int, ev_boolean, int>', values) == 'idScriptVariable<int, 14, int>'
}

fn test_cpp_abstract_pointer_type_conversion() {
	c := C2V{
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

fn test_strict_sdl_version_abi_declarations() {
	assert 'SDL_GetVersion' in c_known_fn_names
	assert 'SDL_GetCurrentVideoDriver' in c_known_fn_names
	mut out := strings.new_builder(512)
	write_strict_cpp_compat_declarations(mut out)
	declarations := out.str()
	assert declarations.contains('struct C.SDL_version {')
	assert declarations.contains('fn C.SDL_GetVersion(&C.SDL_version)')
	assert declarations.contains('fn C.SDL_GetCurrentVideoDriver() &i8')
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

fn test_filter_single_module_skeleton_globals() {
	source := '@[translated]\nmodule main\n\nstruct Service {}\nfn helper() {}\nfn repeated() {}\nfn repeated(args ...voidptr) {}\nfn (this Wrapper) value(args ...voidptr) int { return 0 }\nconst local_value = 0\nconst fallback_value = 1\n@[weak] __global local_value int\n@[weak] __global fallback_value int\n@[weak] __global duplicate int\n@[weak] __global duplicate int\n@[weak] __global retained int\nfn main() {}\n'
	filtered := filter_single_module_skeleton_globals(source, {
		'Service': true
	}, map[string]bool{}, {
		'helper': true
	}, {
		'Wrapper.value': true
	}, {
		'local_value': true
	})
	assert !filtered.contains('struct Service {}')
	assert !filtered.contains('fn helper()')
	assert !filtered.contains('fn (this Wrapper) value')
	assert filtered.count('fn repeated') == 1
	assert !filtered.contains('__global local_value')
	assert !filtered.contains('__global fallback_value')
	assert filtered.count('__global duplicate') == 1
	assert filtered.contains('__global retained int')
}

fn test_filter_single_module_skeleton_globals_removes_interface_methods() {
	source := 'module main\n\nfn (this Service) run() {\n}\n\nfn (this Record) run() {\n}\n'
	filtered := filter_single_module_skeleton_globals(source, {
		'Service': true
		'Record':  true
	}, {
		'Service': true
	}, map[string]bool{}, map[string]bool{}, map[string]bool{})
	assert !filtered.contains('fn (this Service) run()')
	assert filtered.contains('fn (this Record) run()')
}
