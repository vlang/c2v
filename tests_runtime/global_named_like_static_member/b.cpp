#include <stdio.h>
#include "lib.h"
class CommonLocal : public Common {
public:
	int initialized;
	CommonLocal() : initialized(0) {}
	int Init() {
		Lib::Init();
		initialized = 1;
		return Lib::common == this ? 42 : 7;
	}
};
CommonLocal commonLocal;
Common *common = &commonLocal;
int main() {
	int r = common->Init();
	printf("%d %d\n", r, commonLocal.initialized);
	return 0;
}
