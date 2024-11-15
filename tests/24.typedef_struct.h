typedef struct
{
    float x, y;
} ImVec2;

typedef struct ImVec3 ImVec3;
struct ImVec3
{
    float x, y, z;
};

struct ImVec4
{
    float x, y, z, w;
};
typedef struct ImVec4 ImVec4;

struct ImGuiTextRange
{
    const char *b;
    const char *e;
};
typedef struct ImGuiTextRange ImGuiTextRange;

typedef struct ImVector_ImGuiTextRange
{
    int Size;
    int Capacity;
    ImGuiTextRange *Data;
} ImVector_ImGuiTextRange;

struct ImGuiTextFilter
{
    char InputBuf[256];
    ImVector_ImGuiTextRange Filters;
    int CountGrep;
};
typedef struct ImGuiTextRange ImGuiTextRange;

typedef unsigned short ImWchar16;
typedef ImWchar16 ImWchar;

typedef struct ImGuiContext ImGuiContext;
struct ImGuiContext;
struct ImGuiContext
{
    int Initialized;
};