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

# --- SAFETY NETS ---
# Android termux-usb strips environment variables. These guarantee Ghostscript never crashes.
[ -z "$PRINT_PAPER_GS" ] && export PRINT_PAPER_GS="a4"
[ -z "$PRINT_PAPER_CUPS" ] && export PRINT_PAPER_CUPS="A4"
[ -z "$FOO_PAPER" ] && export FOO_PAPER="-p9"
[ -z "$PRINT_RES" ] && export PRINT_RES="1200x600"
[ -z "$PRINT_MODEL" ] && export PRINT_MODEL="-z1"
# -------------------

universal_clone "$FD" "$DEV"

proot-distro login ubuntu \
    --bind "$HOME/fake_usb/sys/bus/usb:/sys/bus/usb" \
    --bind "$HOME/fake_usb/dev/bus/usb:/dev/bus/usb" \
    --bind "$HOME:$HOME" \
    --bind "$REPO_DIR:/repo" \
    -- env TERMUX_USB_FD="$FD" TERMUX_USB_DEV="$DEV_STR" LIBUSB_DEBUG="${BRIDGE_LOG_LEVEL:-0}" FILE_TO_PRINT="$FILE_TO_PRINT" PRINT_PAPER_GS="$PRINT_PAPER_GS" PRINT_PAPER_CUPS="$PRINT_PAPER_CUPS" PRINT_FIT_GS="$PRINT_FIT_GS" PRINT_FIT_CUPS="$PRINT_FIT_CUPS" FOO_PAPER="$FOO_PAPER" PRINT_RES="$PRINT_RES" PRINT_MODEL="$PRINT_MODEL" GS_EXTRA_ARGS="$GS_EXTRA_ARGS" FORCE_DRIVER="$FORCE_DRIVER" bash -c "

    # 1. Rebuild Unified Bridge dynamically
    cp /repo/src/usb_bridge_template.c /tmp/usb_bridge.c
    sed -i \"s/__FD__/\$TERMUX_USB_FD/g\" /tmp/usb_bridge.c
    sed -i \"s/__DEV__/\$TERMUX_USB_DEV/g\" /tmp/usb_bridge.c
    gcc -shared -fPIC -o /usr/local/lib/libusb_bridge.so /tmp/usb_bridge.c -ldl

    # 2. Discover Hardware
    export LD_PRELOAD=\"/usr/local/lib/libusb_bridge.so\"
    echo \"[*] Auto-discovering Printer URI...\"
    DISCOVERED_URI=\$(/usr/lib/cups/backend/usb 2>/dev/null | grep \"^direct usb\" | awk '{print \$2}' | tr -d '\"')
    
    if [ -z \"\$DISCOVERED_URI\" ]; then
        echo \"[!] Failed to auto-discover Printer URI. Check your connection.\"
        exit 1
    fi
    echo \"[*] Found Printer: \$DISCOVERED_URI\"
    HW_NAME=\$(echo \"\$DISCOVERED_URI\" | awk -F'://' '{print \$2}' | cut -d'?' -f1 | sed 's|/| |g' | sed 's/%20/ /g' | sed 's/_/ /g')
    MODEL_NUM=\$(echo \"\$HW_NAME\" | grep -o '[0-9]\{3,4\}' | head -n 1)
    SHORT_NUM=\$(echo \"\$MODEL_NUM\" | cut -c1-3)

    # 3. HYBRID ROUTING ENGINE
    if echo \"\$HW_NAME\" | grep -i -E \"M1136|M1132|P1102|P1005|P1006|P1007|P1008|P1505|P2014|P2035|M1005|M1120|M1212|M1319|P1566|P1606|CP1025|1022|1020|1018|1005|1000\"; then
        echo \"[*] TRICKY HOST-BASED PRINTER DETECTED!\"
        echo \"[*] Bypassing CUPS to use raw Ghostscript -> foo2zjs direct pipeline...\"
        
        ghostscript -q -dBATCH -dSAFER -dNOPAUSE -sDEVICE=pbmraw -sPAPERSIZE=\"\$PRINT_PAPER_GS\" \$PRINT_FIT_GS -r\"\$PRINT_RES\" \$GS_EXTRA_ARGS -sOutputFile=- \"\$FILE_TO_PRINT\" | foo2zjs \"\$PRINT_MODEL\" \"\$FOO_PAPER\" -P > /tmp/out.raw
        
    else
        echo \"[*] Standard Printer Detected. Routing through CUPS Auto-Detection Engine...\"
        
        if ! pgrep -x \"cupsd\" > /dev/null; then
            echo \"[*] Booting CUPS Daemon...\"
            /usr/sbin/cupsd -f &
            CUPS_PID=\$!
            sleep 3 
        fi

        if [ -n \"\$FORCE_DRIVER\" ]; then
            PPD_MATCH=\$(lpinfo -m | grep -i \"\$FORCE_DRIVER\" | head -n 1 | awk '{print \$1}')
        else
            # Priority 1: Exact Number Match
            if [ -n \"\$MODEL_NUM\" ]; then
                PPD_MATCH=\$(lpinfo -m | grep -i \"\$MODEL_NUM\" | grep -v -i \"hplip\|hpcups\" | head -n 1 | awk '{print \$1}')
            fi

            # Priority 2: Fuzzy Match (Catches bundled drivers like Samsung ML-186x or ML-1865)
            if [ -z \"\$PPD_MATCH\" ] && [ -n \"\$SHORT_NUM\" ]; then
                PPD_MATCH=\$(lpinfo -m | grep -i \"\$SHORT_NUM\" | grep -v -i \"hplip\|hpcups\" | head -n 1 | awk '{print \$1}')
            fi
        fi

        # Priority 3: Architecture Fallbacks
        if [ -z \"\$PPD_MATCH\" ]; then
            if echo \"\$HW_NAME\" | grep -i -q \"Samsung\"; then
                echo \"[!] No exact match. Falling back to generic Samsung SPL driver...\"
                PPD_MATCH=\$(lpinfo -m | grep -i \"splix\" | head -n 1 | awk '{print \$1}')
            else
                echo \"[!] No exact driver found. Falling back to Generic PCL 6...\"
                PPD_MATCH=\"drv:///sample.drv/generpcl.ppd\" 
            fi
        else
            echo \"[*] Assigned Driver: \$PPD_MATCH\"
        fi

        echo \"[*] Generating Printer Profile...\"
        lpadmin -p \"TermuxPrinter\" -E -v \"\$DISCOVERED_URI\" -m \"\$PPD_MATCH\"

        echo \"[*] Compiling Document to Native Printer Format (cupsfilter)...\"
        cupsfilter -P /etc/cups/ppd/TermuxPrinter.ppd -m printer/foo -o media=\"\$PRINT_PAPER_CUPS\" \$PRINT_FIT_CUPS \"\$FILE_TO_PRINT\" > /tmp/out.raw 2>/tmp/filter_debug.log
    fi
    
    SIZE_KB=\$(du -k /tmp/out.raw | awk '{print \$1}')
    echo \"[*] Rendered Size: \${SIZE_KB}KB\"

    # 4. Push to Hardware via Bridge
    echo \"[*] Sending raw data to USB...\"
    export DEVICE_URI=\"\$DISCOVERED_URI\"
    /usr/lib/cups/backend/usb 1 user \"Job\" 1 \"\" \"/tmp/out.raw\"
    
    echo \"[*] Finished. If paper didn't pull, check printer lights.\"
    
    if [ -n \"\$CUPS_PID\" ]; then
        sleep 3
        kill \$CUPS_PID 2>/dev/null || true
    fi
"
