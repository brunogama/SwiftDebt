#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <sys/stdio.h>

// Test-only interposition at Foundation Data.write(options: .atomic)'s rename.
// The temporary file is complete, but the canonical destination is unchanged.
static int (*original_renameat)(int, const char *, int, const char *) = renameat;

static int pause_before_artifact_rename(
    int source_directory, const char *source,
    int destination_directory, const char *destination
) {
    const char *artifact_name = getenv("SWIFTDEBT_AT22_ARTIFACT_NAME");
    const char *marker_path = getenv("SWIFTDEBT_AT22_RENAME_MARKER");
    if (artifact_name && marker_path && strcmp(destination, artifact_name) == 0) {
        size_t pending_capacity = strlen(marker_path) + sizeof(".pending");
        char *pending_path = malloc(pending_capacity);
        if (pending_path) {
            // Publish complete marker bytes in one rename before stopping the child.
            snprintf(pending_path, pending_capacity, "%s.pending", marker_path);
            FILE *pending = fopen(pending_path, "w");
            if (pending) {
                int wrote = fprintf(pending, "%s\n", source) > 0;
                int closed = fclose(pending) == 0;
                if (wrote && closed && rename(pending_path, marker_path) == 0) {
                    raise(SIGSTOP);
                }
            }
            free(pending_path);
        }
    }
    return original_renameat(
        source_directory, source, destination_directory, destination
    );
}

#define INTERPOSE(replacement, original)                                      \
    __attribute__((used)) static struct {                                     \
        const void *replacement_function;                                    \
        const void *original_function;                                       \
    } interpose_##original __attribute__((section("__DATA,__interpose"))) = { \
        (const void *)replacement, (const void *)original                    \
    }

INTERPOSE(pause_before_artifact_rename, renameat);
