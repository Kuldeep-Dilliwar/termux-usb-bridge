# termux-USB-bridge

**Bring true desktop-class Printer and Scanner support to Termux (No Root Required!)**

> **⚠️ DISCLAIMER: RUN AT YOUR OWN RISK ⚠️**
> **Please note:** This setup uses `proot` to create a "fake root" sandbox so the Linux drivers can work. Because of this, strict security apps (like banking or mobile carrier apps) might temporarily throw a **"Device is Rooted" false alarm** if you open them while scanning or printing.
> **Your device is NOT actually rooted.** If you see this warning, simply finish your print/scan, close Termux, and clear the app data of the affected security app. It will instantly return to normal.
> *(for me this happen only once, no idea why it only happened once, and never saw the false alerm again).*

## 📱 Prerequisites: Required Android Apps

*Important: Do not install Termux from the Google Play Store, as those versions are no longer supported and will break.* Please install the latest versions of the following apps directly from F-Droid:

* [Termux](https://f-droid.org/en/packages/com.termux/) (The main terminal emulator)
* [Termux:API](https://f-droid.org/en/packages/com.termux.api/) (Required for the USB permission popups to work)
* [Termux:Widget](https://f-droid.org/en/packages/com.termux.widget/) (Optional but recommended: For one-tap home screen shortcuts)

## 🚀 Automated Installation

You no longer need to copy and paste huge blocks of code. Just open Termux and run these commands to install everything automatically:

```bash
pkg update -y && pkg install -y make git
git clone https://github.com/Kuldeep-Dilliwar/termux-USB-bridge.git
cd termux-USB-bridge
make install

```

*(Note: During installation, the HP Plugin script may pause and ask you to accept its license agreement. Press `d` to download or `y` to accept when prompted.)*

---

## 🖨️ How to Print

Plug in your printer via OTG, grant the Android USB permission popup, and type:

```bash
termux-print /path/to/your/document.pdf

```

**Advanced Print Options:**
You can customize paper size, scaling, hardware protocols, and even pass raw Ghostscript flags:

* `--a4` : Print on A4 paper (Default)
* `--letter` : Print on US Letter paper
* `--fit` : Scale the PDF to fit inside printable margins
* `--res` : Set DPI resolution (Default: `1200x600`)
* `--model` : Set foo2zjs protocol (Default: `-z1`)
* `--gs-args` : Pass custom flags directly to Ghostscript (Ensure you wrap the flags in quotes).

*Example 1: Older HP 1020 on Letter paper:*

```bash
termux-print --res 600x600 --model -z0 --letter --fit document.pdf

```

*Example 2: Print only pages 2 through 4 in Grayscale using Ghostscript arguments:*

```bash
termux-print --gs-args "-dFirstPage=2 -dLastPage=4 -sColorConversionStrategy=Gray" document.pdf

```

---

## 📸 How to Scan

Plug in your scanner via OTG, grant the Android USB permission popup, and type:

```bash
termux-scan

```

Your scanned images will be automatically saved as high-quality `.jpg` files to the `~/scans` folder in your Termux home directory! This tool uses **SANE** under the hood, meaning it supports hundreds of scanners natively across brands like HP, Epson, Brother, and Canon.

**Advanced Scan Options:**
You can customize the scan resolution, color mode, or pass raw SANE arguments:

* `--res` : Set DPI resolution (Default: `300`)
* `--mode` : Set color mode (`Color`, `Gray`, `Lineart`. Default: `Color`)
* `--scan-args` : Pass custom flags directly to SANE (Ensure you wrap the flags in quotes).

*Example 1: Scan in Grayscale at 600 DPI, and specify an Automatic Document Feeder (ADF):*

```bash
termux-scan --res 600 --mode Gray --scan-args "--source 'ADF'"

```

*Example 2: Restrict scan area to standard A4 size (Useful to prevent flatbed scanners from scanning blank space up to Legal size):*

```bash
termux-scan --scan-args "-x 210 -y 297"

```

**Viewing Your Scans in Android:**
Because Termux stores files securely, you need to copy them to your public phone storage to see them in your Gallery app.

1. Run `termux-setup-storage` and grant permission (you only need to do this once).
2. Copy your scans to your phone's public Downloads folder by typing: `cp ~/scans/*.jpg ~/storage/downloads/`

---

## ⚡ Home Screen Shortcuts

This installer automatically creates Android home screen widgets for you!
Since you installed the **Termux:Widget** app from F-Droid, you can just tap the "Scan" or "Print" buttons directly from your phone's home screen without ever opening the terminal.

---
---

> ### 📝 Project Scope & Limitations
> 
> 
> * **The Primary Goal:** This project is a **proof-of-concept** to demonstrate that you can run Linux user-space hardware drivers (which normally require `root` or `DBUS`) inside a rootless Android PRoot environment.
> * **Hardware Compatibility:** This setup works flawlessly for my older HP printer and scanner. However, because every printer brand speaks a completely different language (ZjStream, SPL, CAPT, etc.), it may not work out-of-the-box for your specific model. I cannot physically test every printer in existence.
> * **Modern Printers:** If you have a modern Wi-Fi printer, you likely don't need this repository—just download the official app from the Google Play Store.
> * **Make It Your Own:** I encourage you to fork this repository, check out the custom C-bridge in the `src/` folder, and modify the bash scripts to route your specific printer's driver!
> 
> 
