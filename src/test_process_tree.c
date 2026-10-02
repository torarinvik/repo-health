#define _POSIX_C_SOURCE 200809L
#define _DARWIN_C_SOURCE
#define _DEFAULT_SOURCE

#include <stdint.h>
#include <stdlib.h>
#include <fcntl.h>
#include <sys/mman.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <sys/wait.h>

static void pause_millis(long milliseconds) {
    struct timespec duration = {
        .tv_sec = milliseconds / 1000,
        .tv_nsec = (milliseconds % 1000) * 1000000L,
    };
    while (nanosleep(&duration, &duration) != 0) {}
}

int main(int argc, char **argv) {
    if (argc != 2) return 2;
    if (argv[1][0] == 'm') {
        size_t length = (size_t)1280 * 1024 * 1024;
        volatile uint8_t *memory = mmap(NULL, length, PROT_READ | PROT_WRITE,
                                        MAP_PRIVATE | MAP_ANON, -1, 0);
        if (memory == MAP_FAILED) return 3;
        for (size_t offset = 0; offset < length; offset += 4096) memory[offset] = 1;
        pause_millis(100);
        return 42;
    }
    if (argv[1][0] == 'p') {
        pid_t children[96];
        size_t count = 0;
        while (count < sizeof(children) / sizeof(children[0])) {
            pid_t child = fork();
            if (child < 0) return 4;
            if (child == 0) {
                pause_millis(10000);
                _exit(0);
            }
            children[count++] = child;
            pause_millis(2);
        }
        for (size_t index = 0; index < count; ++index) (void)waitpid(children[index], NULL, 0);
        return 42;
    }
    if (argv[1][0] == 'e') {
        pid_t child = fork();
        if (child < 0) return 5;
        if (child == 0) {
            if (setsid() < 0) _exit(6);
            pause_millis(250);
            int marker = open("/tmp/rh-process-escaped-descendant-survived",
                              O_WRONLY | O_CREAT | O_TRUNC, 0600);
            if (marker >= 0) close(marker);
            _exit(0);
        }
        pause_millis(10000);
        return 42;
    }
    return 2;
}
