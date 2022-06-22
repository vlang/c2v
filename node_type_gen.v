module main

enum NodeKind {
	BAD
	AddrLabelExpr
	AnalyzerNoReturnAttr
	ArrayFiller
	ArraySubscriptExpr
	AsmLabelAttr
	AvailabilityAttr
	BinaryOperator
	BlockExpr
	BreakStmt
	BuiltinType
	CStyleCastExpr
	CXXAccessSpecifier
	CXXBindTemporaryExpr
	CXXBoolLiteralExpr
	CXXCatchStmt
	CXXConstCastExpr
	CXXConstructExpr
	CXXConstructor
	CXXConversion
	CXXDeleteExpr
	CXXDestructor
	CXXDynamicCastExpr
	CXXForRangeStmt
	CXXFunctionalCastExpr
	CXXMemberCallExpr
	CXXMethod
	CXXNewExpr
	CXXNullPtrLiteralExpr
	CXXOperatorCallExpr
	CXXReinterpretCastExpr
	CXXStaticCastExpr
	CXXThisExpr
	CXXThrowExpr
	CXXTryStmt
	CXXTypeidExpr
	CallExpr
	CaseStmt
	CharacterLiteral
	ClassDecl
	ClassTemplate
	ClassTemplatePartialSpecialization
	ColdAttr
	CompoundAssignOperator
	CompoundLiteralExpr
	CompoundStmt
	ConditionalOperator
	ConstantExpr
	ContinueStmt
	DecayedType
	DeclRefExpr
	DeclStmt
	DefaultStmt
	DoStmt
	ElaboratedType
	EnumConstantDecl
	Enum
	EnumDecl
	EnumType
	ExprWithCleanups
	FieldDecl
	FixedPointLiteral
	FloatingLiteral
	ForStmt
	FriendDecl
	FullComment
	FunctionDecl
	FunctionTemplate
	GCCAsmStmt
	GNUNullExpr
	GenericSelectionExpr
	GotoStmt
	IfStmt
	ImaginaryLiteral
	ImplicitCastExpr
	ImplicitValueInitExpr
	IndirectGotoStmt
	InitListExpr
	IntegerLiteral
	InvalidCode
	InvalidFile
	LabelRef
	LabelStmt
	LambdaExpr
	LinkageSpec
	MSAsmStmt
	MaterializeTemporaryExpr
	MemberExpr
	MemberRef
	MemberRefExpr
	ModuleImport
	Namespace
	NamespaceAlias
	NamespaceRef
	NoDeclFound
	NoEscapeAttr
	NonTypeTemplateParameter
	NotImplemented
	Null
	NullStmt
	OMPArraySectionExpr
	OMPAtomicDirective
	OMPBarrierDirective
	OMPCancelDirective
	OMPCancellationPointDirective
	OMPCriticalDirective
	OMPDistributeDirective
	OMPDistributeParallelForDirective
	OMPDistributeParallelForSimdDirective
	OMPDistributeSimdDirective
	OMPFlushDirective
	OMPForDirective
	OMPForSimdDirective
	OMPMasterDirective
	OMPOrderedDirective
	OMPParallelDirective
	OMPParallelForDirective
	OMPParallelForSimdDirective
	OMPParallelSectionsDirective
	OMPSectionDirective
	OMPSectionsDirective
	OMPSimdDirective
	OMPSingleDirective
	OMPTargetDataDirective
	OMPTargetDirective
	OMPTargetEnterDataDirective
	OMPTargetExitDataDirective
	OMPTargetParallelDirective
	OMPTargetParallelForDirective
	OMPTargetParallelForSimdDirective
	OMPTargetSimdDirective
	OMPTargetTeamsDirective
	OMPTargetTeamsDistributeDirective
	OMPTargetTeamsDistributeParallelForDirective
	OMPTargetTeamsDistributeParallelForSimdDirective
	OMPTargetTeamsDistributeSimdDirective
	OMPTargetUpdateDirective
	OMPTaskDirective
	OMPTaskLoopDirective
	OMPTaskLoopSimdDirective
	OMPTaskgroupDirective
	OMPTaskwaitDirective
	OMPTaskyieldDirective
	OMPTeamsDirective
	OMPTeamsDistributeDirective
	OMPTeamsDistributeParallelForDirective
	OMPTeamsDistributeParallelForSimdDirective
	OMPTeamsDistributeSimdDirective
	ObjCAtCatchStmt
	ObjCAtFinallyStmt
	ObjCAtSynchronizedStmt
	ObjCAtThrowStmt
	ObjCAtTryStmt
	ObjCAutoreleasePoolStmt
	ObjCAvailabilityCheckExpr
	ObjCBoolLiteralExpr
	ObjCBridgedCastExpr
	ObjCCategoryDecl
	ObjCCategoryImplDecl
	ObjCClassMethodDecl
	ObjCClassRef
	ObjCDynamicDecl
	ObjCEncodeExpr
	ObjCForCollectionStmt
	ObjCImplementationDecl
	ObjCInstanceMethodDecl
	ObjCInterfaceDecl
	ObjCIvarDecl
	ObjCMessageExpr
	ObjCPropertyDecl
	ObjCProtocolDecl
	ObjCProtocolExpr
	ObjCProtocolRef
	ObjCSelectorExpr
	ObjCSelfExpr
	ObjCStringLiteral
	ObjCSuperClassRef
	ObjCSynthesizeDecl
	OverloadCandidate
	OverloadedDeclRef
	PackExpansionExpr
	ParagraphComment
	ParenExpr
	ParmDecl
	ParmVarDecl
	Record
	RecordDecl
	RecordType
	ReturnStmt
	SEHExceptStmt
	SEHFinallyStmt
	SEHLeaveStmt
	SEHTryStmt
	SizeOfPackExpr
	StaticAssert
	StmtExpr
	StringLiteral
	StructDecl
	SwitchStmt
	TemplateRef
	TemplateTemplateParameter
	TemplateTypeParameter
	TextComment
	TranslationUnit
	TypeAliasDecl
	TypeAliasTemplateDecl
	TypeRef
	Typedef
	TypedefDecl
	TypedefType
	UnaryExpr
	UnaryExprOrTypeTraitExpr
	UnaryOperator
	UnexposedAttr
	UnexposedDecl
	UnexposedExpr
	UnexposedStmt
	Unhandled
	CXCursorKind
	UnionDecl
	UsingDeclaration
	UsingDirective
	UsingDirectiveDecl
	VarDecl
	VariableRef
	WhileStmt
	VAArgExpr
	NoThrowAttr
	PointerType
	AlignedAttr
	AllocSizeAttr
	ConstAttr
	ConstantArrayType
	DeprecatedAttr
	FunctionProtoType
	IncompleteArrayType
	MaxFieldAlignmentAttr
	NoInlineAttr
	OffsetOfExpr
	PackedAttr
	ParenType
	QualType
	ReturnsTwiceAttr
	TranslationUnitDecl
	HTMLStartTagComment
	HTMLEndTagComment
	FormatAttr
	AlwaysInlineAttr
	WarnUnusedResultAttr
	FunctionNoProtoType
	FormatArgAttr
	PureAttr
	VisibilityAttr
	CXXRecord
	NamespaceDecl
	CXXRecordDecl
	CXXConstructorDecl
	CXXDestructorDecl
	CXXMethodDecl
	LinkageSpecDecl
	EnableIfAttr
	ClassTemplateDecl
	TemplateTypeParmDecl
	TypeVisibilityAttr
	ClassTemplateSpecializationDecl
	TemplateArgument
	ClassTemplateSpecialization
	AccessSpecDecl
	SubstTemplateTypeParmType
	TemplateTypeParmType
	TemplateTypeParm
	LValueReferenceType
	TemplateSpecializationType
	FunctionTemplateDecl
	StaticAssertDecl
	CXXCtorInitializer
	CXXDefaultArgExpr
	CXXConversionDecl
	UsingDecl
	UsingShadowDecl
	NonTypeTemplateParmDecl
	ClassTemplatePartialSpecializationDecl
	DependentNameType
	NoSanitizeAttr
	InjectedClassNameType
	SubstNonTypeTemplateParmExpr
	original
	public
	DependentScopeDeclRefExpr
	ruct
	DecltypeType
	UnresolvedLookupExpr
	CXXUnresolvedConstructExpr
	ParenListExpr
	UnaryTransformType
	CXXDependentScopeMemberExpr
	RestrictAttr
	private
	AtomicExpr
	TemplateTemplateParmDecl
	CXXPseudoDestructorExpr
	CXXTemporaryObjectExpr
	UnresolvedMemberExpr
	UnusedAttr
	protected
	CXXScalarValueInitExpr
	IndirectFieldDecl
	Field
	Function
	virtual
	Overrides
	OverrideAttr
	PredefinedExpr
	OpaqueValueExpr
	BlockCommandComment
	DisableTailCallsAttr
	DiagnoseIfAttr
	MemberPointerType
	RValueReferenceType
	PackExpansionType
	CXXNoexceptExpr
	DependentTemplateSpecializationType
	BuiltinTemplateDecl
	CXX
	CXXDefaultInitExpr
	CapabilityAttr
	AcquireCapabilityAttr
	ReleaseCapabilityAttr
	AssertExclusiveLockAttr
	RequiresCapabilityAttr
	GuardedByAttr
	ScopedLockableAttr
	InlineCommandComment
}

fn node_kind_from_str(s string) NodeKind {
	match s {
		'AddrLabelExpr' { return .AddrLabelExpr }
		'AnalyzerNoReturnAttr' { return .AnalyzerNoReturnAttr }
		'ArrayFiller' { return .ArrayFiller }
		'ArraySubscriptExpr' { return .ArraySubscriptExpr }
		'AsmLabelAttr' { return .AsmLabelAttr }
		'AvailabilityAttr' { return .AvailabilityAttr }
		'BinaryOperator' { return .BinaryOperator }
		'BlockExpr' { return .BlockExpr }
		'BreakStmt' { return .BreakStmt }
		'BuiltinType' { return .BuiltinType }
		'CStyleCastExpr' { return .CStyleCastExpr }
		'CXXAccessSpecifier' { return .CXXAccessSpecifier }
		'CXXBindTemporaryExpr' { return .CXXBindTemporaryExpr }
		'CXXBoolLiteralExpr' { return .CXXBoolLiteralExpr }
		'CXXCatchStmt' { return .CXXCatchStmt }
		'CXXConstCastExpr' { return .CXXConstCastExpr }
		'CXXConstructExpr' { return .CXXConstructExpr }
		'CXXConstructor' { return .CXXConstructor }
		'CXXConversion' { return .CXXConversion }
		'CXXDeleteExpr' { return .CXXDeleteExpr }
		'CXXDestructor' { return .CXXDestructor }
		'CXXDynamicCastExpr' { return .CXXDynamicCastExpr }
		'CXXForRangeStmt' { return .CXXForRangeStmt }
		'CXXFunctionalCastExpr' { return .CXXFunctionalCastExpr }
		'CXXMemberCallExpr' { return .CXXMemberCallExpr }
		'CXXMethod' { return .CXXMethod }
		'CXXNewExpr' { return .CXXNewExpr }
		'CXXNullPtrLiteralExpr' { return .CXXNullPtrLiteralExpr }
		'CXXOperatorCallExpr' { return .CXXOperatorCallExpr }
		'CXXReinterpretCastExpr' { return .CXXReinterpretCastExpr }
		'CXXStaticCastExpr' { return .CXXStaticCastExpr }
		'CXXThisExpr' { return .CXXThisExpr }
		'CXXThrowExpr' { return .CXXThrowExpr }
		'CXXTryStmt' { return .CXXTryStmt }
		'CXXTypeidExpr' { return .CXXTypeidExpr }
		'CallExpr' { return .CallExpr }
		'CaseStmt' { return .CaseStmt }
		'CharacterLiteral' { return .CharacterLiteral }
		'ClassDecl' { return .ClassDecl }
		'ClassTemplate' { return .ClassTemplate }
		'ClassTemplatePartialSpecialization' { return .ClassTemplatePartialSpecialization }
		'ColdAttr' { return .ColdAttr }
		'CompoundAssignOperator' { return .CompoundAssignOperator }
		'CompoundLiteralExpr' { return .CompoundLiteralExpr }
		'CompoundStmt' { return .CompoundStmt }
		'ConditionalOperator' { return .ConditionalOperator }
		'ConstantExpr' { return .ConstantExpr }
		'ContinueStmt' { return .ContinueStmt }
		'DecayedType' { return .DecayedType }
		'DeclRefExpr' { return .DeclRefExpr }
		'DeclStmt' { return .DeclStmt }
		'DefaultStmt' { return .DefaultStmt }
		'DoStmt' { return .DoStmt }
		'ElaboratedType' { return .ElaboratedType }
		'EnumConstantDecl' { return .EnumConstantDecl }
		'Enum' { return .Enum }
		'EnumDecl' { return .EnumDecl }
		'EnumType' { return .EnumType }
		'ExprWithCleanups' { return .ExprWithCleanups }
		'FieldDecl' { return .FieldDecl }
		'FixedPointLiteral' { return .FixedPointLiteral }
		'FloatingLiteral' { return .FloatingLiteral }
		'ForStmt' { return .ForStmt }
		'FriendDecl' { return .FriendDecl }
		'FullComment' { return .FullComment }
		'FunctionDecl' { return .FunctionDecl }
		'FunctionTemplate' { return .FunctionTemplate }
		'GCCAsmStmt' { return .GCCAsmStmt }
		'GNUNullExpr' { return .GNUNullExpr }
		'GenericSelectionExpr' { return .GenericSelectionExpr }
		'GotoStmt' { return .GotoStmt }
		'IfStmt' { return .IfStmt }
		'ImaginaryLiteral' { return .ImaginaryLiteral }
		'ImplicitCastExpr' { return .ImplicitCastExpr }
		'ImplicitValueInitExpr' { return .ImplicitValueInitExpr }
		'IndirectGotoStmt' { return .IndirectGotoStmt }
		'InitListExpr' { return .InitListExpr }
		'IntegerLiteral' { return .IntegerLiteral }
		'InvalidCode' { return .InvalidCode }
		'InvalidFile' { return .InvalidFile }
		'LabelRef' { return .LabelRef }
		'LabelStmt' { return .LabelStmt }
		'LambdaExpr' { return .LambdaExpr }
		'LinkageSpec' { return .LinkageSpec }
		'MSAsmStmt' { return .MSAsmStmt }
		'MaterializeTemporaryExpr' { return .MaterializeTemporaryExpr }
		'MemberExpr' { return .MemberExpr }
		'MemberRef' { return .MemberRef }
		'MemberRefExpr' { return .MemberRefExpr }
		'ModuleImport' { return .ModuleImport }
		'Namespace' { return .Namespace }
		'NamespaceAlias' { return .NamespaceAlias }
		'NamespaceRef' { return .NamespaceRef }
		'NoDeclFound' { return .NoDeclFound }
		'NoEscapeAttr' { return .NoEscapeAttr }
		'NonTypeTemplateParameter' { return .NonTypeTemplateParameter }
		'NotImplemented' { return .NotImplemented }
		'Null' { return .Null }
		'NullStmt' { return .NullStmt }
		'OMPArraySectionExpr' { return .OMPArraySectionExpr }
		'OMPAtomicDirective' { return .OMPAtomicDirective }
		'OMPBarrierDirective' { return .OMPBarrierDirective }
		'OMPCancelDirective' { return .OMPCancelDirective }
		'OMPCancellationPointDirective' { return .OMPCancellationPointDirective }
		'OMPCriticalDirective' { return .OMPCriticalDirective }
		'OMPDistributeDirective' { return .OMPDistributeDirective }
		'OMPDistributeParallelForDirective' { return .OMPDistributeParallelForDirective }
		'OMPDistributeParallelForSimdDirective' { return .OMPDistributeParallelForSimdDirective }
		'OMPDistributeSimdDirective' { return .OMPDistributeSimdDirective }
		'OMPFlushDirective' { return .OMPFlushDirective }
		'OMPForDirective' { return .OMPForDirective }
		'OMPForSimdDirective' { return .OMPForSimdDirective }
		'OMPMasterDirective' { return .OMPMasterDirective }
		'OMPOrderedDirective' { return .OMPOrderedDirective }
		'OMPParallelDirective' { return .OMPParallelDirective }
		'OMPParallelForDirective' { return .OMPParallelForDirective }
		'OMPParallelForSimdDirective' { return .OMPParallelForSimdDirective }
		'OMPParallelSectionsDirective' { return .OMPParallelSectionsDirective }
		'OMPSectionDirective' { return .OMPSectionDirective }
		'OMPSectionsDirective' { return .OMPSectionsDirective }
		'OMPSimdDirective' { return .OMPSimdDirective }
		'OMPSingleDirective' { return .OMPSingleDirective }
		'OMPTargetDataDirective' { return .OMPTargetDataDirective }
		'OMPTargetDirective' { return .OMPTargetDirective }
		'OMPTargetEnterDataDirective' { return .OMPTargetEnterDataDirective }
		'OMPTargetExitDataDirective' { return .OMPTargetExitDataDirective }
		'OMPTargetParallelDirective' { return .OMPTargetParallelDirective }
		'OMPTargetParallelForDirective' { return .OMPTargetParallelForDirective }
		'OMPTargetParallelForSimdDirective' { return .OMPTargetParallelForSimdDirective }
		'OMPTargetSimdDirective' { return .OMPTargetSimdDirective }
		'OMPTargetTeamsDirective' { return .OMPTargetTeamsDirective }
		'OMPTargetTeamsDistributeDirective' { return .OMPTargetTeamsDistributeDirective }
		'OMPTargetTeamsDistributeParallelForDirective' { return .OMPTargetTeamsDistributeParallelForDirective }
		'OMPTargetTeamsDistributeParallelForSimdDirective' { return .OMPTargetTeamsDistributeParallelForSimdDirective }
		'OMPTargetTeamsDistributeSimdDirective' { return .OMPTargetTeamsDistributeSimdDirective }
		'OMPTargetUpdateDirective' { return .OMPTargetUpdateDirective }
		'OMPTaskDirective' { return .OMPTaskDirective }
		'OMPTaskLoopDirective' { return .OMPTaskLoopDirective }
		'OMPTaskLoopSimdDirective' { return .OMPTaskLoopSimdDirective }
		'OMPTaskgroupDirective' { return .OMPTaskgroupDirective }
		'OMPTaskwaitDirective' { return .OMPTaskwaitDirective }
		'OMPTaskyieldDirective' { return .OMPTaskyieldDirective }
		'OMPTeamsDirective' { return .OMPTeamsDirective }
		'OMPTeamsDistributeDirective' { return .OMPTeamsDistributeDirective }
		'OMPTeamsDistributeParallelForDirective' { return .OMPTeamsDistributeParallelForDirective }
		'OMPTeamsDistributeParallelForSimdDirective' { return .OMPTeamsDistributeParallelForSimdDirective }
		'OMPTeamsDistributeSimdDirective' { return .OMPTeamsDistributeSimdDirective }
		'ObjCAtCatchStmt' { return .ObjCAtCatchStmt }
		'ObjCAtFinallyStmt' { return .ObjCAtFinallyStmt }
		'ObjCAtSynchronizedStmt' { return .ObjCAtSynchronizedStmt }
		'ObjCAtThrowStmt' { return .ObjCAtThrowStmt }
		'ObjCAtTryStmt' { return .ObjCAtTryStmt }
		'ObjCAutoreleasePoolStmt' { return .ObjCAutoreleasePoolStmt }
		'ObjCAvailabilityCheckExpr' { return .ObjCAvailabilityCheckExpr }
		'ObjCBoolLiteralExpr' { return .ObjCBoolLiteralExpr }
		'ObjCBridgedCastExpr' { return .ObjCBridgedCastExpr }
		'ObjCCategoryDecl' { return .ObjCCategoryDecl }
		'ObjCCategoryImplDecl' { return .ObjCCategoryImplDecl }
		'ObjCClassMethodDecl' { return .ObjCClassMethodDecl }
		'ObjCClassRef' { return .ObjCClassRef }
		'ObjCDynamicDecl' { return .ObjCDynamicDecl }
		'ObjCEncodeExpr' { return .ObjCEncodeExpr }
		'ObjCForCollectionStmt' { return .ObjCForCollectionStmt }
		'ObjCImplementationDecl' { return .ObjCImplementationDecl }
		'ObjCInstanceMethodDecl' { return .ObjCInstanceMethodDecl }
		'ObjCInterfaceDecl' { return .ObjCInterfaceDecl }
		'ObjCIvarDecl' { return .ObjCIvarDecl }
		'ObjCMessageExpr' { return .ObjCMessageExpr }
		'ObjCPropertyDecl' { return .ObjCPropertyDecl }
		'ObjCProtocolDecl' { return .ObjCProtocolDecl }
		'ObjCProtocolExpr' { return .ObjCProtocolExpr }
		'ObjCProtocolRef' { return .ObjCProtocolRef }
		'ObjCSelectorExpr' { return .ObjCSelectorExpr }
		'ObjCSelfExpr' { return .ObjCSelfExpr }
		'ObjCStringLiteral' { return .ObjCStringLiteral }
		'ObjCSuperClassRef' { return .ObjCSuperClassRef }
		'ObjCSynthesizeDecl' { return .ObjCSynthesizeDecl }
		'OverloadCandidate' { return .OverloadCandidate }
		'OverloadedDeclRef' { return .OverloadedDeclRef }
		'PackExpansionExpr' { return .PackExpansionExpr }
		'ParagraphComment' { return .ParagraphComment }
		'ParenExpr' { return .ParenExpr }
		'ParmDecl' { return .ParmDecl }
		'ParmVarDecl' { return .ParmVarDecl }
		'Record' { return .Record }
		'RecordDecl' { return .RecordDecl }
		'RecordType' { return .RecordType }
		'ReturnStmt' { return .ReturnStmt }
		'SEHExceptStmt' { return .SEHExceptStmt }
		'SEHFinallyStmt' { return .SEHFinallyStmt }
		'SEHLeaveStmt' { return .SEHLeaveStmt }
		'SEHTryStmt' { return .SEHTryStmt }
		'SizeOfPackExpr' { return .SizeOfPackExpr }
		'StaticAssert' { return .StaticAssert }
		'StmtExpr' { return .StmtExpr }
		'StringLiteral' { return .StringLiteral }
		'StructDecl' { return .StructDecl }
		'SwitchStmt' { return .SwitchStmt }
		'TemplateRef' { return .TemplateRef }
		'TemplateTemplateParameter' { return .TemplateTemplateParameter }
		'TemplateTypeParameter' { return .TemplateTypeParameter }
		'TextComment' { return .TextComment }
		'TranslationUnit' { return .TranslationUnit }
		'TypeAliasDecl' { return .TypeAliasDecl }
		'TypeAliasTemplateDecl' { return .TypeAliasTemplateDecl }
		'TypeRef' { return .TypeRef }
		'Typedef' { return .Typedef }
		'TypedefDecl' { return .TypedefDecl }
		'TypedefType' { return .TypedefType }
		'UnaryExpr' { return .UnaryExpr }
		'UnaryExprOrTypeTraitExpr' { return .UnaryExprOrTypeTraitExpr }
		'UnaryOperator' { return .UnaryOperator }
		'UnexposedAttr' { return .UnexposedAttr }
		'UnexposedDecl' { return .UnexposedDecl }
		'UnexposedExpr' { return .UnexposedExpr }
		'UnexposedStmt' { return .UnexposedStmt }
		'Unhandled' { return .Unhandled }
		'CXCursorKind' { return .CXCursorKind }
		'UnionDecl' { return .UnionDecl }
		'UsingDeclaration' { return .UsingDeclaration }
		'UsingDirective' { return .UsingDirective }
		'UsingDirectiveDecl' { return .UsingDirectiveDecl }
		'VarDecl' { return .VarDecl }
		'VariableRef' { return .VariableRef }
		'WhileStmt' { return .WhileStmt }
		'VAArgExpr' { return .VAArgExpr }
		'NoThrowAttr' { return .NoThrowAttr }
		'PointerType' { return .PointerType }
		'AlignedAttr' { return .AlignedAttr }
		'AllocSizeAttr' { return .AllocSizeAttr }
		'ConstAttr' { return .ConstAttr }
		'ConstantArrayType' { return .ConstantArrayType }
		'DeprecatedAttr' { return .DeprecatedAttr }
		'FunctionProtoType' { return .FunctionProtoType }
		'IncompleteArrayType' { return .IncompleteArrayType }
		'MaxFieldAlignmentAttr' { return .MaxFieldAlignmentAttr }
		'NoInlineAttr' { return .NoInlineAttr }
		'OffsetOfExpr' { return .OffsetOfExpr }
		'PackedAttr' { return .PackedAttr }
		'ParenType' { return .ParenType }
		'QualType' { return .QualType }
		'ReturnsTwiceAttr' { return .ReturnsTwiceAttr }
		'TranslationUnitDecl' { return .TranslationUnitDecl }
		'HTMLStartTagComment' { return .HTMLStartTagComment }
		'HTMLEndTagComment' { return .HTMLEndTagComment }
		'FormatAttr' { return .FormatAttr }
		'AlwaysInlineAttr' { return .AlwaysInlineAttr }
		'WarnUnusedResultAttr' { return .WarnUnusedResultAttr }
		'FunctionNoProtoType' { return .FunctionNoProtoType }
		'FormatArgAttr' { return .FormatArgAttr }
		'PureAttr' { return .PureAttr }
		'VisibilityAttr' { return .VisibilityAttr }
		'CXXRecord' { return .CXXRecord }
		'NamespaceDecl' { return .NamespaceDecl }
		'CXXRecordDecl' { return .CXXRecordDecl }
		'CXXConstructorDecl' { return .CXXConstructorDecl }
		'CXXDestructorDecl' { return .CXXDestructorDecl }
		'CXXMethodDecl' { return .CXXMethodDecl }
		'LinkageSpecDecl' { return .LinkageSpecDecl }
		'EnableIfAttr' { return .EnableIfAttr }
		'ClassTemplateDecl' { return .ClassTemplateDecl }
		'TemplateTypeParmDecl' { return .TemplateTypeParmDecl }
		'TypeVisibilityAttr' { return .TypeVisibilityAttr }
		'ClassTemplateSpecializationDecl' { return .ClassTemplateSpecializationDecl }
		'TemplateArgument' { return .TemplateArgument }
		'ClassTemplateSpecialization' { return .ClassTemplateSpecialization }
		'AccessSpecDecl' { return .AccessSpecDecl }
		'SubstTemplateTypeParmType' { return .SubstTemplateTypeParmType }
		'TemplateTypeParmType' { return .TemplateTypeParmType }
		'TemplateTypeParm' { return .TemplateTypeParm }
		'LValueReferenceType' { return .LValueReferenceType }
		'TemplateSpecializationType' { return .TemplateSpecializationType }
		'FunctionTemplateDecl' { return .FunctionTemplateDecl }
		'StaticAssertDecl' { return .StaticAssertDecl }
		'CXXCtorInitializer' { return .CXXCtorInitializer }
		'CXXDefaultArgExpr' { return .CXXDefaultArgExpr }
		'CXXConversionDecl' { return .CXXConversionDecl }
		'UsingDecl' { return .UsingDecl }
		'UsingShadowDecl' { return .UsingShadowDecl }
		'NonTypeTemplateParmDecl' { return .NonTypeTemplateParmDecl }
		'ClassTemplatePartialSpecializationDecl' { return .ClassTemplatePartialSpecializationDecl }
		'DependentNameType' { return .DependentNameType }
		'NoSanitizeAttr' { return .NoSanitizeAttr }
		'InjectedClassNameType' { return .InjectedClassNameType }
		'SubstNonTypeTemplateParmExpr' { return .SubstNonTypeTemplateParmExpr }
		'original' { return .original }
		'public' { return .public }
		'DependentScopeDeclRefExpr' { return .DependentScopeDeclRefExpr }
		'ruct' { return .ruct }
		'DecltypeType' { return .DecltypeType }
		'UnresolvedLookupExpr' { return .UnresolvedLookupExpr }
		'CXXUnresolvedConstructExpr' { return .CXXUnresolvedConstructExpr }
		'ParenListExpr' { return .ParenListExpr }
		'UnaryTransformType' { return .UnaryTransformType }
		'CXXDependentScopeMemberExpr' { return .CXXDependentScopeMemberExpr }
		'RestrictAttr' { return .RestrictAttr }
		'private' { return .private }
		'AtomicExpr' { return .AtomicExpr }
		'TemplateTemplateParmDecl' { return .TemplateTemplateParmDecl }
		'CXXPseudoDestructorExpr' { return .CXXPseudoDestructorExpr }
		'CXXTemporaryObjectExpr' { return .CXXTemporaryObjectExpr }
		'UnresolvedMemberExpr' { return .UnresolvedMemberExpr }
		'UnusedAttr' { return .UnusedAttr }
		'protected' { return .protected }
		'CXXScalarValueInitExpr' { return .CXXScalarValueInitExpr }
		'IndirectFieldDecl' { return .IndirectFieldDecl }
		'Field' { return .Field }
		'Function' { return .Function }
		'virtual' { return .virtual }
		'Overrides' { return .Overrides }
		'OverrideAttr' { return .OverrideAttr }
		'PredefinedExpr' { return .PredefinedExpr }
		'OpaqueValueExpr' { return .OpaqueValueExpr }
		'BlockCommandComment' { return .BlockCommandComment }
		'DisableTailCallsAttr' { return .DisableTailCallsAttr }
		'DiagnoseIfAttr' { return .DiagnoseIfAttr }
		'MemberPointerType' { return .MemberPointerType }
		'RValueReferenceType' { return .RValueReferenceType }
		'PackExpansionType' { return .PackExpansionType }
		'CXXNoexceptExpr' { return .CXXNoexceptExpr }
		'DependentTemplateSpecializationType' { return .DependentTemplateSpecializationType }
		'BuiltinTemplateDecl' { return .BuiltinTemplateDecl }
		'CXX' { return .CXX }
		'CXXDefaultInitExpr' { return .CXXDefaultInitExpr }
		'CapabilityAttr' { return .CapabilityAttr }
		'AcquireCapabilityAttr' { return .AcquireCapabilityAttr }
		'ReleaseCapabilityAttr' { return .ReleaseCapabilityAttr }
		'AssertExclusiveLockAttr' { return .AssertExclusiveLockAttr }
		'RequiresCapabilityAttr' { return .RequiresCapabilityAttr }
		'GuardedByAttr' { return .GuardedByAttr }
		'ScopedLockableAttr' { return .ScopedLockableAttr }
		'InlineCommandComment' { return .InlineCommandComment }
		else {}
	}
	return .BAD
}
