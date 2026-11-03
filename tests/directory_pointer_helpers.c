typedef enum { first_mode = 4, second_mode = 9 } Mode;
typedef struct { int value; } Record;
static Record *record = (void *)0;
static unsigned char *buffer = (void *)0;
Record storage = {3};

int support_value(void) {
    unsigned char bytes[2] = {11, 13};
    int values[3] = {2, 4, 6};
    int *cursor = values;
    int first = *cursor++;
    int last = *++cursor;
    int selected = 0;
    long long wide = 1LL << 40;
    record = &storage;
    record->value += 4;
    buffer = bytes;
    if (first != 2 || last != 6 || cursor != values + 2) return 1;
    if (record->value != 7 || *(buffer + 1) != 13) return 2;
    switch (-1) {
    case -1:
        switch (first_mode) {
        case first_mode: selected = 11; break;
        case second_mode: selected = 12; break;
        }
        break;
    case 0: selected = 13; break;
    }
    if (selected != 11) return 3;
    switch (wide) {
    case 1LL << 40:
        switch ('x') { case 'x': selected += 7; break; }
        break;
    default: return 4;
    }
    if (selected != 18) return 5;
    record = (void *)0;
    buffer = (void *)0;
    return 0;
}
