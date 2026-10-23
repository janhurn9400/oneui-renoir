One UI 8.0 for the Xiaomi Mi 11 Lite 5G (renoir)
================================================

Samsung's One UI 8.0 (Galaxy S23 firmware, Android 16) ported to renoir. Experimental, at your own risk.
Built from the open-source scripts at https://github.com/janhurn9400/oneui-renoir (every change is documented
there; you can also build these images yourself).

Developed with Claude Code (Anthropic's AI coding agent), which did the porting work: build scripts, shims,
overlays and fixes. janhurn9400 ran the project, debugged on the phone and tested every build and feature.

FLASHING ERASES ALL DATA ON THE PHONE.

Before you start
----------------
1. Unlocked bootloader.
2. Stock MIUI V14.0.7.0.TKIMIXM (Global), exactly this version: this ROM keeps renoir's kernel, dtbo and firmware
   (modem, audio, camera) from it. Official download (6.3 GB):
   https://bigota.d.miui.com/V14.0.7.0.TKIMIXM/renoir_global_images_V14.0.7.0.TKIMIXM_20231222.0000.00_13.0_global_e21e2a7d85.tgz
   Unpack it and run its flash_all.bat / flash_all.sh from fastboot (or MiFlash "clean all").
   Do NOT use flash_all_lock / "clean all and lock": it relocks the bootloader.
   No need to set up MIUI afterwards, go straight back to fastboot.
3. Android platform-tools (fastboot) installed, or unpacked into a "platform-tools" folder next to this file.
   Windows: Xiaomi/Google USB driver installed.

Flash
-----
1. Phone off, hold Power + Volume down until FASTBOOT shows, connect USB.
2. Windows: double-click flash_all.bat
   Linux/macOS: ./flash_all.sh   (macOS: allow it in System Settings if blocked)
3. Type YES when asked. The first boot takes 5-10 minutes.

The images can be checked with SHA256SUMS.

Camera
------
There is no camera app in the ROM (Samsung's needs Samsung's camera hardware). Install a Google Camera (GCam)
port for the Mi 11 Lite 5G, e.g. from https://www.celsoazevedo.com/files/android/google-camera/
Other camera apps and the camera in browsers/messengers work too.

Known issues
------------
- After every boot, USB data/adb needs the cable unplugged and plugged in once.
- Samsung Core Services and Theme Center crash once during boot (harmless).
- Galaxy Store may show error 2300:1004.
- The fingerprint ring animation is missing.
- Knox features (Samsung Wallet, Secure Folder, Samsung Pass) do not work.
- Not verified yet: NFC, GPS, call microphone.

Back to MIUI: flash the stock fastboot ROM with Xiaomi's flash_all (MiFlash or the script in the ROM).

Samsung, Galaxy and One UI are trademarks of Samsung Electronics; Xiaomi and MIUI are trademarks of Xiaomi.
Not affiliated with either.
