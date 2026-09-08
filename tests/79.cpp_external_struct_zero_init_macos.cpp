#include <signal.h>

int main() {
	struct sigaction action = {0};
	return action.sa_flags;
}
