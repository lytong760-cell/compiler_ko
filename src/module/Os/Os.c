#include "Os.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/wait.h>
#include <signal.h>
#include <sys/stat.h>
#include <time.h>

const char* ko_get_env(const char *name) {
    return getenv(name);
}

int ko_set_env(const char *name, const char *value) {
    return setenv(name, value, 1);
}

int ko_file_exists_X(const char *path) {
    if (!path) return 0;
    struct stat st;
    return stat(path, &st) == 0;
}

int64_t ko_file_size(const char *path) {
    if (!path) return -1;
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
    if (!path) return -1;
    return chdir(path) == 0 ? 0 : -1;
}

int ko_exit(int code) {
    exit(code);
    return 0;
}

int ko_exec(const char *cmd, char *output, size_t output_size) {
    if (!cmd || !output || output_size == 0) {
        return -1;
    }

    // Make a copy of cmd to tokenize
    char *cmd_copy = strdup(cmd);
    if (!cmd_copy) {
        return -1;
    }

    // Tokenize by whitespace (space, tab, newline) using strtok_r for safety
    const char *delim = " \t\n";
    char *saveptr = NULL;
    char *token = strtok_r(cmd_copy, delim, &saveptr);
    char **argv = NULL;
    size_t argc = 0;
    size_t capacity = 0;

    while (token) {
        if (argc >= capacity) {
            capacity = capacity ? capacity * 2 : 4;
            char **newargv = realloc(argv, (capacity + 1) * sizeof(char *)); // +1 for NULL terminator
            if (!newargv) {
                free(cmd_copy);
                free(argv);
                return -1;
            }
            argv = newargv;
        }
        argv[argc] = token;
        argc++;
        token = strtok_r(NULL, delim, &saveptr);
    }

    if (argc == 0) {
        free(cmd_copy);
        free(argv);
        return -1;
    }

    // Ensure we have space for the NULL terminator
    if (argc >= capacity) {
        capacity = argc + 1;
        char **newargv = realloc(argv, (capacity + 1) * sizeof(char *));
        if (!newargv) {
            free(cmd_copy);
            free(argv);
            return -1;
        }
        argv = newargv;
    }
    argv[argc] = NULL;

    // Check for shell metacharacters in each token
    const char *shell_metachars = "&;|$`><!";
    for (size_t j = 0; j < argc; j++) {
        const char *arg = argv[j];
        for (; *arg; arg++) {
            if (strchr(shell_metachars, *arg)) {
                free(cmd_copy);
                free(argv);
                return -1;
            }
        }
    }

    // Create pipe for child's stdout
    int pipefd[2];
    if (pipe(pipefd) == -1) {
        free(cmd_copy);
        free(argv);
        return -1;
    }

    pid_t pid = fork();
    if (pid == -1) {
        free(cmd_copy);
        free(argv);
        close(pipefd[0]);
        close(pipefd[1]);
        return -1;
    }

    if (pid == 0) {
        // Child process
        close(pipefd[0]); // Close read end
        dup2(pipefd[1], STDOUT_FILENO); // Redirect stdout to pipe
        close(pipefd[1]); // Close the duplicate write end

        execvp(argv[0], argv);
        // If execvp fails
        _exit(127);
    }

    // Parent process
    close(pipefd[1]); // Close write end

    // Read from pipe
    ssize_t total = 0;
    while ((size_t)total < output_size - 1) {
        ssize_t n = read(pipefd[0], output + total, output_size - total - 1);
        if (n <= 0) {
            break;
        }
        total += n;
    }
    output[total] = '\0';
    close(pipefd[0]);

    // Wait for child with timeout (5 seconds)
    int status;
    pid_t w;
    time_t start = time(NULL);
    do {
        w = waitpid(pid, &status, WNOHANG);
        if (w == 0) {
            // Child still running
            if (time(NULL) - start >= 5) {
                kill(pid, SIGKILL);
                w = waitpid(pid, &status, 0); // Wait for it to die
                break;
            }
            usleep(100000); // 100ms
        }
    } while (w == 0);

    free(cmd_copy);
    free(argv);

    if (w == -1) {
        return -1;
    }

    if (WIFEXITED(status)) {
        return WEXITSTATUS(status);
    } else {
        return -1;
    }
}

int ko_list_dir(const char *path, char ***entries, size_t *count) {
    (void)path;
    (void)entries;
    (void)count;
    return -1; // Not implemented
}