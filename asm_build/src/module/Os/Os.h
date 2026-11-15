#ifndef KO_OS_H
#define KO_OS_H

#include <stdint.h>
#include <stddef.h>

const char* ko_get_env(const char *name);
int ko_set_env(const char *name, const char *value);
int ko_list_dir(const char *path, char ***entries, size_t *count);
int ko_file_exists(const char *path);
int64_t ko_file_size(const char *path);
int ko_exec(const char *cmd, char *output, size_t output_size);
int ko_exit(int code);
const char* ko_get_cwd(void);
int ko_set_cwd(const char *path);
#endif