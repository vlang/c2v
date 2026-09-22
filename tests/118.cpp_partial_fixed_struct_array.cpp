struct PartialEntry {
	int value;
};

static PartialEntry entries[4] = {
	{ 11 },
	{ 22 },
};

int main() {
	return entries[0].value + entries[1].value;
}
