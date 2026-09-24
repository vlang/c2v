#include <stdio.h>
class Common {
public:
	typedef void *(*FunctionPointer)(void *);
	virtual bool GetFunction(int ft, FunctionPointer *out_fnptr, void **out_arg) = 0;
	virtual ~Common() {}
};
static void *twice(void *p) { return (void *)((long)p * 2); }
class CommonLocal : public Common {
public:
	bool GetFunction(int ft, FunctionPointer *out_fnptr, void **out_arg) {
		if (out_fnptr == NULL) {
			return false;
		}
		*out_fnptr = ft == 1 ? (FunctionPointer)twice : NULL;
		if (out_arg) {
			*out_arg = NULL;
		}
		return *out_fnptr != NULL;
	}
};
int main() {
	CommonLocal local;
	Common *common = &local;
	Common::FunctionPointer fn = NULL;
	bool ok = common->GetFunction(1, &fn, NULL);
	printf("%d %ld\n", ok ? 1 : 0, (long)fn((void *)21));
	return 0;
}
