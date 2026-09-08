struct Vector {
	float x;
};

struct Matrix {
	Vector operator*(const Vector &value) const {
		return Vector{value.x * 2};
	}
};

Vector operator*(const Vector &value, const Matrix &matrix) {
	return matrix * value;
}

Vector &operator*=(Vector &value, const Matrix &matrix) {
	value = matrix * value;
	return value;
}

Vector reverse_product(const Vector &value, const Matrix &matrix) {
	return value * matrix;
}

void reverse_assign(Vector &value, const Matrix &matrix) {
	value *= matrix;
}

void reverse_assign_local(const Matrix &matrix) {
	Vector value{};
	value *= matrix;
}

Vector &same_vector(Vector &value) {
	return value;
}

Vector reverse_reference(Vector &value, const Matrix &matrix) {
	return same_vector(value) * matrix;
}

Vector reverse_temporary(const Matrix &matrix) {
	return Vector{} * matrix;
}

Vector reverse_nested_temporary(const Matrix &matrix) {
	return (Vector{} * matrix) * matrix;
}
