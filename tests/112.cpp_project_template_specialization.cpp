template <class T, int N>
struct TinyArray {
	TinyArray() : size_value(0) {}

	void push_back(const T &value) {
		values[size_value] = value;
		size_value++;
	}

	T &operator[](int index) {
		return values[index];
	}

	int size() const {
		return size_value;
	}

	T values[N];
	int size_value;
};

typedef TinyArray<int, 4> TinyInts;

int project_template_value() {
	TinyInts values;
	values.push_back(7);
	return values[0] + values.size();
}
