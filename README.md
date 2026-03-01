# termux-USB-bridge

**Bring true desktop-class (HP) Printer and Scanner support to Termux (No Root Required!)**

> **⚠️ DISCLAIMER: RUN AT YOUR OWN RISK ⚠️**
> **Please note:** This setup uses `proot` to create a "fake root" sandbox so the Linux drivers can work. Because of this, strict security apps (like banking or mobile carrier apps) might temporarily throw a **"Device is Rooted" false alarm** if you open them while scanning or printing.
> **Your device is NOT actually rooted.** If you see this warning, simply finish your print/scan, close Termux, and clear the app data of the affected security app. It will instantly return to normal.

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
You can customize paper size, scaling, and hardware protocols:

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

Your scanned images will be automatically saved to the `~/scans` folder in your Termux home directory!

---

## ⚡ Home Screen Shortcuts

This installer automatically creates Android home screen widgets for you!
Since you installed the **Termux:Widget** app from F-Droid, you can just tap the "Scan" or "Print" buttons directly from your phone's home screen without ever opening the terminal.

---

