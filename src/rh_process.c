#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
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

enum {
    RH_PROCESS_EXIT = 0,
    RH_PROCESS_TIMEOUT = 1,
    RH_PROCESS_OUTPUT_LIMIT = 2,
    RH_PROCESS_SETUP_ERROR = 3,
    RH_PROCESS_SIGNAL = 4,
    RH_PROCESS_IO_ERROR = 5
};

static int rh_process_result(int *code_out, int kind, int code) {
    if (code_out != NULL) *code_out = code;
    return kind;
}

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

static int rh_process_write_all(int descriptor, const char *bytes, size_t length) {
    size_t written = 0;
    while (written < length) {
        ssize_t count = write(descriptor, bytes + written, length - written);
        if (count > 0) written += (size_t)count;
        else if (count < 0 && errno == EINTR) continue;
        else return -1;
    }
    return 0;
}

static void rh_process_close(int *descriptor) {
    if (*descriptor >= 0) close(*descriptor);
    *descriptor = -1;
}

static int rh_process_nonblocking(int descriptor) {
    int flags = fcntl(descriptor, F_GETFL);
    return flags < 0 || fcntl(descriptor, F_SETFL, flags | O_NONBLOCK) < 0 ? -1 : 0;
}

/*
 * Run one explicit executable with argv/envp, optional stdin, separately
 * captured output streams, an aggregate output cap, and a wall-clock deadline.
 * Returns a result kind and writes its associated code to code_out. No shell
 * is involved; timeout/overflow terminate the spawned process group.
 */
int rh_process_run(const char *executable, const char *argv_flat,
                   const char *env_flat, const char *input_data,
                   size_t input_length, const char *stdout_path,
                   const char *stderr_path, size_t max_output_bytes,
                   int timeout_ms, int *code_out) {
    if (code_out == NULL) return RH_PROCESS_SETUP_ERROR;
    *code_out = 0;
    if (executable == NULL || argv_flat == NULL ||
        env_flat == NULL || input_length > 65536 ||
        (input_length > 0 && input_data == NULL) ||
        max_output_bytes == 0 || max_output_bytes > INT_MAX ||
        timeout_ms < 1 || timeout_ms > 600000)
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, EINVAL);

    char **argv = rh_process_vector(argv_flat, 256);
    char **envp = rh_process_vector(env_flat, 128);
    if (argv == NULL || envp == NULL || argv[0] == NULL) {
        free(argv);
        free(envp);
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, EINVAL);
    }
    char resolved_storage[PATH_MAX];
    const char *resolved = rh_process_resolve(executable, envp, resolved_storage,
                                             sizeof(resolved_storage));
    if (resolved == NULL) {
        free(argv);
        free(envp);
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, ENOENT);
    }

    int input_pipe[2] = {-1, -1};
    int stdout_pipe[2] = {-1, -1};
    int stderr_pipe[2] = {-1, -1};
    int stdout_file = -1;
    int stderr_file = -1;
    if (input_length > 0 && pipe(input_pipe) != 0) {
        free(argv);
        free(envp);
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, errno);
    }
    if (pipe(stdout_pipe) != 0 || pipe(stderr_pipe) != 0) {
        int saved_error = errno;
        rh_process_close(&input_pipe[0]); rh_process_close(&input_pipe[1]);
        rh_process_close(&stdout_pipe[0]); rh_process_close(&stdout_pipe[1]);
        rh_process_close(&stderr_pipe[0]); rh_process_close(&stderr_pipe[1]);
        free(argv); free(envp);
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, saved_error);
    }
    if (stdout_path != NULL) stdout_file = open(stdout_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (stderr_path != NULL) stderr_file = open(stderr_path, O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if ((stdout_path != NULL && stdout_file < 0) || (stderr_path != NULL && stderr_file < 0) ||
        rh_process_nonblocking(stdout_pipe[0]) != 0 || rh_process_nonblocking(stderr_pipe[0]) != 0 ||
        (input_length > 0 && rh_process_nonblocking(input_pipe[1]) != 0)) {
        int saved_error = errno == 0 ? EIO : errno;
        rh_process_close(&input_pipe[0]); rh_process_close(&input_pipe[1]);
        rh_process_close(&stdout_pipe[0]); rh_process_close(&stdout_pipe[1]);
        rh_process_close(&stderr_pipe[0]); rh_process_close(&stderr_pipe[1]);
        rh_process_close(&stdout_file); rh_process_close(&stderr_file);
        free(argv); free(envp);
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, saved_error);
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
    if (error == 0) error = posix_spawn_file_actions_adddup2(&actions, stdout_pipe[1], STDOUT_FILENO);
    if (error == 0) error = posix_spawn_file_actions_adddup2(&actions, stderr_pipe[1], STDERR_FILENO);
    if (error == 0) error = posix_spawn_file_actions_addclose(&actions, stdout_pipe[0]);
    if (error == 0) error = posix_spawn_file_actions_addclose(&actions, stdout_pipe[1]);
    if (error == 0) error = posix_spawn_file_actions_addclose(&actions, stderr_pipe[0]);
    if (error == 0) error = posix_spawn_file_actions_addclose(&actions, stderr_pipe[1]);

    pid_t child = -1;
    posix_spawnattr_t attributes;
    int attributes_ready = 0;
    if (error == 0) {
        error = posix_spawnattr_init(&attributes);
        attributes_ready = error == 0;
    }
    if (error == 0) error = posix_spawnattr_setpgroup(&attributes, 0);
    if (error == 0) error = posix_spawnattr_setflags(&attributes, POSIX_SPAWN_SETPGROUP);
    int64_t started = rh_process_millis();
    if (error == 0 && started < 0) error = EIO;
    if (error == 0) error = posix_spawn(&child, resolved, &actions, &attributes, argv, envp);
    if (attributes_ready) posix_spawnattr_destroy(&attributes);
    if (actions_ready) posix_spawn_file_actions_destroy(&actions);
    free(argv);
    free(envp);
    rh_process_close(&input_pipe[0]);
    rh_process_close(&stdout_pipe[1]); rh_process_close(&stderr_pipe[1]);
    if (error != 0) {
        rh_process_close(&input_pipe[1]); rh_process_close(&stdout_pipe[0]);
        rh_process_close(&stderr_pipe[0]); rh_process_close(&stdout_file); rh_process_close(&stderr_file);
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, error);
    }

    sigset_t pipe_signal, previous_mask, pending;
    sigemptyset(&pipe_signal); sigaddset(&pipe_signal, SIGPIPE);
    int mask_error = pthread_sigmask(SIG_BLOCK, &pipe_signal, &previous_mask);
    if (mask_error != 0) {
        (void)kill(-child, SIGKILL); (void)waitpid(child, NULL, 0);
        rh_process_close(&input_pipe[1]); rh_process_close(&stdout_pipe[0]);
        rh_process_close(&stderr_pipe[0]); rh_process_close(&stdout_file); rh_process_close(&stderr_file);
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, mask_error);
    }
    int pipe_was_pending = sigpending(&pending) == 0 && sigismember(&pending, SIGPIPE) == 1;
    int stdout_open = 1, stderr_open = 1, child_reaped = 0, status = 0;
    size_t input_written = 0, output_bytes = 0;
    int result_kind = RH_PROCESS_EXIT;
    int result_code = 0;
    while (stdout_open || stderr_open || !child_reaped) {
        int64_t now = rh_process_millis();
        if (now < 0) { result_kind = RH_PROCESS_IO_ERROR; result_code = EIO; (void)kill(-child, SIGKILL); break; }
        if (now - started >= timeout_ms) { result_kind = RH_PROCESS_TIMEOUT; result_code = timeout_ms; (void)kill(-child, SIGKILL); break; }

        struct pollfd fds[3];
        nfds_t count = 0;
        int input_slot = -1, stdout_slot = -1, stderr_slot = -1;
        if (input_pipe[1] >= 0) { input_slot = (int)count; fds[count++] = (struct pollfd){input_pipe[1], POLLOUT, 0}; }
        if (stdout_open) { stdout_slot = (int)count; fds[count++] = (struct pollfd){stdout_pipe[0], POLLIN | POLLHUP, 0}; }
        if (stderr_open) { stderr_slot = (int)count; fds[count++] = (struct pollfd){stderr_pipe[0], POLLIN | POLLHUP, 0}; }
        int remaining = timeout_ms - (int)(now - started);
        int wait_ms = remaining < 10 ? remaining : 10;
        int polled = poll(fds, count, wait_ms);
        if (polled < 0 && errno != EINTR) { result_kind = RH_PROCESS_IO_ERROR; result_code = errno; (void)kill(-child, SIGKILL); break; }

        if (input_slot >= 0 && polled > 0 && (fds[input_slot].revents & (POLLOUT | POLLERR | POLLHUP))) {
            ssize_t written = write(input_pipe[1], input_data + input_written, input_length - input_written);
            if (written > 0) input_written += (size_t)written;
            else if (written < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) {
                result_kind = RH_PROCESS_IO_ERROR; result_code = EIO; (void)kill(-child, SIGKILL); break;
            }
            if (input_written == input_length) rh_process_close(&input_pipe[1]);
        }

        int *read_fds[2] = {&stdout_pipe[0], &stderr_pipe[0]};
        int output_fds[2] = {stdout_file, stderr_file};
        int slots[2] = {stdout_slot, stderr_slot};
        int *open_flags[2] = {&stdout_open, &stderr_open};
        for (int stream = 0; stream < 2 && polled > 0; ++stream) {
            if (slots[stream] < 0 || !(fds[slots[stream]].revents & (POLLIN | POLLHUP | POLLERR))) continue;
            char buffer[16384];
            for (;;) {
                ssize_t bytes = read(*read_fds[stream], buffer, sizeof(buffer));
                if (bytes > 0) {
                    if ((size_t)bytes > max_output_bytes - output_bytes) {
                        result_kind = RH_PROCESS_OUTPUT_LIMIT; result_code = (int)max_output_bytes; (void)kill(-child, SIGKILL); goto finished;
                    }
                    output_bytes += (size_t)bytes;
                    if (output_fds[stream] >= 0 && rh_process_write_all(output_fds[stream], buffer, (size_t)bytes) != 0) {
                        result_kind = RH_PROCESS_IO_ERROR; result_code = EIO; (void)kill(-child, SIGKILL); goto finished;
                    }
                } else if (bytes == 0) {
                    *open_flags[stream] = 0; rh_process_close(read_fds[stream]); break;
                } else if (errno == EINTR) continue;
                else if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                else { result_kind = RH_PROCESS_IO_ERROR; result_code = errno; (void)kill(-child, SIGKILL); goto finished; }
            }
        }
        if (!child_reaped) {
            pid_t waited = waitpid(child, &status, WNOHANG);
            if (waited == child) child_reaped = 1;
            else if (waited < 0 && errno != EINTR) { result_kind = RH_PROCESS_IO_ERROR; result_code = errno; (void)kill(-child, SIGKILL); break; }
        }
    }
finished:
    rh_process_close(&input_pipe[1]);
    if (!child_reaped) while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
    if (!pipe_was_pending && sigpending(&pending) == 0 && sigismember(&pending, SIGPIPE) == 1) {
        int received = 0; while (sigwait(&pipe_signal, &received) == EINTR) {}
    }
    (void)pthread_sigmask(SIG_SETMASK, &previous_mask, NULL);
    rh_process_close(&stdout_pipe[0]); rh_process_close(&stderr_pipe[0]);
    rh_process_close(&stdout_file); rh_process_close(&stderr_file);
    if (result_kind == RH_PROCESS_EXIT && WIFEXITED(status)) result_code = WEXITSTATUS(status);
    else if (result_kind == RH_PROCESS_EXIT && WIFSIGNALED(status)) {
        result_kind = RH_PROCESS_SIGNAL;
        result_code = WTERMSIG(status);
    } else if (result_kind == RH_PROCESS_EXIT) {
        result_kind = RH_PROCESS_IO_ERROR;
        result_code = ECHILD;
    }
    return rh_process_result(code_out, result_kind, result_code);
}
