#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

typedef int (*file_exists_fn)(const char *);
typedef long long (*file_size_fn)(const char *);
typedef void (*seed_fn)(long long);
typedef long long (*int_fn)(void);
typedef double (*float_fn)(void);
typedef int (*exec_fn)(const char *, char *, unsigned long);

static void *must_open(const char *lib) {
    void *h = dlopen(lib, RTLD_NOW);
    if (!h) {
        fprintf(stderr, "LOAD_FAIL %s: %s\n", lib, dlerror());
        exit(3);
    }
    return h;
}

static void *must_sym(void *h, const char *name) {
    dlerror();
    void *s = dlsym(h, name);
    if (!s) {
        fprintf(stderr, "SYMBOL_MISSING %s\n", name);
        exit(4);
    }
    return s;
}

int main(int argc, char **argv) {
    if (argc < 3) {
        fprintf(stderr, "usage: %s <lib> <check>\n", argv[0]);
        return 2;
    }
    const char *lib = argv[1];
    const char *check = argv[2];
    void *h = must_open(lib);

    if (strcmp(check, "file_exists_true") == 0) {
        file_exists_fn f = (file_exists_fn)must_sym(h, "ko_file_exists");
        int r = f("examples/simple.ko");
        printf("value=%d\n", r);
        return r == 1 ? 0 : 1;
    }
    if (strcmp(check, "file_exists_false") == 0) {
        file_exists_fn f = (file_exists_fn)must_sym(h, "ko_file_exists");
        int r = f("definitely-not-here.ko");
        printf("value=%d\n", r);
        return r == 0 ? 0 : 1;
    }
    if (strcmp(check, "file_size") == 0) {
        file_size_fn f = (file_size_fn)must_sym(h, "ko_file_size");
        long long r = f("examples/simple.ko");
        printf("value=%lld\n", r);
        return r > 0 ? 0 : 1;
    }
    if (strcmp(check, "random_reproducible") == 0) {
        seed_fn sd = (seed_fn)must_sym(h, "ko_random_seed");
        int_fn gi = (int_fn)must_sym(h, "ko_random_int");
        sd(4242);
        long long a = gi(), b = gi();
        sd(4242);
        long long c = gi(), d = gi();
        printf("first=%lld second=%lld\n", a, b);
        return (a == c && b == d) ? 0 : 1;
    }
    if (strcmp(check, "random_differs") == 0) {
        seed_fn sd = (seed_fn)must_sym(h, "ko_random_seed");
        int_fn gi = (int_fn)must_sym(h, "ko_random_int");
        sd(1);
        long long a = gi();
        sd(2);
        long long b = gi();
        printf("first=%lld second=%lld\n", a, b);
        return a != b ? 0 : 1;
    }
    if (strcmp(check, "random_float_range") == 0) {
        seed_fn sd = (seed_fn)must_sym(h, "ko_random_seed");
        float_fn rf = (float_fn)must_sym(h, "ko_random_float");
        sd(99);
        double worst = 0.0;
        int bad = 0;
        for (int i = 0; i < 20000; i++) {
            double v = rf();
            if (v < 0.0 || v >= 1.0) bad++;
            if (v > worst) worst = v;
        }
        printf("max=%.17g out_of_range=%d\n", worst, bad);
        return bad == 0 ? 0 : 1;
    }
    if (strcmp(check, "exec_rejects_injection") == 0) {
        exec_fn ex = (exec_fn)must_sym(h, "ko_exec");
        char buf[256];
        int r = ex("; touch /tmp/ko_should_not_exist #", buf, sizeof buf);
        printf("rc=%d\n", r);
        return r < 0 ? 0 : 1;
    }
    if (strcmp(check, "exec_simple") == 0) {
        exec_fn ex = (exec_fn)must_sym(h, "ko_exec");
        char buf[256];
        int r = ex("echo hello", buf, sizeof buf);
        printf("rc=%d\n", r);
        return r >= 0 ? 0 : 1;
    }
    if (strcmp(check, "symbol") == 0) {
        (void)must_sym(h, argc > 3 ? argv[3] : "ko_loop_engine_create");
        return 0;
    }

    fprintf(stderr, "unknown check: %s\n", check);
    return 2;
}