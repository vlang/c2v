struct Box {
	int value;
};

Box assign_and_return(Box &target) {
	return target = Box();
}
