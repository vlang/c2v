#include <stdio.h>

const int a = 0;

void main() 
{ 
    switch(a)
    {
    default:
        printf("foo\n");
        break;
    case 0:
        printf("bar\n");
        break;
    }


    switch(a)
    {
    case 0:
        printf("bar\n");
        break;
    default:
        printf("foo\n");
        break;
    }
}