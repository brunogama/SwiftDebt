#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdatomic.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/stdio.h>
#include <sys/stat.h>
#include <unistd.h>

// Foundation reaches atomic replacement through different rename symbols across macOS hosts.
static int (*original_rename)(const char *, const char *) = rename;
static int (*original_renameat)(int, const char *, int, const char *) = renameat;
static int (*original_renamex_np)(const char *, const char *, unsigned int) = renamex_np;
static int (*original_renameatx_np)(int, const char *, int, const char *, unsigned int) = renameatx_np;
static ssize_t (*original_write)(int, const void *, size_t) = write;
static atomic_flag artifact_write_started = ATOMIC_FLAG_INIT;

__attribute__((constructor)) static void report_interposer_loaded(void) {
    fputs("SwiftDebt AT22 write interposer loaded\n", stderr);
}

static const char *last_path_component(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
}

static int paths_have_same_parent(const char *first, const char *second) {
    const char *first_slash = strrchr(first, '/');
    const char *second_slash = strrchr(second, '/');
    if (!first_slash || !second_slash) {
        return 0;
    }
    size_t first_length = (size_t)(first_slash - first);
    size_t second_length = (size_t)(second_slash - second);
    return first_length == second_length && strncmp(first, second, first_length) == 0;
}

static int artifact_sibling_path(int descriptor, char path[PATH_MAX]) {
    const char *artifact_path = getenv("SWIFTDEBT_AT22_ARTIFACT_PATH");
    const char *marker_path = getenv("SWIFTDEBT_AT22_WRITE_MARKER");
    if (!artifact_path || !marker_path || fcntl(descriptor, F_GETPATH, path) != 0) {
        return 0;
    }

    char resolved_artifact[PATH_MAX];
    if (!realpath(artifact_path, resolved_artifact)
        || strcmp(path, resolved_artifact) == 0
        || !paths_have_same_parent(path, resolved_artifact)) {
        return 0;
    }
    return 1;
}

static int temporary_artifact_path(int descriptor, char path[PATH_MAX]) {
    if (!artifact_sibling_path(descriptor, path)) {
        return 0;
    }

    struct stat status;
    int flags = fcntl(descriptor, F_GETFL);
    off_t offset = lseek(descriptor, 0, SEEK_CUR);
    return flags >= 0
        && (flags & O_ACCMODE) != O_RDONLY
        && offset == 0
        && fstat(descriptor, &status) == 0
        && S_ISREG(status.st_mode)
        && status.st_size == 0;
}

static int publish_byte_write_marker(
    const char *temporary_path,
    off_t temporary_byte_count,
    ssize_t written_byte_count,
    size_t requested_byte_count
) {
    const char *marker_path = getenv("SWIFTDEBT_AT22_WRITE_MARKER");
    if (!marker_path) {
        return 0;
    }
    size_t pending_capacity = strlen(marker_path) + sizeof(".pending");
    char *pending_path = malloc(pending_capacity);
    if (!pending_path) {
        return 0;
    }
    snprintf(pending_path, pending_capacity, "%s.pending", marker_path);
    FILE *pending = fopen(pending_path, "w");
    int published = 0;
    if (pending) {
        int wrote = fprintf(
            pending,
            "%s\n%lld\n%zd\n%zu\n",
            temporary_path,
            (long long)temporary_byte_count,
            written_byte_count,
            requested_byte_count
        ) > 0;
        int closed = fclose(pending) == 0;
        published = wrote && closed && original_rename(pending_path, marker_path) == 0;
    }
    free(pending_path);
    return published;
}

static ssize_t pause_during_artifact_write(int descriptor, const void *bytes, size_t count) {
    char temporary_path[PATH_MAX];
    if (count < 2 || !temporary_artifact_path(descriptor, temporary_path)) {
        return original_write(descriptor, bytes, count);
    }
    if (atomic_flag_test_and_set_explicit(&artifact_write_started, memory_order_relaxed)) {
        return original_write(descriptor, bytes, count);
    }

    size_t prefix_count = count / 2;
    ssize_t written_count = original_write(descriptor, bytes, prefix_count);
    struct stat status;
    if (written_count > 0
        && (size_t)written_count < count
        && fstat(descriptor, &status) == 0
        && publish_byte_write_marker(temporary_path, status.st_size, written_count, count)) {
        raise(SIGSTOP);
    } else {
        atomic_flag_clear_explicit(&artifact_write_started, memory_order_relaxed);
    }
    return written_count;
}

static void pause_before_artifact_rename(const char *source, const char *destination) {
    const char *artifact_name = getenv("SWIFTDEBT_AT22_ARTIFACT_NAME");
    const char *marker_path = getenv("SWIFTDEBT_AT22_RENAME_MARKER");
    if (artifact_name && marker_path && strcmp(last_path_component(destination), artifact_name) == 0) {
        size_t pending_capacity = strlen(marker_path) + sizeof(".pending");
        char *pending_path = malloc(pending_capacity);
        if (pending_path) {
            snprintf(pending_path, pending_capacity, "%s.pending", marker_path);
            FILE *pending = fopen(pending_path, "w");
            if (pending) {
                int wrote = fprintf(pending, "%s\n", last_path_component(source)) > 0;
                int closed = fclose(pending) == 0;
                if (wrote && closed && original_rename(pending_path, marker_path) == 0) {
                    raise(SIGSTOP);
                }
            }
            free(pending_path);
        }
    }
}

static int pause_before_rename(const char *source, const char *destination) {
    pause_before_artifact_rename(source, destination);
    return original_rename(source, destination);
}

static int pause_before_renameat(
    int source_directory, const char *source,
    int destination_directory, const char *destination
) {
    pause_before_artifact_rename(source, destination);
    return original_renameat(source_directory, source, destination_directory, destination);
}

static int pause_before_renamex_np(const char *source, const char *destination, unsigned int flags) {
    pause_before_artifact_rename(source, destination);
    return original_renamex_np(source, destination, flags);
}

static int pause_before_renameatx_np(
    int source_directory, const char *source,
    int destination_directory, const char *destination, unsigned int flags
) {
    pause_before_artifact_rename(source, destination);
    return original_renameatx_np(source_directory, source, destination_directory, destination, flags);
}

#define INTERPOSE(replacement, original)                                      \
    __attribute__((used)) static struct {                                     \
        const void *replacement_function;                                    \
        const void *original_function;                                       \
    } interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)replacement, (const void *)original                    \
    }

INTERPOSE(pause_before_rename, rename);
INTERPOSE(pause_before_renameat, renameat);
INTERPOSE(pause_before_renamex_np, renamex_np);
INTERPOSE(pause_before_renameatx_np, renameatx_np);
INTERPOSE(pause_during_artifact_write, write);
