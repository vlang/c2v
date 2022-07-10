#pragma once

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>

// Standard types and macros that are always available.

// Types

// Represents a 2D vector.
typedef struct tm_vec2_t
{
    float x, y;
} tm_vec2_t;

// Represents a 3D vector.
typedef struct tm_vec3_t
{
    float x, y, z;
} tm_vec3_t;

// Represents a 3D vector in double precision.
typedef struct tm_vec3d_t
{
    double x, y, z;
} tm_vec3d_t;

// Represents a 4D vector.
typedef struct tm_vec4_t
{
    float x, y, z, w;
} tm_vec4_t;

// Represents a 4x4 matrix.
typedef struct tm_mat44_t
{
    float xx, xy, xz, xw;
    float yx, yy, yz, yw;
    float zx, zy, zz, zw;
    float wx, wy, wz, ww;
} tm_mat44_t;

// Represents a transform in TRS form.
typedef struct tm_transform_t
{
    tm_vec3_t pos;
    tm_vec4_t rot;
    tm_vec3_t scl;
} tm_transform_t;

// Represents a rectangle.
typedef struct tm_rect_t
{
    float x, y, w, h;
} tm_rect_t;

// Used to represent a string slice with pointer and length.
//
// This lets you reason about parts of a string, which you are not able to do with standard
// NULL-terminated strings.
typedef struct tm_str_t
{
    // Pointer to string bytes.
    const char *data;

    // Length of the string.
    uint32_t size;

    // If set to *true*, indicates that there is an allocated NULL-byte after the string data. I.e.
    // `data[size] == 0`. This means that `data` can be used immediately as a C string without
    // needing to copy it to a separate memory area.
    //
    // If *false*, there may or may not be a NULL-byte at the end of the string and accessing
    // `data[size]` may cause an access violation, so if you want to use it as a C-string you have
    // to copy it to a new memory area and append a NULL byte.
    //
    // Note that the NULL-byte is never included in the `size`.
    uint32_t null_terminated;
} tm_str_t;

// Creates a [[tm_str_t]] from a `char *` `s`.
#define tm_str(s) (TM_LITERAL(tm_str_t){ (s), s ? (uint32_t)strlen(s) : 0, true })

// Creates a [[tm_str_t]] from a static string `s`. As [[tm_str()]], but uses `sizeof()` instead of
// `strlen()` to determine the length of the string. This means it avoids the `strlen()` overhead
// and can be used to initialize static data, but it can only be used with static strings.
#define TM_STR(s) (TM_LITERAL(tm_str_t){ ("" s ""), (uint32_t)(sizeof("" s "") - 1), true })

// Creates a [[tm_str_t]] from a start pointer `s` and end pointer `e`.
#define tm_str_range(s, e) (e > s ? TM_LITERAL(tm_str_t){ (s), (uint32_t)((e) - (s)), false } : TM_LITERAL(tm_str_t){ 0 })

// Represents a time from the system clock.
//
// You can assume the clock to be monotonically increasing, i.e. a larger `opaque` value represents
// a later time, but you shouldn't assume anything else about what the `opaque` value represents or
// the resolution of the timer. Instead, use [[tm_os_time_api->delta()]] to convert elapsed time to
// seconds.
typedef struct tm_clock_o
{
    uint64_t opaque;
} tm_clock_o;

// Represents a unique 128-bit identifier.
typedef struct tm_uuid_t
{
    uint64_t a;
    uint64_t b;
} tm_uuid_t;

// Represents an 8-bit per channel RGBA color in sRGB color space (Note: alpha is always linear.)
typedef struct tm_color_srgb_t
{
    uint8_t r, g, b, a;
} tm_color_srgb_t;

// Converts an `uint32_t` to an [[tm_color_srgb_t]] color.
//
// The nibbles in the `uint32_t` hex representation specify TRGB, where T is transparancy (0x00
// means fully opaque and 0xff fully transparent, i.e. it is the invert of alpha). This lets you
// leave the highest nibble out for an opaque color (the most common case), but specify it if
// you want transparency.
//
// Hex        | Color
// ---------- | -------------------
// 0x00       | Black
// 0xff0000   | Red
// 0xff000000 | Transparent black
// 0x80ffff00 | 50 % transparent yellow
#define TM_RGB(c) (TM_LITERAL(tm_color_srgb_t){ 0xff & (c >> 16), 0xff & (c >> 8), 0xff & (c >> 0), 0xff - (0xff & (c >> 24)) })

// Type representing a type in The Truth.
typedef struct tm_tt_type_t
{
    uint64_t u64;
} tm_tt_type_t;

// ID representing an object in The Truth.
typedef struct tm_tt_id_t
{
    union
    {
        // Used for comparing objects or storing them in hash tables.
        uint64_t u64;

        struct
        {
            // Type of the object.
            uint64_t type : 10;
            // Generation of the object, used to distinguish objects created at the same index.
            uint64_t generation : 22;
            // Index of the object.
            uint64_t index : 32;
        };
    };
} tm_tt_id_t;

// Returns the type of `id`.
static inline tm_tt_type_t tm_tt_type(tm_tt_id_t id)
{
    tm_tt_type_t res = { id.type };
    return res;
}

// Type representing an undo scope in The Truth.
typedef struct tm_tt_undo_scope_t
{
    uint64_t u64;
} tm_tt_undo_scope_t;

// Used to represent API versions.
//
// Version numbers follow the SemVer 2.0.0 specification:
//
// * The major version is bumped for breaking API changes.
// * The minor version is bumped when new functionality is added in a backwards-compatible manner.
// * The patch version is bumped for backwards-compatible bug fixes.
// * If the major version is 0, the API is considered unstable and under development. In this case,
//   nothing should be assumed about backwards compatibility.
//
// See: https://semver.org/spec/v2.0.0.html
//
// !!! WARNING: Be careful about backwards compatibility
//     The default action should be to bump the major version whenever you change something in the
//     API. If you are considering just bumping the minor or patch version, you must make 100 %
//     sure that your changes are backwards compatible, since otherwise you will break existing
//     plugins without any warning.
typedef struct tm_version_t
{
    // Bumped when breaking changes are made to the API. For example:
    //
    // * Adding functions in the middle of the API.
    // * Changing the number of parameters to a function or their types.
    // * Changing the return type of a function.
    // * Changing the fields of a struct.
    uint32_t major;

    // Bumped when new functionality is added to the API in a backwards-compatible manner.
    // Changes are backwards compatible if a caller using an old version of the header file can
    // still call into the new version of the ABI without errors. Examples of backwards-compatible
    // changes are:
    //
    // * Adding new functions to the end of the API.
    // * Repurposing unused bits in structs.
    //
    // If you want to change an API and only bump the minor version you should make sure to take
    // special care that your changes are really backwards compatible.
    uint32_t minor;

    // Bumped for backwards-compatible bug fixes.
    uint32_t patch;
} tm_version_t;

// Creates a [[tm_version_t]] literal.
#define TM_VERSION(major, minor, patch) (TM_LITERAL(tm_version_t){ major, minor, patch })

// The [[TM_VERSION()]] macro cannot be used to initialize constant objects in Visual Studio.
// (It will give the error "initializer not constant".) This macro can be used as an alternative
// for constant initializations.
//
// !!! TODO: TODO
//     Having two separate macros for this is not very elegant. See if we can find a better
//     solution.
#define TM_VERSION_INITIALIZER(major, minor, patch) \
    {                                               \
        major, minor, patch                         \
    }

// Build configuration
//
// These macros are defined in the build file `premake5.lua`, but listed here for documentation
// purposes.

#if 0

// Defined for Windows builds.
#define TM_OS_WINDOWS

// Defined for OS X builds.
#define TM_OS_MACOSX

// Defined for Linux builds.
#define TM_OS_LINUX

// Defined for POSIX builds (OS X or Linux).
#define TM_OS_POSIX

// If defined, the main job runs on a thread, not a fiber.
#define TM_NO_MAIN_FIBER

// Defined for debug builds.
#define TM_CONFIGURATION_DEBUG

// Defined for release builds.
#define TM_CONFIGURATION_RELEASE

#endif

// String hashes

#if defined(_MSC_VER) && !defined(__clang__)

// `#define TM_USE_STRHASH_TYPE` controls whether we should use a custom type [[tm_strhash_t]] for
// string hashes, or if they should just be `uint64_t`. Currently, it is set to `0` when compiling
// using MSVC and `1` otherwise.
//
// We cannot use the [[tm_strhash_t]] type with the Visual Studio compiler, because it doesn't see
// our [[TM_STATIC_HASH()]] macro as a constant, and thus will generate
// [C2099](https://docs.microsoft.com/en-us/cpp/error-messages/compiler-errors-1/compiler-error-c2099?view=msvc-160)
// compiler error. errors whenever it is used to initialize a global variable. This is unfortunate,
// because it means we can't get type safe string hashes in Visual Studio.
//
// Hopefully, this will be fixed in a future Visual Studio release and we can transition fully to
// the [[tm_strhash_t]] type.
#define TM_USE_STRHASH_TYPE 0

#else

// tm_docgen ignore
#define TM_USE_STRHASH_TYPE 1

#endif

#if TM_USE_STRHASH_TYPE

// Type-safe representation of a hashed string.
//
// !!! WARNING: WARNING
//     In Visual Studio, string hashes won't use this string type, instead
//     [[tm_strhash_t]] will be typedefed to `uint64_t`. The reason for this is that the
//     [[TM_STATIC_HASH()]] macro is not seen as a constant by the MSVC compiler and thus using it
//     to initialize global variables yields the
//     [C2099](https://docs.microsoft.com/en-us/cpp/error-messages/compiler-errors-1/compiler-error-c2099?view=msvc-160)
//     compiler error.
//
//     This means that the type safety of string hashes won't be checked when compiling with MSVC.
//     Make sure you build your code under clang too, with `tmbuild --clang` to check the type
//     safety of string hashes. Also, always use the macros [[TM_STRHASH()]] and
//     [[TM_STRHASH_U64()]] to convert between [[tm_strhash_t]] and `uint64_t`. This ensures that
//     the conversions work on all platforms.
typedef struct tm_strhash_t
{
    uint64_t u64;
} tm_strhash_t;

// Converts a `uint64_t` to a [[tm_strhash_t]].
#define TM_STRHASH(x) (TM_LITERAL(tm_strhash_t){ x })

// Extracts the `uint64_t` of a [[tm_strhash_t]] value `x`.
#define TM_STRHASH_U64(x) ((x).u64)

#else

// tm_docgen ignore
typedef uint64_t tm_strhash_t;

// tm_docgen ignore
#define TM_STRHASH(x) (x)

// tm_docgen ignore
#define TM_STRHASH_U64(x) (x)

#endif

// Returns true if the the two [[tm_strhash_t]] are equal.
#define TM_STRHASH_EQUAL(a, b) (TM_STRHASH_U64(a) == TM_STRHASH_U64(b))

// Used for static string hashes. The `hash.exe` utility checks the entire source code and makes
// sure that wherever you use [[TM_STATIC_HASH()]], the numeric value `v` matches the actual hash of the
// string `s` (if not, the code is updated).
//
// When you create a new static hash, don't enter the numeric value, just the string:
// `TM_STATIC_HASH<!-- -->("bla")`.
//
// This ensures that the macro fails to compile until you run `hash.exe` to generate a numeric
// value.
//
// [[TM_STATIC_HASH()]] returns a constant value of type [[tm_strhash_t]].
//
// <!--
//     `(sizeof("" s "") ? v : v)` is a trick to get an expression that evaluates to `v` but
//     produces a compile error if `s` is anything other than a static string.
// -->
#define TM_STATIC_HASH(s, v) TM_STRHASH(sizeof("" s "") > 0 ? v : v)

// Macros

#ifdef __cplusplus

// tm_docgen ignore
#define TM_LITERAL(T) T

#else

// Macro for creating a struct literal of type `T` that works both in C and C++. Use as:
//
// ~~~c
// x = TM_LITERAL(tm_vec2_t) {x, y}
// ~~~
//
// In C, this turns into `(tm_vec2_t){0, 0}` and in C++ to `tm_vec2_t{0, 0}`.
//
// Note that use of [[TM_LITERAL()]] is only needed in .h and .inl files that might be included from
// both C and C++. In .c and .cpp file you should just use the native literal format instead of
// relying on [[TM_LITERAL()]].
#define TM_LITERAL(T) (T)

#endif

#if defined(_MSC_VER)

// Marks a function to be exported to DLLs.
#define TM_DLL_EXPORT __declspec(dllexport)

#else

// tm_docgen ignore
#define TM_DLL_EXPORT __attribute__((visibility("default")))

#endif

#if defined(TM_OS_MACOSX)
#ifndef __restrict

// tm_docgen ignore
//
// This is not ideal -- preferably we would want to use `restrict` rather than `__restrict` as our
// `restrict` keyword, since that is what the C standard specifies. However, VS does not support
// this, and if we try `#define restrict __restrict` we run into trouble, because some of the
// windows headers actually use `restrict` already.
#define __restrict restrict

#endif
#endif

#if defined(_MSC_VER) && !defined(__clang__)

// Mark struct fields in header files as atomic.
#define TM_ATOMIC

#else

// tm_docgen ignore
#define TM_ATOMIC _Atomic

#endif

// tm_docgen off

// Generate an error if this file was included in a C++ file, without wrapping the include in extern
// "C". If you forget extern "C", the first declaration will get C++ linkage and you will then get a
// conflict on the second declaration.
#ifdef __cplusplus
void use_extern_c_wrapper_to_include_the_machinery_headers_in_cpp_files(void);
extern "C" void use_extern_c_wrapper_to_include_the_machinery_headers_in_cpp_files(void);
#endif

// tm_docgen on

// Returns the `name` as a string.
#define TM_STRINGIFY(name) #name

// tm_docgen ignore
#define TM_CONCAT_IMPL(a, b) a##b

// Concatenates `a` and `b` , allowing you to expand macros before doing the concatenation. This is
// useful when used with builtin macros like `__LINE__` or `__COUNTER__`. `x##__COUNTER__` doesn't
// expand to `x1` since a macro is not expanded if preceded by `#` or `##`, but `TM_CONCAT(x,
// __COUNTER__)` works.
#define TM_CONCAT(a, b) TM_CONCAT_IMPL(a, b)

// Generates a unique name for a macro variable, based on `name`.
#define TM_MACRO_VAR(name) TM_CONCAT(name, __LINE__)

// Declares a field that pads a struct with the specified number of bytes. To ensure that structs
// are completely zero-initialized by designated initializers, we require all struct padding to be
// explicitly declared using this macro. (We enable warnings that trigger if there is undeclared
// padding in a struct.)
//
// Example:
//
// ~~~c
// struct x {
//     uint32_t a;
//     // This padding is needed since `b` needs to be aligned to a 64-bit boundary.
//     TM_PAD(4);
//     uint64_t b;
// };
// ~~~
//
// Note that in situations where types have different sizes on different platforms you may need to
// pad with different amounts:
//
// ~~~c
// TM_PAD(8 - sizeof(x));
// ~~~
#define TM_PAD(n) char TM_MACRO_VAR(_padding_)[n]

#if defined(TM_OS_WINDOWS)

// Disable warnings about padding inserted into structs. Use this before including external headers
// that do not explicitly declare padding. Restore the padding warning afterwards with
// [[TM_RESTORE_PADDING_WARNINGS]].
#define TM_DISABLE_PADDING_WARNINGS \
    __pragma(warning(push))         \
        __pragma(warning(disable : 4121 4820))

// Restore padding warnings disabled by [[TM_DISABLE_PADDING_WARNINGS]].
#define TM_RESTORE_PADDING_WARNINGS \
    __pragma(warning(pop))

#elif defined(__clang__)
// tm_docgen ignore
#define TM_DISABLE_PADDING_WARNINGS  \
    _Pragma("clang diagnostic push") \
        _Pragma("clang diagnostic ignored \"-Wpadded\"")
// tm_docgen ignore
#define TM_RESTORE_PADDING_WARNINGS \
    _Pragma("clang diagnostic pop")
#elif defined(__GNUC__) || defined(__GNUG__)
// tm_docgen ignore
#define TM_DISABLE_PADDING_WARNINGS \
    _Pragma("GCC diagnostic push")  \
        _Pragma("GCC diagnostic ignored \"-Wpadded\"")
// tm_docgen ignore
#define TM_RESTORE_PADDING_WARNINGS \
    _Pragma("GCC diagnostic pop")
#endif

#if !defined(__cplusplus)

// Used to implement "inheritance" -- inserting the members of one struct into another, with a
// construct like:
//
// ~~~c
// struct tm_class_t {
//     TM_INHERITS(struct tm_super_t);
//     ...
// }
// ~~~
//
// In a compiler that supports anonymous structs, (`-Wno-microsoft-anon-tag`, `-fms-extensions`),
// this will be expanded to just `struct tm_super_t;`, otherwise to `struct tm_super_t super;`.
//
// !!! note
//     A struct should never have more than one [[TM_INHERITS()]] and it should always be placed
//     at the top of the struct.
#define TM_INHERITS(TYPE) TYPE

#else
// tm_docgen ignore
#define TM_INHERITS(TYPE) TYPE super
#endif

#if defined(TM_OS_MACOSX) && defined(TM_CPU_ARM)
// tm_docgen ignore
#define TM_PAGE_SIZE 16384
#else
#define TM_PAGE_SIZE 4096
#endif