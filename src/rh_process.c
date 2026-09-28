#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
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

/*
 * Run one absolute executable path with explicit argv/envp and optional file
 * redirection. Returns child exit status, 124 on timeout, or a negative errno
 * on setup/wait failure. No shell is involved.
 */
int rh_process_run(const char *executable, const char *argv_flat,
                   const char *env_flat, const char *stdout_path,
                   const char *stderr_path, int timeout_ms) {
    if (executable == NULL || executable[0] != '/' || argv_flat == NULL ||
        env_flat == NULL || timeout_ms < 1 || timeout_ms > 600000)
        return -EINVAL;

    char **argv = rh_process_vector(argv_flat, 256);
    char **envp = rh_process_vector(env_flat, 128);
    if (argv == NULL || envp == NULL || argv[0] == NULL) {
        free(argv);
        free(envp);
        return -EINVAL;
    }

    posix_spawn_file_actions_t actions;
    int error = posix_spawn_file_actions_init(&actions);
    int actions_ready = error == 0;
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
        error = posix_spawn(&child, executable, &actions, NULL, argv, envp);
    if (actions_ready) posix_spawn_file_actions_destroy(&actions);
    free(argv);
    free(envp);
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
