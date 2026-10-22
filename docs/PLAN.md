# One UI 8 for renoir — plan (phase 1, 2026-10-21)

Target: Samsung One UI 8 (Android 16) on the Xiaomi Mi 11 Lite 5G "renoir" (SM7350 / lahaina, A/B, UFS,
vendor API 30, sepolicy 30.0, VINTF level 5). Sibling project: `~/Desktop/nothing-renoir` (Nothing OS 4.1, daily
driver) — same pipeline idea, same flashing rules (see its `HANDOFF.md`).

## 1. What the lisa reference port really is

Studied read-only in the VM (`/mnt/oui_sys`, `/mnt/oui_ven`, `/mnt/oui_odm`), from
`~/Desktop/nothing-renoir/work/ref-oneui-lisa`:

| part | content |
|---|---|
| `system_a.img` | ext4, 6.9 GB used (100 % full). Galaxy S23 **SM-S911B**, `S911BXXU8ZYHB`, One UI 8.0 (`ro.build.version.oneui=80000`), SDK 36, patch 2025-09. "Mystic GSI": system-as-root GSI on **phh-treble**, `system_ext` + `product` merged into `/system`. |
| `vendor_a.img` / `odm_a.img` | erofs, lisa **stock** HyperOS vendor (Android 13 vendor, API 30, sepolicy 30.0, also `fpc1540` + `mfp-daemon` like renoir). odm only 550 KB. Correction (boot 10): Mystic added `etc/audio_effects_sec.xml` + `etc/audio_policy_configuration_sec.xml` (Samsung's audioserver reads only those) and `persist.sys.phh.disable_a2dp_offload=true` to build.prop; everything else is Xiaomi's. |
| `boot.img` / `vendor_boot.img` | lisa stock kernel 5.4.289-qgki (Xiaomi build). No custom kernel. |
| install | `windows_install_and_format_data.bat` / `updater-script`: full lisa firmware + boot/vendor_boot + one `super.img`, then erase metadata+userdata. |

What Mystic/phh changed on top of the official S23 system (found by mtime and diffing layout):
- **Only one framework binary is modified: `framework.jar`** (dated 2026-09-15, everything else 2009-01-01).
  `services.jar` and all Samsung jars are stock → Samsung's system_server tolerates a non-Samsung vendor
  without services patches (big de-risk). Content of the framework.jar patch still unknown (diff it later
  against the official jar; study only, we don't ship Mystic's binary).
- phh layer: `rw-system.sh` (1280 lines, per-device fixups; renoir block = headset button keylayout; lahaina
  block = 25 media volume steps), `phh-on-boot/-on-data`, `vndk.rc`/`vndk-detect`, `phh/*.kl` keylayouts,
  `busybox_phh`, `phh-remotectl`.
- `com.android.vndk.v30.apex` (110 MB) in `/system/apex` — needed for renoir's API-30 vendor.
- sepolicy mappings 29.0 … 34.0, 202404, 202504 and `compatibility_matrix.5…8` present → API-30 vendor accepted.
- `mystic/vo/*`: GSI vendor-overlay replacements (connectivity/tethering/softap/framework-res RRO).
- Shortcuts we will **not** copy: `permissiver.rc` → `setenforce 0` at early-init; `ro.secure=0`, `ro.adb.secure=0`,
  `persist.sys.usb.config=mtp,adb`, `persist.service.debuggable=1` (open root-ish adb on a user build);
  `ro.control_privapp_permissions=disable`; `persist.sys.disable_rescue=true`; `ro.config.knox=false`;
  `ro.csc.sales_code=XAR`; a logcat-to-/data service at boot.

Conclusion: an official S23 One UI 8 system runs on a lahaina API-30 Xiaomi vendor with very little glue.
Everything Mystic did is reproducible from the official firmware + the open-source phh-treble pieces.

## 2. Routes

### (a) GSI route — Mystic system + renoir vendor/odm/vendor_boot (like the lisa port)
- Effort: low (days). Take the GSI system as-is, renoir stock vendor/odm, our patched vendor_boot, build super.
- Contra: it is another porter's protected build (user rule: don't use/bypass it) — **excluded**. Also permissive
  SELinux and open adb baked in, ext4 system at 7.4 GB, no control over the framework patch, every update
  depends on Mystic.

### (b) Clean route — official Samsung firmware, own assembly (like the Nothing port)
- system / system_ext / product straight from the official SM-S911B One UI 8 AP (`super.img` inside the AP tar),
  separate partitions as in renoir's super layout (no merging needed: we are not a GSI).
- renoir stock vendor/odm + our vendor_boot (no AVB/mi_ext fstab, AVB footer) — reuse
  `nothing-renoir` know-how: default.prop merge, fstab, vibrator HAL patch, displayconfig brightness, LineageOS
  overlays (AOSP resource names exist in Samsung's framework-res too), own RROs at /vendor/overlay.
- Glue we write ourselves (small vendor init script + props) instead of the phh shell layer; VNDK v30 apex from
  the official system if Samsung ships it, otherwise from AOSP (Apache-2.0).
- SELinux enforcing: compile Samsung's `plat_sepolicy.cil` + mapping 30.0 + renoir vendor policy with
  `scripts/fix_sepolicy.sh`, add own vendor CIL rules from denials (debug builds permissive only).
- Targeted smali patches (apktool) only where a Samsung service needs a Samsung HAL and does not fall back
  (candidates below). adb without auth only in DEBUG builds (Mac key in `/product/etc/security/adb_keys`).
- Effort: with the nothing-renoir tooling and renoir know-how reused and lisa proving the vendor combination,
  a first DEBUG boot is realistic on the download day, daily-usable in a few days (depends on telephony and
  fingerprint needing patches); enforcing SELinux and release polish after that. Every change is ours,
  documented, enforcing, updatable to new Samsung builds.

### (c) Hybrid (recommended)
Route (b), but use the lisa/Mystic system as a **read-only lab**: diff its `framework.jar` against the official
one to learn which fixes One UI needs on non-Samsung vendors, and borrow the *ideas* of phh's open-source
`rw-system.sh` (github.com/phhusson/device_phh_treble, Apache-2.0) for the few renoir/lahaina-relevant fixes —
reimplemented as our own vendor init/props, not the generic 1280-line script.

**Recommendation: (c).** Same discipline as the Nothing port (enforcing, own code, no foreign protected
binaries), and the lisa port already proves the hardest question (does One UI 8 boot on an API-30 lahaina
Xiaomi vendor?) — yes.

## 3. Milestones
1. Download + unpack official firmware in the VM, keep only system/system_ext/product (sizes → super budget).
2. Compare official vs Mystic: file lists, props, framework.jar diff (jadx), VNDK v30, mappings, vintf.
3. `scripts/assemble_oui.sh` (DEBUG=1: permissive, adb key) + `build_super_oui.sh` → first boot test
   (only after the user's go, coordinated with the Nothing session; TWRP RAM boot + pstore for boot logs;
   way back = re-flash the Nothing super with `nothing-renoir/scripts/flash_super.sh`).
4. Bring-up: boot → setup wizard → wifi → RIL/IMS → fingerprint → brightness → 90 Hz → audio → camera (GCam).
5. SELinux enforcing, debloat, DEBUG=0 build, release packaging.

## 4. Risks

| area | risk | plan |
|---|---|---|
| **super size** | renoir super 9,126,805,504 B; group `qti_dynamic_partitions_a` max **9,073,118,412 B** (template `nothing-renoir/work/super-stock-head.bin`). renoir vendor 1,575 MB + odm 18 MB → **≈7.48 GB left** for system+system_ext+product. Mystic system alone is 7.4 GB ext4. | Repack all three as erofs lz4hc (Nothing port: same tooling), debloat apps that can't work (Samsung Pay/Wallet, Knox/Secure Folder, Samsung camera + AR/Bixby Vision bits, Galaxy Store extras); `mi_ext` stays empty. If still too big: lz4hc→lzma erofs for product, or trim vendor (Xiaomi apps). |
| Samsung HAL expectations | Samsung services look for `vendor.samsung.hardware.*` (vaultkeeper, Knox/KG, TEE/wsm, sec biometrics, sec radio/wifi, sehradio, light/display "SemDisplay"). Lisa evidence: stock services.jar boots fine; only framework.jar patched. | Start without patches; read system_server crash/ANR logs; smali-patch only services that crash or block (expect: vaultkeeper/KnoxGuard, keystore attestation paths). Knox/Samsung Pay/Secure Folder/Samsung Health are written off (Knox bit can't be faked properly). |
| **telephony** | Samsung's telephony stack (SecTelephony, `telephony-common` with Samsung RIL extensions) on Qualcomm's RIL/IMS: calls/SMS/data/VoLTE may need work. Daily-driver critical. | Test early (milestone 4). Study how phh handles QTI IMS; fallback props. |
| wifi | Samsung's SemWifi on QTI supplicant; Nothing port crashed on `ISupplicantVendor`. | Reuse the hwservice hiding trick if the same crash shows up. |
| fingerprint | FPC1540 side sensor via stock `mfp-daemon` (HIDL 2.1). One UI natively knows side sensors (A/Z series) — better than Nothing; but Samsung's BiometricService may prefer `vendor.samsung.hardware.biometrics.fingerprint`. Lisa has the same sensor + daemon. | First try plain AIDL/HIDL fallback; config overlay for side sensor location; patch if Samsung's fingerprint manager insists on Sem HAL. |
| display | One UI's motion smoothness assumes 120 Hz; brightness via Samsung display service (scale, `/sys/class/lcd/panel` that renoir doesn't have). renoir: 60/90 Hz, backlight max 2047, density 440. | displayconfig XML (HWC brightness, as in Nothing), props/overlays for refresh rate; phh's mask_brightness hint. |
| camera | Samsung Camera needs Samsung's camera HAL → won't work. | GCam installed by the user (same as Nothing); remove Samsung Camera to save space. |
| SELinux | Samsung SEPF policy (many sec types/neverallows) + Xiaomi API-30 vendor; Mystic just runs permissive. | `fix_sepolicy.sh` loop, own vendor CIL rules from denials; enforcing before release. |
| encryption/keystore | Samsung vold/keystore2 with Xiaomi keymaster 4.x. Lisa port formats data and works. | Clean wipe on first flash (`--wipe`); attestation/Play Integrity basic only. |
| RAM/perf | S23 build assumes 8 GB; renoir 6/8 GB, SD780G. | Samsung "lite" props if needed (blur/animations), RAM Plus off. |
| Mac disk | Mac has **≈38 GB free**; lisa ref folder 8.6 GB (Nothing project's `work/`). | Download and unpack inside the VM (`/root/oneui-*`), stream AP→super→partitions, delete archives right after; VM disk has 26 GB free. |
| legal | Samsung firmware redistribution grey zone (same as Nothing). | Release = scripts + instructions, or packages with clear credits; decide at release time. |

## 5. Download list (nothing downloaded yet — ask first)

| # | file | source | size | where |
|---|---|---|---|---|
| 1 | Official firmware **SM-S911B**, CSC **EUX** (or DBT, Germany), latest One UI 8.0 build (Samsung's Oct-2025 One UI 8 OTA was `S91xBXXU8EYI5`; the Mystic base is `S911BXXU8ZYHB`). We need only `AP_*.tar.md5` → `super.img.lz4`. | Samsung FUS servers via the open-source **samloader** (pip, GitHub `nlscc/samloader` / maintained fork) — downloads straight from Samsung. Fallback: SamMobile / samfw mirrors. | full zip ≈ **8–10 GB** (exact size printed by the tool before the transfer; I confirm again then) | VM `/root/oneui-dl/`, deleted after extracting the three partitions (kept: system/system_ext/product ≈ 7–8 GB until the first build, then erofs outputs only) |
| 2 | `samloader-v2.2.0-linux-aarch64.zip` (topjohnwu/samloader-rs, release 2026-09-25; the Python samloader is gone from PyPI and broken by Samsung's newer FUS protocol) | github.com/topjohnwu/samloader-rs/releases | 3.2 MB | VM `/root/oneui-tools/` |
| 3 | `lz4` — installed in the VM (apt, 2026-10-21) | Ubuntu archive | < 1 MB | VM |
| — | Already available, no download: renoir stock vendor/odm/vendor_boot (`nothing-renoir/work/renoir-stock`), super template, jadx 1.5.1, apktool, erofs-utils, simg2img/img2simg, LineageOS renoir overlays, TWRP. | | | |

Optional later: AOSP `com.android.vndk.v30.apex` only if the official system lacks it (~110 MB);
phh-treble sources for reading (git, few MB).

## 5b. Downloaded (2026-10-21)
- (superseded by 5d: rebased on One UI 8.0) Firmware `SM-S911B_5_20260909105150_9x31s5f5m2_fac.zip` (15,971,074,225 B, EUX/OXM, PDA `S911BXXSAFZI1`)
  via samloader-rs from Samsung FUS. AP `..._meta_OS16.tar.md5` (17.5 GB) holds `super.img.lz4` (10 GB, sparse
  11.42 GiB). Streamed with `scripts/extract_firmware.sh`; zip deleted afterwards.
- Result in `work/fw/` (erofs, Samsung's lz4): `system.img` 7,647,588,352 B, `product.img` 1,469,267,968 B,
  `system_ext.img` 180,686,848 B. One UI **8.5** (`ro.build.version.oneui=80500`), Android 16
  `BP4A.251205.006`, security patch 2026-09-05.
- Official system already has sepolicy mapping 29.0–34.0/202404/202504 and compatibility_matrix.5 → API-30
  vendor accepted. **No `com.android.vndk.v30.apex`** (the GSI added it) → must be supplied (AOSP prebuilt or
  Nothing OS 4.1's system).
- Super budget: 9,298 MB needed vs ≈7,480 MB free in the group → **≈1.8 GB over**. Next: try lz4hc/lzma
  recompression (system content is 8.9 GB uncompressed, Samsung's image only ~18 % smaller) + debloat list.
- Other partitions in Samsung's super (not extracted): vendor 1847 MiB, vendor_dlkm 31 MiB, odm, system_dlkm.

## 5c. First DEBUG build (2026-10-21)
- Mystic's `framework.jar` change is confined to `classes4.dex`; no new strings/props versus Samsung's code
  (string-table diff shows only 8.0→8.5 noise) → not reproducible without Samsung's original 8.0 jar, ignored
  until a framework problem shows up.
- Debloat (`configs/debloat.txt`, 98 app dirs) = Mystic's removals minus NFC apps and the German TTS voice.
- VNDK v30 apex from Nothing OS 4.1's system_ext (AOSP prebuilt) → our system_ext/apex.
- SELinux: Samsung's system_ext mapping 30.0 references 234 Samsung-only `*_30_0` attributes → pre-declared by
  `fix_sepolicy.sh`; policy compiles like init does.
- Images (erofs lz4hc,12): system 5,083,787,264 · system_ext 208,826,368 · product 581,656,576 ·
  vendor 1,531,457,536 · odm 143,360 → super 6.90 GiB used of 8.50 GiB (group budget 9,073,118,412 B, 1.67 GB spare).
  `work/out/super.img` (sparse, 7.4 GB) verified by sha256 per partition.

## 5d. Boot attempts with One UI 8.5 (2026-10-21) → switched to One UI 8.0
Logs from `/sys/fs/pstore/console-ramoops-0` via TWRP RAM boot (`work/logs/boot*`). The phone never brings up
USB/adb before init reaches `on boot`, so TWRP is the way to read failed boots.
1. Kernel panic in init: `SetupMountNamespaces` denied `mounton /` (`unlabeled`). Cause: overlayfs merged root =
   upper dir without the image root's owner/mode/label. Fixed in `assemble_oui.sh` (+ check includes roots).
2. Stuck on the Mi logo: Samsung init waits for `security.fbe.global_de`, which Samsung's vold may not set here
   (`security.*` → `exported_system_prop` from system_ext; a Samsung vendor labels/allows it). Fixed with vendor
   CIL rules for vold (also `system_prop` for `sys.is_vold_shutdown`, generic netlink socket). The DEBUG
   `write /sys/fs/selinux/enforce 0` fails under Samsung's policy (open denied, no avc) → debug builds stay
   enforcing for now; fixes must be real policy rules anyway.
3. Reboot loop `reboot,bpfloader-failed`: `NetBpfLoad: Android 25Q4 requires kernel 5.10.` One UI 8.5 is Android
   16 QPR2 (`api 36/3610`); renoir runs kernel 5.4. The tethering APEX is byte-identical to Nothing OS 4.1's —
   the platform level triggers the check. Mystic's base (One UI 8.0, Android 16 QPR0) avoids it.
   **Decision: rebase on official One UI 8.0, `S911BXXS9EZCI` (EUX/OXM, 2026-03).** Patching/re-signing the
   tethering APEX for 8.5 stays an option for later (LineageOS runs QPR2 on 5.4 with source patches).

## 5e. Boot 10/11: One UI 8.0 reaches the setup wizard (2026-10-22)
Read live via adb (avc denials are not in Samsung's logcat and dmesg needs root, so SELinux causes are inferred):
- "internal problem" dialog = `Build.isBuildConsistent()` → on treble `VintfObject.verifyBuildAtBoot()`, not the
  fingerprint: framework manifest declares vendor-ndk 33 only, renoir's device matrix needs 30. Fix: framework
  manifest fragment for vendor-ndk 30 in system_ext.
- audioserver abort `AudioPolicyEffects: Failed to load XML effect configuration`: Samsung's libeffectsconfig only
  looks for `audio_effects_sec.xml`; libaudiopolicycomponents only for `audio_policy_configuration_sec.xml`
  ("file name is empty" → speaker-only fallback). Fix: renoir's files installed under those names.
- SystemUI loop `Unable to open socket for UEventObserver` (platform_app) → vendor rule for the uevent socket.
- com.sec.imsservice: setting `ril.twwan911Timer` (radio_prop) denied for system_app → vendor rule.
- Samsung apps with OEM uids (cmh 5004, scloud/scpm 5009, rubin 5010): no seapp_contexts match → zygote abort.
  Mystic has the same gap. Fix: `user=oem_* seinfo=platform domain=system_app` in system_ext_seapp_contexts.
- Left for later: dumpstate aborts on `/data/log` (only runs after crashes), themecenter DB crash, phh's
  a2dp-offload switch (check when testing Bluetooth audio).

## 5f. Fingerprint, status bar, store, audio (2026-10-22)
- Fingerprint: Samsung's service binds `ISehBiometricsFingerprint` unless the floating feature
  `SEC_FLOATING_FEATURE_COMMON_CONFIG_DEVICE_MANUFACTURING_TYPE` contains `jdm` -> set to `jdm` (+ sensor type `side`).
  Then Samsung's HIDL stub always sends enroll timeout 0 ("no limit" for Samsung HALs); renoir's FPC HAL waits
  0 ms -> FPC_ERROR_TIMEDOUT. Fix: own LD_PRELOAD shim for mfp-daemon (`shims/fpc_timeout`, built with NDK r27c by
  `shims/build.sh`): fpc_enroll timeout 0 -> 60 s (needs `noatsecure` for init -> vendor_mfp-daemon). Enrolment
  works; Samsung's UI shows odd progress (FPC reports 26 steps as "remaining", Samsung expects a larger scale).
- Samsung reads only `*_sec.xml` audio configs; 16-bit primary/deep-buffer outputs (distortion).
- Status bar: own SystemUI overlay (`overlays/SystemUIOverlayOneUIRenoir`, `tools/build_overlays.sh`) moves the
  clock right of the top-left punch hole; S23 framework overlay patched (`tools/patch_s23_rro.sh`) without
  cutout/status bar sizes (removing it entirely crashes system_server on the brightness map).
- USB: Samsung's `sec_charging(,adb)` functions handled in `configs/init/oneui-renoir-usb.rc`.
- Brightness (2026-10-23): Samsung only reads config.xml (displayconfig default.xml is used for density only) and drives
  the lights HAL. lights.qcom.so takes its MIUI path when ro.product.manufacturer is "Xiaomi" (color & 0xfff), which
  turned Samsung's AOSP colour into (level*257)&0xfff -> zig-zag, black at the low end. shims/lights_scale makes
  property_get report "samsung" inside the lights HAL only -> AOSP path, panel (level+1)*8-1. S23 brightness tables
  and config_screenBrightnessExtendedMaximum (612 -> max 2.4) removed; own 0..255 / 2..500 nits table.
- Bluetooth audio: TrebleDroid sysbta + shims/btaudio_alias (Samsung's stack only looks for ".../default").
- Vibration (2026-10-23): shims/vibrator_proxy registers IVibrator/default as a pass-through to Xiaomi's
  IVibrator/vibratorfeature with a minimal vendor.samsung ISehVibrator (V5) extension answering "unsupported"
  (Samsung's AidlHalWrapper dereferences that extension unchecked). Domain hal_vibrator_proxy permissive for now.
- Open:
  Samsung Core Services `/data/sec/geodb` (an init mkdir on /data/sec sent the phone to recovery: don't),
  Galaxy Store 2300:1004 (server side; test with SIM), proximity sensor missing.

## 6. Repo layout (so far)
- `tools/` — copied from nothing-renoir: `lpmake.py`, `lpunpack.py`, `avb_footer.py`, `vendorboot_fstab.py`,
  `sparse2raw.py`; `vm.sh` adapted (`$P=/media/psf/Home/Desktop/oneui-renoir`, same VM + ssh key).
- `scripts/fix_sepolicy.sh` — copied. To be written: `assemble_oui.sh`, `build_super_oui.sh`, `flash_super.sh`
  (adapted, same safety rules: wait for the bootloader after super, never interrupt fastboot, LUN 4 GPT fix).
- VM paths: `/root/oneui-*` work dirs, `/mnt/oui_*` mounts. Never `/root/port-nos4`, `/root/nos4`, `/mnt/n*`, `/mnt/r*`.
