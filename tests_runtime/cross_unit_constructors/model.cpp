#include "model.h"
int Model::live = 0;
Model::Model(void) { index = -1; live++; }
Model::Model(const char *name) { index = -5; (void)name; live++; }
Model::Model(const int handle) { index = handle; live++; }
Model::Model(const Model *other) { index = other->index + 100; live++; }
Model::~Model(void) { live--; }
Model::Model(const Model &other) { index = other.index + 1000; live++; }
