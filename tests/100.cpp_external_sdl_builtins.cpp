extern int SDL_Init(unsigned flags);
extern const char *SDL_GetError();
extern int SDL_SetHint(const char *name, const char *value);
extern void SDL_Quit();
extern const char *SDL_GetCurrentVideoDriver();

const char *initialize_sdl() {
	if (SDL_Init(1) != 0) {
		return SDL_GetError();
	}
	SDL_SetHint("driver", "enabled");
	SDL_Quit();
	return "";
}

const char *current_video_driver() {
	return SDL_GetCurrentVideoDriver();
}

void force_trap() {
	__builtin_trap();
}
