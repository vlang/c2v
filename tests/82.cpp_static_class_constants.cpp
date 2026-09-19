struct StaticValues {
	static const int INLINE_VALUE = 7;
	static const float DECLARED_VALUE;
	static int mutable_value;
};

const float StaticValues::DECLARED_VALUE = 3.5f;
int StaticValues::mutable_value = 2;

float static_value_sum() {
	return StaticValues::INLINE_VALUE + StaticValues::DECLARED_VALUE + StaticValues::mutable_value;
}

int static_value_through_object(StaticValues *values) {
	return values->mutable_value;
}
