struct Angles {
	float yaw;
	float pitch;
};

class Player {
public:
	Angles viewAngles;
	Angles angles[2];
	int health;
	Player *Next() { return this; }
};

class Game {
public:
	Player player;
	Player *GetLocalPlayer() { return &player; }
	Player &Local() { return player; }
};

extern Game gameLocal;
