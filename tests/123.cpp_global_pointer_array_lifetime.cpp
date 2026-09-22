const char *global_pointer_names[] = {
	"first", "second", 0
};

const char **saved_global_pointer_names = global_pointer_names;

const char *read_saved_global_pointer_name(int index) {
	return saved_global_pointer_names[index];
}
