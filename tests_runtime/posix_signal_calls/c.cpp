#include <stdio.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <unistd.h>

static volatile int caught = 0;

static void Handler(int sig) { caught = sig; }

int main() {
	struct sigaction action;
	action.sa_handler = Handler;
	sigemptyset(&action.sa_mask);
	action.sa_flags = 0;
	int installed = sigaction(SIGUSR1, &action, NULL);
	raise(SIGUSR1);
	int available = 0;
	int result = ioctl(-1, FIONREAD, &available);
	printf("%d %d %d\n", installed, caught == SIGUSR1, result);
	return 0;
}
