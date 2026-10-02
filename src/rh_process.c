#define _DARWIN_C_SOURCE
#define _POSIX_C_SOURCE 200809L

#include <errno.h>
#include <dirent.h>
#include <fcntl.h>
#include <limits.h>
#include <poll.h>
#include <pthread.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <sys/wait.h>
#include <sys/resource.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/socket.h>
#include <libproc.h>
#include <sys/proc_info.h>
#elif defined(__linux__)
#include <stdio.h>
#else
#error "rh_process requires Darwin or Linux process-group resource accounting"
#endif

extern char **environ;

enum {
    RH_PROCESS_EXIT = 0,
    RH_PROCESS_TIMEOUT = 1,
    RH_PROCESS_OUTPUT_LIMIT = 2,
    RH_PROCESS_SETUP_ERROR = 3,
    RH_PROCESS_SIGNAL = 4,
    RH_PROCESS_IO_ERROR = 5,
    RH_PROCESS_CAPACITY_LIMIT = 6,
    RH_PROCESS_RESOURCE_LIMIT = 7,
    RH_PROCESS_MAX_GROUP_PROCESSES = 64,
    RH_PROCESS_MAX_GROUP_MEMORY_MIB = 1024,
    RH_PROCESS_RESOURCE_SAMPLE_MS = 50,
    RH_PROCESS_MAX_ACTIVE_GROUPS = 32
};

#define RH_PROCESS_MAX_GROUP_MEMORY_BYTES \
    ((uint64_t)RH_PROCESS_MAX_GROUP_MEMORY_MIB * 1024 * 1024)

static pthread_mutex_t rh_process_capacity_mutex = PTHREAD_MUTEX_INITIALIZER;
static size_t rh_process_active_groups = 0;

typedef struct {
    int64_t elapsed_ms;
    size_t stdout_bytes;
    size_t stderr_bytes;
    size_t peak_group_processes;
    uint64_t peak_group_memory_bytes;
} rh_process_metrics;

static void rh_process_metrics_reset(rh_process_metrics *metrics) {
    if (metrics == NULL) return;
    metrics->elapsed_ms = -1;
    metrics->stdout_bytes = 0;
    metrics->stderr_bytes = 0;
    metrics->peak_group_processes = 0;
    metrics->peak_group_memory_bytes = 0;
}

static void rh_process_metrics_publish(const rh_process_metrics *metrics,
                                       int64_t *elapsed_ms_out,
                                       size_t *stdout_bytes_out,
                                       size_t *stderr_bytes_out,
                                       size_t *peak_group_processes_out,
                                       uint64_t *peak_group_memory_bytes_out) {
    if (metrics == NULL) return;
    if (elapsed_ms_out != NULL) *elapsed_ms_out = metrics->elapsed_ms;
    if (stdout_bytes_out != NULL) *stdout_bytes_out = metrics->stdout_bytes;
    if (stderr_bytes_out != NULL) *stderr_bytes_out = metrics->stderr_bytes;
    if (peak_group_processes_out != NULL) *peak_group_processes_out = metrics->peak_group_processes;
    if (peak_group_memory_bytes_out != NULL) *peak_group_memory_bytes_out = metrics->peak_group_memory_bytes;
}

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

typedef struct {
    pid_t pid;
    pid_t parent;
    uint64_t start_time;
    int descendant;
} rh_process_identity;

static int rh_process_identity_compare(const void *left, const void *right) {
    const rh_process_identity *a = left;
    const rh_process_identity *b = right;
    return (a->pid > b->pid) - (a->pid < b->pid);
}

static rh_process_identity *rh_process_identity_find(rh_process_identity *items,
                                                      size_t count, pid_t pid) {
    size_t low = 0;
    size_t high = count;
    while (low < high) {
        size_t middle = low + (high - low) / 2;
        if (items[middle].pid < pid) low = middle + 1;
        else high = middle;
    }
    return low < count && items[low].pid == pid ? &items[low] : NULL;
}

#if defined(__APPLE__)
static int rh_process_read_identity(pid_t pid, rh_process_identity *identity) {
    struct proc_bsdinfo info;
    int bytes = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, sizeof(info));
    if (bytes != sizeof(info)) return bytes == 0 ? ESRCH : EIO;
    identity->pid = pid;
    identity->parent = (pid_t)info.pbi_ppid;
    identity->start_time = (uint64_t)info.pbi_start_tvsec * 1000000 +
                           (uint64_t)info.pbi_start_tvusec;
    return 0;
}

static int rh_process_snapshot(rh_process_identity **items_out,
                               size_t *count_out) {
    enum { MAX_SYSTEM_PROCESSES = 65536 };
    pid_t *pids = malloc((size_t)MAX_SYSTEM_PROCESSES * sizeof(*pids));
    if (pids == NULL) return ENOMEM;
    int bytes = proc_listpids(PROC_ALL_PIDS, 0, pids,
                              MAX_SYSTEM_PROCESSES * (int)sizeof(*pids));
    if (bytes < 0) { int error = errno == 0 ? EIO : errno; free(pids); return error; }
    if (bytes >= MAX_SYSTEM_PROCESSES * (int)sizeof(*pids) ||
        bytes % (int)sizeof(*pids) != 0) { free(pids); return E2BIG; }
    size_t capacity = (size_t)bytes / sizeof(*pids);
    rh_process_identity *items = calloc(capacity == 0 ? 1 : capacity, sizeof(*items));
    if (items == NULL) { free(pids); return ENOMEM; }
    size_t count = 0;
    for (size_t index = 0; index < capacity; ++index) {
        if (pids[index] <= 0) continue;
        rh_process_identity identity = {0};
        if (rh_process_read_identity(pids[index], &identity) != 0) continue;
        items[count++] = identity;
    }
    free(pids);
    qsort(items, count, sizeof(*items), rh_process_identity_compare);
    *items_out = items;
    *count_out = count;
    return 0;
}
#elif defined(__linux__)
static int rh_process_read_identity(pid_t pid, rh_process_identity *identity) {
    char path[64];
    int length = snprintf(path, sizeof(path), "/proc/%ld/stat", (long)pid);
    if (length < 0 || (size_t)length >= sizeof(path)) return EIO;
    FILE *file = fopen(path, "r");
    if (file == NULL) return errno == 0 ? EIO : errno;
    char line[4096];
    if (fgets(line, sizeof(line), file) == NULL) { fclose(file); return EIO; }
    fclose(file);
    char *command_end = strrchr(line, ')');
    if (command_end == NULL || command_end[1] != ' ') return EIO;
    char *cursor = command_end + 2;
    if (*cursor == '\0') return EIO;
    cursor += 1;
    char *end = NULL;
    long long parent = strtoll(cursor, &end, 10);
    if (end == cursor || parent < 0 || parent > INT_MAX) return EIO;
    long long start_time = 0;
    for (int field = 5; field <= 22; ++field) {
        cursor = end;
        long long value = strtoll(cursor, &end, 10);
        if (end == cursor) return EIO;
        if (field == 22) start_time = value;
    }
    if (start_time < 0) return EIO;
    identity->pid = pid;
    identity->parent = (pid_t)parent;
    identity->start_time = (uint64_t)start_time;
    return 0;
}

static int rh_process_snapshot(rh_process_identity **items_out,
                               size_t *count_out) {
    enum { MAX_SYSTEM_PROCESSES = 65536 };
    DIR *directory = opendir("/proc");
    if (directory == NULL) return errno == 0 ? EIO : errno;
    size_t capacity = 256;
    size_t count = 0;
    rh_process_identity *items = malloc(capacity * sizeof(*items));
    if (items == NULL) { closedir(directory); return ENOMEM; }
    struct dirent *entry;
    int result = 0;
    while ((entry = readdir(directory)) != NULL) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
        char *pid_end = NULL;
        long raw_pid = strtol(entry->d_name, &pid_end, 10);
        if (pid_end == entry->d_name || *pid_end != '\0' || raw_pid <= 0 || raw_pid > INT_MAX) continue;
        rh_process_identity identity = {0};
        int error = rh_process_read_identity((pid_t)raw_pid, &identity);
        if (error == ESRCH || error == ENOENT) continue;
        if (error != 0) { result = error; break; }
        if (count == MAX_SYSTEM_PROCESSES) { result = E2BIG; break; }
        if (count == capacity) {
            size_t next_capacity = capacity * 2;
            rh_process_identity *next = realloc(items, next_capacity * sizeof(*items));
            if (next == NULL) { result = ENOMEM; break; }
            items = next;
            capacity = next_capacity;
        }
        items[count++] = identity;
    }
    closedir(directory);
    if (result != 0) { free(items); return result; }
    qsort(items, count, sizeof(*items), rh_process_identity_compare);
    *items_out = items;
    *count_out = count;
    return 0;
}
#endif

/* Best-effort cleanup for live descendants that deliberately leave the group. */
static void rh_process_kill_descendants(pid_t root) {
    rh_process_identity *items = NULL;
    size_t count = 0;
    if (rh_process_snapshot(&items, &count) != 0) return;
    rh_process_identity *root_identity = rh_process_identity_find(items, count, root);
    if (root_identity == NULL) { free(items); return; }
    root_identity->descendant = 1;
    int changed = 1;
    while (changed) {
        changed = 0;
        for (size_t index = 0; index < count; ++index) {
            if (items[index].descendant || items[index].parent <= 0) continue;
            rh_process_identity *parent = rh_process_identity_find(items, count,
                                                                    items[index].parent);
            if (parent != NULL && parent->descendant) {
                items[index].descendant = 1;
                changed = 1;
            }
        }
    }
    for (size_t index = 0; index < count; ++index) {
        if (!items[index].descendant || items[index].pid == root) continue;
        rh_process_identity current = {0};
        if (rh_process_read_identity(items[index].pid, &current) == 0 &&
            current.start_time == items[index].start_time)
            (void)kill(items[index].pid, SIGKILL);
    }
    free(items);
}

static void rh_process_cancel(pid_t child, int child_reaped) {
    if (!child_reaped) rh_process_kill_descendants(child);
    (void)kill(-child, SIGKILL);
}

/* Account for the complete spawned process group, including descendants. */
static int rh_process_group_usage(pid_t group, size_t *processes_out,
                                  uint64_t *memory_out) {
    if (group <= 0 || processes_out == NULL || memory_out == NULL) return EINVAL;
    size_t processes = 0;
    uint64_t memory = 0;
#if defined(__APPLE__)
    pid_t pids[RH_PROCESS_MAX_GROUP_PROCESSES + 1];
    int bytes = proc_listpids(PROC_PGRP_ONLY, (uint32_t)group, pids,
                              (int)sizeof(pids));
    if (bytes < 0) return errno == 0 ? EIO : errno;
    if (bytes % (int)sizeof(pid_t) != 0) return EIO;
    processes = (size_t)bytes / sizeof(pid_t);
    if (processes > RH_PROCESS_MAX_GROUP_PROCESSES) {
        *processes_out = processes;
        *memory_out = RH_PROCESS_MAX_GROUP_MEMORY_BYTES + 1;
        return 0;
    }
    for (size_t index = 0; index < processes; ++index) {
        if (pids[index] <= 0) continue;
        rusage_info_current usage;
        if (proc_pid_rusage(pids[index], RUSAGE_INFO_CURRENT,
                            (rusage_info_t *)&usage) != 0) {
            if (errno == ESRCH) continue;
            return errno == 0 ? EIO : errno;
        }
        if (UINT64_MAX - memory < usage.ri_phys_footprint) return EOVERFLOW;
        memory += usage.ri_phys_footprint;
    }
#elif defined(__linux__)
    DIR *directory = opendir("/proc");
    if (directory == NULL) return errno == 0 ? EIO : errno;
    struct dirent *entry;
    while ((entry = readdir(directory)) != NULL) {
        if (entry->d_name[0] < '0' || entry->d_name[0] > '9') continue;
        char *pid_end = NULL;
        long raw_pid = strtol(entry->d_name, &pid_end, 10);
        if (pid_end == entry->d_name || *pid_end != '\0' || raw_pid <= 0 || raw_pid > INT_MAX) continue;
        char path[64];
        int length = snprintf(path, sizeof(path), "/proc/%ld/stat", raw_pid);
        if (length < 0 || (size_t)length >= sizeof(path)) { closedir(directory); return EIO; }
        FILE *stat_file = fopen(path, "r");
        if (stat_file == NULL) continue;
        char stat_line[4096];
        char *read_line = fgets(stat_line, sizeof(stat_line), stat_file);
        fclose(stat_file);
        if (read_line == NULL) continue;
        char *command_end = strrchr(stat_line, ')');
        if (command_end == NULL || command_end[1] != ' ') { closedir(directory); return EIO; }
        char state = 0;
        long parent = 0;
        long process_group = 0;
        if (sscanf(command_end + 2, "%c %ld %ld", &state, &parent, &process_group) != 3) {
            closedir(directory);
            return EIO;
        }
        if (process_group != (long)group) continue;
        processes += 1;
        if (processes > RH_PROCESS_MAX_GROUP_PROCESSES) continue;
        length = snprintf(path, sizeof(path), "/proc/%ld/statm", raw_pid);
        if (length < 0 || (size_t)length >= sizeof(path)) { closedir(directory); return EIO; }
        FILE *memory_file = fopen(path, "r");
        if (memory_file == NULL) continue;
        unsigned long total_pages = 0;
        unsigned long resident_pages = 0;
        int scanned = fscanf(memory_file, "%lu %lu", &total_pages, &resident_pages);
        fclose(memory_file);
        (void)total_pages;
        if (scanned != 2) { closedir(directory); return EIO; }
        long page_size = sysconf(_SC_PAGESIZE);
        if (page_size <= 0 || resident_pages > UINT64_MAX / (uint64_t)page_size) {
            closedir(directory);
            return EOVERFLOW;
        }
        uint64_t resident = (uint64_t)resident_pages * (uint64_t)page_size;
        if (UINT64_MAX - memory < resident) { closedir(directory); return EOVERFLOW; }
        memory += resident;
    }
    closedir(directory);
#endif
    *processes_out = processes;
    *memory_out = memory;
    return 0;
}

/*
 * Run one explicit executable with argv/envp, optional stdin, separately
 * captured output streams, an aggregate output cap, and a wall-clock deadline.
 * Returns a result kind and writes its associated code to code_out. No shell
 * is involved; timeout/overflow terminate the spawned process group.
 */
static int rh_process_run_inner(const char *executable, const char *argv_flat,
                   const char *env_flat, const char *input_data,
                   size_t input_length, const char *stdout_path,
                   const char *stderr_path, size_t max_output_bytes,
                   int timeout_ms, int *code_out,
                   rh_process_metrics *metrics) {
    rh_process_metrics_reset(metrics);
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
        int64_t finished = rh_process_millis();
        if (metrics != NULL && finished >= started) metrics->elapsed_ms = finished - started;
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, mask_error);
    }
    int pipe_was_pending = sigpending(&pending) == 0 && sigismember(&pending, SIGPIPE) == 1;
    int stdout_open = 1, stderr_open = 1, child_reaped = 0, status = 0;
    size_t input_written = 0, output_bytes = 0;
    int64_t last_resource_sample = started - RH_PROCESS_RESOURCE_SAMPLE_MS;
    int result_kind = RH_PROCESS_EXIT;
    int result_code = 0;
    while (stdout_open || stderr_open || !child_reaped) {
        int64_t now = rh_process_millis();
        if (now < 0) { result_kind = RH_PROCESS_IO_ERROR; result_code = EIO; rh_process_cancel(child, child_reaped); break; }
        if (now - started >= timeout_ms) { result_kind = RH_PROCESS_TIMEOUT; result_code = timeout_ms; rh_process_cancel(child, child_reaped); break; }
        if (now - last_resource_sample >= RH_PROCESS_RESOURCE_SAMPLE_MS) {
            size_t group_processes = 0;
            uint64_t group_memory = 0;
            int usage_error = rh_process_group_usage(child, &group_processes, &group_memory);
            last_resource_sample = now;
            if (metrics != NULL && usage_error == 0) {
                if (group_processes > metrics->peak_group_processes)
                    metrics->peak_group_processes = group_processes;
                if (group_memory > metrics->peak_group_memory_bytes)
                    metrics->peak_group_memory_bytes = group_memory;
            }
            if (usage_error != 0 || group_processes > RH_PROCESS_MAX_GROUP_PROCESSES ||
                group_memory > RH_PROCESS_MAX_GROUP_MEMORY_BYTES) {
                result_kind = RH_PROCESS_RESOURCE_LIMIT;
                result_code = usage_error != 0 ? usage_error :
                    group_processes > RH_PROCESS_MAX_GROUP_PROCESSES ?
                    RH_PROCESS_MAX_GROUP_PROCESSES : RH_PROCESS_MAX_GROUP_MEMORY_MIB;
                rh_process_cancel(child, child_reaped);
                break;
            }
        }

        struct pollfd fds[3];
        nfds_t count = 0;
        int input_slot = -1, stdout_slot = -1, stderr_slot = -1;
        if (input_pipe[1] >= 0) { input_slot = (int)count; fds[count++] = (struct pollfd){input_pipe[1], POLLOUT, 0}; }
        if (stdout_open) { stdout_slot = (int)count; fds[count++] = (struct pollfd){stdout_pipe[0], POLLIN | POLLHUP, 0}; }
        if (stderr_open) { stderr_slot = (int)count; fds[count++] = (struct pollfd){stderr_pipe[0], POLLIN | POLLHUP, 0}; }
        int remaining = timeout_ms - (int)(now - started);
        int wait_ms = remaining < 10 ? remaining : 10;
        int polled = poll(fds, count, wait_ms);
        if (polled < 0 && errno != EINTR) { result_kind = RH_PROCESS_IO_ERROR; result_code = errno; rh_process_cancel(child, child_reaped); break; }

        if (input_slot >= 0 && polled > 0 && (fds[input_slot].revents & (POLLOUT | POLLERR | POLLHUP))) {
            ssize_t written = write(input_pipe[1], input_data + input_written, input_length - input_written);
            if (written > 0) input_written += (size_t)written;
            else if (written < 0 && errno != EINTR && errno != EAGAIN && errno != EWOULDBLOCK) {
                result_kind = RH_PROCESS_IO_ERROR; result_code = EIO; rh_process_cancel(child, child_reaped); break;
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
                    if (metrics != NULL) {
                        size_t *stream_bytes = stream == 0 ? &metrics->stdout_bytes : &metrics->stderr_bytes;
                        if ((size_t)bytes > SIZE_MAX - *stream_bytes) *stream_bytes = SIZE_MAX;
                        else *stream_bytes += (size_t)bytes;
                    }
                    if ((size_t)bytes > max_output_bytes - output_bytes) {
                        result_kind = RH_PROCESS_OUTPUT_LIMIT; result_code = (int)max_output_bytes; rh_process_cancel(child, child_reaped); goto finished;
                    }
                    output_bytes += (size_t)bytes;
                    if (output_fds[stream] >= 0 && rh_process_write_all(output_fds[stream], buffer, (size_t)bytes) != 0) {
                        result_kind = RH_PROCESS_IO_ERROR; result_code = EIO; rh_process_cancel(child, child_reaped); goto finished;
                    }
                } else if (bytes == 0) {
                    *open_flags[stream] = 0; rh_process_close(read_fds[stream]); break;
                } else if (errno == EINTR) continue;
                else if (errno == EAGAIN || errno == EWOULDBLOCK) break;
                else { result_kind = RH_PROCESS_IO_ERROR; result_code = errno; rh_process_cancel(child, child_reaped); goto finished; }
            }
        }
        if (!child_reaped) {
            pid_t waited = waitpid(child, &status, WNOHANG);
            if (waited == child) child_reaped = 1;
            else if (waited < 0 && errno != EINTR) { result_kind = RH_PROCESS_IO_ERROR; result_code = errno; rh_process_cancel(child, child_reaped); break; }
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
    int64_t finished = rh_process_millis();
    if (metrics != NULL && finished >= started) metrics->elapsed_ms = finished - started;
    return rh_process_result(code_out, result_kind, result_code);
}

/* Bound concurrently managed process groups even when callers run in parallel. */
int rh_process_run(const char *executable, const char *argv_flat,
                   const char *env_flat, const char *input_data,
                   size_t input_length, const char *stdout_path,
                   const char *stderr_path, size_t max_output_bytes,
                   int timeout_ms, int *code_out, int64_t *elapsed_ms_out,
                   size_t *stdout_bytes_out, size_t *stderr_bytes_out,
                   size_t *peak_group_processes_out,
                   uint64_t *peak_group_memory_bytes_out) {
    rh_process_metrics metrics;
    rh_process_metrics_reset(&metrics);
    rh_process_metrics_publish(&metrics, elapsed_ms_out, stdout_bytes_out,
                               stderr_bytes_out, peak_group_processes_out,
                               peak_group_memory_bytes_out);
    if (code_out == NULL) return RH_PROCESS_SETUP_ERROR;
    int lock_error = pthread_mutex_lock(&rh_process_capacity_mutex);
    if (lock_error != 0)
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, lock_error);
    if (rh_process_active_groups >= RH_PROCESS_MAX_ACTIVE_GROUPS) {
        (void)pthread_mutex_unlock(&rh_process_capacity_mutex);
        return rh_process_result(code_out, RH_PROCESS_CAPACITY_LIMIT, EAGAIN);
    }
    rh_process_active_groups += 1;
    (void)pthread_mutex_unlock(&rh_process_capacity_mutex);

    int result = rh_process_run_inner(executable, argv_flat, env_flat, input_data,
                                      input_length, stdout_path, stderr_path,
                                      max_output_bytes, timeout_ms, code_out,
                                      &metrics);
    rh_process_metrics_publish(&metrics, elapsed_ms_out, stdout_bytes_out,
                               stderr_bytes_out, peak_group_processes_out,
                               peak_group_memory_bytes_out);
    lock_error = pthread_mutex_lock(&rh_process_capacity_mutex);
    if (lock_error == 0) {
        rh_process_active_groups -= 1;
        (void)pthread_mutex_unlock(&rh_process_capacity_mutex);
    } else {
        /* Keep accounting conservative if the platform mutex reports failure. */
        return rh_process_result(code_out, RH_PROCESS_SETUP_ERROR, lock_error);
    }
    return result;
}
