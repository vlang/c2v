#include <stdio.h>
class Cinematic;

struct TextureStage {
	Cinematic *cinematic;
	int width;
};

struct Material {
	TextureStage stages[2];
	int numStages;
	void FreeData();
	int Frames() const;
};

Material *MakeMaterial(bool withCinematic);
