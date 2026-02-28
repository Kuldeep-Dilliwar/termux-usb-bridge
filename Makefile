# Makefile for Termux USB Bridge

PREFIX ?= /data/data/com.termux/files/usr
PWD := $(shell pwd)
BIN_DIR := bin
SRC_DIR := src
SCRIPT_DIR := scripts

all: build-native build-proot

install-deps:
	@echo "Installing Termux dependencies..."
	pkg update -y && pkg install -y clang termux-api jq proot-distro
	@echo "Installing Ubuntu PRoot..."
	proot-distro install ubuntu || true
	@echo "Installing Ubuntu dependencies..."
	proot-distro login ubuntu -- apt update
	proot-distro login ubuntu -- DEBIAN_FRONTEND=noninteractive apt install -y git gcc cups wget curl hplip dialog libtool usbutils autoconf automake sane-utils pkg-config ghostscript build-essential cups-core-drivers printer-driver-foo2zjs
	
	@echo "Compiling Custom libusb (--disable-udev)..."
	proot-distro login ubuntu -- bash -c "if [ ! -f /usr/local/lib/libusb-1.0.so ]; then git clone --depth 1 https://github.com/libusb/libusb.git /tmp/libusb && cd /tmp/libusb && ./autogen.sh --disable-udev && make -j4 && make install && ldconfig && rm -rf /tmp/libusb; else echo 'libusb already compiled.'; fi"
	
	@echo "Installing HP Proprietary Plugin..."
	proot-distro login ubuntu -- bash -c "hp-plugin -i -g || true"

build-native:
	@echo "Compiling Universal Clone for Termux..."
	mkdir -p $(BIN_DIR)
	gcc -o $(BIN_DIR)/universal_clone $(SRC_DIR)/universal_clone.c

build-proot:
	@echo "Compiling Scanner Bridge inside Ubuntu PRoot..."
	mkdir -p $(BIN_DIR)
	proot-distro login ubuntu --bind "$(PWD):/build" -- bash -c "gcc -shared -fPIC -o /build/$(BIN_DIR)/libusb_scanner.so /build/$(SRC_DIR)/scanner_bridge.c -ldl"

install: install-deps all
	@echo "Installing scripts and binaries..."
	cp $(BIN_DIR)/universal_clone $(PREFIX)/bin/
	chmod +x $(PREFIX)/bin/universal_clone
	
	proot-distro login ubuntu --bind "$(PWD):/build" -- bash -c "cp /build/$(BIN_DIR)/libusb_scanner.so /usr/local/lib/ && chmod 777 /usr/local/lib/*.so"
	
	@echo "Configuring CUPS USB Wrapper..."
	proot-distro login ubuntu -- bash -c "if [ ! -f /usr/lib/cups/backend/usb-real ]; then mv /usr/lib/cups/backend/usb /usr/lib/cups/backend/usb-real; fi"
	proot-distro login ubuntu -- bash -c "chmod a-s /usr/lib/cups/backend/usb-real && chmod 755 /usr/lib/cups/backend/usb-real"
	proot-distro login ubuntu -- bash -c "echo '#!/bin/bash' > /usr/lib/cups/backend/usb"
	proot-distro login ubuntu -- bash -c "echo 'export LD_LIBRARY_PATH=\"/usr/local/lib\"' >> /usr/lib/cups/backend/usb"
	proot-distro login ubuntu -- bash -c "echo 'export LD_PRELOAD=\"/usr/local/lib/libusb_printer.so\"' >> /usr/lib/cups/backend/usb"
	proot-distro login ubuntu -- bash -c "echo 'export LIBUSB_DEBUG=4' >> /usr/lib/cups/backend/usb"
	proot-distro login ubuntu -- bash -c "echo 'exec /usr/lib/cups/backend/usb-real \"\$$@\"' >> /usr/lib/cups/backend/usb"
	proot-distro login ubuntu -- bash -c "chmod 755 /usr/lib/cups/backend/usb"
	
	@echo "Copying worker scripts and wrappers to global bin..."
	cp $(SCRIPT_DIR)/run_scanner.sh $(PREFIX)/bin/
	cp $(SCRIPT_DIR)/run_printer.sh $(PREFIX)/bin/
	cp $(SCRIPT_DIR)/termux-scan $(PREFIX)/bin/
	cp $(SCRIPT_DIR)/termux-print $(PREFIX)/bin/
	chmod +x $(PREFIX)/bin/run_*.sh $(PREFIX)/bin/termux-*
	
	mkdir -p ~/.shortcuts
	cp shortcuts/* ~/.shortcuts/
	chmod +x ~/.shortcuts/*
	
	@echo "Installation Complete!"

clean:
	rm -rf $(BIN_DIR)