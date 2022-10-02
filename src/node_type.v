// Since C2V uses Clang AST to "parse" C code and output of this parse step is a JSON file that describes code "nodes",
// names of nodes from this JSON are converted into enum form to simplify working on a code level.
//
// This file contains 2 main things - constant str_to_node_type_map and NodeType enum declaration itself.
// str_to_node_type_map contains <node_name, enum value> data pairs, so to add a new node that C2V should support,
// simply define a new member of NodeType enum (that is snake_case name of node) and add it to str_to_node_type_map.

module main

// Take into account that records of this map are sorted alphabetically A -> Z, but 'bad' value is on the top.
// Use this style when defining a new record.
const str_to_node_type_map = {
	'BAD':                                              NodeType.bad // is used only inside a C2V to mark unknown or corrupted node.
	'AccessSpecDecl':                                   NodeType.access_spec_decl
	'AcquireCapabilityAttr':                            NodeType.acquire_capability_attr
	'AddrLabelExpr':                                    NodeType.addr_label_expr
	'AlignedAttr':                                      NodeType.aligned_attr
	'AllocSizeAttr':                                    NodeType.alloc_size_attr
	'AlwaysInlineAttr':                                 NodeType.always_inline_attr
	'AnalyzerNoReturnAttr':                             NodeType.analyzer_no_return_attr
	'ArrayFiller':                                      NodeType.array_filler
	'ArraySubscriptExpr':                               NodeType.array_subscript_expr
	'AsmLabelAttr':                                     NodeType.asm_label_attr
	'AssertExclusiveLockAttr':                          NodeType.assert_exclusive_lock_attr
	'AtomicExpr':                                       NodeType.atomic_expr
	'AvailabilityAttr':                                 NodeType.availability_attr
	'BinaryOperator':                                   NodeType.binary_operator
	'BlockCommandComment':                              NodeType.block_command_comment
	'BlockExpr':                                        NodeType.block_expr
	'BreakStmt':                                        NodeType.break_stmt
	'BuiltinTemplateDecl':                              NodeType.builtin_template_decl
	'BuiltinType':                                      NodeType.builtin_type
	'CallExpr':                                         NodeType.call_expr
	'CapabilityAttr':                                   NodeType.capability_attr
	'CaseStmt':                                         NodeType.case_stmt
	'CharacterLiteral':                                 NodeType.character_literal
	'ClassDecl':                                        NodeType.class_decl
	'ClassTemplate':                                    NodeType.class_template
	'ClassTemplateDecl':                                NodeType.class_template_decl
	'ClassTemplatePartialSpecialization':               NodeType.class_template_partial_specialization
	'ClassTemplatePartialSpecializationDecl':           NodeType.class_template_partial_specialization_decl
	'ClassTemplateSpecialization':                      NodeType.class_template_specialization
	'ClassTemplateSpecializationDecl':                  NodeType.class_template_specialization_decl
	'ColdAttr':                                         NodeType.cold_attr
	'CompoundAssignOperator':                           NodeType.compound_assign_operator
	'CompoundLiteralExpr':                              NodeType.compound_literal_expr
	'CompoundStmt':                                     NodeType.compound_stmt
	'ConditionalOperator':                              NodeType.conditional_operator
	'ConstantArrayType':                                NodeType.constant_array_type
	'ConstantExpr':                                     NodeType.constant_expr
	'ConstAttr':                                        NodeType.const_attr
	'ContinueStmt':                                     NodeType.continue_stmt
	'CStyleCastExpr':                                   NodeType.c_style_cast_expr
	'CXCursorKind':                                     NodeType.cx_cursor_kind
	'CXX':                                              NodeType.cxx
	'CXXAccessSpecifier':                               NodeType.cxx_access_specifier
	'CXXBindTemporaryExpr':                             NodeType.cxx_bind_temporary_expr
	'CXXBoolLiteralExpr':                               NodeType.cxx_bool_literal_expr
	'CXXCatchStmt':                                     NodeType.cxx_catch_stmt
	'CXXConstCastExpr':                                 NodeType.cxx_const_cast_expr
	'CXXConstructExpr':                                 NodeType.cxx_construct_expr
	'CXXConstructor':                                   NodeType.cxx_constructor
	'CXXConstructorDecl':                               NodeType.cxx_constructor_decl
	'CXXConversion':                                    NodeType.cxx_conversion
	'CXXConversionDecl':                                NodeType.cxx_conversion_decl
	'CXXCtorInitializer':                               NodeType.cxx_ctor_initializer
	'CXXDefaultArgExpr':                                NodeType.cxx_default_arg_expr
	'CXXDefaultInitExpr':                               NodeType.cxx_default_init_expr
	'CXXDeleteExpr':                                    NodeType.cxx_delete_expr
	'CXXDependentScopeMemberExpr':                      NodeType.cxx_dependent_scope_member_expr
	'CXXDestructor':                                    NodeType.cxx_destructor
	'CXXDestructorDecl':                                NodeType.cxx_destructor_decl
	'CXXDynamicCastExpr':                               NodeType.cxx_dynamic_cast_expr
	'CXXForRangeStmt':                                  NodeType.cxx_for_range_stmt
	'CXXFunctionalCastExpr':                            NodeType.cxx_functional_cast_expr
	'CXXMemberCallExpr':                                NodeType.cxx_member_call_expr
	'CXXMethod':                                        NodeType.cxx_method
	'CXXMethodDecl':                                    NodeType.cxx_method_decl
	'CXXNewExpr':                                       NodeType.cxx_new_expr
	'CXXNoexceptExpr':                                  NodeType.cxx_noexcept_expr
	'CXXNullPtrLiteralExpr':                            NodeType.cxx_null_ptr_literal_expr
	'CXXOperatorCallExpr':                              NodeType.cxx_operator_call_expr
	'CXXPseudoDestructorExpr':                          NodeType.cxx_pseudo_destructor_expr
	'CXXRecord':                                        NodeType.cxx_record
	'CXXRecordDecl':                                    NodeType.cxx_record_decl
	'CXXReinterpretCastExpr':                           NodeType.cxx_reinterpret_cast_expr
	'CXXScalarValueInitExpr':                           NodeType.cxx_scalar_value_init_expr
	'CXXStaticCastExpr':                                NodeType.cxx_static_cast_expr
	'CXXTemporaryObjectExpr':                           NodeType.cxx_temporary_object_expr
	'CXXThisExpr':                                      NodeType.cxx_this_expr
	'CXXThrowExpr':                                     NodeType.cxx_throw_expr
	'CXXTryStmt':                                       NodeType.cxx_try_stmt
	'CXXTypeidExpr':                                    NodeType.cxx_typeid_expr
	'CXXUnresolvedConstructExpr':                       NodeType.cxx_unresolved_construct_expr
	'DecayedType':                                      NodeType.decayed_type
	'DeclRefExpr':                                      NodeType.decl_ref_expr
	'DeclStmt':                                         NodeType.decl_stmt
	'DecltypeType':                                     NodeType.decltype_type
	'DefaultStmt':                                      NodeType.default_stmt
	'DependentNameType':                                NodeType.dependent_name_type
	'DependentScopeDeclRefExpr':                        NodeType.dependent_scope_decl_ref_expr
	'DependentTemplateSpecializationType':              NodeType.dependent_template_specialization_type
	'DeprecatedAttr':                                   NodeType.deprecated_attr
	'DiagnoseIfAttr':                                   NodeType.diagnose_if_attr
	'DisableTailCallsAttr':                             NodeType.disable_tail_calls_attr
	'DoStmt':                                           NodeType.do_stmt
	'ElaboratedType':                                   NodeType.elaborated_type
	'EnableIfAttr':                                     NodeType.enable_if_attr
	'Enum':                                             NodeType.@enum
	'EnumConstantDecl':                                 NodeType.enum_constant_decl
	'EnumDecl':                                         NodeType.enum_decl
	'EnumType':                                         NodeType.enum_type
	'ExprWithCleanups':                                 NodeType.expr_with_cleanups
	'Field':                                            NodeType.field
	'FieldDecl':                                        NodeType.field_decl
	'FixedPointLiteral':                                NodeType.fixed_point_literal
	'FloatingLiteral':                                  NodeType.floating_literal
	'FormatArgAttr':                                    NodeType.format_arg_attr
	'FormatAttr':                                       NodeType.format_attr
	'ForStmt':                                          NodeType.for_stmt
	'FriendDecl':                                       NodeType.friend_decl
	'FullComment':                                      NodeType.full_comment
	'Function':                                         NodeType.function
	'FunctionDecl':                                     NodeType.function_decl
	'FunctionNoProtoType':                              NodeType.function_no_proto_type
	'FunctionProtoType':                                NodeType.function_proto_type
	'FunctionTemplate':                                 NodeType.function_template
	'FunctionTemplateDecl':                             NodeType.function_template_decl
	'GCCAsmStmt':                                       NodeType.gcc_asm_stmt
	'GenericSelectionExpr':                             NodeType.generic_selection_expr
	'GNUNullExpr':                                      NodeType.gnu_null_expr
	'GotoStmt':                                         NodeType.goto_stmt
	'GuardedByAttr':                                    NodeType.guarded_by_attr
	'HTMLEndTagComment':                                NodeType.html_end_tag_comment
	'HTMLStartTagComment':                              NodeType.html_start_tag_comment
	'IfStmt':                                           NodeType.if_stmt
	'ImaginaryLiteral':                                 NodeType.imaginary_literal
	'ImplicitCastExpr':                                 NodeType.implicit_cast_expr
	'ImplicitValueInitExpr':                            NodeType.implicit_value_init_expr
	'IncompleteArrayType':                              NodeType.incomplete_array_type
	'IndirectFieldDecl':                                NodeType.indirect_field_decl
	'IndirectGotoStmt':                                 NodeType.indirect_goto_stmt
	'InitListExpr':                                     NodeType.init_list_expr
	'InjectedClassNameType':                            NodeType.injected_class_name_type
	'InlineCommandComment':                             NodeType.inline_command_comment
	'IntegerLiteral':                                   NodeType.integer_literal
	'InvalidCode':                                      NodeType.invalid_code
	'InvalidFile':                                      NodeType.invalid_file
	'LabelRef':                                         NodeType.label_ref
	'LabelStmt':                                        NodeType.label_stmt
	'LambdaExpr':                                       NodeType.lambda_expr
	'LinkageSpec':                                      NodeType.linkage_spec
	'LinkageSpecDecl':                                  NodeType.linkage_spec_decl
	'LValueReferenceType':                              NodeType.l_value_reference_type
	'MaterializeTemporaryExpr':                         NodeType.materialize_temporary_expr
	'MaxFieldAlignmentAttr':                            NodeType.max_field_alignment_attr
	'MemberExpr':                                       NodeType.member_expr
	'MemberPointerType':                                NodeType.member_pointer_type
	'MemberRef':                                        NodeType.member_ref
	'MemberRefExpr':                                    NodeType.member_ref_expr
	'ModuleImport':                                     NodeType.module_import
	'MSAsmStmt':                                        NodeType.ms_asm_stmt
	'Namespace':                                        NodeType.namespace
	'NamespaceAlias':                                   NodeType.namespace_alias
	'NamespaceDecl':                                    NodeType.namespace_decl
	'NamespaceRef':                                     NodeType.namespace_ref
	'NoDeclFound':                                      NodeType.no_decl_found
	'NoEscapeAttr':                                     NodeType.no_escape_attr
	'NoInlineAttr':                                     NodeType.no_inline_attr
	'NonTypeTemplateParameter':                         NodeType.non_type_template_parameter
	'NonTypeTemplateParmDecl':                          NodeType.non_type_template_parm_decl
	'NoSanitizeAttr':                                   NodeType.no_sanitize_attr
	'NoThrowAttr':                                      NodeType.no_throw_attr
	'NotImplemented':                                   NodeType.not_implemented
	'Null':                                             NodeType.null
	'NullStmt':                                         NodeType.null_stmt
	'ObjCAtCatchStmt':                                  NodeType.obj_c_at_catch_stmt
	'ObjCAtFinallyStmt':                                NodeType.obj_c_at_finally_stmt
	'ObjCAtSynchronizedStmt':                           NodeType.obj_c_at_synchronized_stmt
	'ObjCAtThrowStmt':                                  NodeType.obj_c_at_throw_stmt
	'ObjCAtTryStmt':                                    NodeType.obj_c_at_try_stmt
	'ObjCAutoreleasePoolStmt':                          NodeType.obj_c_autorelease_pool_stmt
	'ObjCAvailabilityCheckExpr':                        NodeType.obj_c_availability_check_expr
	'ObjCBoolLiteralExpr':                              NodeType.obj_c_bool_literal_expr
	'ObjCBridgedCastExpr':                              NodeType.obj_c_bridged_cast_expr
	'ObjCCategoryDecl':                                 NodeType.obj_c_category_decl
	'ObjCCategoryImplDecl':                             NodeType.obj_c_category_impl_decl
	'ObjCClassMethodDecl':                              NodeType.obj_c_class_method_decl
	'ObjCClassRef':                                     NodeType.obj_c_class_ref
	'ObjCDynamicDecl':                                  NodeType.obj_c_dynamic_decl
	'ObjCEncodeExpr':                                   NodeType.obj_c_encode_expr
	'ObjCForCollectionStmt':                            NodeType.obj_c_for_collection_stmt
	'ObjCImplementationDecl':                           NodeType.obj_c_implementation_decl
	'ObjCInstanceMethodDecl':                           NodeType.obj_c_instance_method_decl
	'ObjCInterfaceDecl':                                NodeType.obj_c_interface_decl
	'ObjCIvarDecl':                                     NodeType.obj_c_ivar_decl
	'ObjCMessageExpr':                                  NodeType.obj_c_message_expr
	'ObjCPropertyDecl':                                 NodeType.obj_c_property_decl
	'ObjCProtocolDecl':                                 NodeType.obj_c_protocol_decl
	'ObjCProtocolExpr':                                 NodeType.obj_c_protocol_expr
	'ObjCProtocolRef':                                  NodeType.obj_c_protocol_ref
	'ObjCSelectorExpr':                                 NodeType.obj_c_selector_expr
	'ObjCSelfExpr':                                     NodeType.obj_c_self_expr
	'ObjCStringLiteral':                                NodeType.obj_c_string_literal
	'ObjCSuperClassRef':                                NodeType.obj_c_super_class_ref
	'ObjCSynthesizeDecl':                               NodeType.obj_c_synthesize_decl
	'OffsetOfExpr':                                     NodeType.offset_of_expr
	'OMPArraySectionExpr':                              NodeType.omp_array_section_expr
	'OMPAtomicDirective':                               NodeType.omp_atomic_directive
	'OMPBarrierDirective':                              NodeType.omp_barrier_directive
	'OMPCancelDirective':                               NodeType.omp_cancel_directive
	'OMPCancellationPointDirective':                    NodeType.omp_cancellation_point_directive
	'OMPCriticalDirective':                             NodeType.omp_critical_directive
	'OMPDistributeDirective':                           NodeType.omp_distribute_directive
	'OMPDistributeParallelForDirective':                NodeType.omp_distribute_parallel_for_directive
	'OMPDistributeParallelForSimdDirective':            NodeType.omp_distribute_parallel_for_simd_directive
	'OMPDistributeSimdDirective':                       NodeType.omp_distribute_simd_directive
	'OMPFlushDirective':                                NodeType.omp_flush_directive
	'OMPForDirective':                                  NodeType.omp_for_directive
	'OMPForSimdDirective':                              NodeType.omp_for_simd_directive
	'OMPMasterDirective':                               NodeType.omp_master_directive
	'OMPOrderedDirective':                              NodeType.omp_ordered_directive
	'OMPParallelDirective':                             NodeType.omp_parallel_directive
	'OMPParallelForDirective':                          NodeType.omp_parallel_for_directive
	'OMPParallelForSimdDirective':                      NodeType.omp_parallel_for_simd_directive
	'OMPParallelSectionsDirective':                     NodeType.omp_parallel_sections_directive
	'OMPSectionDirective':                              NodeType.omp_section_directive
	'OMPSectionsDirective':                             NodeType.omp_sections_directive
	'OMPSimdDirective':                                 NodeType.omp_simd_directive
	'OMPSingleDirective':                               NodeType.omp_single_directive
	'OMPTargetDataDirective':                           NodeType.omp_target_data_directive
	'OMPTargetDirective':                               NodeType.omp_target_directive
	'OMPTargetEnterDataDirective':                      NodeType.omp_target_enter_data_directive
	'OMPTargetExitDataDirective':                       NodeType.omp_target_exit_data_directive
	'OMPTargetParallelDirective':                       NodeType.omp_target_parallel_directive
	'OMPTargetParallelForDirective':                    NodeType.omp_target_parallel_for_directive
	'OMPTargetParallelForSimdDirective':                NodeType.omp_target_parallel_for_simd_directive
	'OMPTargetSimdDirective':                           NodeType.omp_target_simd_directive
	'OMPTargetTeamsDirective':                          NodeType.omp_target_teams_directive
	'OMPTargetTeamsDistributeDirective':                NodeType.omp_target_teams_distribute_directive
	'OMPTargetTeamsDistributeParallelForDirective':     NodeType.omp_target_teams_distribute_parallel_for_directive
	'OMPTargetTeamsDistributeParallelForSimdDirective': NodeType.omp_target_teams_distribute_parallel_for_simd_directive
	'OMPTargetTeamsDistributeSimdDirective':            NodeType.omp_target_teams_distribute_simd_directive
	'OMPTargetUpdateDirective':                         NodeType.omp_target_update_directive
	'OMPTaskDirective':                                 NodeType.omp_task_directive
	'OMPTaskgroupDirective':                            NodeType.omp_taskgroup_directive
	'OMPTaskLoopDirective':                             NodeType.omp_task_loop_directive
	'OMPTaskLoopSimdDirective':                         NodeType.omp_task_loop_simd_directive
	'OMPTaskwaitDirective':                             NodeType.omp_taskwait_directive
	'OMPTaskyieldDirective':                            NodeType.omp_taskyield_directive
	'OMPTeamsDirective':                                NodeType.omp_teams_directive
	'OMPTeamsDistributeDirective':                      NodeType.omp_teams_distribute_directive
	'OMPTeamsDistributeParallelForDirective':           NodeType.omp_teams_distribute_parallel_for_directive
	'OMPTeamsDistributeParallelForSimdDirective':       NodeType.omp_teams_distribute_parallel_for_simd_directive
	'OMPTeamsDistributeSimdDirective':                  NodeType.omp_teams_distribute_simd_directive
	'OpaqueValueExpr':                                  NodeType.opaque_value_expr
	'original':                                         NodeType.original
	'OverloadCandidate':                                NodeType.overload_candidate
	'OverloadedDeclRef':                                NodeType.overloaded_decl_ref
	'OverrideAttr':                                     NodeType.override_attr
	'Overrides':                                        NodeType.overrides
	'PackedAttr':                                       NodeType.packed_attr
	'PackExpansionExpr':                                NodeType.pack_expansion_expr
	'PackExpansionType':                                NodeType.pack_expansion_type
	'ParagraphComment':                                 NodeType.paragraph_comment
	'ParenExpr':                                        NodeType.paren_expr
	'ParenListExpr':                                    NodeType.paren_list_expr
	'ParenType':                                        NodeType.paren_type
	'ParmDecl':                                         NodeType.parm_decl
	'ParmVarDecl':                                      NodeType.parm_var_decl
	'PointerType':                                      NodeType.pointer_type
	'PredefinedExpr':                                   NodeType.predefined_expr
	'private':                                          NodeType.private
	'protected':                                        NodeType.protected
	'public':                                           NodeType.public
	'PureAttr':                                         NodeType.pure_attr
	'QualType':                                         NodeType.qual_type
	'Record':                                           NodeType.record
	'RecordDecl':                                       NodeType.record_decl
	'RecordType':                                       NodeType.record_type
	'ReleaseCapabilityAttr':                            NodeType.release_capability_attr
	'RequiresCapabilityAttr':                           NodeType.requires_capability_attr
	'RestrictAttr':                                     NodeType.restrict_attr
	'ReturnStmt':                                       NodeType.return_stmt
	'ReturnsTwiceAttr':                                 NodeType.returns_twice_attr
	'ruct':                                             NodeType.ruct
	'RValueReferenceType':                              NodeType.r_value_reference_type
	'ScopedLockableAttr':                               NodeType.scoped_lockable_attr
	'SEHExceptStmt':                                    NodeType.seh_except_stmt
	'SEHFinallyStmt':                                   NodeType.seh_finally_stmt
	'SEHLeaveStmt':                                     NodeType.seh_leave_stmt
	'SEHTryStmt':                                       NodeType.seh_try_stmt
	'SizeOfPackExpr':                                   NodeType.size_of_pack_expr
	'StaticAssert':                                     NodeType.static_assert
	'StaticAssertDecl':                                 NodeType.static_assert_decl
	'StmtExpr':                                         NodeType.stmt_expr
	'StringLiteral':                                    NodeType.string_literal
	'StructDecl':                                       NodeType.struct_decl
	'SubstNonTypeTemplateParmExpr':                     NodeType.subst_non_type_template_parm_expr
	'SubstTemplateTypeParmType':                        NodeType.subst_template_type_parm_type
	'SwitchStmt':                                       NodeType.switch_stmt
	'TemplateArgument':                                 NodeType.template_argument
	'TemplateRef':                                      NodeType.template_ref
	'TemplateSpecializationType':                       NodeType.template_specialization_type
	'TemplateTemplateParameter':                        NodeType.template_template_parameter
	'TemplateTemplateParmDecl':                         NodeType.template_template_parm_decl
	'TemplateTypeParameter':                            NodeType.template_type_parameter
	'TemplateTypeParm':                                 NodeType.template_type_parm
	'TemplateTypeParmDecl':                             NodeType.template_type_parm_decl
	'TemplateTypeParmType':                             NodeType.template_type_parm_type
	'TextComment':                                      NodeType.text_comment
	'TranslationUnit':                                  NodeType.translation_unit
	'TranslationUnitDecl':                              NodeType.translation_unit_decl
	'TypeAliasDecl':                                    NodeType.type_alias_decl
	'TypeAliasTemplateDecl':                            NodeType.type_alias_template_decl
	'Typedef':                                          NodeType.typedef
	'TypedefDecl':                                      NodeType.typedef_decl
	'TypedefType':                                      NodeType.typedef_type
	'TypeRef':                                          NodeType.type_ref
	'TypeVisibilityAttr':                               NodeType.type_visibility_attr
	'UnaryExpr':                                        NodeType.unary_expr
	'UnaryExprOrTypeTraitExpr':                         NodeType.unary_expr_or_type_trait_expr
	'UnaryOperator':                                    NodeType.unary_operator
	'UnaryTransformType':                               NodeType.unary_transform_type
	'UnexposedAttr':                                    NodeType.unexposed_attr
	'UnexposedDecl':                                    NodeType.unexposed_decl
	'UnexposedExpr':                                    NodeType.unexposed_expr
	'UnexposedStmt':                                    NodeType.unexposed_stmt
	'Unhandled':                                        NodeType.unhandled
	'UnionDecl':                                        NodeType.union_decl
	'UnresolvedLookupExpr':                             NodeType.unresolved_lookup_expr
	'UnresolvedMemberExpr':                             NodeType.unresolved_member_expr
	'UnusedAttr':                                       NodeType.unused_attr
	'UsingDecl':                                        NodeType.using_decl
	'UsingDeclaration':                                 NodeType.using_declaration
	'UsingDirective':                                   NodeType.using_directive
	'UsingDirectiveDecl':                               NodeType.using_directive_decl
	'UsingShadowDecl':                                  NodeType.using_shadow_decl
	'VAArgExpr':                                        NodeType.va_arg_expr
	'VarDecl':                                          NodeType.var_decl
	'VariableRef':                                      NodeType.variable_ref
	'virtual':                                          NodeType.virtual
	'VisibilityAttr':                                   NodeType.visibility_attr
	'WarnUnusedResultAttr':                             NodeType.warn_unused_result_attr
	'WhileStmt':                                        NodeType.while_stmt
}

// Reverse process is done in a runtime, so this map always contains correct data.
// We are using reversed str_to_node_type_map to implement NodeType.str() method.
const node_type_to_str_map = reverse_str_to_node_type_map()

// Take into account that members of this enum are sorted alphabetically A -> Z, but 'bad' value is on the top.
// Use this style when defining a new record.
enum NodeType {
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

// Use this method when you want to convert a node's name into NodeType enum form.
// ATTENTION: the 'value' parameter is case sensitive!
//
// Example:
//	convert_node_type_into_str('AccessSpecDecl') -> NodeType.access_spec_decl
//	convert_node_type_into_str('access_spec_decl') -> NodeType.bad
//	convert_node_type_into_str('RANDOM123_NOT_EXISTS') -> NodeType.bad
pub fn convert_node_type_into_str(value string) NodeType {
	return str_to_node_type_map[value] or { NodeType.bad }
}

// ATTENTION: NodeType string form - is the original name of a node, generated by Clang AST, not a 'node_type_enum_member_name'.
//
// Example:
//	NodeType.access_spec_decl.str() -> 'AccessSpecDecl'
pub fn (typ NodeType) str() string {
	return node_type_to_str_map[typ]
}

fn reverse_str_to_node_type_map() map[NodeType]string {
	mut reversed_map := map[NodeType]string{}

	for key, value in str_to_node_type_map {
		reversed_map[value] = key
	}

	return reversed_map
}
