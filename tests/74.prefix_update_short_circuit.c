int message_counter;
int message_locked;
int message_on;

void tick_message(void) {
	if (message_counter && !--message_counter) {
		message_on = 0;
		message_locked = 0;
	}
}
