#include "Os.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>

const char* ko_get_env(const char *name) {
    return getenv(name);
}

int ko_set_env(const char *name, const char *value) {
    return setenv(name, value, 1);
}

int ko_file_exists(const char *path) {
    struct stat st;
    return stat(path, &st) == 0;
}

int64_t ko_file_size(const char *path) {
    struct stat st;
    if (stat(path, &st) != 0) return -1;
    return (int64_t)st.st_size;
}

const char* ko_get_cwd(void) {
    static char buf[1024];
    if (getcwd(buf, sizeof(buf)) != NULL) {
        return buf;
    }
    return NULL;
}

int ko_set_cwd(const char *path) {
    return chdir(path) == 0 ? 0 : -1;
}

int ko_exit(int code) {
    exit(code);
    return 0;
}

int ko_exec(const char *cmd, char *output, size_t output_size) {
    FILE *pipe = popen(cmd, "r");
    if (!pipe) return -1;
    size_t total = 0;
    size_t n;
    while (total < output_size - 1 && (n = fread(output + total, 1, output_size - total - 1, pipe)) > 0) {
        total += n;
    }
    output[total] = '\0';
    pclose(pipe);
    return (int)total;
}

int ko_list_dir(const char *path, char ***entries, size_t *count) {
    return 0;
}