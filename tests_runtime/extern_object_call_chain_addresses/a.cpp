#include <stdio.h>
#include "game.h"

// Addresses of members reached through calls on a global object that a later
// translation unit defines: while this file is translated the object is still
// an external symbol.
static float Yaw(const Angles &angles) { return angles.yaw; }
static void Turn(Angles *angles, float delta) { angles->yaw += delta; }

int main() {
	gameLocal.GetLocalPlayer()->viewAngles.yaw = 30.0f;
	Turn(&gameLocal.GetLocalPlayer()->viewAngles, 15.0f);
	Turn(&gameLocal.GetLocalPlayer()->Next()->angles[1], 2.5f);
	int *health = &gameLocal.Local().health;
	*health = 75;
	printf("%g %g %d\n", Yaw(gameLocal.GetLocalPlayer()->viewAngles), gameLocal.player.angles[1].yaw,
		gameLocal.player.health);
	return 0;
}
