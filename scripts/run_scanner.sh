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
universal_clone "$FD" "$DEV"

echo "2. Running lsusb through Custom libusb & C-Bridge..."

# Create the scans directory if it doesn't exist
mkdir -p "$HOME/scans"
OUT_FILE="$HOME/scans/scan_$(date +%s).png"

proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    -- env LD_LIBRARY_PATH="/usr/local/lib" TERMUX_USB_FD="$FD" LIBUSB_DEBUG=4 TARGET_USB_PATH="$USB_PATH" LD_PRELOAD="/usr/local/lib/libusb_scanner.so" \
    hp-scan -g --mode=color --res=300 -o "$OUT_FILE"

echo "Scan successfully saved to: $OUT_FILE"
