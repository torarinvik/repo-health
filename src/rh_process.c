#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;

/* Decode a bounded NUL-delimited vector produced by the Elisa caller. */
static char **rh_process_vector(const char *flat, size_t max_items) {
    if (flat == NULL) return NULL;
    size_t count = 0;
    size_t total_bytes = 0;
    const char *cursor = flat;
    while (*cursor != '\0') {
        if (++count > max_items) return NULL;
        size_t length = strnlen(cursor, 1024 * 1024 + 1);
        if (length > 1024 * 1024) return NULL;
        if (length + 1 > 1024 * 1024 - total_bytes) return NULL;
        total_bytes += length + 1;
        cursor += length + 1;
    }
    char **items = calloc(count + 1, sizeof(*items));
    if (items == NULL) return NULL;
    cursor = flat;
    for (size_t index = 0; index < count; ++index) {
        items[index] = (char *)cursor;
        cursor += strlen(cursor) + 1;
    }
    return items;
}

static int64_t rh_process_millis(void) {
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return -1;
    return (int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000;
}

static const char *rh_process_resolve(const char *executable, char **envp,
                                      char *resolved, size_t resolved_size) {
    if (executable[0] == '/') return executable;
    if (strchr(executable, '/') != NULL || executable[0] == '\0') return NULL;
    const char *path = NULL;
    for (size_t index = 0; envp[index] != NULL; ++index) {
        if (strncmp(envp[index], "PATH=", 5) == 0) {
            path = envp[index] + 5;
            break;
        }
    }
    if (path == NULL) return NULL;
    while (*path != '\0') {
        const char *end = strchr(path, ':');
        size_t directory_size = end == NULL ? strlen(path) : (size_t)(end - path);
        size_t executable_size = strlen(executable);
        if (directory_size + 1 + executable_size + 1 <= resolved_size) {
            memcpy(resolved, path, directory_size);
            resolved[directory_size] = '/';
            memcpy(resolved + directory_size + 1, executable, executable_size + 1);
            if (access(resolved, X_OK) == 0) return resolved;
        }
        if (end == NULL) break;
        path = end + 1;
    }
    return NULL;
}

/*
 * Run one absolute executable path with explicit argv/envp and optional file
 * redirection. Returns child exit status, 124 on timeout, or a negative errno
 * on setup/wait failure. No shell is involved.
 */
int rh_process_run(const char *executable, const char *argv_flat,
                   const char *env_flat, const char *input_data,
                   size_t input_length, const char *stdout_path,
                   const char *stderr_path, int timeout_ms) {
    if (executable == NULL || argv_flat == NULL ||
        env_flat == NULL || input_length > 65536 ||
        (input_length > 0 && input_data == NULL) ||
        timeout_ms < 1 || timeout_ms > 600000)
        return -EINVAL;

    char **argv = rh_process_vector(argv_flat, 256);
    char **envp = rh_process_vector(env_flat, 128);
    if (argv == NULL || envp == NULL || argv[0] == NULL) {
        free(argv);
        free(envp);
        return -EINVAL;
    }
    char resolved_storage[PATH_MAX];
    const char *resolved = rh_process_resolve(executable, envp, resolved_storage,
                                             sizeof(resolved_storage));
    if (resolved == NULL) {
        free(argv);
        free(envp);
        return -ENOENT;
    }

    int input_pipe[2] = {-1, -1};
    if (input_length > 0 && pipe(input_pipe) != 0) {
        free(argv);
        free(envp);
        return -errno;
    }

    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    int actions_ready = error == 0;
    if (error == 0 && input_length > 0)
        error = posix_spawn_file_actions_adddup2(&actions, input_pipe[0], STDIN_FILENO);
    else if (error == 0)
        error = posix_spawn_file_actions_addopen(&actions, STDIN_FILENO, "/dev/null", O_RDONLY, 0);
    if (error == 0 && input_length > 0)
        error = posix_spawn_file_actions_addclose(&actions, input_pipe[0]);
    if (error == 0 && input_length > 0)
        error = posix_spawn_file_actions_addclose(&actions, input_pipe[1]);
    if (error == 0 && stdout_path != NULL)
        error = posix_spawn_file_actions_addopen(
            &actions, STDOUT_FILENO, stdout_path,
            O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (error == 0 && stderr_path != NULL)
        error = posix_spawn_file_actions_addopen(
            &actions, STDERR_FILENO, stderr_path,
            O_WRONLY | O_CREAT | O_TRUNC, 0600);

    pid_t child = -1;
    if (error == 0)
        error = posix_spawn(&child, resolved, &actions, NULL, argv, envp);
    if (actions_ready) posix_spawn_file_actions_destroy(&actions);
    free(argv);
    free(envp);
    if (input_pipe[0] >= 0) close(input_pipe[0]);
    if (error == 0 && input_length > 0) {
        sigset_t pipe_signal;
        sigset_t previous_mask;
        sigemptyset(&pipe_signal);
        sigaddset(&pipe_signal, SIGPIPE);
        int mask_error = pthread_sigmask(SIG_BLOCK, &pipe_signal, &previous_mask);
        if (mask_error != 0) {
            (void)kill(child, SIGKILL);
            (void)waitpid(child, NULL, 0);
            close(input_pipe[1]);
            return -mask_error;
        }
        sigset_t pending;
        int pipe_was_pending = sigpending(&pending) == 0 &&
                               sigismember(&pending, SIGPIPE) == 1;
        size_t written = 0;
        int write_failed = 0;
        while (written < input_length) {
            ssize_t count = write(input_pipe[1], input_data + written,
                                  input_length - written);
            if (count > 0) {
                written += (size_t)count;
            } else if (count < 0 && errno == EINTR) {
                continue;
            } else {
                (void)kill(child, SIGKILL);
                (void)waitpid(child, NULL, 0);
                write_failed = 1;
                break;
            }
        }
        if (!pipe_was_pending) {
            sigset_t pending_after_write;
            if (sigpending(&pending_after_write) == 0 &&
                sigismember(&pending_after_write, SIGPIPE) == 1) {
                int received_signal = 0;
                while (sigwait(&pipe_signal, &received_signal) == EINTR) {}
            }
        }
        (void)pthread_sigmask(SIG_SETMASK, &previous_mask, NULL);
        if (write_failed) {
            close(input_pipe[1]);
            return -EIO;
        }
    }
    if (input_pipe[1] >= 0) close(input_pipe[1]);
    if (error != 0) return -error;

    const int64_t started = rh_process_millis();
    if (started < 0) {
        (void)kill(child, SIGKILL);
        (void)waitpid(child, NULL, 0);
        return -EIO;
    }
    for (;;) {
        int status = 0;
        pid_t waited = waitpid(child, &status, WNOHANG);
        if (waited == child) {
            if (WIFEXITED(status)) return WEXITSTATUS(status);
            if (WIFSIGNALED(status)) return 128 + WTERMSIG(status);
            return -ECHILD;
        }
        if (waited < 0 && errno != EINTR) return -errno;
        int64_t now = rh_process_millis();
        if (now < 0) {
            (void)kill(child, SIGKILL);
            (void)waitpid(child, NULL, 0);
            return -EIO;
        }
        if (now - started >= timeout_ms) {
            (void)kill(child, SIGKILL);
            while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
            return 124;
        }
        struct timespec pause = {.tv_sec = 0, .tv_nsec = 10000000};
        while (nanosleep(&pause, &pause) < 0 && errno == EINTR) {}
    }
}
