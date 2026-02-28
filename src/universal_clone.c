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

void fetch_usb_string(int fd, uint8_t index, char *out, int out_len) {
    if (index == 0) { snprintf(out, out_len, "Unknown"); return; }
    
    uint8_t data[255];
    struct usbdevfs_ctrltransfer ctrl = {
        .bRequestType = 0x80,
        .bRequest = 0x06,
        .wValue = (3 << 8) | index,
        .wIndex = 0x0409,
        .wLength = sizeof(data),
        .data = data,
        .timeout = 1000
    };
    
    if (ioctl(fd, USBDEVFS_CONTROL, &ctrl) > 2 && data[1] == 3) {
        int len = data[0];
        int j = 0;

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

    char cmd[512];
    snprintf(cmd, sizeof(cmd), "rm -rf %s/fake_usb", home); system(cmd);
    snprintf(cmd, sizeof(cmd), "mkdir -p %s", dev_dir); system(cmd);
    snprintf(cmd, sizeof(cmd), "mkdir -p %s/fake_usb/dev/bus/usb/001", home); system(cmd);

    uint8_t buf[2048];
    lseek(fd, 0, SEEK_SET);
    int len = read(fd, buf, sizeof(buf));
    if (len < 18) { printf("Failed to read FD\n"); return 1; }

    char desc_path[512];
    snprintf(desc_path, sizeof(desc_path), "%s/descriptors", dev_dir);
    int df = open(desc_path, O_WRONLY|O_CREAT|O_TRUNC, 0644);
    if (df >= 0) { write(df, buf, len); close(df); }

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

    char str_buf[256];
    fetch_usb_string(fd, buf[14], str_buf, sizeof(str_buf)); write_str(dev_dir, "manufacturer", str_buf);
    fetch_usb_string(fd, buf[15], str_buf, sizeof(str_buf)); write_str(dev_dir, "product", str_buf);
    fetch_usb_string(fd, buf[16], str_buf, sizeof(str_buf)); write_str(dev_dir, "serial", str_buf);

    int offset = 18;
    int current_config = 1;
    
    while (offset < len) {
        uint8_t d_len = buf[offset];
        uint8_t d_type = buf[offset + 1];
        if (d_len == 0) break;
        
        if (d_type == 2) {
            current_config = buf[offset + 5];
        } 
        else if (d_type == 4) {
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
