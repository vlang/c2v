#include <stdio.h>

class Compressor {
public:
	virtual ~Compressor() {}
	virtual int Compress(int value) = 0;
};

class Doubler : public Compressor {
public:
	int calls;
	Doubler() { calls = 0; }
	int Compress(int value) { calls++; return value * 2; }
};

struct Channel {
	Compressor *compressor;
	int *buffer;
	void Init() {
		compressor = new Doubler;
		buffer = new int[16];
	}
	void Shutdown() {
		delete compressor;
		compressor = NULL;
		delete[] buffer;
		buffer = NULL;
	}
};

int main() {
	int total = 0;
	for (int round = 0; round < 1000; round++) {
		Channel channel;
		channel.Init();
		channel.buffer[3] = round;
		total += channel.compressor->Compress(channel.buffer[3]);
		channel.Shutdown();
		Compressor *none = NULL;
		delete none;
	}
	printf("%d\n", total);
	return 0;
}
