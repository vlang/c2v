struct Node {
	Node *other;

	bool points_to_self() {
		return other == this;
	}

	bool differs_from(Node *candidate) {
		return this != candidate;
	}
};
