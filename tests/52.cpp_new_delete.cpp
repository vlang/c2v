struct Point {
    int x;
    int y;
};

void test_new_delete() {
    Point* p = new Point();
    delete p;
}
