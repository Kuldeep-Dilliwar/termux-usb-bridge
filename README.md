# termux-USB-bridge 
*⚠️⚠️⚠️ disclaimer: `run this setup at your own risk` ; if you open any app in doing this or printing or scanning, the opened app might say `the device is rooted`, i found `my official mobile carrier app` showing devices rooted message and `it instantly logged me off my account`, but it was fixed by `clearing the data` of the `infected` app, also `I have no idea why that happend`, ⚠️⚠️⚠️)*
# (HP) Printer And Scanner support for Termux (no-root):
## **1. In Termux.**

```
pkg update -y && yes | pkg upgrade
```
```
yes | pkg i clang termux-api jq
```
```
pkg install proot-distro -y
proot-distro install ubuntu
proot-distro login ubuntu
```
## **2. In Proot.**
```
apt update && apt upgrade -y
```
```
apt install -y \
    git \
    gcc \
    cups \
    wget \
    curl \
    hplip \
    dialog \
    libtool \
    usbutils \
    autoconf \
    automake \
    sane-utils \
    pkg-config \
    ghostscript \
    build-essential \
    cups-core-drivers \
    printer-driver-foo2zjs 
```
```
hp-plugin -i -g
```
```
git clone --depth 1 https://github.com/libusb/libusb.git
cd libusb
./autogen.sh --disable-udev
make -j4
make install
ldconfig
```

```
exit
```
## **3. In Termux: Compile the cloner.**
```
cd ~
cat << 'EOF' > universal_clone.c
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <stdint.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <string.h>
#include <sys/ioctl.h>
#include <linux/usbdevice_fs.h>

void write_str(const char *dir, const char *file, const char *val) {
    char path[512];
    snprintf(path, sizeof(path), "%s/%s", dir, file);
    FILE *f = fopen(path, "w");
    if (f) { fprintf(f, "%s\n", val); fclose(f); }
}

// Dynamically ask the USB device for its string descriptors
void fetch_usb_string(int fd, uint8_t index, char *out, int out_len) {
    if (index == 0) { snprintf(out, out_len, "Unknown"); return; }
    
    uint8_t data[255];
    struct usbdevfs_ctrltransfer ctrl = {
        .bRequestType = 0x80, // USB_DIR_IN
        .bRequest = 0x06,     // USB_REQ_GET_DESCRIPTOR
        .wValue = (3 << 8) | index, // 3 is String Descriptor type
        .wIndex = 0x0409,     // Language ID (English)
        .wLength = sizeof(data),
        .data = data,
        .timeout = 1000
    };
    
    if (ioctl(fd, USBDEVFS_CONTROL, &ctrl) > 2 && data[1] == 3) {
        int len = data[0];
        int j = 0;
        // Convert UTF-16LE to standard ASCII
        for (int i = 2; i < len && j < out_len - 1; i += 2) {
            out[j++] = data[i];
        }
        out[j] = '\0';
    } else {
        snprintf(out, out_len, "Generic_Device");
    }
}

int main(int argc, char **argv) {
    if (argc < 3) return 1;
    int fd = atoi(argv[1]);
    int dev_num = atoi(argv[2]);
    char *home = getenv("HOME");

    char dev_dir[512];
    snprintf(dev_dir, sizeof(dev_dir), "%s/fake_usb/sys/bus/usb/devices/1-1", home);

    // 1. Prepare Directories
    char cmd[512];
    snprintf(cmd, sizeof(cmd), "rm -rf %s/fake_usb", home); system(cmd);
    snprintf(cmd, sizeof(cmd), "mkdir -p %s", dev_dir); system(cmd);
    snprintf(cmd, sizeof(cmd), "mkdir -p %s/fake_usb/dev/bus/usb/001", home); system(cmd);

    // 2. Read full descriptors natively from Android FD
    uint8_t buf[2048];
    lseek(fd, 0, SEEK_SET);
    int len = read(fd, buf, sizeof(buf));
    if (len < 18) { printf("Failed to read FD\n"); return 1; }

    // 3. Dump the real binary descriptors into the fake sysfs
    char desc_path[512];
    snprintf(desc_path, sizeof(desc_path), "%s/descriptors", dev_dir);
    int df = open(desc_path, O_WRONLY|O_CREAT|O_TRUNC, 0644);
    if (df >= 0) { write(df, buf, len); close(df); }

    // 4. Parse Device Descriptor (First 18 bytes)
    uint16_t vid = buf[8] | (buf[9] << 8);
    uint16_t pid = buf[10] | (buf[11] << 8);
    
    char hex[10];
    snprintf(hex, sizeof(hex), "%04x", vid); write_str(dev_dir, "idVendor", hex);
    snprintf(hex, sizeof(hex), "%04x", pid); write_str(dev_dir, "idProduct", hex);
    snprintf(hex, sizeof(hex), "%02x", buf[4]); write_str(dev_dir, "bDeviceClass", hex);
    snprintf(hex, sizeof(hex), "%02x", buf[5]); write_str(dev_dir, "bDeviceSubClass", hex);
    snprintf(hex, sizeof(hex), "%02x", buf[6]); write_str(dev_dir, "bDeviceProtocol", hex);
    snprintf(hex, sizeof(hex), "%d", buf[17]); write_str(dev_dir, "bNumConfigurations", hex);
    
    write_str(dev_dir, "busnum", "1");
    write_str(dev_dir, "devnum", argv[2]);
    write_str(dev_dir, "bConfigurationValue", "1");
    write_str(dev_dir, "speed", "480");

    // Fetch dynamic strings
    char str_buf[256];
    fetch_usb_string(fd, buf[14], str_buf, sizeof(str_buf)); write_str(dev_dir, "manufacturer", str_buf);
    fetch_usb_string(fd, buf[15], str_buf, sizeof(str_buf)); write_str(dev_dir, "product", str_buf);
    fetch_usb_string(fd, buf[16], str_buf, sizeof(str_buf)); write_str(dev_dir, "serial", str_buf);

    // 5. Dynamically Parse Configurations & Interfaces
    int offset = 18; // Skip the 18-byte Device Descriptor
    int current_config = 1;
    
    while (offset < len) {
        uint8_t d_len = buf[offset];
        uint8_t d_type = buf[offset + 1];
        if (d_len == 0) break; // Prevent infinite loop on corrupted data
        
        if (d_type == 2) { // Configuration Descriptor
            current_config = buf[offset + 5]; // bConfigurationValue
        } 
        else if (d_type == 4) { // Interface Descriptor
            uint8_t bInterfaceNumber = buf[offset + 2];
            
            char iface_dir[512];
            snprintf(iface_dir, sizeof(iface_dir), "%s/1-1:%d.%d", dev_dir, current_config, bInterfaceNumber);
            snprintf(cmd, sizeof(cmd), "mkdir -p %s", iface_dir); system(cmd);
            
            snprintf(hex, sizeof(hex), "%02x", buf[offset + 5]); write_str(iface_dir, "bInterfaceClass", hex);
            snprintf(hex, sizeof(hex), "%02x", buf[offset + 6]); write_str(iface_dir, "bInterfaceSubClass", hex);
            snprintf(hex, sizeof(hex), "%02x", buf[offset + 7]); write_str(iface_dir, "bInterfaceProtocol", hex);
            snprintf(hex, sizeof(hex), "%02x", bInterfaceNumber); write_str(iface_dir, "bInterfaceNumber", hex);
        }
        offset += d_len;
    }

    // 6. Fake Root Hub & Dummy Stat nodes
    char root_dir[512];
    snprintf(root_dir, sizeof(root_dir), "%s/fake_usb/sys/bus/usb/devices/usb1", home);
    snprintf(cmd, sizeof(cmd), "mkdir -p %s", root_dir); system(cmd);
    write_str(root_dir, "busnum", "1");
    write_str(root_dir, "devnum", "1");
    uint8_t root_desc[] = {0x12,0x01,0x09,0x02,0x09,0x00,0x01,0x40,0x6b,0x1d,0x02,0x00,0x03,0x01,0x03,0x02,0x01,0x01};
    snprintf(desc_path, sizeof(desc_path), "%s/descriptors", root_dir);
    df = open(desc_path, O_WRONLY|O_CREAT|O_TRUNC, 0644);
    if (df >= 0) { write(df, root_desc, sizeof(root_desc)); close(df); }

    snprintf(cmd, sizeof(cmd), "touch %s/fake_usb/dev/bus/usb/001/001", home); system(cmd);
    snprintf(cmd, sizeof(cmd), "touch %s/fake_usb/dev/bus/usb/001/%03d", home, dev_num); system(cmd);

    printf("Successfully cloned Universal Device: %04x:%04x\n", vid, pid);
    return 0;
}
EOF

gcc -o universal_clone universal_clone.c
```

## **4. In Termux: Compile the `Scanner` bridge**
```
cd ~
cat << 'OUTER_EOF' > fix_bridge_fortify.sh
proot-distro login ubuntu << 'PROOT_EOF'
mkdir -p /home/scanner
cat << 'C_EOF' > /home/scanner/usb_bridge.c
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

int dbus_connection_send(void *c, void *m, void *s) {
    if (!c) { fprintf(stderr, "[BRIDGE] DBus send blocked!\n"); return 1; }
    int (*o)(void*, void*, void*) = dlsym(RTLD_NEXT, "dbus_connection_send");
    return o ? o(c, m, s) : 1;
}
void dbus_connection_flush(void *c) {
    void (*o)(void*) = dlsym(RTLD_NEXT, "dbus_connection_flush");
    if (o && c) o(c);
}
void dbus_connection_unref(void *c) {
    void (*o)(void*) = dlsym(RTLD_NEXT, "dbus_connection_unref");
    if (o && c) o(c);
}

/* --- STANDARD OPEN HOOKS --- */
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

/* --- FORTIFIED (_FORTIFY_SOURCE) OPEN HOOKS --- */
int __open_2(const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__open_2"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, "__open_2");
    return orig ? orig(pathname, flags) : -1;
}

int __open64_2(const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__open64_2"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, "__open64_2");
    return orig ? orig(pathname, flags) : -1;
}

int __openat_2(int dirfd, const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__openat_2"); if (h >= 0) return h;
    int (*orig)(int, const char *, int) = dlsym(RTLD_NEXT, "__openat_2");
    return orig ? orig(dirfd, pathname, flags) : -1;
}

int __openat64_2(int dirfd, const char *pathname, int flags) {
    int h = check_and_hijack(pathname, "__openat64_2"); if (h >= 0) return h;
    int (*orig)(int, const char *, int) = dlsym(RTLD_NEXT, "__openat64_2");
    return orig ? orig(dirfd, pathname, flags) : -1;
}
C_EOF

gcc -shared -fPIC -o /home/scanner/libusb_bridge.so /home/scanner/usb_bridge.c -ldl
echo "================================================="
echo " SUCCESS: The Fortified libusb bridge is compiled!"
echo "================================================="
PROOT_EOF
OUTER_EOF
bash fix_bridge_fortify.sh
```
## **5. In Termux: Compile the `Printer` bridge**
```
cd ~
cat << 'OUTER_EOF' > master_setup_v4.sh
#!/data/data/com.termux/files/usr/bin/bash

FD=$1
USB_PATH=$2

if [ -z "$FD" ]; then exit 1; fi
DEV=$(echo "$USB_PATH" | cut -d'/' -f6 | sed 's/^0*//')
if [ -z "$DEV" ]; then DEV="2"; fi
DEV_STR=$(echo "$USB_PATH" | cut -d'/' -f6)
if [ -z "$DEV_STR" ]; then DEV_STR="002"; fi

echo "[*] Cloning Sysfs..."
./universal_clone $FD $DEV

echo "[*] Automating CUPS Injection & Printer Setup..."
proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    -- env TERMUX_USB_FD="$FD" TERMUX_USB_DEV="$DEV_STR" bash -c "

    cat << 'C_EOF' > /home/scanner/usb_bridge_final.c
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
#define DEV_NUM_STR \"__DEV__\"

__attribute__((constructor)) void init(void) {
    fprintf(stderr, \"[BRIDGE] HARDCODED BRIDGE LOADED! Target FD: %d, Target DEV: %s\\n\", ANDROID_USB_FD, DEV_NUM_STR);
}

int close(int fd) {
    if (fd == ANDROID_USB_FD) return 0;
    int (*orig)(int) = dlsym(RTLD_NEXT, \"close\");
    return orig ? orig(fd) : -1;
}

int fcntl(int fd, int cmd, ...) {
    int (*orig)(int, int, ...) = dlsym(RTLD_NEXT, \"fcntl\");
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
    int (*orig)(int, unsigned long, ...) = dlsym(RTLD_NEXT, \"ioctl\");
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
    if (path && strstr(path, \"dev/bus/usb\") && strstr(path, DEV_NUM_STR)) {
        fprintf(stderr, \"[BRIDGE] HIJACKING %s for %s! Returning FD %d\\n\", func, path, ANDROID_USB_FD);
        return ANDROID_USB_FD;
    }
    return -1;
}

int open(const char *path, int flags, ...) {
    int h = check_and_hijack(path, \"open\"); if (h >= 0) return h;
    int (*orig)(const char *, int, ...) = dlsym(RTLD_NEXT, \"open\");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(path, flags, mode); }
    return orig(path, flags);
}
int open64(const char *path, int flags, ...) {
    int h = check_and_hijack(path, \"open64\"); if (h >= 0) return h;
    int (*orig)(const char *, int, ...) = dlsym(RTLD_NEXT, \"open64\");
    if (!orig) orig = dlsym(RTLD_NEXT, \"open\");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(path, flags, mode); }
    return orig(path, flags);
}
int openat(int dirfd, const char *path, int flags, ...) {
    int h = check_and_hijack(path, \"openat\"); if (h >= 0) return h;
    int (*orig)(int, const char *, int, ...) = dlsym(RTLD_NEXT, \"openat\");
    mode_t mode = 0; if (flags & O_CREAT) { va_list args; va_start(args, flags); mode = va_arg(args, int); va_end(args); return orig(dirfd, path, flags, mode); }
    return orig(dirfd, path, flags);
}

/* THE MISSING FORTIFY HOOKS */
int __open_2(const char *path, int flags) {
    int h = check_and_hijack(path, \"__open_2\"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, \"__open_2\"); return orig ? orig(path, flags) : -1;
}
int __open64_2(const char *path, int flags) {
    int h = check_and_hijack(path, \"__open64_2\"); if (h >= 0) return h;
    int (*orig)(const char *, int) = dlsym(RTLD_NEXT, \"__open64_2\"); return orig ? orig(path, flags) : -1;
}
int __openat_2(int dirfd, const char *path, int flags) {
    int h = check_and_hijack(path, \"__openat_2\"); if (h >= 0) return h;
    int (*orig)(int, const char *, int) = dlsym(RTLD_NEXT, \"__openat_2\"); return orig ? orig(dirfd, path, flags) : -1;
}

int socket(int domain, int type, int protocol) { int (*orig)(int, int, int) = dlsym(RTLD_NEXT, \"socket\"); return domain == 16 ? orig(AF_UNIX, type, 0) : orig(domain, type, protocol); }
int bind(int sockfd, const struct sockaddr *addr, socklen_t addrlen) { if (addr && addr->sa_family == 16) return 0; int (*orig)(int, const struct sockaddr *, socklen_t) = dlsym(RTLD_NEXT, \"bind\"); return orig(sockfd, addr, addrlen); }
int dbus_connection_send(void *c, void *m, void *s) { return 1; } void dbus_connection_flush(void *c) {} void dbus_connection_unref(void *c) {}
C_EOF

    sed -i \"s/__FD__/\$TERMUX_USB_FD/g\" /home/scanner/usb_bridge_final.c
    sed -i \"s/__DEV__/\$TERMUX_USB_DEV/g\" /home/scanner/usb_bridge_final.c

    gcc -shared -fPIC -o /usr/local/lib/libusb_bridge.so /home/scanner/usb_bridge_final.c -ldl
    chmod 777 /usr/local/lib/libusb_bridge.so

    if [ ! -f /usr/lib/cups/backend/usb-real ]; then
        mv /usr/lib/cups/backend/usb /usr/lib/cups/backend/usb-real
    fi

    chmod a-s /usr/lib/cups/backend/usb-real
    chmod 755 /usr/lib/cups/backend/usb-real

    cat << 'W_EOF' > /usr/lib/cups/backend/usb
#!/bin/bash
export LD_LIBRARY_PATH=\"/usr/local/lib\"
export LD_PRELOAD=\"/usr/local/lib/libusb_bridge.so\"
export LIBUSB_DEBUG=4
exec /usr/lib/cups/backend/usb-real \"\$@\"
W_EOF
    chmod 755 /usr/lib/cups/backend/usb

    pkill cupsd || true
    /usr/sbin/cupsd
    sleep 3

    echo \"-----------------------------------------\"
    echo \"[*] Forcing USB Driver Probe...\"
    /usr/lib/cups/backend/usb
    echo \"-----------------------------------------\"

    URI=\$(/usr/lib/cups/backend/usb 2>/dev/null | grep \"^direct usb\" | awk '{print \$2}' | tr -d '\"')

    if [ -n \"\$URI\" ]; then
        echo \"[SUCCESS] Extracted URI: \$URI\"
        echo \"[*] Adding printer queue 'HP_Printer'...\"
        lpadmin -p HP_Printer -E -v \"\$URI\" -m everywhere
        echo \"[SUCCESS] PRINTER FULLY CONFIGURED!\"
    else
        echo \"[!] Failed to extract URI. Check logs above.\"
    fi
    pkill cupsd
"
OUTER_EOF

chmod +x master_setup_v4.sh
```
## **6. Script to start the `Scanner`.**
```
cd ~
cat << 'EOF' > run_hardware.sh
#!/data/data/com.termux/files/usr/bin/bash

FD=$1
USB_PATH=$2

if [ -z "$FD" ]; then
    echo "Error: No File Descriptor provided."
    exit 1
fi

DEV=$(echo "$USB_PATH" | cut -d'/' -f6 | sed 's/^0*//')
if [ -z "$DEV" ]; then DEV="2"; fi

echo "1. Cloning Native Hardware to Sysfs..."
./universal_clone $FD $DEV

echo ""
echo "2. Running lsusb through Custom libusb & C-Bridge..."

# We create a unique filename using the current timestamp
OUT_FILE="$HOME/scan_$(date +%s).png"


proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    -- env LD_LIBRARY_PATH="/usr/local/lib"  TERMUX_USB_FD="$FD" LIBUSB_DEBUG=4 TARGET_USB_PATH="$USB_PATH" LD_PRELOAD="/home/scanner/libusb_bridge.so" \
    hp-scan -g --mode=color --res=300 -o "$OUT_FILE"
echo "Scan successfully saved to: $OUT_FILE"
EOF
chmod +x run_hardware.sh
```
## **7. Script to start the `Printer`.**
```
cd ~
cat << 'OUTER_EOF' > print_document.sh
#!/data/data/com.termux/files/usr/bin/bash

FD=$1
USB_PATH=$2

if [ -z "$FILE_TO_PRINT" ]; then
    echo "[!] Error: FILE_TO_PRINT variable not set."
    exit 1
fi

DEV=$(echo "$USB_PATH" | cut -d'/' -f6 | sed 's/^0*//')
[ -z "$DEV" ] && DEV="2"
DEV_STR=$(echo "$USB_PATH" | cut -d'/' -f6)
[ -z "$DEV_STR" ] && DEV_STR="002"

./universal_clone $FD $DEV

proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    --bind "$HOME:$HOME" \
    -- env TERMUX_USB_FD="$FD" TERMUX_USB_DEV="$DEV_STR" FILE_TO_PRINT="$FILE_TO_PRINT" bash -c "

    # 1. Rebuild Bridge
    sed -i \"s/#define ANDROID_USB_FD .*/#define ANDROID_USB_FD \$TERMUX_USB_FD/\" /home/scanner/usb_bridge_final.c
    sed -i \"s/#define DEV_NUM_STR .*/#define DEV_NUM_STR \\\"\$TERMUX_USB_DEV\\\"/\" /home/scanner/usb_bridge_final.c
    gcc -shared -fPIC -o /usr/local/lib/libusb_bridge.so /home/scanner/usb_bridge_final.c -ldl

    # 2. Render PDF to ZJS (Added -P for Hardware Padding/Reset)
    echo \"[*] Rendering PDF...\"
    ghostscript -q -dBATCH -dSAFER -dNOPAUSE -sDEVICE=pbmraw -sPAPERSIZE=a4 -r600x600 -sOutputFile=- \"\$FILE_TO_PRINT\" | foo2zjs -z1 -p9 -P > /tmp/out.zjs

    # 3. Validation
    SIZE_KB=\$(du -k /tmp/out.zjs | awk '{print \$1}')
    echo \"[*] Rendered Size: \${SIZE_KB}KB\"

    # 4. Push to hardware via Bridge
    export LD_PRELOAD=\"/usr/local/lib/libusb_bridge.so\"
    export DEVICE_URI=\"usb://HP/LaserJet%20Professional%20M1136%20MFP?serial=000000000QHCL8QVPR1a\"
    
    echo \"[*] Sending data to USB...\"
    /usr/lib/cups/backend/usb 1 user \"Job\" 1 \"\" \"/tmp/out.zjs\"
    
    echo \"[*] Finished. If paper didn't pull, check printer lights.\"
    sleep 5
"
OUTER_EOF
chmod +x print_document.sh
```
## **8. Connect the Printer/Scanner and give permission and extract the device uri and serial number (needed to put in print_document.sh script manually).**
```
termux-usb -l
```
```
cd ~
termux-usb -r -e ./master_setup_v4.sh /dev/bus/usb/001/002
```
## **9. Commands to `Scanner` and `Printer`.**
### **To `print`:**
```
cd ~
FILE_TO_PRINT=$HOME/downloads/your_document.pdf termux-usb -r -e ./print_document.sh /dev/bus/usb/001/002
```
### **To `scan`:**
```
cd ~
termux-usb -r -e ./run_hardware.sh /dev/bus/usb/001/002
```
```
cd ~
mv $PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu/root/hpscan*.* ~/ 2>/dev/null || echo "Not in Ubuntu root, checking current folder..."

# Check if it's here
ls -l ~/hpscan*.*
```
## **10. Termux-widget Script for ease**
### **For `Scan`:**
```
cd ~
cat << 'EOF' > ~/.shortcuts/quick_scan.sh
#!/data/data/com.termux/files/usr/bin/bash

# 1. Cleanly extract the USB path (removes brackets, quotes, and commas)
USB_DEVICE=$(termux-usb -l | grep "/dev/bus/usb" | tr -d '", ')

if [ -z "$USB_DEVICE" ]; then
    termux-toast "Error: Scanner not found. Check USB connection."
    exit 1
fi

termux-toast "Starting HP Scan: $USB_DEVICE"

# 2. Trigger the scan
# We use the absolute path to your home directory script
termux-usb -r -e $HOME/run_hardware.sh "$USB_DEVICE"

# 3. Handle the file moving
# Note: Since scanning takes time, we wait for the scan process to finish 
# before trying to move the files.
sleep 5
mv $PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu/root/hpscan*.* $HOME/ 2>/dev/null

if ls $HOME/hpscan*.* 1> /dev/null 2>&1; then
    termux-toast "Scan complete!"
fi
EOF
```
### **For `Print`:**
```
# For Community
```

