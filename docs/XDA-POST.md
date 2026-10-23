<!-- XDA thread (Mi 11 Lite 5G / renoir: "ROMs, Kernels, Recoveries & Other Development"), ready to paste.
     Title: [ROM][PORT][16] One UI 8.0 for Mi 11 Lite 5G (renoir)
     Editor: switch to BB code ([ ] button), paste everything between the two lines below. Replace the two
     [ATTACH] placeholders by uploading docs/xda/banner.png and docs/xda/screenshots.png at exactly that spot
     ("Insert" > "Full image"). Check with "Preview" before posting. -->

----------------------------------------------------------------------------------------------------------------------

[ATTACH type="full"]BANNER[/ATTACH]

Samsung's [B]One UI 8.0[/B] (Galaxy S23 firmware, Android 16) running on the [B]Mi 11 Lite 5G[/B], on renoir's own MIUI vendor. SELinux enforcing.

Flash the stock MIUI firmware, then the zip with [ICODE]flash_all.bat[/ICODE] (Windows) or [ICODE]flash_all.sh[/ICODE] (Linux/macOS) – done. Everything is [B]open source[/B]: the GitHub repository has every script and fix that went into the zip, so you can check what's inside – or build the same images yourself from the official firmware.

[SIZE=5][B]What works[/B][/SIZE]
[LIST]
[*]Boot, setup, One UI launcher and Samsung apps
[*]Wi-Fi, mobile network (calls/SMS/VoLTE: please report)
[*]Bluetooth incl. audio (AirPods etc.)
[*]Fingerprint (in-display), unlock
[*]Punch-hole cutout, rounded corners, 60/90 Hz, brightness
[*]Vibration incl. keyboard haptics
[*]Cameras in GCam and third-party apps (see Camera below)
[*]Sensors
[/LIST]

[SIZE=5][B]Known issues[/B][/SIZE]
[LIST]
[*]adb/USB data needs one cable replug after every boot
[*]Samsung Core Services and Theme Center crash once at boot (harmless)
[*]Galaxy Store may show error 2300:1004
[*]Fingerprint ring animation missing
[*]Knox features (Samsung Wallet, Secure Folder, Samsung Pass) won't work
[*]Not verified yet: NFC, GPS, call microphone – reports welcome
[/LIST]

[SIZE=5][B]Camera[/B][/SIZE]
[B]There is no camera app in the ROM[/B] (Samsung's needs Samsung's camera hardware). [B]Install a GCam port[/B] for the Mi 11 Lite 5G (link in Downloads) – it works without problems, as do other camera apps and the camera in browsers and messengers.

[SIZE=5][B]Requirements[/B][/SIZE]
[LIST]
[*]Unlocked bootloader
[*]Stock [B]MIUI V14.0.7.0.TKIMIXM (Global)[/B] – exactly this version: the ROM keeps its kernel and firmware (modem, audio, camera), and our vendor's drivers only match this build. Already on it? Skip step 1 below.
[*]Android platform-tools (fastboot); on Windows the Xiaomi/Google USB driver
[/LIST]

[SIZE=5][B]Downloads[/B][/SIZE]
[LIST]
[*][URL='https://bigota.d.miui.com/V14.0.7.0.TKIMIXM/renoir_global_images_V14.0.7.0.TKIMIXM_20231222.0000.00_13.0_global_e21e2a7d85.tgz']Stock MIUI V14.0.7.0.TKIMIXM fastboot ROM[/URL] (official Xiaomi server, 6.3 GB) – step 1
[*][URL='https://sourceforge.net/projects/oneui-renoir/files/oneui-renoir-20261023.zip/download']One UI 8.0 for renoir – flashable zip[/URL] (6.0 GB) – step 2
SHA256: [ICODE]13b35663cdbc1fb07a4d3bebe4910a5595345b2a23e6875e830a5d82a982e8ff[/ICODE]
[*][URL='https://www.celsoazevedo.com/files/android/google-camera/']GCam ports[/URL] (camera app)
[*][URL='https://developer.android.com/tools/releases/platform-tools']Android platform-tools[/URL] (fastboot)
[/LIST]

[SIZE=5][B]Install[/B][/SIZE]
[B]Flashing erases all data.[/B]
[LIST=1]
[*][B]Stock firmware:[/B] unpack the MIUI .tgz, phone in fastboot (off, hold [B]Power + Volume down[/B], USB), run [ICODE]flash_all.bat[/ICODE] / [ICODE]flash_all.sh[/ICODE] from it – or MiFlash with [B]"clean all"[/B].
[COLOR=rgb(226, 80, 65)][B]Do NOT use flash_all_lock / "clean all and lock" – it relocks the bootloader.[/B][/COLOR]
No need to set up MIUI afterwards: go back to fastboot (Power + Volume down) and continue.
[*][B]One UI:[/B] unzip the ROM zip, phone in fastboot, run [ICODE]flash_all.bat[/ICODE] (Windows) or [ICODE]./flash_all.sh[/ICODE] (Linux/macOS), type [ICODE]YES[/ICODE].
[*]The first boot takes 5–10 minutes.
[*]Install a GCam port for the camera.
[/LIST]
Back to MIUI: step 1 again.

[SIZE=5][B]Source[/B][/SIZE]
[URL='https://github.com/janhurn9400/oneui-renoir']github.com/janhurn9400/oneui-renoir[/URL] – build scripts, shims, overlays and the full log of every boot and fix ([ICODE]docs/PLAN.md[/ICODE]). Build it yourself with [ICODE]./build.sh[/ICODE] from the official Samsung/Xiaomi downloads (see README).

[SIZE=5][B]How this port was made[/B][/SIZE]
Developed with [B]Claude Code[/B] (Anthropic's AI coding agent): Claude Code did the porting work – build scripts, shims, overlays and the fixes, worked out from the logs. I ran the project, debugged on the phone and tested every build and feature.

[SIZE=5][B]Credits[/B][/SIZE]
TrebleDroid (system-side Bluetooth audio HAL), LineageOS (renoir overlays), erofs-utils, Apktool, samloader-rs.

[SIZE=5][B]Screenshots[/B][/SIZE]
[SPOILER="Screenshots"]
[ATTACH type="full"]SCREENSHOTS[/ATTACH]
[/SPOILER]

[B]Disclaimer:[/B] experimental, flashing wipes your data, you do this at your own risk. Not affiliated with Samsung or Xiaomi. Samsung, Galaxy and One UI are trademarks of Samsung Electronics; Xiaomi and MIUI are trademarks of Xiaomi.

----------------------------------------------------------------------------------------------------------------------
