struct Item {
};

Item *acquire();

bool consume_items() {
	Item *item;
	if ((item = acquire()) == nullptr) {
		return false;
	}
	while ((item = acquire()) != nullptr) {
	}
	return true;
}
