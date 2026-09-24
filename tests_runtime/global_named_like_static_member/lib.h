class Common {
public:
	virtual int Init() = 0;
	virtual ~Common() {}
};
class Lib {
public:
	static Common *common;
	static void Init();
};
extern Common *common;
