#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/stdio.h>

// Foundation reaches atomic replacement through different rename symbols across macOS hosts.
static int (*original_rename)(const char *, const char *) = rename;
static int (*original_renameat)(int, const char *, int, const char *) = renameat;
static int (*original_renamex_np)(const char *, const char *, unsigned int) = renamex_np;
static int (*original_renameatx_np)(int, const char *, int, const char *, unsigned int) = renameatx_np;

__attribute__((constructor)) static void report_interposer_loaded(void) {
    fputs("SwiftDebt AT22 rename interposer loaded\n", stderr);
}

static const char *last_path_component(const char *path) {
    const char *slash = strrchr(path, '/');
    return slash ? slash + 1 : path;
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
