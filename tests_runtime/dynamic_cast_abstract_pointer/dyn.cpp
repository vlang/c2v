#include <stdio.h>

class File {
public:
	virtual ~File() {}
	virtual int Length() = 0;
};

class File_Permanent : public File {
public:
	int length;
	File_Permanent() { length = 10; }
	int Length() { return length; }
};

class File_Buffered : public File_Permanent {
public:
	int Length() { return length * 2; }
};

class File_Memory : public File {
public:
	int Length() { return 4; }
};

static int Describe(File *f) {
	if (dynamic_cast<File_Permanent *>(f)) {
		return 100 + dynamic_cast<File_Permanent *>(f)->length;
	} else {
		return f->Length();
	}
}

int main() {
	File *files[3] = { new File_Permanent(), new File_Memory(), new File_Buffered() };
	for (int i = 0; i < 3; i++) {
		File_Permanent *permanent = dynamic_cast<File_Permanent *>(files[i]);
		printf("%d %s\n", Describe(files[i]), permanent ? "permanent" : "other");
	}
	return 0;
}
