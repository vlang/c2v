#include <stdio.h>
#include <string.h>

typedef unsigned short word;
typedef unsigned int dword;

struct waveformat_s {
	word wFormatTag;
	word nChannels;
	dword nSamplesPerSec;
	dword nAvgBytesPerSec;
	word nBlockAlign;
} __attribute__((packed));

struct pcmwaveformat_s {
	waveformat_s wf;
	word wBitsPerSample;
} __attribute__((packed));

struct Plain {
	word a;
	dword b;
	word c;
};

int main() {
	unsigned char bytes[16] = {1, 0, 2, 0, 0x44, 0xac, 0, 0, 0x10, 0xb1, 2, 0, 4, 0, 16, 0};
	pcmwaveformat_s format;
	memcpy(&format, bytes, sizeof(format));
	printf("%d %d %d\n", (int)sizeof(waveformat_s), (int)sizeof(pcmwaveformat_s), (int)sizeof(Plain));
	printf("%d %d %u %u %d %d\n", format.wf.wFormatTag, format.wf.nChannels, format.wf.nSamplesPerSec,
		format.wf.nAvgBytesPerSec, format.wf.nBlockAlign, format.wBitsPerSample);
	return 0;
}
