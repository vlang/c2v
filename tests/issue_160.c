#include <stdio.h>
enum LuaType { NIL, INT };
struct Lua {
    enum LuaType (*getArgType)(int pos, const char **out);
};
enum LuaType get_type(int pos, const char **out) {
    *out = "integer";
    return pos ? INT : NIL;
}
int main(void) {
    struct Lua api = {.getArgType = get_type};
    const char *name;
    enum LuaType type = api.getArgType(1, &name);
    printf("%d %s\n", type, name);
    return 0;
}
