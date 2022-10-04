// Since C2V uses Clang AST to "parse" C code and output of this parse step is a JSON file that describes code "nodes",
// names of nodes from this JSON are converted into enum form to simplify working on a code level.
//
// This file contains 2 main things - constant str_to_node_kind_map and NodeKind enum declaration itself.
// str_to_node_kind_map contains <node_name, enum value> data pairs, so to add a new node that C2V should support,
// simply define a new member of NodeKind enum (that is snake_case name of node) and add it to str_to_node_kind_map.

module main

// Take into account that records of this map are sorted alphabetically A -> Z, but 'bad' value is on the top.
// Use this style when defining a new record.
const str_to_node_kind_map = {
	'BAD':                                              NodeKind.bad // is used only inside a C2V to mark unknown or corrupted node.
	'AccessSpecDecl':                                   NodeKind.access_spec_decl
	'AcquireCapabilityAttr':                            NodeKind.acquire_capability_attr
	'AddrLabelExpr':                                    NodeKind.addr_label_expr
	'AlignedAttr':                                      NodeKind.aligned_attr
	'AllocSizeAttr':                                    NodeKind.alloc_size_attr
	'AlwaysInlineAttr':                                 NodeKind.always_inline_attr
	'AnalyzerNoReturnAttr':                             NodeKind.analyzer_no_return_attr
	'ArrayFiller':                                      NodeKind.array_filler
	'ArraySubscriptExpr':                               NodeKind.array_subscript_expr
	'AsmLabelAttr':                                     NodeKind.asm_label_attr
	'AssertExclusiveLockAttr':                          NodeKind.assert_exclusive_lock_attr
	'AtomicExpr':                                       NodeKind.atomic_expr
	'AvailabilityAttr':                                 NodeKind.availability_attr
	'BinaryOperator':                                   NodeKind.binary_operator
	'BlockCommandComment':                              NodeKind.block_command_comment
	'BlockExpr':                                        NodeKind.block_expr
	'BreakStmt':                                        NodeKind.break_stmt
	'BuiltinTemplateDecl':                              NodeKind.builtin_template_decl
	'BuiltinType':                                      NodeKind.builtin_type
	'CallExpr':                                         NodeKind.call_expr
	'CapabilityAttr':                                   NodeKind.capability_attr
	'CaseStmt':                                         NodeKind.case_stmt
	'CharacterLiteral':                                 NodeKind.character_literal
	'ClassDecl':                                        NodeKind.class_decl
	'ClassTemplate':                                    NodeKind.class_template
	'ClassTemplateDecl':                                NodeKind.class_template_decl
	'ClassTemplatePartialSpecialization':               NodeKind.class_template_partial_specialization
	'ClassTemplatePartialSpecializationDecl':           NodeKind.class_template_partial_specialization_decl
	'ClassTemplateSpecialization':                      NodeKind.class_template_specialization
	'ClassTemplateSpecializationDecl':                  NodeKind.class_template_specialization_decl
	'ColdAttr':                                         NodeKind.cold_attr
	'CompoundAssignOperator':                           NodeKind.compound_assign_operator
	'CompoundLiteralExpr':                              NodeKind.compound_literal_expr
	'CompoundStmt':                                     NodeKind.compound_stmt
	'ConditionalOperator':                              NodeKind.conditional_operator
	'ConstantArrayType':                                NodeKind.constant_array_type
	'ConstantExpr':                                     NodeKind.constant_expr
	'ConstAttr':                                        NodeKind.const_attr
	'ContinueStmt':                                     NodeKind.continue_stmt
	'CStyleCastExpr':                                   NodeKind.c_style_cast_expr
	'CXCursorKind':                                     NodeKind.cx_cursor_kind
	'CXX':                                              NodeKind.cxx
	'CXXAccessSpecifier':                               NodeKind.cxx_access_specifier
	'CXXBindTemporaryExpr':                             NodeKind.cxx_bind_temporary_expr
	'CXXBoolLiteralExpr':                               NodeKind.cxx_bool_literal_expr
	'CXXCatchStmt':                                     NodeKind.cxx_catch_stmt
	'CXXConstCastExpr':                                 NodeKind.cxx_const_cast_expr
	'CXXConstructExpr':                                 NodeKind.cxx_construct_expr
	'CXXConstructor':                                   NodeKind.cxx_constructor
	'CXXConstructorDecl':                               NodeKind.cxx_constructor_decl
	'CXXConversion':                                    NodeKind.cxx_conversion
	'CXXConversionDecl':                                NodeKind.cxx_conversion_decl
	'CXXCtorInitializer':                               NodeKind.cxx_ctor_initializer
	'CXXDefaultArgExpr':                                NodeKind.cxx_default_arg_expr
	'CXXDefaultInitExpr':                               NodeKind.cxx_default_init_expr
	'CXXDeleteExpr':                                    NodeKind.cxx_delete_expr
	'CXXDependentScopeMemberExpr':                      NodeKind.cxx_dependent_scope_member_expr
	'CXXDestructor':                                    NodeKind.cxx_destructor
	'CXXDestructorDecl':                                NodeKind.cxx_destructor_decl
	'CXXDynamicCastExpr':                               NodeKind.cxx_dynamic_cast_expr
	'CXXForRangeStmt':                                  NodeKind.cxx_for_range_stmt
	'CXXFunctionalCastExpr':                            NodeKind.cxx_functional_cast_expr
	'CXXMemberCallExpr':                                NodeKind.cxx_member_call_expr
	'CXXMethod':                                        NodeKind.cxx_method
	'CXXMethodDecl':                                    NodeKind.cxx_method_decl
	'CXXNewExpr':                                       NodeKind.cxx_new_expr
	'CXXNoexceptExpr':                                  NodeKind.cxx_noexcept_expr
	'CXXNullPtrLiteralExpr':                            NodeKind.cxx_null_ptr_literal_expr
	'CXXOperatorCallExpr':                              NodeKind.cxx_operator_call_expr
	'CXXPseudoDestructorExpr':                          NodeKind.cxx_pseudo_destructor_expr
	'CXXRecord':                                        NodeKind.cxx_record
	'CXXRecordDecl':                                    NodeKind.cxx_record_decl
	'CXXReinterpretCastExpr':                           NodeKind.cxx_reinterpret_cast_expr
	'CXXScalarValueInitExpr':                           NodeKind.cxx_scalar_value_init_expr
	'CXXStaticCastExpr':                                NodeKind.cxx_static_cast_expr
	'CXXTemporaryObjectExpr':                           NodeKind.cxx_temporary_object_expr
	'CXXThisExpr':                                      NodeKind.cxx_this_expr
	'CXXThrowExpr':                                     NodeKind.cxx_throw_expr
	'CXXTryStmt':                                       NodeKind.cxx_try_stmt
	'CXXTypeidExpr':                                    NodeKind.cxx_typeid_expr
	'CXXUnresolvedConstructExpr':                       NodeKind.cxx_unresolved_construct_expr
	'DecayedType':                                      NodeKind.decayed_type
	'DeclRefExpr':                                      NodeKind.decl_ref_expr
	'DeclStmt':                                         NodeKind.decl_stmt
	'DecltypeType':                                     NodeKind.decltype_type
	'DefaultStmt':                                      NodeKind.default_stmt
	'DependentNameType':                                NodeKind.dependent_name_type
	'DependentScopeDeclRefExpr':                        NodeKind.dependent_scope_decl_ref_expr
	'DependentTemplateSpecializationType':              NodeKind.dependent_template_specialization_type
	'DeprecatedAttr':                                   NodeKind.deprecated_attr
	'DiagnoseIfAttr':                                   NodeKind.diagnose_if_attr
	'DisableTailCallsAttr':                             NodeKind.disable_tail_calls_attr
	'DoStmt':                                           NodeKind.do_stmt
	'ElaboratedType':                                   NodeKind.elaborated_type
	'EnableIfAttr':                                     NodeKind.enable_if_attr
	'Enum':                                             NodeKind.@enum
	'EnumConstantDecl':                                 NodeKind.enum_constant_decl
	'EnumDecl':                                         NodeKind.enum_decl
	'EnumType':                                         NodeKind.enum_type
	'ExprWithCleanups':                                 NodeKind.expr_with_cleanups
	'Field':                                            NodeKind.field
	'FieldDecl':                                        NodeKind.field_decl
	'FixedPointLiteral':                                NodeKind.fixed_point_literal
	'FloatingLiteral':                                  NodeKind.floating_literal
	'FormatArgAttr':                                    NodeKind.format_arg_attr
	'FormatAttr':                                       NodeKind.format_attr
	'ForStmt':                                          NodeKind.for_stmt
	'FriendDecl':                                       NodeKind.friend_decl
	'FullComment':                                      NodeKind.full_comment
	'Function':                                         NodeKind.function
	'FunctionDecl':                                     NodeKind.function_decl
	'FunctionNoProtoType':                              NodeKind.function_no_proto_type
	'FunctionProtoType':                                NodeKind.function_proto_type
	'FunctionTemplate':                                 NodeKind.function_template
	'FunctionTemplateDecl':                             NodeKind.function_template_decl
	'GCCAsmStmt':                                       NodeKind.gcc_asm_stmt
	'GenericSelectionExpr':                             NodeKind.generic_selection_expr
	'GNUNullExpr':                                      NodeKind.gnu_null_expr
	'GotoStmt':                                         NodeKind.goto_stmt
	'GuardedByAttr':                                    NodeKind.guarded_by_attr
	'HTMLEndTagComment':                                NodeKind.html_end_tag_comment
	'HTMLStartTagComment':                              NodeKind.html_start_tag_comment
	'IfStmt':                                           NodeKind.if_stmt
	'ImaginaryLiteral':                                 NodeKind.imaginary_literal
	'ImplicitCastExpr':                                 NodeKind.implicit_cast_expr
	'ImplicitValueInitExpr':                            NodeKind.implicit_value_init_expr
	'IncompleteArrayType':                              NodeKind.incomplete_array_type
	'IndirectFieldDecl':                                NodeKind.indirect_field_decl
	'IndirectGotoStmt':                                 NodeKind.indirect_goto_stmt
	'InitListExpr':                                     NodeKind.init_list_expr
	'InjectedClassNameType':                            NodeKind.injected_class_name_type
	'InlineCommandComment':                             NodeKind.inline_command_comment
	'IntegerLiteral':                                   NodeKind.integer_literal
	'InvalidCode':                                      NodeKind.invalid_code
	'InvalidFile':                                      NodeKind.invalid_file
	'LabelRef':                                         NodeKind.label_ref
	'LabelStmt':                                        NodeKind.label_stmt
	'LambdaExpr':                                       NodeKind.lambda_expr
	'LinkageSpec':                                      NodeKind.linkage_spec
	'LinkageSpecDecl':                                  NodeKind.linkage_spec_decl
	'LValueReferenceType':                              NodeKind.l_value_reference_type
	'MaterializeTemporaryExpr':                         NodeKind.materialize_temporary_expr
	'MaxFieldAlignmentAttr':                            NodeKind.max_field_alignment_attr
	'MemberExpr':                                       NodeKind.member_expr
	'MemberPointerType':                                NodeKind.member_pointer_type
	'MemberRef':                                        NodeKind.member_ref
	'MemberRefExpr':                                    NodeKind.member_ref_expr
	'ModuleImport':                                     NodeKind.module_import
	'MSAsmStmt':                                        NodeKind.ms_asm_stmt
	'Namespace':                                        NodeKind.namespace
	'NamespaceAlias':                                   NodeKind.namespace_alias
	'NamespaceDecl':                                    NodeKind.namespace_decl
	'NamespaceRef':                                     NodeKind.namespace_ref
	'NoDeclFound':                                      NodeKind.no_decl_found
	'NoEscapeAttr':                                     NodeKind.no_escape_attr
	'NoInlineAttr':                                     NodeKind.no_inline_attr
	'NonTypeTemplateParameter':                         NodeKind.non_type_template_parameter
	'NonTypeTemplateParmDecl':                          NodeKind.non_type_template_parm_decl
	'NoSanitizeAttr':                                   NodeKind.no_sanitize_attr
	'NoThrowAttr':                                      NodeKind.no_throw_attr
	'NotImplemented':                                   NodeKind.not_implemented
	'Null':                                             NodeKind.null
	'NullStmt':                                         NodeKind.null_stmt
	'ObjCAtCatchStmt':                                  NodeKind.obj_c_at_catch_stmt
	'ObjCAtFinallyStmt':                                NodeKind.obj_c_at_finally_stmt
	'ObjCAtSynchronizedStmt':                           NodeKind.obj_c_at_synchronized_stmt
	'ObjCAtThrowStmt':                                  NodeKind.obj_c_at_throw_stmt
	'ObjCAtTryStmt':                                    NodeKind.obj_c_at_try_stmt
	'ObjCAutoreleasePoolStmt':                          NodeKind.obj_c_autorelease_pool_stmt
	'ObjCAvailabilityCheckExpr':                        NodeKind.obj_c_availability_check_expr
	'ObjCBoolLiteralExpr':                              NodeKind.obj_c_bool_literal_expr
	'ObjCBridgedCastExpr':                              NodeKind.obj_c_bridged_cast_expr
	'ObjCCategoryDecl':                                 NodeKind.obj_c_category_decl
	'ObjCCategoryImplDecl':                             NodeKind.obj_c_category_impl_decl
	'ObjCClassMethodDecl':                              NodeKind.obj_c_class_method_decl
	'ObjCClassRef':                                     NodeKind.obj_c_class_ref
	'ObjCDynamicDecl':                                  NodeKind.obj_c_dynamic_decl
	'ObjCEncodeExpr':                                   NodeKind.obj_c_encode_expr
	'ObjCForCollectionStmt':                            NodeKind.obj_c_for_collection_stmt
	'ObjCImplementationDecl':                           NodeKind.obj_c_implementation_decl
	'ObjCInstanceMethodDecl':                           NodeKind.obj_c_instance_method_decl
	'ObjCInterfaceDecl':                                NodeKind.obj_c_interface_decl
	'ObjCIvarDecl':                                     NodeKind.obj_c_ivar_decl
	'ObjCMessageExpr':                                  NodeKind.obj_c_message_expr
	'ObjCPropertyDecl':                                 NodeKind.obj_c_property_decl
	'ObjCProtocolDecl':                                 NodeKind.obj_c_protocol_decl
	'ObjCProtocolExpr':                                 NodeKind.obj_c_protocol_expr
	'ObjCProtocolRef':                                  NodeKind.obj_c_protocol_ref
	'ObjCSelectorExpr':                                 NodeKind.obj_c_selector_expr
	'ObjCSelfExpr':                                     NodeKind.obj_c_self_expr
	'ObjCStringLiteral':                                NodeKind.obj_c_string_literal
	'ObjCSuperClassRef':                                NodeKind.obj_c_super_class_ref
	'ObjCSynthesizeDecl':                               NodeKind.obj_c_synthesize_decl
	'OffsetOfExpr':                                     NodeKind.offset_of_expr
	'OMPArraySectionExpr':                              NodeKind.omp_array_section_expr
	'OMPAtomicDirective':                               NodeKind.omp_atomic_directive
	'OMPBarrierDirective':                              NodeKind.omp_barrier_directive
	'OMPCancelDirective':                               NodeKind.omp_cancel_directive
	'OMPCancellationPointDirective':                    NodeKind.omp_cancellation_point_directive
	'OMPCriticalDirective':                             NodeKind.omp_critical_directive
	'OMPDistributeDirective':                           NodeKind.omp_distribute_directive
	'OMPDistributeParallelForDirective':                NodeKind.omp_distribute_parallel_for_directive
	'OMPDistributeParallelForSimdDirective':            NodeKind.omp_distribute_parallel_for_simd_directive
	'OMPDistributeSimdDirective':                       NodeKind.omp_distribute_simd_directive
	'OMPFlushDirective':                                NodeKind.omp_flush_directive
	'OMPForDirective':                                  NodeKind.omp_for_directive
	'OMPForSimdDirective':                              NodeKind.omp_for_simd_directive
	'OMPMasterDirective':                               NodeKind.omp_master_directive
	'OMPOrderedDirective':                              NodeKind.omp_ordered_directive
	'OMPParallelDirective':                             NodeKind.omp_parallel_directive
	'OMPParallelForDirective':                          NodeKind.omp_parallel_for_directive
	'OMPParallelForSimdDirective':                      NodeKind.omp_parallel_for_simd_directive
	'OMPParallelSectionsDirective':                     NodeKind.omp_parallel_sections_directive
	'OMPSectionDirective':                              NodeKind.omp_section_directive
	'OMPSectionsDirective':                             NodeKind.omp_sections_directive
	'OMPSimdDirective':                                 NodeKind.omp_simd_directive
	'OMPSingleDirective':                               NodeKind.omp_single_directive
	'OMPTargetDataDirective':                           NodeKind.omp_target_data_directive
	'OMPTargetDirective':                               NodeKind.omp_target_directive
	'OMPTargetEnterDataDirective':                      NodeKind.omp_target_enter_data_directive
	'OMPTargetExitDataDirective':                       NodeKind.omp_target_exit_data_directive
	'OMPTargetParallelDirective':                       NodeKind.omp_target_parallel_directive
	'OMPTargetParallelForDirective':                    NodeKind.omp_target_parallel_for_directive
	'OMPTargetParallelForSimdDirective':                NodeKind.omp_target_parallel_for_simd_directive
	'OMPTargetSimdDirective':                           NodeKind.omp_target_simd_directive
	'OMPTargetTeamsDirective':                          NodeKind.omp_target_teams_directive
	'OMPTargetTeamsDistributeDirective':                NodeKind.omp_target_teams_distribute_directive
	'OMPTargetTeamsDistributeParallelForDirective':     NodeKind.omp_target_teams_distribute_parallel_for_directive
	'OMPTargetTeamsDistributeParallelForSimdDirective': NodeKind.omp_target_teams_distribute_parallel_for_simd_directive
	'OMPTargetTeamsDistributeSimdDirective':            NodeKind.omp_target_teams_distribute_simd_directive
	'OMPTargetUpdateDirective':                         NodeKind.omp_target_update_directive
	'OMPTaskDirective':                                 NodeKind.omp_task_directive
	'OMPTaskgroupDirective':                            NodeKind.omp_taskgroup_directive
	'OMPTaskLoopDirective':                             NodeKind.omp_task_loop_directive
	'OMPTaskLoopSimdDirective':                         NodeKind.omp_task_loop_simd_directive
	'OMPTaskwaitDirective':                             NodeKind.omp_taskwait_directive
	'OMPTaskyieldDirective':                            NodeKind.omp_taskyield_directive
	'OMPTeamsDirective':                                NodeKind.omp_teams_directive
	'OMPTeamsDistributeDirective':                      NodeKind.omp_teams_distribute_directive
	'OMPTeamsDistributeParallelForDirective':           NodeKind.omp_teams_distribute_parallel_for_directive
	'OMPTeamsDistributeParallelForSimdDirective':       NodeKind.omp_teams_distribute_parallel_for_simd_directive
	'OMPTeamsDistributeSimdDirective':                  NodeKind.omp_teams_distribute_simd_directive
	'OpaqueValueExpr':                                  NodeKind.opaque_value_expr
	'original':                                         NodeKind.original
	'OverloadCandidate':                                NodeKind.overload_candidate
	'OverloadedDeclRef':                                NodeKind.overloaded_decl_ref
	'OverrideAttr':                                     NodeKind.override_attr
	'Overrides':                                        NodeKind.overrides
	'PackedAttr':                                       NodeKind.packed_attr
	'PackExpansionExpr':                                NodeKind.pack_expansion_expr
	'PackExpansionType':                                NodeKind.pack_expansion_type
	'ParagraphComment':                                 NodeKind.paragraph_comment
	'ParenExpr':                                        NodeKind.paren_expr
	'ParenListExpr':                                    NodeKind.paren_list_expr
	'ParenType':                                        NodeKind.paren_type
	'ParmDecl':                                         NodeKind.parm_decl
	'ParmVarDecl':                                      NodeKind.parm_var_decl
	'PointerType':                                      NodeKind.pointer_type
	'PredefinedExpr':                                   NodeKind.predefined_expr
	'private':                                          NodeKind.private
	'protected':                                        NodeKind.protected
	'public':                                           NodeKind.public
	'PureAttr':                                         NodeKind.pure_attr
	'QualType':                                         NodeKind.qual_type
	'Record':                                           NodeKind.record
	'RecordDecl':                                       NodeKind.record_decl
	'RecordType':                                       NodeKind.record_type
	'ReleaseCapabilityAttr':                            NodeKind.release_capability_attr
	'RequiresCapabilityAttr':                           NodeKind.requires_capability_attr
	'RestrictAttr':                                     NodeKind.restrict_attr
	'ReturnStmt':                                       NodeKind.return_stmt
	'ReturnsTwiceAttr':                                 NodeKind.returns_twice_attr
	'ruct':                                             NodeKind.ruct
	'RValueReferenceType':                              NodeKind.r_value_reference_type
	'ScopedLockableAttr':                               NodeKind.scoped_lockable_attr
	'SEHExceptStmt':                                    NodeKind.seh_except_stmt
	'SEHFinallyStmt':                                   NodeKind.seh_finally_stmt
	'SEHLeaveStmt':                                     NodeKind.seh_leave_stmt
	'SEHTryStmt':                                       NodeKind.seh_try_stmt
	'SizeOfPackExpr':                                   NodeKind.size_of_pack_expr
	'StaticAssert':                                     NodeKind.static_assert
	'StaticAssertDecl':                                 NodeKind.static_assert_decl
	'StmtExpr':                                         NodeKind.stmt_expr
	'StringLiteral':                                    NodeKind.string_literal
	'StructDecl':                                       NodeKind.struct_decl
	'SubstNonTypeTemplateParmExpr':                     NodeKind.subst_non_type_template_parm_expr
	'SubstTemplateTypeParmType':                        NodeKind.subst_template_type_parm_type
	'SwitchStmt':                                       NodeKind.switch_stmt
	'TemplateArgument':                                 NodeKind.template_argument
	'TemplateRef':                                      NodeKind.template_ref
	'TemplateSpecializationType':                       NodeKind.template_specialization_type
	'TemplateTemplateParameter':                        NodeKind.template_template_parameter
	'TemplateTemplateParmDecl':                         NodeKind.template_template_parm_decl
	'TemplateTypeParameter':                            NodeKind.template_type_parameter
	'TemplateTypeParm':                                 NodeKind.template_type_parm
	'TemplateTypeParmDecl':                             NodeKind.template_type_parm_decl
	'TemplateTypeParmType':                             NodeKind.template_type_parm_type
	'TextComment':                                      NodeKind.text_comment
	'TranslationUnit':                                  NodeKind.translation_unit
	'TranslationUnitDecl':                              NodeKind.translation_unit_decl
	'TypeAliasDecl':                                    NodeKind.type_alias_decl
	'TypeAliasTemplateDecl':                            NodeKind.type_alias_template_decl
	'Typedef':                                          NodeKind.typedef
	'TypedefDecl':                                      NodeKind.typedef_decl
	'TypedefType':                                      NodeKind.typedef_type
	'TypeRef':                                          NodeKind.type_ref
	'TypeVisibilityAttr':                               NodeKind.type_visibility_attr
	'UnaryExpr':                                        NodeKind.unary_expr
	'UnaryExprOrTypeTraitExpr':                         NodeKind.unary_expr_or_type_trait_expr
	'UnaryOperator':                                    NodeKind.unary_operator
	'UnaryTransformType':                               NodeKind.unary_transform_type
	'UnexposedAttr':                                    NodeKind.unexposed_attr
	'UnexposedDecl':                                    NodeKind.unexposed_decl
	'UnexposedExpr':                                    NodeKind.unexposed_expr
	'UnexposedStmt':                                    NodeKind.unexposed_stmt
	'Unhandled':                                        NodeKind.unhandled
	'UnionDecl':                                        NodeKind.union_decl
	'UnresolvedLookupExpr':                             NodeKind.unresolved_lookup_expr
	'UnresolvedMemberExpr':                             NodeKind.unresolved_member_expr
	'UnusedAttr':                                       NodeKind.unused_attr
	'UsingDecl':                                        NodeKind.using_decl
	'UsingDeclaration':                                 NodeKind.using_declaration
	'UsingDirective':                                   NodeKind.using_directive
	'UsingDirectiveDecl':                               NodeKind.using_directive_decl
	'UsingShadowDecl':                                  NodeKind.using_shadow_decl
	'VAArgExpr':                                        NodeKind.va_arg_expr
	'VarDecl':                                          NodeKind.var_decl
	'VariableRef':                                      NodeKind.variable_ref
	'virtual':                                          NodeKind.virtual
	'VisibilityAttr':                                   NodeKind.visibility_attr
	'WarnUnusedResultAttr':                             NodeKind.warn_unused_result_attr
	'WhileStmt':                                        NodeKind.while_stmt
}

// Reverse process is done in a runtime, so this map always contains correct data.
// We are using reversed str_to_node_kind_map to implement NodeKind.str() method.
const node_kind_to_str_map = reverse_str_to_node_kind_map()

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
