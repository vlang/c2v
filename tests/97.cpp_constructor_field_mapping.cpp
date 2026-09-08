#include <stdarg.h>

class idEventDef {
public:
	const char *name;
	const char *formatspec;
	unsigned int formatspecIndex;
	int returnType;

	idEventDef(const char *command, const char *format, char result = 0) {
	}
};

idEventDef make_event() {
	return idEventDef("play", "s", 'd');
}

typedef void (*argCompletion_t)(const char *value);

class idCVar {
public:
	const char *name;
	const char *value;
	const char *description;
	int flags;
	float valueMin;
	float valueMax;
	const char **valueStrings;
	argCompletion_t valueCompletion;

	idCVar(const char *varName, const char *varValue, int varFlags,
		const char *varDescription, argCompletion_t completion = 0) {
	}
	idCVar(const char *varName, const char *varValue, int varFlags,
		const char *varDescription, float minimum, float maximum,
		argCompletion_t completion = 0) {
	}
	idCVar(const char *varName, const char *varValue, int varFlags,
		const char *varDescription, const char **strings,
		argCompletion_t completion = 0) {
	}
};

idCVar make_cvar() {
	return idCVar("test_name", "test_value", 7, "test description");
}

idCVar make_range_cvar() {
	return idCVar("range_name", "1", 9, "range description", 0.0f, 2.0f);
}

idCVar make_choice_cvar(const char **strings, argCompletion_t completion) {
	return idCVar("choice_name", "a", 11, "choice description", strings, completion);
}

const char *choice_values[2] = { "first", 0 };
char version_text[4] = { 'v', '1', 0, 0 };

idCVar make_array_choice_cvar(argCompletion_t completion) {
	return idCVar("array_name", "first", 13, "array description", choice_values, completion);
}

idCVar make_array_value_cvar() {
	return idCVar("version_name", version_text, 15, "version description");
}

class idTypeInfo {
public:
	const char *classname;
	const char *superclass;
	void *createInstance;
	void *spawn;
	void *save;
	void *restore;
	void **eventCallbacks;

	idTypeInfo(const char *typeName, const char *superTypeName, void **callbacks,
		void *create, void *spawnFunction, void *saveFunction, void *restoreFunction) {
	}
};

void *type_callbacks[1] = { 0 };

idTypeInfo make_type_info(void *create, void *spawnFunction, void *saveFunction,
	void *restoreFunction) {
	return idTypeInfo("Child", "Parent", type_callbacks, create, spawnFunction,
		saveFunction, restoreFunction);
}

class idVarDef;

class idStr {
public:
	int len;
	const char *data;
	int alloced;

	idStr() {
	}
	idStr(const char *text) {
	}

	const char *c_str() const {
		return data;
	}

	void append(const char *text) {
	}

	int Cmp(const char *text) const {
		return 0;
	}

	int IcmpPath(const char *text) const {
		return 0;
	}

	operator const char *() const {
		return data;
	}

	idStr &operator+=(const idStr &other) {
		return *this;
	}

	idStr &operator+=(const char *text) {
		return *this;
	}
};

class idToken : public idStr {
};

void append_derived_idstr(idStr &out, const idToken &token) {
	out += token;
}

bool operator==(const idStr &left, const char *right) {
	return left.data == right;
}

bool operator!=(const char *left, const idStr &right) {
	return left != right.data;
}

idStr operator+(const idStr &left, const char *right) {
	return left;
}

idStr operator+(const char *left, const idStr &right) {
	return right;
}

bool idstr_literal_comparisons(const idStr &value) {
	return value == "ok" && "bad" != value;
}

idStr idstr_append_copy(idStr value, const char *suffix) {
	return value + suffix;
}

idStr idstr_prepend_copy(const char *prefix, idStr value) {
	return prefix + value;
}

idStr construct_idstr(const char *text) {
	return idStr(text);
}

typedef idStr *idStrPtr;

int compare_idstr_pointer_aliases(const idStrPtr *left, const idStrPtr *right) {
	return (*left)->IcmpPath(**right);
}

const char *idstr_text(idStr &value) {
	return value;
}

void accept_text(const char *text) {
}

void accept_char(char value) {
}

void pass_char_literal() {
	accept_char(' ');
	char slash = '\\';
	accept_char(slash);
}

void pass_text_buffer() {
	char text[8];
	accept_text(text);
}

void pass_conditional_text(bool set) {
	accept_text(set ? "1" : "0");
}

class idCmdArgs {
public:
	int argc;

	idCmdArgs(const char *text, bool keepAsStrings) {
		argc = keepAsStrings ? 2 : 1;
	}

	const char *firstText(bool unused, ...) {
		va_list args;
		va_start(args, unused);
		const char *result = va_arg(args, const char *);
		va_end(args);
		return result;
	}
};

int consume_cmd_args(const idCmdArgs &args) {
	return args.argc;
}

int construct_cmd_args(const char *text) {
	return consume_cmd_args(idCmdArgs(text, false));
}

struct NamedBuffer {
	char name[8];
};

void pass_indirect_member_buffer(NamedBuffer **item) {
	accept_text((*item)->name);
}

void pass_text_buffer_to_member(idStr &value) {
	char text[8];
	value.append(text);
}

class FieldMethodCollision {
public:
	int contacts;
	int Contacts(int value);
};

class ReferenceBase {
public:
	int value;
};

class ReferenceDerived : public ReferenceBase {
};

class ReferenceOwner {
public:
	ReferenceDerived *item;

	const ReferenceBase &base() const {
		return *item;
	}
};

void accept_reference_base(const ReferenceBase &value) {
}

void pass_reference_derived(const ReferenceDerived &value) {
	accept_reference_base(value);
}

ReferenceBase *return_reference_derived_pointer(ReferenceOwner &owner) {
	return owner.item;
}

bool cpp_truthy_values(int count, ReferenceBase *pointer) {
	return count || pointer;
}

int cpp_bool_index(bool pick_second) {
	int values[2] = { 3, 7 };
	return values[pick_second];
}

class NestedEnumOwner {
public:
	typedef enum {
		NESTED_IDLE = 0,
		NESTED_BUSY
	} state_t;

	state_t state;
	state_t get_state() { return state; }
};

float Min(float left, float right);
float Max(float left, float right);
float Square(float value);
float Cube(float value);

float cpp_inline_math_helpers(float left, float right) {
	return Min(left, right) + Max(left, right) + Square(left) + Cube(right);
}

template<class T>
class idList {
public:
	int num;
	int size;
	int granularity;
	T *list;
};

struct ListItem {
	int value;
};

typedef idList<ListItem *> listItemPtrList;

int local_idlist_typedef_layout() {
	idList<ListItem *> values;
	return values.num;
}

int function_local_enum(bool description) {
	enum {
		SHOW_VALUE,
		SHOW_DESCRIPTION
	} show;
	show = SHOW_VALUE;
	if (description) {
		show = SHOW_DESCRIPTION;
	}
	return show;
}

enum ExecMode {
	EXEC_NOW,
	EXEC_LATER
};

int switch_exec_mode(ExecMode mode) {
	switch (mode) {
	case EXEC_NOW:
		return 1;
	case EXEC_LATER:
		return 2;
	}
	return 0;
}

int FieldMethodCollision::Contacts(int value) {
	contacts = value;
	return contacts;
}

class idTypeDef {
public:
	int type;
	idStr name;
	int size;
	idTypeDef *auxType;
	void *parmTypes;
	idVarDef *def;

	idTypeDef(int etype, idVarDef *edef, const char *ename, int esize,
		idTypeDef *aux) {
	}
};

class idVarDef {
public:
	int num;
	idTypeDef *typeDef;

	idVarDef(idTypeDef *typeptr) {
	}
};

idVarDef *script_def;
idTypeDef *script_aux;
idVarDef script_value(script_aux);

idTypeDef make_script_type() {
	return idTypeDef(3, script_def, "script", 8, script_aux);
}

idVarDef make_script_def(idTypeDef *typeptr) {
	return idVarDef(typeptr);
}
