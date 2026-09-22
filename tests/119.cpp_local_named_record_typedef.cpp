int local_named_record_typedef() {
	typedef struct local_node_s {
		int value;
	} local_node_t;
	local_node_t item = { 7 };
	local_node_t *ptr = &item;
	return ptr->value;
}
