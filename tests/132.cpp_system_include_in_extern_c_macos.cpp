extern "C" {
#include <sys/select.h>
}

int is_set(int fd) {
	fd_set set;
	FD_ZERO(&set);
	FD_SET(fd, &set);
	return FD_ISSET(fd, &set) ? 1 : 0;
}
