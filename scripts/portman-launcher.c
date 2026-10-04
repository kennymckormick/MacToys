// A native helper keeps the CLI relocatable and covered by the app signature.
#include <mach-o/dyld.h>
#include <errno.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

int main(int argc, char **argv) {
    uint32_t size = 0;
    _NSGetExecutablePath(NULL, &size);
    char *executable = malloc(size);
    if (!executable || _NSGetExecutablePath(executable, &size) != 0) return 1;
    char *resolved = realpath(executable, NULL);
    free(executable);
    if (!resolved) { perror("MacToys launcher path"); return 1; }
    char *slash = strrchr(resolved, '/');
    if (!slash) { free(resolved); return 1; }
    *slash = '\0';
    char *python = NULL, *entry = NULL;
    if (asprintf(&python, "%s/../Resources/Python/bin/python3", resolved) < 0 ||
        asprintf(&entry, "%s/../Resources/Portman/portman/_entry.py", resolved) < 0) {
        free(resolved); free(python); return 1;
    }
    free(resolved);
    char **args = calloc((size_t)argc + 6, sizeof(char *));
    if (!args) { free(python); free(entry); return 1; }
    args[0] = python; args[1] = "-I"; args[2] = "-B"; args[3] = entry; args[4] = "portman";
    for (int i = 1; i < argc; ++i) args[i + 4] = argv[i];
    execv(python, args);
    fprintf(stderr, "MacToys could not start its bundled Python: %s\n", strerror(errno));
    free(args); free(entry); free(python);
    return 1;
}
