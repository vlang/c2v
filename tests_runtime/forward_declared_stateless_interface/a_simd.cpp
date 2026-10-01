#include "material.h"

int CountStages(const Material *material) {
	int count = 0;
	for (int i = 0; i < material->numStages; i++) {
		if (material->stages[i].width > 0) {
			count++;
		}
	}
	return count;
}
