// Since C2V uses Clang AST to "parse" C code and output of this parse step is a JSON file that describes code "nodes",
// names of nodes from this JSON are converted into enum form to simplify working on a code level.
//
// This file contains 2 main things - constant str_to_node_kind_map and NodeKind enum declaration itself.
// str_to_node_kind_map contains <node_name, enum value> data pairs, so to add a new node that C2V should support,
// simply define a new member of NodeKind enum (that is snake_case name of node) and add it to str_to_node_kind_map.
//
// You can also generate NodeKind enum and str_to_node_kind_map map code. See tools/node_kind_gen/gen_node_kind_code.v for details.

module main

// Take into account that members of this enum are sorted alphabetically A -> Z, but 'bad' value is on the top.
// Use this style when defining a new record.
enum NodeKind {
	bad // is used only inside a C2V to mark unknown or corrupted node.
	access_spec_decl
	acquire_capability_attr
	addr_label_expr
	aligned_attr
	alloc_size_attr
	always_inline_attr
	analyzer_no_return_attr
	array_filler
	array_subscript_expr
	asm_label_attr
	assert_exclusive_lock_attr
	atomic_expr
	availability_attr
	binary_operator
	block_command_comment
	block_expr
	break_stmt
	builtin_template_decl
	builtin_type
	call_expr
	capability_attr
	case_stmt
	character_literal
	class_decl
	class_template
	class_template_decl
	class_template_partial_specialization
	class_template_partial_specialization_decl
	class_template_specialization
	class_template_specialization_decl
	cold_attr
	compound_assign_operator
	compound_literal_expr
	compound_stmt
	conditional_operator
	constant_array_type
	constant_expr
	const_attr
	continue_stmt
	c_style_cast_expr
	cx_cursor_kind
	cxx
	cxx_access_specifier
	cxx_bind_temporary_expr
	cxx_bool_literal_expr
	cxx_catch_stmt
	cxx_const_cast_expr
	cxx_construct_expr
	cxx_constructor
	cxx_constructor_decl
	cxx_conversion
	cxx_conversion_decl
	cxx_ctor_initializer
	cxx_default_arg_expr
	cxx_default_init_expr
	cxx_delete_expr
	cxx_dependent_scope_member_expr
	cxx_destructor
	cxx_destructor_decl
	cxx_dynamic_cast_expr
	cxx_for_range_stmt
	cxx_functional_cast_expr
	cxx_member_call_expr
	cxx_method
	cxx_method_decl
	cxx_new_expr
	cxx_noexcept_expr
	cxx_null_ptr_literal_expr
	cxx_operator_call_expr
	cxx_pseudo_destructor_expr
	cxx_record
	cxx_record_decl
	cxx_reinterpret_cast_expr
	cxx_scalar_value_init_expr
	cxx_static_cast_expr
	cxx_temporary_object_expr
	cxx_this_expr
	cxx_throw_expr
	cxx_try_stmt
	cxx_typeid_expr
	cxx_unresolved_construct_expr
	decayed_type
	decl_ref_expr
	decl_stmt
	decltype_type
	default_stmt
	dependent_name_type
	dependent_scope_decl_ref_expr
	dependent_template_specialization_type
	deprecated_attr
	diagnose_if_attr
	disable_tail_calls_attr
	do_stmt
	elaborated_type
	enable_if_attr
	@enum
	enum_constant_decl
	enum_decl
	enum_type
	expr_with_cleanups
	field
	field_decl
	fixed_point_literal
	floating_literal
	format_arg_attr
	format_attr
	for_stmt
	friend_decl
	full_comment
	function
	function_decl
	function_no_proto_type
	function_proto_type
	function_template
	function_template_decl
	gcc_asm_stmt
	generic_selection_expr
	gnu_null_expr
	goto_stmt
	guarded_by_attr
	html_end_tag_comment
	html_start_tag_comment
	if_stmt
	imaginary_literal
	implicit_cast_expr
	implicit_value_init_expr
	incomplete_array_type
	indirect_field_decl
	indirect_goto_stmt
	init_list_expr
	injected_class_name_type
	inline_command_comment
	integer_literal
	invalid_code
	invalid_file
	label_ref
	label_stmt
	lambda_expr
	linkage_spec
	linkage_spec_decl
	l_value_reference_type
	materialize_temporary_expr
	max_field_alignment_attr
	member_expr
	member_pointer_type
	member_ref
	member_ref_expr
	module_import
	ms_asm_stmt
	namespace
	namespace_alias
	namespace_decl
	namespace_ref
	no_decl_found
	no_escape_attr
	no_inline_attr
	non_type_template_parameter
	non_type_template_parm_decl
	no_sanitize_attr
	no_throw_attr
	not_implemented
	null
	null_stmt
	obj_c_at_catch_stmt
	obj_c_at_finally_stmt
	obj_c_at_synchronized_stmt
	obj_c_at_throw_stmt
	obj_c_at_try_stmt
	obj_c_autorelease_pool_stmt
	obj_c_availability_check_expr
	obj_c_bool_literal_expr
	obj_c_bridged_cast_expr
	obj_c_category_decl
	obj_c_category_impl_decl
	obj_c_class_method_decl
	obj_c_class_ref
	obj_c_dynamic_decl
	obj_c_encode_expr
	obj_c_for_collection_stmt
	obj_c_implementation_decl
	obj_c_instance_method_decl
	obj_c_interface_decl
	obj_c_ivar_decl
	obj_c_message_expr
	obj_c_property_decl
	obj_c_protocol_decl
	obj_c_protocol_expr
	obj_c_protocol_ref
	obj_c_selector_expr
	obj_c_self_expr
	obj_c_string_literal
	obj_c_super_class_ref
	obj_c_synthesize_decl
	offset_of_expr
	omp_array_section_expr
	omp_atomic_directive
	omp_barrier_directive
	omp_cancel_directive
	omp_cancellation_point_directive
	omp_critical_directive
	omp_distribute_directive
	omp_distribute_parallel_for_directive
	omp_distribute_parallel_for_simd_directive
	omp_distribute_simd_directive
	omp_flush_directive
	omp_for_directive
	omp_for_simd_directive
	omp_master_directive
	omp_ordered_directive
	omp_parallel_directive
	omp_parallel_for_directive
	omp_parallel_for_simd_directive
	omp_parallel_sections_directive
	omp_section_directive
	omp_sections_directive
	omp_simd_directive
	omp_single_directive
	omp_target_data_directive
	omp_target_directive
	omp_target_enter_data_directive
	omp_target_exit_data_directive
	omp_target_parallel_directive
	omp_target_parallel_for_directive
	omp_target_parallel_for_simd_directive
	omp_target_simd_directive
	omp_target_teams_directive
	omp_target_teams_distribute_directive
	omp_target_teams_distribute_parallel_for_directive
	omp_target_teams_distribute_parallel_for_simd_directive
	omp_target_teams_distribute_simd_directive
	omp_target_update_directive
	omp_task_directive
	omp_taskgroup_directive
	omp_task_loop_directive
	omp_task_loop_simd_directive
	omp_taskwait_directive
	omp_taskyield_directive
	omp_teams_directive
	omp_teams_distribute_directive
	omp_teams_distribute_parallel_for_directive
	omp_teams_distribute_parallel_for_simd_directive
	omp_teams_distribute_simd_directive
	opaque_value_expr
	original
	overload_candidate
	overloaded_decl_ref
	override_attr
	overrides
	packed_attr
	pack_expansion_expr
	pack_expansion_type
	paragraph_comment
	paren_expr
	paren_list_expr
	paren_type
	parm_decl
	parm_var_decl
	pointer_type
	predefined_expr
	private
	protected
	public
	pure_attr
	qual_type
	record
	record_decl
	record_type
	release_capability_attr
	requires_capability_attr
	restrict_attr
	return_stmt
	returns_twice_attr
	ruct
	r_value_reference_type
	scoped_lockable_attr
	seh_except_stmt
	seh_finally_stmt
	seh_leave_stmt
	seh_try_stmt
	size_of_pack_expr
	static_assert
	static_assert_decl
	stmt_expr
	string_literal
	struct_decl
	subst_non_type_template_parm_expr
	subst_template_type_parm_type
	switch_stmt
	template_argument
	template_ref
	template_specialization_type
	template_template_parameter
	template_template_parm_decl
	template_type_parameter
	template_type_parm
	template_type_parm_decl
	template_type_parm_type
	text_comment
	translation_unit
	translation_unit_decl
	type_alias_decl
	type_alias_template_decl
	typedef
	typedef_decl
	typedef_type
	type_ref
	type_visibility_attr
	unary_expr
	unary_expr_or_type_trait_expr
	unary_operator
	unary_transform_type
	unexposed_attr
	unexposed_decl
	unexposed_expr
	unexposed_stmt
	unhandled
	union_decl
	unresolved_lookup_expr
	unresolved_member_expr
	unused_attr
	using_decl
	using_declaration
	using_directive
	using_directive_decl
	using_shadow_decl
	va_arg_expr
	var_decl
	variable_ref
	virtual
	visibility_attr
	warn_unused_result_attr
	while_stmt
}

// Take into account that records of this map are sorted alphabetically A -> Z, but 'bad' value is on the top.
// Use this style when defining a new record.
const str_to_node_kind_map = {
	'BAD':                                              NodeKind.bad // is used only inside a C2V to mark unknown or corrupted node.
	'AccessSpecDecl':                                   .access_spec_decl
	'AcquireCapabilityAttr':                            .acquire_capability_attr
	'AddrLabelExpr':                                    .addr_label_expr
	'AlignedAttr':                                      .aligned_attr
	'AllocSizeAttr':                                    .alloc_size_attr
	'AlwaysInlineAttr':                                 .always_inline_attr
	'AnalyzerNoReturnAttr':                             .analyzer_no_return_attr
	'ArrayFiller':                                      .array_filler
	'ArraySubscriptExpr':                               .array_subscript_expr
	'AsmLabelAttr':                                     .asm_label_attr
	'AssertExclusiveLockAttr':                          .assert_exclusive_lock_attr
	'AtomicExpr':                                       .atomic_expr
	'AvailabilityAttr':                                 .availability_attr
	'BinaryOperator':                                   .binary_operator
	'BlockCommandComment':                              .block_command_comment
	'BlockExpr':                                        .block_expr
	'BreakStmt':                                        .break_stmt
	'BuiltinTemplateDecl':                              .builtin_template_decl
	'BuiltinType':                                      .builtin_type
	'CallExpr':                                         .call_expr
	'CapabilityAttr':                                   .capability_attr
	'CaseStmt':                                         .case_stmt
	'CharacterLiteral':                                 .character_literal
	'ClassDecl':                                        .class_decl
	'ClassTemplate':                                    .class_template
	'ClassTemplateDecl':                                .class_template_decl
	'ClassTemplatePartialSpecialization':               .class_template_partial_specialization
	'ClassTemplatePartialSpecializationDecl':           .class_template_partial_specialization_decl
	'ClassTemplateSpecialization':                      .class_template_specialization
	'ClassTemplateSpecializationDecl':                  .class_template_specialization_decl
	'ColdAttr':                                         .cold_attr
	'CompoundAssignOperator':                           .compound_assign_operator
	'CompoundLiteralExpr':                              .compound_literal_expr
	'CompoundStmt':                                     .compound_stmt
	'ConditionalOperator':                              .conditional_operator
	'ConstantArrayType':                                .constant_array_type
	'ConstantExpr':                                     .constant_expr
	'ConstAttr':                                        .const_attr
	'ContinueStmt':                                     .continue_stmt
	'CStyleCastExpr':                                   .c_style_cast_expr
	'CXCursorKind':                                     .cx_cursor_kind
	'CXX':                                              .cxx
	'CXXAccessSpecifier':                               .cxx_access_specifier
	'CXXBindTemporaryExpr':                             .cxx_bind_temporary_expr
	'CXXBoolLiteralExpr':                               .cxx_bool_literal_expr
	'CXXCatchStmt':                                     .cxx_catch_stmt
	'CXXConstCastExpr':                                 .cxx_const_cast_expr
	'CXXConstructExpr':                                 .cxx_construct_expr
	'CXXConstructor':                                   .cxx_constructor
	'CXXConstructorDecl':                               .cxx_constructor_decl
	'CXXConversion':                                    .cxx_conversion
	'CXXConversionDecl':                                .cxx_conversion_decl
	'CXXCtorInitializer':                               .cxx_ctor_initializer
	'CXXDefaultArgExpr':                                .cxx_default_arg_expr
	'CXXDefaultInitExpr':                               .cxx_default_init_expr
	'CXXDeleteExpr':                                    .cxx_delete_expr
	'CXXDependentScopeMemberExpr':                      .cxx_dependent_scope_member_expr
	'CXXDestructor':                                    .cxx_destructor
	'CXXDestructorDecl':                                .cxx_destructor_decl
	'CXXDynamicCastExpr':                               .cxx_dynamic_cast_expr
	'CXXForRangeStmt':                                  .cxx_for_range_stmt
	'CXXFunctionalCastExpr':                            .cxx_functional_cast_expr
	'CXXMemberCallExpr':                                .cxx_member_call_expr
	'CXXMethod':                                        .cxx_method
	'CXXMethodDecl':                                    .cxx_method_decl
	'CXXNewExpr':                                       .cxx_new_expr
	'CXXNoexceptExpr':                                  .cxx_noexcept_expr
	'CXXNullPtrLiteralExpr':                            .cxx_null_ptr_literal_expr
	'CXXOperatorCallExpr':                              .cxx_operator_call_expr
	'CXXPseudoDestructorExpr':                          .cxx_pseudo_destructor_expr
	'CXXRecord':                                        .cxx_record
	'CXXRecordDecl':                                    .cxx_record_decl
	'CXXReinterpretCastExpr':                           .cxx_reinterpret_cast_expr
	'CXXScalarValueInitExpr':                           .cxx_scalar_value_init_expr
	'CXXStaticCastExpr':                                .cxx_static_cast_expr
	'CXXTemporaryObjectExpr':                           .cxx_temporary_object_expr
	'CXXThisExpr':                                      .cxx_this_expr
	'CXXThrowExpr':                                     .cxx_throw_expr
	'CXXTryStmt':                                       .cxx_try_stmt
	'CXXTypeidExpr':                                    .cxx_typeid_expr
	'CXXUnresolvedConstructExpr':                       .cxx_unresolved_construct_expr
	'DecayedType':                                      .decayed_type
	'DeclRefExpr':                                      .decl_ref_expr
	'DeclStmt':                                         .decl_stmt
	'DecltypeType':                                     .decltype_type
	'DefaultStmt':                                      .default_stmt
	'DependentNameType':                                .dependent_name_type
	'DependentScopeDeclRefExpr':                        .dependent_scope_decl_ref_expr
	'DependentTemplateSpecializationType':              .dependent_template_specialization_type
	'DeprecatedAttr':                                   .deprecated_attr
	'DiagnoseIfAttr':                                   .diagnose_if_attr
	'DisableTailCallsAttr':                             .disable_tail_calls_attr
	'DoStmt':                                           .do_stmt
	'ElaboratedType':                                   .elaborated_type
	'EnableIfAttr':                                     .enable_if_attr
	'Enum':                                             .@enum
	'EnumConstantDecl':                                 .enum_constant_decl
	'EnumDecl':                                         .enum_decl
	'EnumType':                                         .enum_type
	'ExprWithCleanups':                                 .expr_with_cleanups
	'Field':                                            .field
	'FieldDecl':                                        .field_decl
	'FixedPointLiteral':                                .fixed_point_literal
	'FloatingLiteral':                                  .floating_literal
	'FormatArgAttr':                                    .format_arg_attr
	'FormatAttr':                                       .format_attr
	'ForStmt':                                          .for_stmt
	'FriendDecl':                                       .friend_decl
	'FullComment':                                      .full_comment
	'Function':                                         .function
	'FunctionDecl':                                     .function_decl
	'FunctionNoProtoType':                              .function_no_proto_type
	'FunctionProtoType':                                .function_proto_type
	'FunctionTemplate':                                 .function_template
	'FunctionTemplateDecl':                             .function_template_decl
	'GCCAsmStmt':                                       .gcc_asm_stmt
	'GenericSelectionExpr':                             .generic_selection_expr
	'GNUNullExpr':                                      .gnu_null_expr
	'GotoStmt':                                         .goto_stmt
	'GuardedByAttr':                                    .guarded_by_attr
	'HTMLEndTagComment':                                .html_end_tag_comment
	'HTMLStartTagComment':                              .html_start_tag_comment
	'IfStmt':                                           .if_stmt
	'ImaginaryLiteral':                                 .imaginary_literal
	'ImplicitCastExpr':                                 .implicit_cast_expr
	'ImplicitValueInitExpr':                            .implicit_value_init_expr
	'IncompleteArrayType':                              .incomplete_array_type
	'IndirectFieldDecl':                                .indirect_field_decl
	'IndirectGotoStmt':                                 .indirect_goto_stmt
	'InitListExpr':                                     .init_list_expr
	'InjectedClassNameType':                            .injected_class_name_type
	'InlineCommandComment':                             .inline_command_comment
	'IntegerLiteral':                                   .integer_literal
	'InvalidCode':                                      .invalid_code
	'InvalidFile':                                      .invalid_file
	'LabelRef':                                         .label_ref
	'LabelStmt':                                        .label_stmt
	'LambdaExpr':                                       .lambda_expr
	'LinkageSpec':                                      .linkage_spec
	'LinkageSpecDecl':                                  .linkage_spec_decl
	'LValueReferenceType':                              .l_value_reference_type
	'MaterializeTemporaryExpr':                         .materialize_temporary_expr
	'MaxFieldAlignmentAttr':                            .max_field_alignment_attr
	'MemberExpr':                                       .member_expr
	'MemberPointerType':                                .member_pointer_type
	'MemberRef':                                        .member_ref
	'MemberRefExpr':                                    .member_ref_expr
	'ModuleImport':                                     .module_import
	'MSAsmStmt':                                        .ms_asm_stmt
	'Namespace':                                        .namespace
	'NamespaceAlias':                                   .namespace_alias
	'NamespaceDecl':                                    .namespace_decl
	'NamespaceRef':                                     .namespace_ref
	'NoDeclFound':                                      .no_decl_found
	'NoEscapeAttr':                                     .no_escape_attr
	'NoInlineAttr':                                     .no_inline_attr
	'NonTypeTemplateParameter':                         .non_type_template_parameter
	'NonTypeTemplateParmDecl':                          .non_type_template_parm_decl
	'NoSanitizeAttr':                                   .no_sanitize_attr
	'NoThrowAttr':                                      .no_throw_attr
	'NotImplemented':                                   .not_implemented
	'Null':                                             .null
	'NullStmt':                                         .null_stmt
	'ObjCAtCatchStmt':                                  .obj_c_at_catch_stmt
	'ObjCAtFinallyStmt':                                .obj_c_at_finally_stmt
	'ObjCAtSynchronizedStmt':                           .obj_c_at_synchronized_stmt
	'ObjCAtThrowStmt':                                  .obj_c_at_throw_stmt
	'ObjCAtTryStmt':                                    .obj_c_at_try_stmt
	'ObjCAutoreleasePoolStmt':                          .obj_c_autorelease_pool_stmt
	'ObjCAvailabilityCheckExpr':                        .obj_c_availability_check_expr
	'ObjCBoolLiteralExpr':                              .obj_c_bool_literal_expr
	'ObjCBridgedCastExpr':                              .obj_c_bridged_cast_expr
	'ObjCCategoryDecl':                                 .obj_c_category_decl
	'ObjCCategoryImplDecl':                             .obj_c_category_impl_decl
	'ObjCClassMethodDecl':                              .obj_c_class_method_decl
	'ObjCClassRef':                                     .obj_c_class_ref
	'ObjCDynamicDecl':                                  .obj_c_dynamic_decl
	'ObjCEncodeExpr':                                   .obj_c_encode_expr
	'ObjCForCollectionStmt':                            .obj_c_for_collection_stmt
	'ObjCImplementationDecl':                           .obj_c_implementation_decl
	'ObjCInstanceMethodDecl':                           .obj_c_instance_method_decl
	'ObjCInterfaceDecl':                                .obj_c_interface_decl
	'ObjCIvarDecl':                                     .obj_c_ivar_decl
	'ObjCMessageExpr':                                  .obj_c_message_expr
	'ObjCPropertyDecl':                                 .obj_c_property_decl
	'ObjCProtocolDecl':                                 .obj_c_protocol_decl
	'ObjCProtocolExpr':                                 .obj_c_protocol_expr
	'ObjCProtocolRef':                                  .obj_c_protocol_ref
	'ObjCSelectorExpr':                                 .obj_c_selector_expr
	'ObjCSelfExpr':                                     .obj_c_self_expr
	'ObjCStringLiteral':                                .obj_c_string_literal
	'ObjCSuperClassRef':                                .obj_c_super_class_ref
	'ObjCSynthesizeDecl':                               .obj_c_synthesize_decl
	'OffsetOfExpr':                                     .offset_of_expr
	'OMPArraySectionExpr':                              .omp_array_section_expr
	'OMPAtomicDirective':                               .omp_atomic_directive
	'OMPBarrierDirective':                              .omp_barrier_directive
	'OMPCancelDirective':                               .omp_cancel_directive
	'OMPCancellationPointDirective':                    .omp_cancellation_point_directive
	'OMPCriticalDirective':                             .omp_critical_directive
	'OMPDistributeDirective':                           .omp_distribute_directive
	'OMPDistributeParallelForDirective':                .omp_distribute_parallel_for_directive
	'OMPDistributeParallelForSimdDirective':            .omp_distribute_parallel_for_simd_directive
	'OMPDistributeSimdDirective':                       .omp_distribute_simd_directive
	'OMPFlushDirective':                                .omp_flush_directive
	'OMPForDirective':                                  .omp_for_directive
	'OMPForSimdDirective':                              .omp_for_simd_directive
	'OMPMasterDirective':                               .omp_master_directive
	'OMPOrderedDirective':                              .omp_ordered_directive
	'OMPParallelDirective':                             .omp_parallel_directive
	'OMPParallelForDirective':                          .omp_parallel_for_directive
	'OMPParallelForSimdDirective':                      .omp_parallel_for_simd_directive
	'OMPParallelSectionsDirective':                     .omp_parallel_sections_directive
	'OMPSectionDirective':                              .omp_section_directive
	'OMPSectionsDirective':                             .omp_sections_directive
	'OMPSimdDirective':                                 .omp_simd_directive
	'OMPSingleDirective':                               .omp_single_directive
	'OMPTargetDataDirective':                           .omp_target_data_directive
	'OMPTargetDirective':                               .omp_target_directive
	'OMPTargetEnterDataDirective':                      .omp_target_enter_data_directive
	'OMPTargetExitDataDirective':                       .omp_target_exit_data_directive
	'OMPTargetParallelDirective':                       .omp_target_parallel_directive
	'OMPTargetParallelForDirective':                    .omp_target_parallel_for_directive
	'OMPTargetParallelForSimdDirective':                .omp_target_parallel_for_simd_directive
	'OMPTargetSimdDirective':                           .omp_target_simd_directive
	'OMPTargetTeamsDirective':                          .omp_target_teams_directive
	'OMPTargetTeamsDistributeDirective':                .omp_target_teams_distribute_directive
	'OMPTargetTeamsDistributeParallelForDirective':     .omp_target_teams_distribute_parallel_for_directive
	'OMPTargetTeamsDistributeParallelForSimdDirective': .omp_target_teams_distribute_parallel_for_simd_directive
	'OMPTargetTeamsDistributeSimdDirective':            .omp_target_teams_distribute_simd_directive
	'OMPTargetUpdateDirective':                         .omp_target_update_directive
	'OMPTaskDirective':                                 .omp_task_directive
	'OMPTaskgroupDirective':                            .omp_taskgroup_directive
	'OMPTaskLoopDirective':                             .omp_task_loop_directive
	'OMPTaskLoopSimdDirective':                         .omp_task_loop_simd_directive
	'OMPTaskwaitDirective':                             .omp_taskwait_directive
	'OMPTaskyieldDirective':                            .omp_taskyield_directive
	'OMPTeamsDirective':                                .omp_teams_directive
	'OMPTeamsDistributeDirective':                      .omp_teams_distribute_directive
	'OMPTeamsDistributeParallelForDirective':           .omp_teams_distribute_parallel_for_directive
	'OMPTeamsDistributeParallelForSimdDirective':       .omp_teams_distribute_parallel_for_simd_directive
	'OMPTeamsDistributeSimdDirective':                  .omp_teams_distribute_simd_directive
	'OpaqueValueExpr':                                  .opaque_value_expr
	'original':                                         .original
	'OverloadCandidate':                                .overload_candidate
	'OverloadedDeclRef':                                .overloaded_decl_ref
	'OverrideAttr':                                     .override_attr
	'Overrides':                                        .overrides
	'PackedAttr':                                       .packed_attr
	'PackExpansionExpr':                                .pack_expansion_expr
	'PackExpansionType':                                .pack_expansion_type
	'ParagraphComment':                                 .paragraph_comment
	'ParenExpr':                                        .paren_expr
	'ParenListExpr':                                    .paren_list_expr
	'ParenType':                                        .paren_type
	'ParmDecl':                                         .parm_decl
	'ParmVarDecl':                                      .parm_var_decl
	'PointerType':                                      .pointer_type
	'PredefinedExpr':                                   .predefined_expr
	'private':                                          .private
	'protected':                                        .protected
	'public':                                           .public
	'PureAttr':                                         .pure_attr
	'QualType':                                         .qual_type
	'Record':                                           .record
	'RecordDecl':                                       .record_decl
	'RecordType':                                       .record_type
	'ReleaseCapabilityAttr':                            .release_capability_attr
	'RequiresCapabilityAttr':                           .requires_capability_attr
	'RestrictAttr':                                     .restrict_attr
	'ReturnStmt':                                       .return_stmt
	'ReturnsTwiceAttr':                                 .returns_twice_attr
	'ruct':                                             .ruct
	'RValueReferenceType':                              .r_value_reference_type
	'ScopedLockableAttr':                               .scoped_lockable_attr
	'SEHExceptStmt':                                    .seh_except_stmt
	'SEHFinallyStmt':                                   .seh_finally_stmt
	'SEHLeaveStmt':                                     .seh_leave_stmt
	'SEHTryStmt':                                       .seh_try_stmt
	'SizeOfPackExpr':                                   .size_of_pack_expr
	'StaticAssert':                                     .static_assert
	'StaticAssertDecl':                                 .static_assert_decl
	'StmtExpr':                                         .stmt_expr
	'StringLiteral':                                    .string_literal
	'StructDecl':                                       .struct_decl
	'SubstNonTypeTemplateParmExpr':                     .subst_non_type_template_parm_expr
	'SubstTemplateTypeParmType':                        .subst_template_type_parm_type
	'SwitchStmt':                                       .switch_stmt
	'TemplateArgument':                                 .template_argument
	'TemplateRef':                                      .template_ref
	'TemplateSpecializationType':                       .template_specialization_type
	'TemplateTemplateParameter':                        .template_template_parameter
	'TemplateTemplateParmDecl':                         .template_template_parm_decl
	'TemplateTypeParameter':                            .template_type_parameter
	'TemplateTypeParm':                                 .template_type_parm
	'TemplateTypeParmDecl':                             .template_type_parm_decl
	'TemplateTypeParmType':                             .template_type_parm_type
	'TextComment':                                      .text_comment
	'TranslationUnit':                                  .translation_unit
	'TranslationUnitDecl':                              .translation_unit_decl
	'TypeAliasDecl':                                    .type_alias_decl
	'TypeAliasTemplateDecl':                            .type_alias_template_decl
	'Typedef':                                          .typedef
	'TypedefDecl':                                      .typedef_decl
	'TypedefType':                                      .typedef_type
	'TypeRef':                                          .type_ref
	'TypeVisibilityAttr':                               .type_visibility_attr
	'UnaryExpr':                                        .unary_expr
	'UnaryExprOrTypeTraitExpr':                         .unary_expr_or_type_trait_expr
	'UnaryOperator':                                    .unary_operator
	'UnaryTransformType':                               .unary_transform_type
	'UnexposedAttr':                                    .unexposed_attr
	'UnexposedDecl':                                    .unexposed_decl
	'UnexposedExpr':                                    .unexposed_expr
	'UnexposedStmt':                                    .unexposed_stmt
	'Unhandled':                                        .unhandled
	'UnionDecl':                                        .union_decl
	'UnresolvedLookupExpr':                             .unresolved_lookup_expr
	'UnresolvedMemberExpr':                             .unresolved_member_expr
	'UnusedAttr':                                       .unused_attr
	'UsingDecl':                                        .using_decl
	'UsingDeclaration':                                 .using_declaration
	'UsingDirective':                                   .using_directive
	'UsingDirectiveDecl':                               .using_directive_decl
	'UsingShadowDecl':                                  .using_shadow_decl
	'VAArgExpr':                                        .va_arg_expr
	'VarDecl':                                          .var_decl
	'VariableRef':                                      .variable_ref
	'virtual':                                          .virtual
	'VisibilityAttr':                                   .visibility_attr
	'WarnUnusedResultAttr':                             .warn_unused_result_attr
	'WhileStmt':                                        .while_stmt
}

// Reverse process is done in a runtime, so this map always contains correct data.
// We are using reversed str_to_node_kind_map to implement NodeKind.str() method.
const node_kind_to_str_map = reverse_str_to_node_kind_map()

// Use this method when you want to convert a node's name into NodeKind enum form.
// ATTENTION: the 'value' parameter is case sensitive!
//
// Example:
//	convert_str_into_node_kind('AccessSpecDecl') -> NodeKind.access_spec_decl
//	convert_str_into_node_kind('access_spec_decl') -> NodeKind.bad
//	convert_str_into_node_kind('RANDOM123_NOT_EXISTS') -> NodeKind.bad
pub fn convert_str_into_node_kind(value string) NodeKind {
	return str_to_node_kind_map[value] or { NodeKind.bad }
}

// ATTENTION: NodeKind string form - is the original name of a node, generated by Clang AST, not a 'node_kind_enum_member_name'.
//
// Example:
//	NodeKind.access_spec_decl.str() -> 'AccessSpecDecl'
pub fn (kind NodeKind) str() string {
	return node_kind_to_str_map[kind]
}

fn reverse_str_to_node_kind_map() map[NodeKind]string {
	mut reversed_map := map[NodeKind]string{}

	for key, value in str_to_node_kind_map {
		reversed_map[value] = key
	}

	return reversed_map
}
