#!/data/data/com.termux/files/usr/bin/bash

FD=$1
USB_PATH=$2
REPO_DIR="$HOME/termux-USB-bridge"

if [ -z "$FD" ]; then
    echo "Error: No File Descriptor provided."
    exit 1
fi

DEV=$(echo "$USB_PATH" | cut -d'/' -f6 | sed 's/^0*//')
[ -z "$DEV" ] && DEV="2"
DEV_STR=$(echo "$USB_PATH" | cut -d'/' -f6)
[ -z "$DEV_STR" ] && DEV_STR="002"

echo "1. Cloning Native Hardware to Sysfs..."
universal_clone "$FD" "$DEV"

echo "2. Building Universal Bridge..."
proot-distro login ubuntu \
    --bind "$REPO_DIR:/repo" \
    -- env TERMUX_USB_FD="$FD" TERMUX_USB_DEV="$DEV_STR" bash -c "
    cp /repo/src/usb_bridge_template.c /tmp/usb_bridge.c
    sed -i \"s/__FD__/\$TERMUX_USB_FD/g\" /tmp/usb_bridge.c
    sed -i \"s/__DEV__/\$TERMUX_USB_DEV/g\" /tmp/usb_bridge.c
    gcc -shared -fPIC -o /usr/local/lib/libusb_bridge.so /tmp/usb_bridge.c -ldl
"

echo "3. Running lsusb -v through Custom libusb & C-Bridge..."
proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    -- env LD_LIBRARY_PATH="/usr/local/lib" TERMUX_USB_FD="$FD" LIBUSB_DEBUG=4 LD_PRELOAD="/usr/local/lib/libusb_bridge.so" \
    bash -c "lsusb -v -s 1:$DEV"
