typedef struct Flags {
    unsigned int visible : 1;
    unsigned int index : 4;
    int delta : 3;
    float weight;
} Flags;

union Packed {
    unsigned short low : 4;
    float f;
};
