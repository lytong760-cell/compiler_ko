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

int ko_file_exists(const char *path) {
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
    // Debug: entry
    const char *entry_msg = "ko_exec entered\n";
    write(STDERR_FILENO, entry_msg, strlen(entry_msg));

    if (!cmd || !output || output_size == 0) {
        const char *err_msg = "ko_exec: invalid args\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }

    // Make a copy of cmd to tokenize
    char *cmd_copy = strdup(cmd);
    if (!cmd_copy) {
        const char *err_msg = "ko_exec: strdup failed\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }

    // Tokenize by whitespace (space, tab, newline)
    const char *delim = " \t\n";
    size_t argc = 0;
    char *token = strtok(cmd_copy, delim);
    while (token) {
        argc++;
        token = strtok(NULL, delim);
    }

    if (argc == 0) {
        free(cmd_copy);
        const char *err_msg = "ko_exec: no tokens\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }

    // Allocate argv array
    char **argv = malloc((argc + 1) * sizeof(char *));
    if (!argv) {
        free(cmd_copy);
        const char *err_msg = "ko_exec: malloc argv failed\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }
    // Debug: after malloc argv
    write(STDERR_FILENO, "ko_exec: after malloc argv\n", 27);

    // Reset string and tokenize again to fill argv
    token = strtok(cmd_copy, delim);
    size_t i = 0;
    while (token) {
        argv[i] = token;
        i++;
        token = strtok(NULL, delim);
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
                const char *err_msg = "ko_exec: shell metachar\n";
                write(STDERR_FILENO, err_msg, strlen(err_msg));
                return -1;
            }
        }
    }

    // Debug: after shell metachar check
    write(STDERR_FILENO, "ko_exec: after shell metachar check\n", 34);

    // Create pipe for child's stdout
    int pipefd[2];
    if (pipe(pipefd) == -1) {
        free(cmd_copy);
        free(argv);
        const char *err_msg = "ko_exec: pipe failed\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }

    pid_t pid = fork();
    if (pid == -1) {
        free(cmd_copy);
        free(argv);
        close(pipefd[0]);
        close(pipefd[1]);
        const char *err_msg = "ko_exec: fork failed\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }

    if (pid == 0) {
        // Child process
        close(pipefd[0]); // Close read end
        dup2(pipefd[1], STDOUT_FILENO); // Redirect stdout to pipe
        close(pipefd[1]); // Close the duplicate write end

        // Debug: write to stderr to see if we get here
        const char *msg1 = "Child: about to execvp ";
        write(STDERR_FILENO, msg1, strlen(msg1));
        write(STDERR_FILENO, argv[0], strlen(argv[0]));
        write(STDERR_FILENO, "\n", 1);
        execvp(argv[0], argv);
        // If execvp fails
        const char *msg2 = "Child: execvp failed\n";
        write(STDERR_FILENO, msg2, strlen(msg2));
        _exit(127);
    }

    // Parent process
    write(STDERR_FILENO, "Parent: before close write end\n", 31);
    close(pipefd[1]);
    write(STDERR_FILENO, "Parent: after close write end\n", 30);
    const char *parent_read_msg = "Parent: about to read from pipe\n";
    write(STDERR_FILENO, parent_read_msg, strlen(parent_read_msg));

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
    const char *parent_done_msg = "Parent: finished reading\n";
    write(STDERR_FILENO, parent_done_msg, strlen(parent_done_msg));

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
        const char *err_msg = "ko_exec: waitpid failed\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }

    if (WIFEXITED(status)) {
        int exit_status = WEXITSTATUS(status);
        char exit_msg[32];
        snprintf(exit_msg, sizeof(exit_msg), "ko_exec: child exited with %d\n", exit_status);
        write(STDERR_FILENO, exit_msg, strlen(exit_msg));
        return exit_status;
    } else {
        const char *err_msg = "ko_exec: child terminated by signal\n";
        write(STDERR_FILENO, err_msg, strlen(err_msg));
        return -1;
    }
}

int ko_list_dir(const char *path, char ***entries, size_t *count) {
    (void)path;
    (void)entries;
    (void)count;
    return -1; // Not implemented
}