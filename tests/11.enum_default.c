enum myEnum {
    A,
    B,
    C
};

typedef enum {
    D,
    E,
    F
} myAnotherEnum;

typedef enum myStrangeEnum {
    G,
    H,
    I
} myStrangeEnum;

enum { J = 1 };

void enum_func(enum myEnum a) {
}

void enum_func_const(const enum myEnum a) {
}

int main() {
    enum myEnum myEnumVar = A;
    myAnotherEnum myEnumVar2 = D;
    myStrangeEnum myEnumVar3 = G;
    int myIntVar = J;
    enum_func(myEnumVar);
    enum_func_const(myEnumVar);
    return 0;
}
