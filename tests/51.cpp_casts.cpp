void test_static_cast() {
    double d = 3.14;
    int i = static_cast<int>(d);
}

void test_reinterpret_cast() {
    long addr = 0x1234;
    int* p = reinterpret_cast<int*>(addr);
}

void test_const_cast() {
    const int ci = 10;
    int* mp = const_cast<int*>(&ci);
}

void test_functional_cast() {
    float f = float(42);
}
