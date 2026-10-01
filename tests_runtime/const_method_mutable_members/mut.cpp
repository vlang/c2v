#include <stdio.h>

class Reader {
public:
	const unsigned char *data;
	int size;
	mutable int readCount;
	mutable int readBit;

	Reader(const unsigned char *d, int s) { data = d; size = s; readCount = 0; readBit = 0; }
	int ReadBit() const {
		if (readCount >= size) {
			return -1;
		}
		int bit = (data[readCount] >> readBit) & 1;
		readBit++;
		if (readBit == 8) {
			readBit = 0;
			readCount++;
		}
		return bit;
	}
	int Remaining() const { return (size - readCount) * 8 - readBit; }
	int ReadPair() const { return ReadBit() * 2 + ReadBit(); }
};

class CountingReader : public Reader {
public:
	CountingReader(const unsigned char *d, int s) : Reader(d, s) {}
	int ReadNibble() const { return ReadPair() * 4 + ReadPair(); }
};

static int SumBits(const Reader &reader, int count) {
	int sum = 0;
	for (int i = 0; i < count; i++) {
		sum = sum * 2 + reader.ReadBit();
	}
	return sum;
}

int main() {
	unsigned char bytes[2] = { 0xfe, 0x35 };
	Reader reader(bytes, 2);
	int first = SumBits(reader, 5);
	int second = reader.ReadBit();
	printf("%d %d %d\n", first, second, reader.Remaining());
	int pair = reader.ReadPair();
	CountingReader counting(bytes, 2);
	int nibble = counting.ReadNibble();
	printf("%d %d %d %d\n", pair, reader.Remaining(), nibble, counting.Remaining());
	return 0;
}
