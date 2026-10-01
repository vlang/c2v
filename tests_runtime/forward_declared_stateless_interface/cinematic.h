class Cinematic {
public:
	static Cinematic *Alloc();
	virtual ~Cinematic();
	virtual int AnimationLength();
	virtual void Close();
};

class CinematicLocal : public Cinematic {
public:
	int length;
	CinematicLocal() { length = 24; }
	int AnimationLength() { return length; }
	void Close() { length = 0; }
};
