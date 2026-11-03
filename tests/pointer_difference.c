#include <stddef.h>
#include <stdio.h>

typedef int *IntPointer;
typedef IntPointer *IntPointerList;
typedef int IntRow[3];
typedef IntRow *RowPointer;

int main(void) {
    const char *names[6];
    const char **names_begin = &names[2];
    const char **names_end = &names[5];
    printf("charpp %td %td\n", names_end - names_begin, names_begin - names_end);

    int *pointers[7];
    int **pointers_begin = &pointers[2];
    int **pointers_end = &pointers[6];
    printf("intpp %td %td\n", pointers_end - pointers_begin, pointers_begin - pointers_end);

    char bytes[8];
    char *bytes_begin = &bytes[1];
    char *bytes_end = &bytes[6];
    printf("char %td %td\n", bytes_end - bytes_begin, bytes_begin - bytes_end);

    int numbers[8];
    int *numbers_begin = &numbers[2];
    int *numbers_end = &numbers[6];
    printf("int %td %td\n", numbers_end - numbers_begin, numbers_begin - numbers_end);

    IntPointerList aliases_begin = &pointers[2];
    IntPointerList aliases_end = &pointers[6];
    printf("alias %td %td\n", aliases_end - aliases_begin, aliases_begin - aliases_end);

    int rows[4][3];
    int (*rows_begin)[3] = &rows[1];
    int (*rows_end)[3] = &rows[3];
    printf("rows %td %td\n", rows_end - rows_begin, rows_begin - rows_end);

    IntRow alias_rows[4];
    RowPointer alias_rows_begin = &alias_rows[1];
    RowPointer alias_rows_end = &alias_rows[3];
    printf("row_alias %td %td\n", alias_rows_end - alias_rows_begin,
           alias_rows_begin - alias_rows_end);
    return 0;
}
