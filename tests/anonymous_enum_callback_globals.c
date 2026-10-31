enum { choice_left = -2, choice_right = 5 } choice = choice_left;
enum { unused_zero, unused_one } unused_choice;

typedef struct { int value; } Player;
typedef struct { int value; } Sprite;
typedef struct { int value; } Object;
typedef void (*Action)();
typedef union {
    Action generic;
    void (*object)(Object *);
    void (*weapon)(Player *, Sprite *);
} Callback;
typedef struct { Callback callback; } State;

void update_object(Object *object) { object->value += 11; }
void update_weapon(Player *player, Sprite *sprite) {
    player->value += sprite->value;
}

State states[3] = {
    {{update_object}},
    {{update_weapon}},
    {{0}}
};

int fixture_value(void) {
    Object object = {7};
    Player player = {13};
    Sprite sprite = {19};
    choice = choice_right;
    states[0].callback.object(&object);
    states[1].callback.weapon(&player, &sprite);
    if (object.value != 18 || player.value != 32) return 1;
    if (states[0].callback.object != update_object) return 2;
    if (states[1].callback.weapon != update_weapon) return 3;
    if (states[2].callback.generic != 0) return 4;
    if (choice != 5) return 5;
    choice = choice_left;
    return choice == -2 ? 0 : 6;
}
