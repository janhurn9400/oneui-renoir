# One UI 8.0 for the Xiaomi Mi 11 Lite 5G (renoir)

A port of Samsung's One UI 8.0 (Galaxy S23, SM-S911B, Android 16) to the Xiaomi Mi 11 Lite 5G (`renoir`, SM7350,
kernel 5.4) on renoir's own MIUI vendor.

**This repository contains no Samsung or Xiaomi files.** It contains the scripts that build the ROM from the
official downloads, plus our own small shims, overlays and configs. You download the firmware yourself, the build
checks every input against [`configs/inputs.sha256`](configs/inputs.sha256) (the exact files the tested build used)
and produces the flashable images.

> Experimental. Flashing wipes your data. You need an unlocked bootloader and the MIUI firmware listed below.
> Nothing here is affiliated with Samsung or Xiaomi.

## Status

| Works | Notes |
| --- | --- |
| Boot, setup, One UI launcher, Samsung apps | SELinux **enforcing** |
| Wi-Fi, mobile network, IMS service starts | calls/SMS/VoLTE: please report |
| Bluetooth incl. audio (A2DP, e.g. AirPods) | via TrebleDroid's system-side BT audio HAL |
| Fingerprint (enrol, unlock) | in-display FPC sensor |
| Display: punch-hole cutout, rounded corners, 90 Hz, brightness slider | renoir's own brightness table |
| Vibration incl. keyboard haptics | short haptics mapped to renoir's click effects |
| Cameras (GCam, third-party apps, browser) | **no camera app included: install a GCam port** (see below) |
| Sensors (proximity, light, accelerometer, ...) | |

**Camera app:** Samsung's camera app needs Samsung's camera HAL and is removed, so the ROM has no camera app.
Install a Google Camera (GCam) port for the Mi 11 Lite 5G, e.g. from
[celsoazevedo.com/files/android/google-camera](https://www.celsoazevedo.com/files/android/google-camera/).
Other camera apps and the camera in browsers/messengers work as well.

Known issues:

- After a boot, adb/USB data needs the cable unplugged and plugged in once.
- Samsung Core Services crashes once per boot (`/data/sec/geodb` can't be created): only place names in search.
- Samsung Theme Center crashes once during boot (Samsung's own start-up race), works afterwards.
- Galaxy Store may refuse with error 2300:1004 (region check).
- The fingerprint ring animation is missing.
- Knox-based features (Samsung Pay/Wallet, Secure Folder, Samsung Pass) are not expected to work.
- Not verified yet: NFC, GPS, microphone in calls.

## Install the prebuilt zip

The XDA thread has a flashable zip of these images with `flash_all.bat` (Windows) and `flash_all.sh`
(Linux/macOS); its instructions are in [`release/README.txt`](release/README.txt). The rest of this README is about
building the same images yourself (`scripts/make_release.sh` packs that zip from a release build).

## What you need to build

1. **The phone** with an unlocked bootloader, running stock firmware **MIUI V14.0.7.0.TKIMIXM** (Global): flash it
   with Xiaomi's `flash_all.sh` first, the port keeps its firmware, boot, dtbo and modem.
2. **A Linux machine** (Ubuntu or Debian recommended; a VM works) with Docker, ~40 GB free space, and a kernel
   with erofs and overlayfs (stock Ubuntu kernels have both). Hosts with SELinux enforcing (e.g. Fedora) can't
   set Android's file labels; use an Ubuntu VM there.
3. **`fastboot`** (Android platform-tools) on the machine connected to the phone.
4. **Three downloads**. The build only accepts these exact versions:

| Download | Where |
| --- | --- |
| Samsung **SM-S911B** firmware **`S911BXXS9EZCI`** (CSC EUX/OXM), the zip with `AP_*.tar.md5` | Samsung's servers serve only the latest build (e.g. via [samloader-rs](https://github.com/topjohnwu/samloader-rs)), older ones via firmware mirrors such as samfw.com |
| Xiaomi **renoir** fastboot ROM **V14.0.7.0.TKIMIXM**: `renoir_global_images_V14.0.7.0.TKIMIXM_20231222.0000.00_13.0_global_e21e2a7d85.tgz` | `https://bigota.d.miui.com/V14.0.7.0.TKIMIXM/` + the file name |
| TrebleDroid GSI **`system-td-arm64-vanilla.img.xz`**, release **ci-20250617** | [TrebleDroid/treble_experimentations releases](https://github.com/TrebleDroid/treble_experimentations/releases/tag/ci-20250617) |

From the GSI only the Bluetooth audio HAL (`sysbta`) and the AOSP VNDK v30 apex are used. If the GSI doesn't
contain `com.android.vndk.v30.apex`, pass it with `VNDK30_APEX=<file>` (e.g. from Nothing OS 4.1's `system_ext`);
its sha256 is checked either way.

## Build

```bash
git clone https://github.com/janhurn9400/oneui-renoir && cd oneui-renoir
SAMSUNG_FW=~/dl/SM-S911B_..._fac.zip \
MIUI_TGZ=~/dl/renoir_global_images_V14.0.7.0.TKIMIXM_20231222.0000.00_13.0_global_e21e2a7d85.tgz \
GSI=~/dl/system-td-arm64-vanilla.img.xz \
./build.sh
```

The result is `work/out/super.img` and `work/out/vendor_boot.img`. A first build takes 30–60 minutes.
`NO_DOCKER=1 sudo -E ./build.sh` runs it without Docker (as root on Ubuntu 26.04 or similar: `erofs-utils` ≥ 1.9,
`secilc`, `lz4`, `python3`, `attr`, `openjdk-21-jre-headless`, `zipalign`, `apksigner`, `apktool` 3).

## Flash

1. Phone in the bootloader: power off, hold **Power + Volume down**, connect USB.
2. `scripts/flash_super.sh --wipe`

It writes `vbmeta`/`vbmeta_system` with verification disabled, the port's `vendor_boot` and `super`, wipes
`userdata` + `metadata` and reboots. The first boot takes 5–10 minutes. Without `--wipe` your data stays (only
for updating a build of this port).

## Debug builds

`DEBUG=1 ./build.sh` adds your adb key (`ADB_KEY`, default `~/.android/adbkey.pub`) so adb works without the
authorization prompt from early boot on, writes a logcat of every boot to `/metadata/oneui-logcat.txt` and opens
`dmesg` to the shell. Coming from a debug build to a release build: revoke the USB debugging authorizations in the
developer options once, otherwise the authorization prompt doesn't appear.

`scripts/probe_device.sh` prints a health report over adb; `scripts/twrp_logs.sh` pulls logs through TWRP when
Android doesn't come up.

## How it works

`scripts/assemble_oui.sh` stacks overlayfs on Samsung's `system`/`system_ext`/`product` and renoir's
`vendor`/`odm`, applies the changes (each one is commented with the problem it fixes) and packs erofs images;
`scripts/build_super_oui.sh` builds the super image, `scripts/preflight.sh` checks it before every flash (erofs
fsck, kernel 5.4 erofs limits, XML, ELF dependencies, init services). Our own code:

- `shims/` – small native shims: vibrator HAL proxy with a Samsung ISehVibrator stub, Bluetooth audio service
  alias, fingerprint enrol timeout/progress for the FPC HAL, lights HAL vendor check. Prebuilt in `input/shims/`
  (rebuild with `shims/build.sh` and NDK r27c).
- `overlays/` – framework/SystemUI resource overlays for renoir (prebuilt in `input/oneui-overlays/`).
- `configs/` – debloat list, init scripts, display config.
- `input/lineage-overlays/` – LineageOS's renoir/SM8350 overlays (Apache-2.0).
- `docs/PLAN.md` – the port's log: every boot, every problem and its fix.

## How this port was made

The port was developed with **[Claude Code](https://claude.com/claude-code)**, Anthropic's AI coding agent: Claude
Code wrote the build scripts, the shims and overlays and worked out the fixes from the logs. **janhurn9400** ran
the project, debugged on the phone and tested every build and feature.

## Credits

- [TrebleDroid](https://github.com/TrebleDroid) for the system-side Bluetooth audio HAL (sysbta).
- [LineageOS](https://github.com/LineageOS) for the renoir and SM8350 overlays.
- [erofs-utils](https://github.com/erofs/erofs-utils), [Apktool](https://github.com/iBotPeaches/Apktool),
  [samloader-rs](https://github.com/topjohnwu/samloader-rs).

## License

Our scripts, shims, overlays and docs: [Apache-2.0](LICENSE). Third-party parts keep their own licenses. Samsung,
Galaxy and One UI are trademarks of Samsung Electronics; Xiaomi and MIUI are trademarks of Xiaomi.
