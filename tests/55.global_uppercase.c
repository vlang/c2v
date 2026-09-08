typedef struct {
    int selected;
} menu_t;

menu_t MainDef;
menu_t OptionsDef = {1};

menu_t *get_main(void) {
    return &MainDef;
}

int get_options_selected(void) {
    return OptionsDef.selected;
}
