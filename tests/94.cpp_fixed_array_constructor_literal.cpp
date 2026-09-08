struct Vec2 {
	float x;
	float y;

	Vec2(float x, float y) : x(x), y(y) {
	}
};

struct Mat2 {
	Vec2 rows[2];

	Mat2(const Vec2 &x, const Vec2 &y) : rows{x, y} {
	}

	Mat2(float xx, float xy, float yx, float yy)
		: rows{Vec2(xx, xy), Vec2(yx, yy)} {
	}
};

Mat2 from_rows(const Vec2 &x, const Vec2 &y) {
	return Mat2(x, y);
}

Mat2 from_scalars() {
	return Mat2(1, 2, 3, 4);
}
