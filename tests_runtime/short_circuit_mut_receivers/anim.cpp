#include <stdio.h>

class Animator {
public:
	int queries;
	Animator() { queries = 0; }
	bool GetJointTransform(int joint, int time, int &offset) {
		queries++;
		offset = joint * 10 + time;
		return joint >= 0;
	}
};

class Entity {
public:
	Animator animator;
	Animator *GetAnimator() { return &animator; }
};

class Model {
public:
	Entity *entity;
	Model() { entity = NULL; }
	Entity *GetEntity() { return entity; }
};

int Query(Model &worldModel, int joint) {
	int offset = -1;
	if (worldModel.GetEntity() && worldModel.GetEntity()->GetAnimator()->GetJointTransform(joint, 5, offset)) {
		return offset;
	}
	return offset;
}

static int evaluations = 0;
bool CheckTheFirstVeryLongNamedConditionTerm(int value) { evaluations++; return value > 1; }
bool CheckTheSecondVeryLongNamedConditionTerm(int value) { evaluations += 10; return value > 2; }
bool CheckTheThirdVeryLongNamedConditionTerm(int value) { evaluations += 100; return value > 3; }
bool CheckTheFourthVeryLongNamedConditionTerm(int value) { evaluations += 1000; return value > 4; }

int Mixed(int v) {
	if (CheckTheFirstVeryLongNamedConditionTerm(v) && CheckTheSecondVeryLongNamedConditionTerm(v) || CheckTheThirdVeryLongNamedConditionTerm(v) && CheckTheFourthVeryLongNamedConditionTerm(v)) {
		return 1;
	}
	return 0;
}

int main() {
	int m = 0;
	for (int v = 0; v < 6; v++) {
		m = m * 2 + Mixed(v);
	}
	printf("%d %d\n", m, evaluations);
	Model model;
	int a = Query(model, 2);
	Entity e;
	model.entity = &e;
	int b = Query(model, 3);
	int c = Query(model, -1);
	printf("%d %d %d %d\n", a, b, c, e.animator.queries);
	return 0;
}
