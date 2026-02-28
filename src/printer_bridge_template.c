#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <dlfcn.h>
#include <string.h>
#include <stdarg.h>
#include <fcntl.h>
#include <unistd.h>
#include <sys/socket.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>
#include <errno.h>
#include <stdint.h>

#define ANDROID_USB_FD __FD__
#define DEV_NUM_STR "__DEV__"

__attribute__((constructor)) void init(void) {
    fprintf(stderr, "[BRIDGE] HARDCODED BRIDGE LOADED! Target FD: %d, Target DEV: %s\n", ANDROID_USB_FD, DEV_NUM_STR);
}

int close(int fd) {
    if (fd == ANDROID_USB_FD) return 0;
    int (*orig)(int) = dlsym(RTLD_NEXT, "close");
    return orig ? orig(fd) : -1;
}

int fcntl(int fd, int cmd, ...) {
    int (*orig)(int, int, ...) = dlsym(RTLD_NEXT, "fcntl");
    va_list args; va_start(args, cmd);
    if (fd == ANDROID_USB_FD && cmd == F_SETFD) {
        long flags = va_arg(args, long);
        flags &= ~FD_CLOEXEC; va_end(args);
        return orig(fd, cmd, flags);
    }
    if (cmd == F_GETFD || cmd == F_GETFL) { va_end(args); return orig(fd, cmd); }
    void *arg = va_arg(args, void*); va_end(args);
    return orig(fd, cmd, arg);
}

int ioctl(int fd, unsigned long request, ...) {
    int (*orig)(int, unsigned long, ...) = dlsym(RTLD_NEXT, "ioctl");
    va_list args; va_start(args, request);
    void *argp = va_arg(args, void *); va_end(args);
    if (fd == ANDROID_USB_FD) {
        if (request == USBDEVFS_GETDRIVER) { errno = ENODATA; return -1; }
        if (request == USBDEVFS_GET_CAPABILITIES) { if (argp) *((uint32_t*)argp) = 0; return 0; }
        if (request == USBDEVFS_SETCONFIGURATION || request == USBDEVFS_CLAIMINTERFACE) return 0;
    }
    return orig ? orig(fd, request, argp) : -1;
}

static int check_and_hijack(const char *path, const char *func) {
    if (path && strstr(path, "dev/bus/usb") && strstr(path, DEV_NUM_STR)) {
        fprintf(stderr, "[BRIDGE] HIJACKING %s for %s! Returning FD %d\n", func, path, ANDROID_USB_FD);
        return ANDROID_USB_FD;
    }
    return -1;
}

int open(const char *path, int flags, ...) {
    int h = check_and_hijack(path, "open"); if (h >= 0) return h;
    int (*orig)(const char *, int, ...) = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(path, flags, mode); }
    return orig(path, flags);
}
int open64(const char *path, int flags, ...) {
    int h = check_and_hijack(path, "open64"); if (h >= 0) return h;
    int (*orig)(const char *, int, ...) = dlsym(RTLD_NEXT, "open64");
    if (!orig) orig = dlsym(RTLD_NEXT, "open");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(path, flags, mode); }
    return orig(path, flags);
}
int openat(int dirfd, const char *path, int flags, ...) {
    int h = check_and_hijack(path, "openat"); if (h >= 0) return h;
    int (*orig)(int, const char *, int, ...) = dlsym(RTLD_NEXT, "openat");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(dirfd, path, flags, mode); }
    return orig(dirfd, path, flags);
}

int __open_2(const char *path, int flags) {
    int h = check_and_hijack(path, "__open_2"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, "__open_2"); return orig ? orig(path, flags) : -1;
}
int __open64_2(const char *path, int flags) {
    int h = check_and_hijack(path, "__open64_2"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, "__open64_2"); return orig ? orig(path, flags) : -1;
}
int __openat_2(int dirfd, const char *path, int flags) {
    int h = check_and_hijack(path, "__openat_2"); if (h >= 0) return h;
    int (*orig)(int, const char *, int) = dlsym(RTLD_NEXT, "__openat_2"); return orig ? orig(dirfd, path, flags) : -1;
}

int socket(int domain, int type, int protocol) { int (*orig)(int, int, int) = dlsym(RTLD_NEXT, "socket"); return domain == 16 ? orig(AF_UNIX, type, 0) : orig(domain, type, protocol); }
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) { if (addr && addr->sa_family == 16) return 0; int (*orig)(int, const struct sockaddr *, socklen_t) = dlsym(RTLD_NEXT, "bind"); return orig(sockfd, addr, addrlen); }
int dbus_connection_send(void *c, void *m, void *s) { return 1; } void dbus_connection_flush(void *c) {} void dbus_connection_unref(void *c) {}
