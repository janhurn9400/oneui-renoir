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
| `vendor_a.img` / `odm_a.img` | erofs, lisa **stock** HyperOS vendor (Android 13 vendor, API 30, sepolicy 30.0, also `fpc1540` + `mfp-daemon` like renoir). odm only 550 KB. No visible One UI–specific vendor changes. |
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
- Firmware `SM-S911B_5_20260909105150_9x31s5f5m2_fac.zip` (15,971,074,225 B, EUX/OXM, PDA `S911BXXSAFZI1`)
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

## 6. Repo layout (so far)
- `tools/` — copied from nothing-renoir: `lpmake.py`, `lpunpack.py`, `avb_footer.py`, `vendorboot_fstab.py`,
  `sparse2raw.py`; `vm.sh` adapted (`$P=/media/psf/Home/Desktop/oneui-renoir`, same VM + ssh key).
- `scripts/fix_sepolicy.sh` — copied. To be written: `assemble_oui.sh`, `build_super_oui.sh`, `flash_super.sh`
  (adapted, same safety rules: wait for the bootloader after super, never interrupt fastboot, LUN 4 GPT fix).
- VM paths: `/root/oneui-*` work dirs, `/mnt/oui_*` mounts. Never `/root/port-nos4`, `/root/nos4`, `/mnt/n*`, `/mnt/r*`.
