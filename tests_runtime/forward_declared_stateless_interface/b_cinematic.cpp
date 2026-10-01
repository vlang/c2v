#include "material.h"
#include "cinematic.h"

Cinematic *Cinematic::Alloc() { return new CinematicLocal(); }
Cinematic::~Cinematic() {}
int Cinematic::AnimationLength() { return 0; }
void Cinematic::Close() {}

void Material::FreeData() {
	for (int i = 0; i < numStages; i++) {
		if (stages[i].cinematic) {
			stages[i].cinematic->Close();
			delete stages[i].cinematic;
			stages[i].cinematic = NULL;
		}
	}
}

int Material::Frames() const {
	int frames = 0;
	for (int i = 0; i < numStages; i++) {
		if (stages[i].cinematic) {
			frames += stages[i].cinematic->AnimationLength();
		}
	}
	return frames;
}

Material *MakeMaterial(bool withCinematic) {
	Material *material = new Material();
	material->numStages = 2;
	material->stages[0].cinematic = withCinematic ? Cinematic::Alloc() : NULL;
	material->stages[0].width = 8;
	material->stages[1].cinematic = NULL;
	material->stages[1].width = 0;
	return material;
}
