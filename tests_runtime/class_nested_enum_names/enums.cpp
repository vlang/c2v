#include <stdio.h>

class Multiplayer {
public:
	typedef enum {
		INACTIVE = 0,
		WARMUP,
		GAMEON,
		STATE_COUNT
	} gameState_t;
	gameState_t gameState;
	gameState_t nextState;
	Multiplayer() { gameState = INACTIVE; nextState = WARMUP; }
	gameState_t GetGameState() const { return gameState; }
	void Advance();
	void NewState(gameState_t news);
	const char *Name(gameState_t state) const {
		switch (state) {
			case INACTIVE: return "inactive";
			case WARMUP: return "warmup";
			case GAMEON: return "gameon";
			default: return "?";
		}
	}
};

void Multiplayer::Advance() {
	gameState_t previous = gameState;
	gameState = nextState;
	nextState = (previous == INACTIVE) ? GAMEON : INACTIVE;
}

void Multiplayer::NewState(gameState_t news) {
	gameState = news;
}

class EventQueue {
public:
	typedef enum {
		OUTOFORDER_IGNORE,
		OUTOFORDER_DROP,
		OUTOFORDER_SORT
	} outOfOrderBehaviour_t;
	int count;
	EventQueue() { count = 0; }
	void Enqueue(int ev, outOfOrderBehaviour_t behaviour);
};

void EventQueue::Enqueue(int ev, outOfOrderBehaviour_t behaviour) {
	count += (behaviour == OUTOFORDER_SORT) ? ev * 10 : ev;
}

class Mover {
public:
	enum moveStage_t { ACCELERATION_STAGE, LINEAR_STAGE, DECELERATION_STAGE, FINISHED_STAGE };
	moveStage_t stage;
	Mover() { stage = ACCELERATION_STAGE; }
};

static int StageValue(const Mover &mover) {
	Mover::moveStage_t stage = mover.stage;
	return stage == Mover::FINISHED_STAGE ? 100 : (int)stage;
}

typedef enum {
	GAMESTATE_UNINITIALIZED,
	GAMESTATE_NOMAP,
	GAMESTATE_ACTIVE
} gameState_t;

struct GameLocal {
	gameState_t gamestate;
	Multiplayer mp;
};

int main() {
	GameLocal game;
	game.gamestate = GAMESTATE_NOMAP;
	game.mp.Advance();
	Multiplayer::gameState_t state = game.mp.GetGameState();
	game.mp.Advance();
	EventQueue queue;
	queue.Enqueue(3, EventQueue::OUTOFORDER_SORT);
	queue.Enqueue(4, EventQueue::OUTOFORDER_DROP);
	Mover mover;
	mover.stage = Mover::FINISHED_STAGE;
	game.mp.NewState(Multiplayer::GAMEON);
	printf("%d %d %s\n", queue.count, StageValue(mover), game.mp.Name(game.mp.GetGameState()));
	printf("%d %s %s %d\n", (int)game.gamestate, game.mp.Name(state), game.mp.Name(game.mp.GetGameState()), game.gamestate == GAMESTATE_ACTIVE);
	return 0;
}
