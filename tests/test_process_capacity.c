#define _POSIX_C_SOURCE 200809L
#include <errno.h>
#include <pthread.h>
#include <stdio.h>
#include <time.h>

enum { PROCESS_CAPACITY_LIMIT = 6, WORKERS = 32 };

extern int rh_process_run(const char *, const char *, const char *, const char *,
                         size_t, const char *, const char *, size_t, int, int *);

static const char argv_flat[] = "sleep\0" "0.7\0";
static const char env_flat[] = "PATH=/usr/bin:/bin\0";
static pthread_mutex_t started_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t started_condition = PTHREAD_COND_INITIALIZER;
static size_t started = 0;
static int worker_kinds[WORKERS];
static int worker_codes[WORKERS];

static void *run_worker(void *argument) {
    size_t index = (size_t)argument;
    pthread_mutex_lock(&started_mutex);
    started += 1;
    pthread_cond_signal(&started_condition);
    pthread_mutex_unlock(&started_mutex);
    worker_kinds[index] = rh_process_run("/bin/sleep", argv_flat, env_flat, NULL,
                                         0, "/dev/null", "/dev/null", 1024,
                                         3000, &worker_codes[index]);
    return NULL;
}

int main(void) {
    pthread_t threads[WORKERS];
    for (size_t index = 0; index < WORKERS; ++index) {
        if (pthread_create(&threads[index], NULL, run_worker, (void *)index) != 0)
            return 2;
    }
    pthread_mutex_lock(&started_mutex);
    while (started < WORKERS)
        pthread_cond_wait(&started_condition, &started_mutex);
    pthread_mutex_unlock(&started_mutex);

    struct timespec settle = {.tv_sec = 0, .tv_nsec = 100000000};
    nanosleep(&settle, NULL);
    int overflow_code = 0;
    int overflow_kind = rh_process_run("/bin/sleep", argv_flat, env_flat, NULL,
                                       0, "/dev/null", "/dev/null", 1024,
                                       3000, &overflow_code);
    int failure = overflow_kind != PROCESS_CAPACITY_LIMIT || overflow_code != EAGAIN;
    for (size_t index = 0; index < WORKERS; ++index) {
        pthread_join(threads[index], NULL);
        if (worker_kinds[index] != 0 || worker_codes[index] != 0) failure = 1;
    }
    if (failure) {
        fprintf(stderr, "process capacity failure: kind=%d code=%d\n",
                overflow_kind, overflow_code);
        return 1;
    }
    puts("process group concurrency cap OK");
    return 0;
}
