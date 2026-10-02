enum LuaType { NIL, INT };
struct Lua {
    enum LuaType (*getArgType)(int pos, const char **out);
};
