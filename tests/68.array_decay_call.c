const char *names[] = {"ONE", "TWO", 0};
char label[16] = "READY";

void log_name(const char *fmt, ...);

struct patch;
void take_patches(struct patch **values);
typedef void (*load_callback_t)(const char *name, struct patch **value);

static struct patch *splat[2] = {0, 0};

int count_names(const char **values) {
	const char **check = values;

	while (*check != 0) {
		check++;
	}

	return check - values;
}

int count_global_names(void) {
	return count_names(names);
}

void log_label(void) {
	log_name("%s", label);
}

void pass_patch_array(void) {
	take_patches(splat);
}

void pass_patch_slot(load_callback_t callback) {
	callback("SPLAT", &splat[0]);
}
