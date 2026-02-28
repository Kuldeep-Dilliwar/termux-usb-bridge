#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <string.h>
#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>

int socket(int domain, int type, int protocol) {
    if (domain == 16) {
        int (*orig)(int, int, int) = dlsym(RTLD_NEXT, "socket");
        return orig(AF_UNIX, type, 0);
    }
    int (*orig)(int, int, int) = dlsym(RTLD_NEXT, "socket");
    return orig(domain, type, protocol);
}

int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) {
    if (addr && addr->sa_family == 16) return 0;
    int (*orig)(int, const struct sockaddr *, socklen_t) = dlsym(RTLD_NEXT, "bind");
    return orig(sockfd, addr, addrlen);
}

static int check_and_hijack(const char *pathname, const char *func_name) {
    char *fd_str = getenv("TERMUX_USB_FD");
    if (fd_str && pathname && strstr(pathname, "dev/bus/usb") != NULL) {
        int real_fd = atoi(fd_str);
        fprintf(stderr, "[BRIDGE] HIJACKING %s for %s! Returning dup(%d)\n", func_name, pathname, real_fd);
        return dup(real_fd);
    }
    return -1;
}

int dbus_connection_send(void *c, void *m, void *s) { return 1; }
void dbus_connection_flush(void *c) {}
void dbus_connection_unref(void *c) {}

int open(const char *pathname, int flags, ...) {
    int h = check_and_hijack(pathname, "open"); if (h >= 0) return h;
    int (*orig)(const char *, int, ...) = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(pathname, flags, mode); }
    return orig(pathname, flags);
}

int open64(const char *pathname, int flags, ...) {
    int h = check_and_hijack(pathname, "open64"); if (h >= 0) return h;
    int (*orig)(const char *, int, ...) = dlsym(RTLD_NEXT, "open64");
    if (!orig) orig = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0;
    if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(pathname, flags, mode); }
    return orig(pathname, flags);
}

int __open_2(const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__open_2"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, "__open_2"); return orig ? orig(pathname, flags) : -1;
}

int __open64_2(const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__open64_2"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, "__open64_2"); return orig ? orig(pathname, flags) : -1;
}

int __openat_2(int dirfd, const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__openat_2"); if (h >= 0) return h;
    int (*orig)(int, const char *, int) = dlsym(RTLD_NEXT, "__openat_2"); return orig ? orig(dirfd, pathname, flags) : -1;
}

int __openat64_2(int dirfd, const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__openat64_2"); if (h >= 0) return h;
    int (*orig)(int, const char *, int) = dlsym(RTLD_NEXT, "__openat64_2"); return orig ? orig(dirfd, pathname, flags) : -1;
}
