<!-- Draft for the XDA thread (Mi 11 Lite 5G / renoir forum, "ROMs, Kernels, Recoveries & Other Development").
     Fill in the GitHub link once the repository is public. -->

# [ROM][PORT][16] One UI 8.0 for Mi 11 Lite 5G (renoir)

<!-- XDA: attach docs/xda/banner.png here (Upload > insert "Full image") -->
[banner.png]

Samsung's **One UI 8.0** (Galaxy S23 firmware, Android 16) running on the Mi 11 Lite 5G, on renoir's own MIUI
vendor. SELinux enforcing.

Download the zip, run `flash_all.bat` (Windows) or `flash_all.sh` (Linux/macOS) from fastboot, done.
Everything is **open source**: the GitHub repository has every script and fix that went into the zip, so you can
check what's inside – or build the same images yourself from the official firmware.

## Screenshots

<!-- XDA: attach docs/xda/screenshots.png here, ideally inside a [SPOILER="Screenshots"] block -->
[screenshots.png]

## What works

- Boot, setup, One UI launcher and Samsung apps
- Wi-Fi, mobile network (calls/SMS/VoLTE: please report)
- Bluetooth incl. audio (AirPods etc.)
- Fingerprint (in-display), unlock
- Punch-hole cutout, rounded corners, 60/90 Hz, brightness
- Vibration incl. keyboard haptics
- Cameras in GCam and third-party apps
- Sensors

## Camera

**There is no camera app in the ROM** (Samsung's needs Samsung's camera hardware). **Install a GCam port** for
the Mi 11 Lite 5G, e.g. from celsoazevedo.com/files/android/google-camera – it works without problems, as do other
camera apps and the camera in browsers and messengers.

## Known issues

- adb/USB data needs one cable replug after every boot
- Samsung Core Services and Theme Center crash once at boot (harmless)
- Galaxy Store may show error 2300:1004
- Fingerprint ring animation missing
- Knox features (Samsung Wallet, Secure Folder, Samsung Pass) won't work
- Not verified yet: NFC, GPS, call microphone – reports welcome

## Requirements

- Unlocked bootloader
- Stock **MIUI V14.0.7.0.TKIMIXM** (Global) flashed with Xiaomi's `flash_all` first (the ROM keeps its firmware,
  boot and modem)
- Android platform-tools (fastboot); on Windows the USB driver

## Install

1. Download and unzip **<zip link>** (check it against the `.sha256`)
2. Phone off, hold **Power + Volume down**, connect USB
3. Windows: `flash_all.bat` – Linux/macOS: `./flash_all.sh` – type `YES`
4. First boot takes 5–10 minutes

**Flashing erases all data.** Back to MIUI: flash the stock fastboot ROM.

## Source

**GitHub: <link>** – build scripts, shims, overlays and the full log of every boot and fix (`docs/PLAN.md`).
Build it yourself with `./build.sh` from the official Samsung/Xiaomi downloads (README).

## How this port was made

Developed with **Claude Code** (Anthropic's AI coding agent): Claude Code did the porting work – build scripts,
shims, overlays and the fixes, worked out from the logs. I ran the project, debugged on the phone and tested every
build and feature.

## Credits

TrebleDroid (system-side Bluetooth audio HAL), LineageOS (renoir overlays), erofs-utils, Apktool,
samloader-rs.

**Disclaimer:** experimental, flashing wipes your data, you do this at your own risk. Not affiliated with Samsung
or Xiaomi.
