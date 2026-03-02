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

# SAFETY NET: Provide defaults in case the script is run directly from the Home Screen Shortcut!
[ -z "$SCAN_RES" ] && export SCAN_RES="300"
[ -z "$SCAN_MODE" ] && export SCAN_MODE="Color"

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

echo "3. Running scanimage through Custom libusb & C-Bridge..."
mkdir -p "$HOME/scans"

# THE FIX: Switched extension to .jpg
OUT_FILE="$HOME/scans/scan_$(date +%s).jpg"

# THE FIX: Switched SANE format to jpeg
proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    --bind "$HOME:$HOME" \
    -- env LD_LIBRARY_PATH="/usr/local/lib" TERMUX_USB_FD="$FD" LIBUSB_DEBUG="${BRIDGE_LOG_LEVEL:-0}" TARGET_USB_PATH="$USB_PATH" LD_PRELOAD="/usr/local/lib/libusb_bridge.so" SCAN_MODE="$SCAN_MODE" SCAN_RES="$SCAN_RES" SCAN_EXTRA_ARGS="$SCAN_EXTRA_ARGS" OUT_FILE="$OUT_FILE" \
    bash -c "scanimage --format=jpeg --mode=\"\$SCAN_MODE\" --resolution=\"\$SCAN_RES\" \$SCAN_EXTRA_ARGS -o \"\$OUT_FILE\""

if [ -f "$OUT_FILE" ]; then
    echo "Scan successfully saved to: $OUT_FILE"
else
    echo "Error: Scan failed. Check if your scanner is supported by SANE."
fi
