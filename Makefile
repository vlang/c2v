all: c2v

c2v: *.v
	v -w .

clean:
	rm -rf c2v

.PHONY: all clean

