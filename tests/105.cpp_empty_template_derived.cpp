template<class T>
class idValueBase {
public:
	T value;
};

template<class T>
class idEmptyDerived : public idValueBase<T> {
public:
	T GetValue() const {
		return this->value;
	}
};

int read_empty_derived(void) {
	idEmptyDerived<int> item;
	item.value = 7;
	return item.GetValue();
}
