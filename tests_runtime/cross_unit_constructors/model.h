#ifndef MODEL_H
#define MODEL_H
class Model {
public:
	Model(void);
	Model(const char *name);
	explicit Model(const int handle);
	Model(const Model *other);
	Model(const Model &other);
	~Model(void);
	int index;
	static int live;
};
class Physics {
public:
	virtual ~Physics() {}
	virtual Model *GetClipModel(int id = 0) const = 0;
	virtual void SetClipModel(Model *model, float density, int id = 0, bool freeOld = true) = 0;
};
#endif
