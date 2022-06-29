module main

enum NodeKind {
	bad
	addr_label_expr
	analyzer_no_return_attr
	array_filler
	array_subscript_expr
	asm_label_attr
	availability_attr
	binary_operator
	block_expr
	break_stmt
	builtin_type
	c_style_cast_expr
	cxx_access_specifier
	cxx_bind_temporary_expr
	cxx_bool_literal_expr
	cxx_catch_stmt
	cxx_const_cast_expr
	cxx_construct_expr
	cxx_constructor
	cxx_conversion
	cxx_delete_expr
	cxx_destructor
	cxx_dynamic_cast_expr
	cxx_for_range_stmt
	cxx_functional_cast_expr
	cxx_member_call_expr
	cxx_method
	cxx_new_expr
	cxx_null_ptr_literal_expr
	cxx_operator_call_expr
	cxx_reinterpret_cast_expr
	cxx_static_cast_expr
	cxx_this_expr
	cxx_throw_expr
	cxx_try_stmt
	cxx_typeid_expr
	call_expr
	case_stmt
	character_literal
	class_decl
	class_template
	class_template_partial_specialization
	cold_attr
	compound_assign_operator
	compound_literal_expr
	compound_stmt
	conditional_operator
	constant_expr
	continue_stmt
	decayed_type
	decl_ref_expr
	decl_stmt
	default_stmt
	do_stmt
	elaborated_type
	enum_constant_decl
	@enum
	enum_decl
	enum_type
	expr_with_cleanups
	field_decl
	fixed_point_literal
	floating_literal
	for_stmt
	friend_decl
	full_comment
	function_decl
	function_template
	gcc_asm_stmt
	gnu_null_expr
	generic_selection_expr
	goto_stmt
	if_stmt
	imaginary_literal
	implicit_cast_expr
	implicit_value_init_expr
	indirect_goto_stmt
	init_list_expr
	integer_literal
	invalid_code
	invalid_file
	label_ref
	label_stmt
	lambda_expr
	linkage_spec
	ms_asm_stmt
	materialize_temporary_expr
	member_expr
	member_ref
	member_ref_expr
	module_import
	namespace
	namespace_alias
	namespace_ref
	no_decl_found
	no_escape_attr
	non_type_template_parameter
	not_implemented
	null
	null_stmt
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
	omp_task_loop_directive
	omp_task_loop_simd_directive
	omp_taskgroup_directive
	omp_taskwait_directive
	omp_taskyield_directive
	omp_teams_directive
	omp_teams_distribute_directive
	omp_teams_distribute_parallel_for_directive
	omp_teams_distribute_parallel_for_simd_directive
	omp_teams_distribute_simd_directive
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
	overload_candidate
	overloaded_decl_ref
	pack_expansion_expr
	paragraph_comment
	paren_expr
	parm_decl
	parm_var_decl
	record
	record_decl
	record_type
	return_stmt
	seh_except_stmt
	seh_finally_stmt
	seh_leave_stmt
	seh_try_stmt
	size_of_pack_expr
	static_assert
	stmt_expr
	string_literal
	struct_decl
	switch_stmt
	template_ref
	template_template_parameter
	template_type_parameter
	text_comment
	translation_unit
	type_alias_decl
	type_alias_template_decl
	type_ref
	typedef
	typedef_decl
	typedef_type
	unary_expr
	unary_expr_or_type_trait_expr
	unary_operator
	unexposed_attr
	unexposed_decl
	unexposed_expr
	unexposed_stmt
	unhandled
	cx_cursor_kind
	union_decl
	using_declaration
	using_directive
	using_directive_decl
	var_decl
	variable_ref
	while_stmt
	va_arg_expr
	no_throw_attr
	pointer_type
	aligned_attr
	alloc_size_attr
	const_attr
	constant_array_type
	deprecated_attr
	function_proto_type
	incomplete_array_type
	max_field_alignment_attr
	no_inline_attr
	offset_of_expr
	packed_attr
	paren_type
	qual_type
	returns_twice_attr
	translation_unit_decl
	html_start_tag_comment
	html_end_tag_comment
	format_attr
	always_inline_attr
	warn_unused_result_attr
	function_no_proto_type
	format_arg_attr
	pure_attr
	visibility_attr
	cxx_record
	namespace_decl
	cxx_record_decl
	cxx_constructor_decl
	cxx_destructor_decl
	cxx_method_decl
	linkage_spec_decl
	enable_if_attr
	class_template_decl
	template_type_parm_decl
	type_visibility_attr
	class_template_specialization_decl
	template_argument
	class_template_specialization
	access_spec_decl
	subst_template_type_parm_type
	template_type_parm_type
	template_type_parm
	l_value_reference_type
	template_specialization_type
	function_template_decl
	static_assert_decl
	cxx_ctor_initializer
	cxx_default_arg_expr
	cxx_conversion_decl
	using_decl
	using_shadow_decl
	non_type_template_parm_decl
	class_template_partial_specialization_decl
	dependent_name_type
	no_sanitize_attr
	injected_class_name_type
	subst_non_type_template_parm_expr
	original
	public
	dependent_scope_decl_ref_expr
	ruct
	decltype_type
	unresolved_lookup_expr
	cxx_unresolved_construct_expr
	paren_list_expr
	unary_transform_type
	cxx_dependent_scope_member_expr
	restrict_attr
	private
	atomic_expr
	template_template_parm_decl
	cxx_pseudo_destructor_expr
	cxx_temporary_object_expr
	unresolved_member_expr
	unused_attr
	protected
	cxx_scalar_value_init_expr
	indirect_field_decl
	field
	function
	virtual
	overrides
	override_attr
	predefined_expr
	opaque_value_expr
	block_command_comment
	disable_tail_calls_attr
	diagnose_if_attr
	member_pointer_type
	r_value_reference_type
	pack_expansion_type
	cxx_noexcept_expr
	dependent_template_specialization_type
	builtin_template_decl
	cxx
	cxx_default_init_expr
	capability_attr
	acquire_capability_attr
	release_capability_attr
	assert_exclusive_lock_attr
	requires_capability_attr
	guarded_by_attr
	scoped_lockable_attr
	inline_command_comment
}

fn node_kind_from_str(s string) NodeKind {
	match s {
		'AddrLabelExpr' { return .addr_label_expr }
		'AnalyzerNoReturnAttr' { return .analyzer_no_return_attr }
		'ArrayFiller' { return .array_filler }
		'ArraySubscriptExpr' { return .array_subscript_expr }
		'AsmLabelAttr' { return .asm_label_attr }
		'AvailabilityAttr' { return .availability_attr }
		'BinaryOperator' { return .binary_operator }
		'BlockExpr' { return .block_expr }
		'BreakStmt' { return .break_stmt }
		'BuiltinType' { return .builtin_type }
		'CStyleCastExpr' { return .c_style_cast_expr }
		'CXXAccessSpecifier' { return .cxx_access_specifier }
		'CXXBindTemporaryExpr' { return .cxx_bind_temporary_expr }
		'CXXBoolLiteralExpr' { return .cxx_bool_literal_expr }
		'CXXCatchStmt' { return .cxx_catch_stmt }
		'CXXConstCastExpr' { return .cxx_const_cast_expr }
		'CXXConstructExpr' { return .cxx_construct_expr }
		'CXXConstructor' { return .cxx_constructor }
		'CXXConversion' { return .cxx_conversion }
		'CXXDeleteExpr' { return .cxx_delete_expr }
		'CXXDestructor' { return .cxx_destructor }
		'CXXDynamicCastExpr' { return .cxx_dynamic_cast_expr }
		'CXXForRangeStmt' { return .cxx_for_range_stmt }
		'CXXFunctionalCastExpr' { return .cxx_functional_cast_expr }
		'CXXMemberCallExpr' { return .cxx_member_call_expr }
		'CXXMethod' { return .cxx_method }
		'CXXNewExpr' { return .cxx_new_expr }
		'CXXNullPtrLiteralExpr' { return .cxx_null_ptr_literal_expr }
		'CXXOperatorCallExpr' { return .cxx_operator_call_expr }
		'CXXReinterpretCastExpr' { return .cxx_reinterpret_cast_expr }
		'CXXStaticCastExpr' { return .cxx_static_cast_expr }
		'CXXThisExpr' { return .cxx_this_expr }
		'CXXThrowExpr' { return .cxx_throw_expr }
		'CXXTryStmt' { return .cxx_try_stmt }
		'CXXTypeidExpr' { return .cxx_typeid_expr }
		'CallExpr' { return .call_expr }
		'CaseStmt' { return .case_stmt }
		'CharacterLiteral' { return .character_literal }
		'ClassDecl' { return .class_decl }
		'ClassTemplate' { return .class_template }
		'ClassTemplatePartialSpecialization' { return .class_template_partial_specialization }
		'ColdAttr' { return .cold_attr }
		'CompoundAssignOperator' { return .compound_assign_operator }
		'CompoundLiteralExpr' { return .compound_literal_expr }
		'CompoundStmt' { return .compound_stmt }
		'ConditionalOperator' { return .conditional_operator }
		'ConstantExpr' { return .constant_expr }
		'ContinueStmt' { return .continue_stmt }
		'DecayedType' { return .decayed_type }
		'DeclRefExpr' { return .decl_ref_expr }
		'DeclStmt' { return .decl_stmt }
		'DefaultStmt' { return .default_stmt }
		'DoStmt' { return .do_stmt }
		'ElaboratedType' { return .elaborated_type }
		'EnumConstantDecl' { return .enum_constant_decl }
		'Enum' { return .@enum }
		'EnumDecl' { return .enum_decl }
		'EnumType' { return .enum_type }
		'ExprWithCleanups' { return .expr_with_cleanups }
		'FieldDecl' { return .field_decl }
		'FixedPointLiteral' { return .fixed_point_literal }
		'FloatingLiteral' { return .floating_literal }
		'ForStmt' { return .for_stmt }
		'FriendDecl' { return .friend_decl }
		'FullComment' { return .full_comment }
		'FunctionDecl' { return .function_decl }
		'FunctionTemplate' { return .function_template }
		'GCCAsmStmt' { return .gcc_asm_stmt }
		'GNUNullExpr' { return .gnu_null_expr }
		'GenericSelectionExpr' { return .generic_selection_expr }
		'GotoStmt' { return .goto_stmt }
		'IfStmt' { return .if_stmt }
		'ImaginaryLiteral' { return .imaginary_literal }
		'ImplicitCastExpr' { return .implicit_cast_expr }
		'ImplicitValueInitExpr' { return .implicit_value_init_expr }
		'IndirectGotoStmt' { return .indirect_goto_stmt }
		'InitListExpr' { return .init_list_expr }
		'IntegerLiteral' { return .integer_literal }
		'InvalidCode' { return .invalid_code }
		'InvalidFile' { return .invalid_file }
		'LabelRef' { return .label_ref }
		'LabelStmt' { return .label_stmt }
		'LambdaExpr' { return .lambda_expr }
		'LinkageSpec' { return .linkage_spec }
		'MSAsmStmt' { return .ms_asm_stmt }
		'MaterializeTemporaryExpr' { return .materialize_temporary_expr }
		'MemberExpr' { return .member_expr }
		'MemberRef' { return .member_ref }
		'MemberRefExpr' { return .member_ref_expr }
		'ModuleImport' { return .module_import }
		'Namespace' { return .namespace }
		'NamespaceAlias' { return .namespace_alias }
		'NamespaceRef' { return .namespace_ref }
		'NoDeclFound' { return .no_decl_found }
		'NoEscapeAttr' { return .no_escape_attr }
		'NonTypeTemplateParameter' { return .non_type_template_parameter }
		'NotImplemented' { return .not_implemented }
		'Null' { return .null }
		'NullStmt' { return .null_stmt }
		'OMPArraySectionExpr' { return .omp_array_section_expr }
		'OMPAtomicDirective' { return .omp_atomic_directive }
		'OMPBarrierDirective' { return .omp_barrier_directive }
		'OMPCancelDirective' { return .omp_cancel_directive }
		'OMPCancellationPointDirective' { return .omp_cancellation_point_directive }
		'OMPCriticalDirective' { return .omp_critical_directive }
		'OMPDistributeDirective' { return .omp_distribute_directive }
		'OMPDistributeParallelForDirective' { return .omp_distribute_parallel_for_directive }
		'OMPDistributeParallelForSimdDirective' { return .omp_distribute_parallel_for_simd_directive }
		'OMPDistributeSimdDirective' { return .omp_distribute_simd_directive }
		'OMPFlushDirective' { return .omp_flush_directive }
		'OMPForDirective' { return .omp_for_directive }
		'OMPForSimdDirective' { return .omp_for_simd_directive }
		'OMPMasterDirective' { return .omp_master_directive }
		'OMPOrderedDirective' { return .omp_ordered_directive }
		'OMPParallelDirective' { return .omp_parallel_directive }
		'OMPParallelForDirective' { return .omp_parallel_for_directive }
		'OMPParallelForSimdDirective' { return .omp_parallel_for_simd_directive }
		'OMPParallelSectionsDirective' { return .omp_parallel_sections_directive }
		'OMPSectionDirective' { return .omp_section_directive }
		'OMPSectionsDirective' { return .omp_sections_directive }
		'OMPSimdDirective' { return .omp_simd_directive }
		'OMPSingleDirective' { return .omp_single_directive }
		'OMPTargetDataDirective' { return .omp_target_data_directive }
		'OMPTargetDirective' { return .omp_target_directive }
		'OMPTargetEnterDataDirective' { return .omp_target_enter_data_directive }
		'OMPTargetExitDataDirective' { return .omp_target_exit_data_directive }
		'OMPTargetParallelDirective' { return .omp_target_parallel_directive }
		'OMPTargetParallelForDirective' { return .omp_target_parallel_for_directive }
		'OMPTargetParallelForSimdDirective' { return .omp_target_parallel_for_simd_directive }
		'OMPTargetSimdDirective' { return .omp_target_simd_directive }
		'OMPTargetTeamsDirective' { return .omp_target_teams_directive }
		'OMPTargetTeamsDistributeDirective' { return .omp_target_teams_distribute_directive }
		'OMPTargetTeamsDistributeParallelForDirective' { return .omp_target_teams_distribute_parallel_for_directive }
		'OMPTargetTeamsDistributeParallelForSimdDirective' { return .omp_target_teams_distribute_parallel_for_simd_directive }
		'OMPTargetTeamsDistributeSimdDirective' { return .omp_target_teams_distribute_simd_directive }
		'OMPTargetUpdateDirective' { return .omp_target_update_directive }
		'OMPTaskDirective' { return .omp_task_directive }
		'OMPTaskLoopDirective' { return .omp_task_loop_directive }
		'OMPTaskLoopSimdDirective' { return .omp_task_loop_simd_directive }
		'OMPTaskgroupDirective' { return .omp_taskgroup_directive }
		'OMPTaskwaitDirective' { return .omp_taskwait_directive }
		'OMPTaskyieldDirective' { return .omp_taskyield_directive }
		'OMPTeamsDirective' { return .omp_teams_directive }
		'OMPTeamsDistributeDirective' { return .omp_teams_distribute_directive }
		'OMPTeamsDistributeParallelForDirective' { return .omp_teams_distribute_parallel_for_directive }
		'OMPTeamsDistributeParallelForSimdDirective' { return .omp_teams_distribute_parallel_for_simd_directive }
		'OMPTeamsDistributeSimdDirective' { return .omp_teams_distribute_simd_directive }
		'ObjCAtCatchStmt' { return .obj_c_at_catch_stmt }
		'ObjCAtFinallyStmt' { return .obj_c_at_finally_stmt }
		'ObjCAtSynchronizedStmt' { return .obj_c_at_synchronized_stmt }
		'ObjCAtThrowStmt' { return .obj_c_at_throw_stmt }
		'ObjCAtTryStmt' { return .obj_c_at_try_stmt }
		'ObjCAutoreleasePoolStmt' { return .obj_c_autorelease_pool_stmt }
		'ObjCAvailabilityCheckExpr' { return .obj_c_availability_check_expr }
		'ObjCBoolLiteralExpr' { return .obj_c_bool_literal_expr }
		'ObjCBridgedCastExpr' { return .obj_c_bridged_cast_expr }
		'ObjCCategoryDecl' { return .obj_c_category_decl }
		'ObjCCategoryImplDecl' { return .obj_c_category_impl_decl }
		'ObjCClassMethodDecl' { return .obj_c_class_method_decl }
		'ObjCClassRef' { return .obj_c_class_ref }
		'ObjCDynamicDecl' { return .obj_c_dynamic_decl }
		'ObjCEncodeExpr' { return .obj_c_encode_expr }
		'ObjCForCollectionStmt' { return .obj_c_for_collection_stmt }
		'ObjCImplementationDecl' { return .obj_c_implementation_decl }
		'ObjCInstanceMethodDecl' { return .obj_c_instance_method_decl }
		'ObjCInterfaceDecl' { return .obj_c_interface_decl }
		'ObjCIvarDecl' { return .obj_c_ivar_decl }
		'ObjCMessageExpr' { return .obj_c_message_expr }
		'ObjCPropertyDecl' { return .obj_c_property_decl }
		'ObjCProtocolDecl' { return .obj_c_protocol_decl }
		'ObjCProtocolExpr' { return .obj_c_protocol_expr }
		'ObjCProtocolRef' { return .obj_c_protocol_ref }
		'ObjCSelectorExpr' { return .obj_c_selector_expr }
		'ObjCSelfExpr' { return .obj_c_self_expr }
		'ObjCStringLiteral' { return .obj_c_string_literal }
		'ObjCSuperClassRef' { return .obj_c_super_class_ref }
		'ObjCSynthesizeDecl' { return .obj_c_synthesize_decl }
		'OverloadCandidate' { return .overload_candidate }
		'OverloadedDeclRef' { return .overloaded_decl_ref }
		'PackExpansionExpr' { return .pack_expansion_expr }
		'ParagraphComment' { return .paragraph_comment }
		'ParenExpr' { return .paren_expr }
		'ParmDecl' { return .parm_decl }
		'ParmVarDecl' { return .parm_var_decl }
		'Record' { return .record }
		'RecordDecl' { return .record_decl }
		'RecordType' { return .record_type }
		'ReturnStmt' { return .return_stmt }
		'SEHExceptStmt' { return .seh_except_stmt }
		'SEHFinallyStmt' { return .seh_finally_stmt }
		'SEHLeaveStmt' { return .seh_leave_stmt }
		'SEHTryStmt' { return .seh_try_stmt }
		'SizeOfPackExpr' { return .size_of_pack_expr }
		'StaticAssert' { return .static_assert }
		'StmtExpr' { return .stmt_expr }
		'StringLiteral' { return .string_literal }
		'StructDecl' { return .struct_decl }
		'SwitchStmt' { return .switch_stmt }
		'TemplateRef' { return .template_ref }
		'TemplateTemplateParameter' { return .template_template_parameter }
		'TemplateTypeParameter' { return .template_type_parameter }
		'TextComment' { return .text_comment }
		'TranslationUnit' { return .translation_unit }
		'TypeAliasDecl' { return .type_alias_decl }
		'TypeAliasTemplateDecl' { return .type_alias_template_decl }
		'TypeRef' { return .type_ref }
		'Typedef' { return .typedef }
		'TypedefDecl' { return .typedef_decl }
		'TypedefType' { return .typedef_type }
		'UnaryExpr' { return .unary_expr }
		'UnaryExprOrTypeTraitExpr' { return .unary_expr_or_type_trait_expr }
		'UnaryOperator' { return .unary_operator }
		'UnexposedAttr' { return .unexposed_attr }
		'UnexposedDecl' { return .unexposed_decl }
		'UnexposedExpr' { return .unexposed_expr }
		'UnexposedStmt' { return .unexposed_stmt }
		'Unhandled' { return .unhandled }
		'CXCursorKind' { return .cx_cursor_kind }
		'UnionDecl' { return .union_decl }
		'UsingDeclaration' { return .using_declaration }
		'UsingDirective' { return .using_directive }
		'UsingDirectiveDecl' { return .using_directive_decl }
		'VarDecl' { return .var_decl }
		'VariableRef' { return .variable_ref }
		'WhileStmt' { return .while_stmt }
		'VAArgExpr' { return .va_arg_expr }
		'NoThrowAttr' { return .no_throw_attr }
		'PointerType' { return .pointer_type }
		'AlignedAttr' { return .aligned_attr }
		'AllocSizeAttr' { return .alloc_size_attr }
		'ConstAttr' { return .const_attr }
		'ConstantArrayType' { return .constant_array_type }
		'DeprecatedAttr' { return .deprecated_attr }
		'FunctionProtoType' { return .function_proto_type }
		'IncompleteArrayType' { return .incomplete_array_type }
		'MaxFieldAlignmentAttr' { return .max_field_alignment_attr }
		'NoInlineAttr' { return .no_inline_attr }
		'OffsetOfExpr' { return .offset_of_expr }
		'PackedAttr' { return .packed_attr }
		'ParenType' { return .paren_type }
		'QualType' { return .qual_type }
		'ReturnsTwiceAttr' { return .returns_twice_attr }
		'TranslationUnitDecl' { return .translation_unit_decl }
		'HTMLStartTagComment' { return .html_start_tag_comment }
		'HTMLEndTagComment' { return .html_end_tag_comment }
		'FormatAttr' { return .format_attr }
		'AlwaysInlineAttr' { return .always_inline_attr }
		'WarnUnusedResultAttr' { return .warn_unused_result_attr }
		'FunctionNoProtoType' { return .function_no_proto_type }
		'FormatArgAttr' { return .format_arg_attr }
		'PureAttr' { return .pure_attr }
		'VisibilityAttr' { return .visibility_attr }
		'CXXRecord' { return .cxx_record }
		'NamespaceDecl' { return .namespace_decl }
		'CXXRecordDecl' { return .cxx_record_decl }
		'CXXConstructorDecl' { return .cxx_constructor_decl }
		'CXXDestructorDecl' { return .cxx_destructor_decl }
		'CXXMethodDecl' { return .cxx_method_decl }
		'LinkageSpecDecl' { return .linkage_spec_decl }
		'EnableIfAttr' { return .enable_if_attr }
		'ClassTemplateDecl' { return .class_template_decl }
		'TemplateTypeParmDecl' { return .template_type_parm_decl }
		'TypeVisibilityAttr' { return .type_visibility_attr }
		'ClassTemplateSpecializationDecl' { return .class_template_specialization_decl }
		'TemplateArgument' { return .template_argument }
		'ClassTemplateSpecialization' { return .class_template_specialization }
		'AccessSpecDecl' { return .access_spec_decl }
		'SubstTemplateTypeParmType' { return .subst_template_type_parm_type }
		'TemplateTypeParmType' { return .template_type_parm_type }
		'TemplateTypeParm' { return .template_type_parm }
		'LValueReferenceType' { return .l_value_reference_type }
		'TemplateSpecializationType' { return .template_specialization_type }
		'FunctionTemplateDecl' { return .function_template_decl }
		'StaticAssertDecl' { return .static_assert_decl }
		'CXXCtorInitializer' { return .cxx_ctor_initializer }
		'CXXDefaultArgExpr' { return .cxx_default_arg_expr }
		'CXXConversionDecl' { return .cxx_conversion_decl }
		'UsingDecl' { return .using_decl }
		'UsingShadowDecl' { return .using_shadow_decl }
		'NonTypeTemplateParmDecl' { return .non_type_template_parm_decl }
		'ClassTemplatePartialSpecializationDecl' { return .class_template_partial_specialization_decl }
		'DependentNameType' { return .dependent_name_type }
		'NoSanitizeAttr' { return .no_sanitize_attr }
		'InjectedClassNameType' { return .injected_class_name_type }
		'SubstNonTypeTemplateParmExpr' { return .subst_non_type_template_parm_expr }
		'original' { return .original }
		'public' { return .public }
		'DependentScopeDeclRefExpr' { return .dependent_scope_decl_ref_expr }
		'ruct' { return .ruct }
		'DecltypeType' { return .decltype_type }
		'UnresolvedLookupExpr' { return .unresolved_lookup_expr }
		'CXXUnresolvedConstructExpr' { return .cxx_unresolved_construct_expr }
		'ParenListExpr' { return .paren_list_expr }
		'UnaryTransformType' { return .unary_transform_type }
		'CXXDependentScopeMemberExpr' { return .cxx_dependent_scope_member_expr }
		'RestrictAttr' { return .restrict_attr }
		'private' { return .private }
		'AtomicExpr' { return .atomic_expr }
		'TemplateTemplateParmDecl' { return .template_template_parm_decl }
		'CXXPseudoDestructorExpr' { return .cxx_pseudo_destructor_expr }
		'CXXTemporaryObjectExpr' { return .cxx_temporary_object_expr }
		'UnresolvedMemberExpr' { return .unresolved_member_expr }
		'UnusedAttr' { return .unused_attr }
		'protected' { return .protected }
		'CXXScalarValueInitExpr' { return .cxx_scalar_value_init_expr }
		'IndirectFieldDecl' { return .indirect_field_decl }
		'Field' { return .field }
		'Function' { return .function }
		'virtual' { return .virtual }
		'Overrides' { return .overrides }
		'OverrideAttr' { return .override_attr }
		'PredefinedExpr' { return .predefined_expr }
		'OpaqueValueExpr' { return .opaque_value_expr }
		'BlockCommandComment' { return .block_command_comment }
		'DisableTailCallsAttr' { return .disable_tail_calls_attr }
		'DiagnoseIfAttr' { return .diagnose_if_attr }
		'MemberPointerType' { return .member_pointer_type }
		'RValueReferenceType' { return .r_value_reference_type }
		'PackExpansionType' { return .pack_expansion_type }
		'CXXNoexceptExpr' { return .cxx_noexcept_expr }
		'DependentTemplateSpecializationType' { return .dependent_template_specialization_type }
		'BuiltinTemplateDecl' { return .builtin_template_decl }
		'CXX' { return .cxx }
		'CXXDefaultInitExpr' { return .cxx_default_init_expr }
		'CapabilityAttr' { return .capability_attr }
		'AcquireCapabilityAttr' { return .acquire_capability_attr }
		'ReleaseCapabilityAttr' { return .release_capability_attr }
		'AssertExclusiveLockAttr' { return .assert_exclusive_lock_attr }
		'RequiresCapabilityAttr' { return .requires_capability_attr }
		'GuardedByAttr' { return .guarded_by_attr }
		'ScopedLockableAttr' { return .scoped_lockable_attr }
		'InlineCommandComment' { return .inline_command_comment }
		else {}
	}

	return .bad
}
