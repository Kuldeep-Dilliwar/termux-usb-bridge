#!/data/data/com.termux/files/usr/bin/bash

FD=$1
USB_PATH=$2
REPO_DIR="$HOME/termux-USB-bridge"

if [ -z "$FILE_TO_PRINT" ]; then
    echo "[!] Error: FILE_TO_PRINT variable not set."
    exit 1
fi

DEV=$(echo "$USB_PATH" | cut -d'/' -f6 | sed 's/^0*//')
[ -z "$DEV" ] && DEV="2"
DEV_STR=$(echo "$USB_PATH" | cut -d'/' -f6)
[ -z "$DEV_STR" ] && DEV_STR="002"

# Map paper sizes to hardware codes for foo2zjs
FOO_PAPER="-p9" # Default A4
if [ "$PRINT_PAPER" = "letter" ]; then
    FOO_PAPER="-p1"
fi

universal_clone "$FD" "$DEV"

proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    --bind "$HOME:$HOME" \
    --bind "$REPO_DIR:/repo" \
    -- env TERMUX_USB_FD="$FD" TERMUX_USB_DEV="$DEV_STR" FILE_TO_PRINT="$FILE_TO_PRINT" PRINT_PAPER="$PRINT_PAPER" PRINT_FIT="$PRINT_FIT" FOO_PAPER="$FOO_PAPER" PRINT_RES="$PRINT_RES" PRINT_MODEL="$PRINT_MODEL" GS_EXTRA_ARGS="$GS_EXTRA_ARGS" bash -c "

    # 1. Rebuild Bridge from Template
    cp /repo/src/printer_bridge_template.c /tmp/printer_bridge.c
    sed -i \"s/__FD__/\$TERMUX_USB_FD/g\" /tmp/printer_bridge.c
    sed -i \"s/__DEV__/\$TERMUX_USB_DEV/g\" /tmp/printer_bridge.c
    gcc -shared -fPIC -o /usr/local/lib/libusb_printer.so /tmp/printer_bridge.c -ldl

    # 2. Render PDF to ZJS (Using fully dynamic settings)
    echo \"[*] Rendering PDF (Size: \$PRINT_PAPER, Res: \$PRINT_RES, Model: \$PRINT_MODEL)...\"
    
    # \$GS_EXTRA_ARGS is placed unquoted here to allow bash word-splitting for multiple flags
    ghostscript -q -dBATCH -dSAFER -dNOPAUSE -sDEVICE=pbmraw -sPAPERSIZE=\"\$PRINT_PAPER\" \$PRINT_FIT -r\"\$PRINT_RES\" \$GS_EXTRA_ARGS -sOutputFile=- \"\$FILE_TO_PRINT\" | foo2zjs \"\$PRINT_MODEL\" \"\$FOO_PAPER\" -P > /tmp/out.zjs

    # 3. Validation
    SIZE_KB=\$(du -k /tmp/out.zjs | awk '{print \$1}')
    echo \"[*] Rendered Size: \${SIZE_KB}KB\"

    # 4. Push to hardware via Bridge
    export LD_PRELOAD=\"/usr/local/lib/libusb_printer.so\"
    
    echo \"[*] Auto-discovering Printer URI...\"
    DISCOVERED_URI=\$(/usr/lib/cups/backend/usb 2>/dev/null | grep \"^direct usb\" | awk '{print \$2}' | tr -d '\"')
    
    if [ -z \"\$DISCOVERED_URI\" ]; then
        echo \"[!] Failed to auto-discover Printer URI. Check your connection.\"
        exit 1
    fi
    
    echo \"[*] Using Discovered URI: \$DISCOVERED_URI\"
    export DEVICE_URI=\"\$DISCOVERED_URI\"
    
    echo \"[*] Sending data to USB...\"
    /usr/lib/cups/backend/usb 1 user \"Job\" 1 \"\" \"/tmp/out.zjs\"
    
    echo \"[*] Finished. If paper didn't pull, check printer lights.\"
    sleep 5
"
