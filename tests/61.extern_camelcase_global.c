extern int mouseSensitivity;

int scaled_mouse(int x) {
    return x * (mouseSensitivity + 5) / 10;
}
