#include "material.h"

int CountStages(const Material *material);

int main() {
	Material *plain = MakeMaterial(false);
	Material *movie = MakeMaterial(true);
	printf("%d %d %d\n", CountStages(plain), plain->Frames(), movie->Frames());
	plain->FreeData();
	movie->FreeData();
	printf("%d\n", movie->Frames());
	return 0;
}
