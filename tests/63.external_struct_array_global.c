typedef struct {
    int ammo;
    int upstate;
} weaponinfo_t;

extern weaponinfo_t weaponinfo[2];

weaponinfo_t weaponinfo[2] = {
    {1, 2},
    {3, 4}
};

int get_weapon_ammo(int i) {
    return weaponinfo[i].ammo;
}
