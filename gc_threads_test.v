module main

import os

fn test_native_gc_thread_registration_owns_only_its_threads() {
	$if !linux && !macos {
		return
	}
	dir := os.join_path(os.temp_dir(), 'c2v_gc_threads_${os.getpid()}')
	os.mkdir_all(dir) or { panic(err) }
	defer { os.rmdir_all(dir) or {} }
	os.write_file(os.join_path(dir, 'c2v_gc_threads.inc'), $embed_file('gc_threads.h').to_string()) or { panic(err) }
	source := os.join_path(dir, 'probe.c')
	os.write_file(source, '#define GC_NO_THREAD_REDIRECTS
#include <gc/gc.h>
#include <pthread.h>
#include <assert.h>
#include <stdatomic.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

static atomic_int ready;
static atomic_int start;
static atomic_int cleanups;
static int hide_registration;

static int observed_unregister(void) {
    int result = GC_unregister_my_thread();
    assert(result == GC_SUCCESS);
    atomic_fetch_add(&cleanups, 1);
    return result;
}

static int observed_registration(void) {
    return hide_registration ? 0 : GC_thread_is_registered();
}

#define GC_unregister_my_thread observed_unregister
#define GC_thread_is_registered observed_registration
#include "c2v_gc_threads.inc"
#undef GC_thread_is_registered
#undef GC_unregister_my_thread

static void *worker(void *unused) {
    (void)unused;
    assert(!GC_thread_is_registered());
    atomic_fetch_add(&ready, 1);
    while (!atomic_load(&start)) {}
    c2v_gc_register_thread();
    assert(GC_thread_is_registered());
    c2v_gc_register_thread();
    assert(GC_thread_is_registered());
    assert(GC_MALLOC(64) != NULL);
    return NULL;
}

int main(int argc, char **argv) {
    pthread_t threads[8];
    alarm(15);
    if (argc > 1 && strcmp(argv[1], "zero") == 0) {
        /* Allocate our key before GC creates any of its own TLS keys. */
        assert(pthread_once(&c2v_gc_thread_key_once, c2v_gc_make_thread_key) == 0);
        assert(c2v_gc_thread_key_error == 0);
#ifdef __linux__
        assert(c2v_gc_thread_key == 0);
#endif
    }
    GC_INIT();
    c2v_gc_allow_threads();
    assert(GC_thread_is_registered());
    c2v_gc_register_thread();
    if (argc > 1 && strcmp(argv[1], "duplicate") == 0) {
        /* Exercise GC_DUPLICATE without claiming the existing registration. */
        hide_registration = 1;
        c2v_gc_register_thread();
        hide_registration = 0;
        assert(pthread_getspecific(c2v_gc_thread_key) == NULL);
    }
    for (int i = 0; i < 8; ++i) {
        assert(pthread_create(&threads[i], NULL, worker, NULL) == 0);
    }
    while (atomic_load(&ready) != 8) {}
    atomic_store(&start, 1);
    for (int i = 0; i < 8; ++i) {
        assert(pthread_join(threads[i], NULL) == 0);
    }
    assert(atomic_load(&cleanups) == 8);
    assert(pthread_getspecific(c2v_gc_thread_key) == NULL);
    GC_gcollect();
    printf("key_bytes=%zu cleaned=%d\\n", sizeof(pthread_key_t), atomic_load(&cleanups));
    return 0;
}
') or { panic(err) }
	program := os.join_path(dir, 'probe')
	mut args := ['cc', '-std=c11', '-DGC_THREADS', '-DGC_BUILTIN_ATOMIC', '-DCUSTOM_DEFINE_gcboehm',
		'-I' + os.join_path(@VEXEROOT, 'thirdparty', 'libgc', 'include'), source,
		os.join_path(@VEXEROOT, 'thirdparty', 'libgc', 'gc.c'), '-pthread', '-lm', '-o', program]
	$if linux {
		args << '-ldl'
	}
	compiled := os.exec(args)
	assert compiled.exit_code == 0, compiled.output
	for mode in ['concurrent', 'zero', 'duplicate'] {
		result := os.exec([program, mode])
		assert result.exit_code == 0, '${mode}: ${result.output}'
		assert result.output.contains('cleaned=8'), result.output
	}
}
