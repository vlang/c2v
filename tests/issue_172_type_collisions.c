#include <stddef.h>
#include <stdio.h>

#define INT_MEMBER union { int x; }

union Foo_c2v_anonymous_0 { long long x; };
union Foo_c2v_anonymous_0_1 { long long x; };
struct Foo_item { long long y; };
typedef struct Foo {
    INT_MEMBER;
    struct { int y; } item;
    int tail;
} Foo;
union Foo_c2v_anonymous_0_2 { long long x; };

union lower_c2v_anonymous_0 { long long x; };
typedef struct Lower {
    INT_MEMBER;
    int tail;
} Lower;

union _Hidden_c2v_anonymous_0 { long long x; };
typedef struct Hidden {
    INT_MEMBER;
    int tail;
} Hidden;

typedef long long Alias_c2v_anonymous_0;
typedef struct Alias {
    INT_MEMBER;
    int tail;
} Alias;

int main(void) {
    union Foo_c2v_anonymous_0 user = {0};
    union Foo_c2v_anonymous_0_1 user_next = {0};
    union Foo_c2v_anonymous_0_2 user_later = {0};
    struct Foo_item user_item = {0};
    union lower_c2v_anonymous_0 user_lower = {0};
    union _Hidden_c2v_anonymous_0 user_hidden = {0};
    Alias_c2v_anonymous_0 user_alias = 5000000007LL;
    user.x = 5000000001LL;
    user_next.x = 5000000002LL;
    user_later.x = 5000000003LL;
    user_item.y = 5000000004LL;
    user_lower.x = 5000000005LL;
    user_hidden.x = 5000000006LL;

    Foo foo = {0};
    Lower lower = {0};
    Hidden hidden = {0};
    Alias alias = {0};
    foo.x = 11;
    foo.item.y = 12;
    foo.tail = 13;
    lower.x = 21;
    lower.tail = 22;
    hidden.x = 31;
    hidden.tail = 32;
    alias.x = 41;
    alias.tail = 42;

    printf("%lld %lld %lld %lld %lld %lld %lld\n", user.x, user_next.x,
        user_later.x, user_item.y, user_lower.x, user_hidden.x, user_alias);
    printf("%d %d %d %zu %zu %zu %zu %zu\n", foo.x, foo.item.y, foo.tail,
        sizeof(Foo), sizeof(foo.x), sizeof(foo.item), offsetof(Foo, item),
        offsetof(Foo, tail));
    printf("%d %d %zu %zu %zu\n", lower.x, lower.tail, sizeof(Lower),
        sizeof(lower.x), offsetof(Lower, tail));
    printf("%d %d %zu %zu %zu\n", hidden.x, hidden.tail, sizeof(Hidden),
        sizeof(hidden.x), offsetof(Hidden, tail));
    printf("%d %d %zu %zu %zu %zu\n", alias.x, alias.tail, sizeof(Alias),
        sizeof(alias.x), offsetof(Alias, tail), sizeof(user_alias));
    return 0;
}
