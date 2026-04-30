struct Counter {
    int count;

    Counter() {
        count = 0;
    }

    ~Counter() {
        count = -1;
    }

    int get_count() {
        return count;
    }
};
