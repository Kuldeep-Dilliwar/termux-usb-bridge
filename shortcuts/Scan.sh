#!/data/data/com.termux/files/usr/bin/bash

USB_DEVICE=$(termux-usb -l | grep "/dev/bus/usb" | tr -d '", ')

if [ -z "$USB_DEVICE" ]; then
    termux-toast "Error: Scanner not found. Check USB connection."
    exit 1
fi

termux-toast "Starting HP Scan: $USB_DEVICE"
termux-usb -r -e $PREFIX/bin/run_scanner.sh "$USB_DEVICE"

sleep 5
mv $PREFIX/var/lib/proot-distro/installed-rootfs/ubuntu/root/hpscan*.* $HOME/ 2>/dev/null

if ls $HOME/hpscan*.* 1> /dev/null 2>&1; then
    termux-toast "Scan complete!"
fi
