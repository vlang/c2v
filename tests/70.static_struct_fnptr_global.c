typedef struct {
	void (*ProcessEvents)();
	void (*RunMenu)();
} loop_interface_t;

void D_ProcessEvents(void) {}
void M_Ticker(void) {}
void register_loop(loop_interface_t *i);

static loop_interface_t doom_loop_interface = {
	D_ProcessEvents,
	M_Ticker
};

void setup(void) {
	register_loop(&doom_loop_interface);
}
