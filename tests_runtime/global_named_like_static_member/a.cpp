#include "lib.h"
Common *Lib::common = 0;
void Lib::Init() {
	Lib::common = ::common;
}
