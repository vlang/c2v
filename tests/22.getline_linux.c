#include <stdio.h>
#include <stdlib.h>

int main() {
    char *input = NULL;
    size_t len = 0;
    ssize_t read;
    printf("Enter text (Ctrl+D to quit):\n");
    read = getline(&input, &len, stdin);

    if (read != -1) {
        printf("Entered: %s", input);
    } else {
        printf("error reading input\n");
    }

    free(input);
    return 0;
}