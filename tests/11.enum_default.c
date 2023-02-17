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

int main() {
    enum myEnum myEnumVar = A;
    myAnotherEnum myEnumVar2 = D;
    myStrangeEnum myEnumVar3 = G;
    int myIntVar = J;
    return 0;
}