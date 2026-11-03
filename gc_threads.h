#ifndef C2V_GC_THREADS_H
#define C2V_GC_THREADS_H

#if defined(_VGCBOEHM) || defined(CUSTOM_DEFINE_gcboehm)
#include <stdlib.h>
#include <gc/gc.h>

#ifdef GC_THREADS
#ifndef _WIN32
#include <pthread.h>

// The native key type and once initializer are platform-owned. Zero is a
// valid pthread key, and callbacks can first arrive on several threads.
static pthread_key_t c2v_gc_thread_key;
static pthread_once_t c2v_gc_thread_key_once = PTHREAD_ONCE_INIT;
static int c2v_gc_thread_key_error;

static void c2v_gc_thread_exit(void *value) {
    (void)value;
    GC_unregister_my_thread();
}

static void c2v_gc_make_thread_key(void) {
    c2v_gc_thread_key_error = pthread_key_create(&c2v_gc_thread_key, c2v_gc_thread_exit);
}
#endif

static void c2v_gc_register_thread(void) {
    struct GC_stack_base base;
    int registered;
    if (GC_thread_is_registered()) {
        return;
    }
#ifndef _WIN32
    if (pthread_once(&c2v_gc_thread_key_once, c2v_gc_make_thread_key) != 0
        || c2v_gc_thread_key_error != 0) {
        abort();
    }
#endif
    if (GC_get_stack_base(&base) != GC_SUCCESS) {
        abort();
    }
    registered = GC_register_my_thread(&base);
    if (registered == GC_DUPLICATE) {
        // Another owner registered this thread; its cleanup must retain it.
        return;
    }
    if (registered != GC_SUCCESS) {
        abort();
    }
#ifndef _WIN32
    if (pthread_setspecific(c2v_gc_thread_key, (void *)1) != 0) {
        GC_unregister_my_thread();
        abort();
    }
#endif
}

static void c2v_gc_allow_threads(void) {
    GC_allow_register_threads();
}
#else
static void c2v_gc_register_thread(void) {}
static void c2v_gc_allow_threads(void) {}
#endif
#endif

#endif
