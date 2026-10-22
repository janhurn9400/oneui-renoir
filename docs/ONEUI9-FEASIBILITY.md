# One UI 9 (Android 17) on renoir — feasibility (research, 2026-10-22)

## Zusammenfassung (Deutsch)

**Urteil: machbar mit erheblichem Zusatzaufwand – nicht nur wegen NetBpfLoad.** Der Kernel-Check ist lösbar,
aber Android 17 entfernt zusätzlich die Unterstützung für genau unsere Vendor-Generation (API 30).

- **Wie DerpFest 17 / LineageOS 24 das 5.4-Problem umgehen:** nicht mit einem anderen Kernel-Patch, sondern mit
  einer Property `ro.bpf.kver_override=5.10.239` (LineageOS `sm8350-common`, `product.prop`) plus einem
  LineageOS-Patch in `packages/modules/Connectivity`, der diese Property statt `uname` liest
  (`ab21b78a1812`). NetBpfLoad „glaubt“ dann, es läuft auf 5.10, lädt die 5.10-BPF-Programme, und der
  Lahaina-5.4-Kernel akzeptiert sie offenbar (er hat viele BPF-Backports). Der „Relax“-Patch, der nur aus dem
  Fehler eine Warnung macht (`8e92e094e989`), reicht unter Android 17 **nicht**: Für API ≥ 26Q2 gibt es keine
  5.4-Variante der Pflichtprogramme mehr. DerpFest 17 nutzt den LineageOS-Kernel 5.4.302 ohne eigene BPF-Änderungen.
- **Für One UI:** Samsungs Tethering-APEX ist Googles signiertes Mainline-Modul (bei 8.5 byte-gleich mit
  Nothing OS). Wir können es durch ein **selbst gebautes** `com.android.tethering` aus AOSP-Quellen
  (Apache-2.0) + den zwei LineageOS-Patches ersetzen; apexd vertraut vorinstallierten APEXen über ihren
  eigenen Schlüssel. Ein APEX aus dem DerpFest-Build zu übernehmen ist rechtlich möglich (Apache-2.0),
  passt aber nicht zu unserer Regel und nicht zu Samsungs System (Lineage-Firewall-Patches) → selbst bauen.
- **Weitere Android-17-Hürden (neu, betreffen nur uns, nicht LineageOS):**
  1. **SELinux-Mapping 30.0 ist in AOSP 17 gelöscht** (nur noch 31.0 …). Unser Xiaomi-Vendor-Policy ist 30.0
     → ohne selbst erzeugtes `30.0.cil` (Vorwärts-Port des A16-Mappings) bootet nichts. Größter Brocken.
  2. **VINTF:** `compatibility_matrix.5.xml` (und 6) gibt es nicht mehr, und keine Framework-Matrix
     akzeptiert Kernel 5.4 (Minimum 5.10) → „Interner Fehler“-Dialog; lösbar durch eigene Matrix-Dateien.
  3. VNDK v30 wird von apexd/linkerconfig in 17 noch unterstützt (wir liefern das APEX schon selbst).
- **One UI 9 für S23 (SM-S911B):** stabil seit 19.10.2026, Build `S911BXXUAGZIF` (Patch Oktober 2026).
  Komplette Firmware sollte über Samsung FUS (samloader-rs) für EUX verfügbar sein – nicht geprüft, kein Download.
- **Wichtige Grenze:** Ab Android 17 QPR1 (SDK 37.1, „26Q4“) verlangt NetBpfLoad Kernel **5.15** und
  5.15-BPF-Programme. Ein späteres One UI 9.1 auf Basis 37.1 wäre deutlich riskanter; Ziel wäre nur One UI 9.0.

Empfehlung: Erst auf dem laufenden One-UI-8.0-Port testen, ob der **Stock-Kernel** die 5.10-BPF-Programme
akzeptiert (eigenes Tethering-APEX + Override). Fällt das durch, auf den LineageOS-Kernel 5.4.302 wechseln.
Danach den 30.0-Mapping-Port bauen, dann erst die One-UI-9-Firmware laden.

---

## 1. How DerpFest 17 / LineageOS get past `NetBpfLoad: Android 25Q4 requires kernel 5.10`

### 1.1 The check itself (AOSP)
`packages/modules/Connectivity`, `bpf/loader/NetBpfLoad.cpp`, `doLoad()`:

| branch | check |
|---|---|
| `android16-qpr2-release` (l.1636) | `if (isAtLeast25Q4 && !isAtLeastKernelVersion(5, 10)) { ALOGE("Android 25Q4 requires kernel 5.10."); return 7; }` |
| `android17-release` (l.1578, l.1584) | same 25Q4 → 5.10 check, **plus** `if (isAtLeast26Q4 && !isAtLeastKernelVersion(5, 15)) { "Android 26Q4 requires kernel 5.15." }` |

The platform level comes from `bpf/headers/include/bpf/BpfUtils.h` `get_api_level_full()`:
`ro.build.version.sdk_full` (`37.0` → 3700) combined with the first line of the *system's*
`/system/etc/init/netbpfload.rc` (`# y q a b c #`, quarterly info, max `+8`). Thresholds:
`isAtLeast25Q4 = ≥3610` (36.1), `isAtLeast26Q2 = ≥3700` (37.0), `isAtLeast26Q4 = ≥3710` (37.1).
So any Android 17 build (37.0.x) is past 25Q4 but below 26Q4; 37.1 (QPR1) hits the 5.15 wall.

Faking `sdk_full` is not an option (it is the public `Build.VERSION.SDK_INT_FULL`, and < 36 switches the whole
parser path).

### 1.2 What the open-source ROMs change
| repo / branch | commit | change |
|---|---|---|
| [LineageOS/android_packages_modules_Connectivity](https://github.com/LineageOS/android_packages_modules_Connectivity) `lineage-24.0` (and 23.x) | `ab21b78a18129194859b0f9eff3589388308a5b6` "bpf: Allow overriding kernel version" (Gerrit 490800) | `bpf/headers/include/bpf/KernelUtils.h` `uncachedKernelVersion()` parses `ro.bpf.kver_override` instead of `uname().release` when set. Header-only → affects **every** Connectivity binary (NetBpfLoad, libnetd_updatable, service-connectivity JNI) consistently. |
| same, `lineage-23.2` | `8e92e094e9897249d7bf68041c84d2499d49f4e3` "NetBpfLoad: Relax 5.10 kernel requirement" | `ALOGE … return 7` → `ALOGW`. For 24.0 the same change (Gerrit 490801, `b884d9fe1a72`) was **abandoned** ("we shouldn't need this for 24.0"). |
| [LineageOS/android_system_bpf](https://github.com/LineageOS/android_system_bpf) `lineage-24.0` | `1787201ef625` "bpfloader: Allow overriding kernel version" (Gerrit 490847) | same override for the platform bpfloader. |
| [LineageOS/android_device_xiaomi_sm8350-common](https://github.com/LineageOS/android_device_xiaomi_sm8350-common) `lineage-23.2`/`lineage-24.0` | `c72b337deef2d1cacf079fecc3af7f42577b4395` "sm8350-common: Override kernel BPF version" (2025-07-08) | adds `product.prop`: `ro.bpf.kver_override=5.10.239` (+ `TARGET_PRODUCT_PROP`). Other legacy SoCs (sm8150, sm7125, sm6150 …) got the same "Bump kernel BPF version override to 5.10.239" commits (they carry BPF backports). |
| [LineageOS/android_hardware_interfaces](https://github.com/LineageOS/android_hardware_interfaces) `lineage-24.0` | `82208be116547c4721c248d52fd0bdba934b4e74` "compatibility_matrices: Add kernel_config_t_5.4" | lets the level-7 FCM accept a 5.4 kernel (see §3). |
| [DerpFest-AOSP/android_packages_modules_Connectivity](https://github.com/DerpFest-AOSP/android_packages_modules_Connectivity) branch `17` | `ab21b78a1812` + `b884d9fe1a72` (cherry-picks of the two Bestas commits) | DerpFest 17 carries both: override **and** the warning instead of `return 7`. The 26Q4/5.15 check is untouched. |
| [DerpFest-AOSP/android_system_bpf](https://github.com/DerpFest-AOSP/android_system_bpf) branch `17` | `1787201ef625` + reverts `de9ec3029e5e`, `4bd233606748`, … ("vendorBpfLoader: kernel is guaranteed to be 5.4+") | the reverts are for < 5.4 devices, irrelevant for renoir. |

The XDA thread "[ROM][17][Community][Beta] DerpFest 17 for Mi 11 Lite 5G [UNOFFICIAL][renoir]" (ianchb,
last update 2026-10-10) states "Device / Kernel trees are from LineageOS", kernel 5.4.302, firmware
V14.0.16.0.TKICNXM. Its kernel [ianchb/android_kernel_xiaomi_sm8350-los](https://github.com/ianchb/android_kernel_xiaomi_sm8350-los)
`lineage-24.0` is 25 commits ahead of LineageOS (Docker/Droidspaces configs, KSU, UVC, NTsync, erofs) — **no BPF
changes**. The other public A17 renoir tree ([RobertGarciaa/device_xiaomi_sm8350-common](https://github.com/RobertGarciaa/device_xiaomi_sm8350-common)
`seventeen`) has the same `ro.bpf.kver_override=5.10.239`.

### 1.3 Why the override (not just "relax") is what makes A17 work
`bpf/progs/netd.c` (`android17-release`): the mandatory cgroup programs `ingress/stats`, `egress/stats` exist for
API ≥ 26Q2 only as `5_10…6_1`, `6_1…6_18`, `6_18…INF`; the only 5.4 variants are bounded to `…25Q4`
(`DEFINE_NETD_BPF_PROG_RANGES(ingress, stats, 5_4, 5_10, 25Q2, 25Q4)`). Likewise `inet_release` is 5.10-only.
With the real 5.4 version these programs are simply skipped and netd's attach of the stats programs fails.
With `ro.bpf.kver_override=5.10.239` the 5.10 variants are loaded into the 5.4 kernel — which works only because
the lahaina QGKI 5.4 tree already carries many upstream BPF backports (CAP_BPF, ringbuf, bpf_link, sk_storage …
visible as `UPSTREAM: bpf:` commits in [LineageOS/android_kernel_xiaomi_sm8350](https://github.com/LineageOS/android_kernel_xiaomi_sm8350)).
*(Inference from source; the LineageOS commits give no rationale beyond the version string.)*
With the override set, `isAtLeastKernelVersion(5,10)` is true, so the "relax" patch becomes moot — consistent with
Gerrit 490801 being abandoned for 24.0.

## 2. Can the same be done for a prebuilt Samsung One UI system?

**Yes in principle.** Facts:
- Samsung's `com.android.tethering` is Google's mainline build (on One UI 8.0 it reports version `360743340`;
  on 8.5 it was byte-identical to Nothing OS 4.1's). No Samsung code inside → building it from AOSP gives
  the same component set.
- apexd (`system/apex/apexd/apex_file_repository.cpp`, `android17-release`): a pre-installed APEX is trusted via
  its **own bundled public key** (the partition is the trust anchor); only a key *change between scans* is
  fatal (l.138-141). Data APEXes whose key differs from the pre-installed one are skipped
  (`"public key doesn't match pre-installed one"`, l.425-429). So a self-signed tethering APEX in `/system/apex`
  activates; Play system updates of Tethering will then be rejected (wanted — they would bring the check back).

### Options
| option | verdict |
|---|---|
| A. Build `com.android.tethering` from AOSP `android17-release` (ideally the tag whose version is closest to One UI 9's module) + cherry-pick `ab21b78a1812` (+ optionally `b884d9fe1a72`), sign with our own key, set `ro.bpf.kver_override=5.10.239` in our `product` build.prop | **recommended**. Apache-2.0 source, our own build, minimal diff. |
| B. Take the APEX out of a DerpFest/LineageOS zip | license allows it (Apache-2.0), but it is another porter's build (against our rule), signed with their key, built on a 16.2/24.0 tree with Lineage firewall patches (`netd.c` `bpf_owner_firewall_match`, "Firewall: …" commits) that expect Lineage framework pieces → not used. |
| C. Binary-patch NetBpfLoad inside Google's APEX | needs re-signing anyway, and only removes the check — the 5.10 programs still would not load (§1.3). Not useful. |

### Risks
1. **Stock kernel vs. LineageOS kernel.** LineageOS proves the 5.10 programs pass the verifier on *its* 5.4.302
   kernel. Our port uses Xiaomi's stock `5.4.289-qgki`. Same ACK/CLO lineage, so likely OK, but unverified. If a
   MANDATORY program is rejected → `reboot,bpfloader-failed` loop again. Fallback: build the LineageOS kernel
   (GPL) ourselves.
2. **Module/framework version skew.** `framework-connectivity*.jar` is on the BOOTCLASSPATH and
   `service-connectivity.jar` runs in Samsung's system_server. AOSP vs. Google's build may differ in aconfig flag
   values; Samsung code using hidden module APIs via reflection would break. Mitigation: pick the AOSP source
   that matches the module version Samsung ships (read it from One UI 9's APEX manifest before building).
3. odrefresh will recompile the boot classpath extension on first boot (expected, slower first boot).
4. If Samsung ships it as `.capex`, replace it with a plain `.apex` of the same name (and remove the `.capex`);
   apexd aborts on two packages for one module name.
5. A wiped `/data` is required (no stale `/data/apex/active/com.android.tethering@*`).
6. Platform `bpfloader` (`system/bpf`, A17 `Loader.cpp`) has no hard kernel gate; it keeps using the real 5.4
   version for `/system/etc/bpf` programs (Samsung's own BPF objects) — fine, but watch for its logs.
7. Other modules: A17 init has no kernel minimum (only `SetKernelVersion`), libvintf only flags it (§3). Other
   mainline modules with eBPF (e.g. UprobeStats, profiling) were not audited; check the first boot log.
8. **One UI 9.1 / Android 17 QPR1 (37.1):** the 26Q4 → 5.15 gate plus 5.15-only programs (`bind4/bind6`,
   `set_dscp_ether`) → an override to 5.15 would need far more kernel backports. Treat 9.0 as the end of the line.

## 3. Other Android 17 blockers for an API-30 / target-level-5 vendor on 5.4

| item | A16 QPR2 (One UI 8.5) | A17 (`android17-release`) | impact for us | fix |
|---|---|---|---|---|
| SELinux mapping (`system/sepolicy/private/compat`, `prebuilts/api`) | 29.0 … 34.0, 202404, 202504 | **31.0 … 34.0**, 202404, 202504, 202604 — **29.0 and 30.0 removed** | renoir's vendor policy is 30.0 → no `/system/etc/selinux/mapping/30.0.cil` → init cannot build the policy. LineageOS does not hit this (it builds vendor sepolicy at the current version). | Forward-port A16's `30.0.cil` / `30.0.compat.cil` / `30.0.ignore.cil` to A17's type set (drop types A17 removed, add new types to ignore; same for Samsung's `system_ext` 30.0 mapping that `fix_sepolicy.sh` already patches), or ship a precompiled policy whose sha256 files match. Biggest work item. |
| FCM files (`hardware/interfaces/compatibility_matrices`) | `compatibility_matrix.5.xml` (empty, "kept for android11-5.4 kernel config"), 6, 7, 8, … | **only 7, 8, 202404 … 202704** | device manifest `target-level="5"` → libvintf `"Cannot find framework matrix at FCM version 5"` (`VintfObject.cpp` l.1020) → `verifyBuildAtBoot` fails → "internal problem" dialog (like boot 10). | Add A16's (AOSP) `compatibility_matrix.5.xml` back to `/system/etc/vintf`. LineageOS instead bumped its vendor to `target-level="7"` (`778db2d3f472`), which is not clean for us (see HAL list). |
| kernel requirements in FCMs | 5.4 only via FCM 5/6 (`kernel_config_r_5.4`, `kernel_config_s_5.4`) | min **5.10** (`kernel_config_t_5.10` in FCM 7) | "kernel version mismatch" in the same VINTF check (dialog, not boot-fatal). | Include a 5.4 `<kernel>` block (from AOSP `kernel/configs` r/s `android-5.4`) in the re-added matrix, like LineageOS `82208be11654`. |
| VNDK v30 | apexd + linkerconfig support `com.android.vndk.v30` | still present (`apexd.cpp` `VerifyVndkVersion`, linkerconfig `vndk.cc`) | none; we already ship the AOSP prebuilt APEX. | — |
| HIDL HALs of the stock vendor (not in A17 FCM 7) | | health@2.1, bluetooth.audio@2.0, memtrack@1.0, wifi.hostapd@1.2, wifi.supplicant@1.3, ir@1.0, dumpstate@1.1, tetheroffload.control@1.0 | client code still exists in A17 (`HealthServiceWrapperHidl`, `SupplicantStaIfaceHalHidlImpl`, `HostapdHalHidlImp`, BT `client_interface_hidl.cc`, `ConsumerIrService`, `OffloadHardwareInterface`); HIDL memtrack client was deleted ("delete HIDL memtrack") → only memory accounting lost. | keep target-level 5 + re-added FCM 5 (no deprecation check against FCM 7). |
| Kernel gates elsewhere | | init: none; libvintf: dialog; platform bpfloader: none | | |

LineageOS 24.0 patches relevant to 5.4 besides BPF: `kernel_config_t_5.4` (above), `android_kernel_configs`
`b8edf5101ba9` "Align t/android-5.4 with t/android-5.10", plus vendor-side compat shims (legacy Codec2/Fence
shims in `hardware/lineage/compat`) that we don't need because the vendor keeps running on VNDK v30.

## 4. One UI 9 for the Galaxy S23 (SM-S911B)
- Beta: started 2026-09-03 (India), `S91xBXXUAZZHL`, then `S91xBXXUAZZI8`.
- **Stable**: Korea 2026-10-14 (`S911NKSU8GZIF`), global **`S911BXXUAGZIF`** from 2026-10-19 (Europe incl.),
  security patch October 2026, Android 17.
  Sources: [SamMobile stable](https://www.sammobile.com/news/galaxy-s23-stable-one-ui-9-0-android-17-update-out/),
  [SamMobile beta](https://www.sammobile.com/news/galaxy-s23-s23-s23-ultra-get-one-ui-9-0-beta-update/),
  [samupdater](https://samupdater.com/galaxy-s23-one-ui-9-update/).
- Full firmware: Samsung FUS serves the current full package per model/CSC, which is how we got 8.5/8.0
  (`samloader-rs`). Since EUX received `S911BXXUAGZIF`, a full download should be possible; **not verified**
  (the public `version.xml` endpoint returns 403; no FUS query run). Expected size like before, ~16 GB zip.
- Unknown until the firmware is inspected: whether Samsung ships `netbpfload.rc` with a quarter field, the
  tethering module version, `.capex` vs `.apex`, and Samsung's `system_ext` mapping list.

## 5. Step list (if we go ahead)
1. **De-risk on the running One UI 8.0 port (no new firmware needed):** build `com.android.tethering` from AOSP
   `android16-release` + `ab21b78a1812`, own key, replace Samsung's APEX, add
   `ro.bpf.kver_override=5.10.239`. Pass = NetBpfLoad loads the 5.10 variants on the **stock** kernel
   (logcat `NetBpfLoad`, no `bpfloader-failed`), traffic stats + tethering work.
   Needs an AOSP checkout (≈ 60–100 GB in the VM) — ask before downloading.
   If it fails: build and test the LineageOS `lineage-24.0` sm8350 kernel instead.
2. Download One UI 9 `S911BXXUAGZIF` (EUX) via samloader-rs — ask first with exact size.
3. Inspect: `sdk_full`, `netbpfload.rc` header, tethering version/format, `selinux/mapping/*`, `vintf/*`.
4. Write a mapping generator: A16 `30.0*.cil` (from our 8.5/8.0 images) → A17 types; extend
   `fix_sepolicy.sh`; compile offline like init does until it succeeds.
5. Re-add `compatibility_matrix.5.xml` incl. a 5.4 kernel block to `/system/etc/vintf`; keep the vendor-ndk 30
   framework manifest fragment from 8.0.
6. Rebuild tethering APEX from `android17-release` matching One UI 9's module version + override patch.
7. Carry over the 8.0 fixes (vold/props CIL, audio `_sec.xml`, seapp OEM uids, VNDK v30 APEX), assemble,
   flash, read logs via TWRP/pstore.
