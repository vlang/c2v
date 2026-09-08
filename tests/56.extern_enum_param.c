typedef enum {
    red,
    blue
} color_t;

void set_color(color_t color);

void use_color(void) {
    set_color(blue);
}
