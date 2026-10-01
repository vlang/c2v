#include "powerups.h"

int Powerup(int which) {
	return which == PROJECTILE_DAMAGE ? MELEE_DAMAGE * 10 : SPEED;
}
