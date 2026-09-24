#include <stdio.h>
enum { ON_ACTION = 2, ON_FRAME = 6 };
int frame_code() { return ON_FRAME + ON_ACTION; }
