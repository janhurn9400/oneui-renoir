#!/usr/bin/env bash
# One UI 8.5 port for renoir: Samsung's official SM-S911B system/system_ext/product (work/fw, from
# scripts/extract_firmware.sh) + renoir stock vendor/odm adapted here. Runs as root INSIDE the VM
# (tools/vm.sh < scripts/assemble_oui.sh) -> work/out/{system,system_ext,product,vendor,odm}.img
#
# No full copies of the trees: every partition is an overlayfs (read-only image below, small upper dir in
# /root/oneui-port), packed with mkfs.erofs from the merged view. Files we change get copied up with their
# xattrs; new files get their selinux label explicitly; a final check refuses unlabelled files.
#
# DEBUG=1 (default): adb without authorization (Mac key in /product/etc/security/adb_keys), boot logcat in /metadata,
# dmesg for adb shell. DEBUG=0: release build, adb only after the usual authorization prompt. SELinux is enforcing
# in both (Samsung's policy never let init switch it: every boot so far ran enforcing).
set -euo pipefail
P=${P:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
STOCK=${STOCK:-$P/work/stock}   # renoir stock images from MIUI (scripts/prepare_inputs.sh, read only)
FW=$P/work/fw
OUT=$P/work/out
W=/root/oneui-port
DEBUG=${DEBUG:-1}
Z=${Z:-lz4}             # renoir's 5.4 kernel reads lz4 only; plain lz4 packs much faster than lz4hc,12 (pad retries, see pack)
mkdir -p "$OUT"
[ "$DEBUG" = 1 ] && echo debug > "$OUT/build.kind" || echo release > "$OUT/build.kind"   # scripts/make_release.sh

mnt() { mkdir -p "$2"; mountpoint -q "$2" || mount -o loop,ro "$1" "$2"; }
lower() { case $1 in system|system_ext|product) echo /mnt/oui_f$1 ;; vendor) echo /mnt/oui_rv ;; odm) echo /mnt/oui_ro ;; esac; }
modprobe erofs 2>/dev/null || true
for p in system system_ext product; do mnt $FW/$p.img $(lower $p); done
mnt $STOCK/vendor.img /mnt/oui_rv
mnt $STOCK/odm.img    /mnt/oui_ro

echo "== overlays (fresh upper dirs)"
for p in system system_ext product vendor odm; do
  m=/mnt/oui_m_$p
  mountpoint -q $m && umount $m
  rm -rf $W/$p; mkdir -p $W/$p/u $W/$p/w $m
  # The merged root *is* the upper dir: give it the image root's owner, mode and selinux label, else / or
  # /vendor ends up "unlabeled" (boot 1: init's SetupMountNamespaces was denied mounton / -> kernel panic).
  chown --reference=$(lower $p) $W/$p/u; chmod --reference=$(lower $p) $W/$p/u
  setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux $(lower $p))" $W/$p/u
  mount -t overlay overlay -o lowerdir=$(lower $p),upperdir=$W/$p/u,workdir=$W/$p/w $m
done
S=/mnt/oui_m_system; SE=/mnt/oui_m_system_ext; PR=/mnt/oui_m_product; V=/mnt/oui_m_vendor; O=/mnt/oui_m_odm
label() { setfattr -n security.selinux -v "u:object_r:$1:s0" "${@:2}"; }

echo "== debloat (configs/debloat.txt)"
removed=0
while read -r a; do
  case $a in ''|'#'*) continue ;; esac
  for d in $S/system/app $S/system/priv-app $SE/app $SE/priv-app $PR/app $PR/priv-app; do
    [ -d "$d/$a" ] && { rm -rf "$d/$a"; removed=$((removed + 1)); }
  done
done < $P/configs/debloat.txt
echo "removed $removed app dirs"

echo "== remove single files (configs/remove-files.txt)"
while read -r f; do
  case $f in ''|'#'*) continue ;; esac
  p=${f%%/*}; rel=${f#*/}
  [ -e "/mnt/oui_m_$p/$rel" ] || { echo "missing: $f"; exit 1; }
  rm -f "/mnt/oui_m_$p/$rel"
done < $P/configs/remove-files.txt

echo "== system_ext: VNDK v30 apex for renoir's API-30 vendor (Samsung ships v33 only)"
# AOSP prebuilt (work/input/com.android.vndk.v30.apex, scripts/prepare_inputs.sh, sha256 in configs/inputs.sha256)
install -m 0644 -o root -g root $P/work/input/com.android.vndk.v30.apex $SE/apex/com.android.vndk.v30.apex
label system_file $SE/apex/com.android.vndk.v30.apex
# ...and declare it: Samsung's framework manifest lists vendor-ndk 33 only, so VintfObject::verifyBuildAtBoot fails
# ("Vndk version 30 is not supported") and Build.isBuildConsistent() shows "internal problem" on every boot (boot 10).
cat > $SE/etc/vintf/manifest/oneui-renoir-vndk30.xml <<'XML'
<manifest version="1.0" type="framework">
    <vendor-ndk>
        <version>30</version>
    </vendor-ndk>
</manifest>
XML
chmod 0644 $SE/etc/vintf/manifest/oneui-renoir-vndk30.xml
label system_file $SE/etc/vintf/manifest/oneui-renoir-vndk30.xml

echo "== system: floating features for renoir's fingerprint sensor"
# Samsung's fingerprint service binds vendor.samsung...ISehBiometricsFingerprint unless the manufacturing type
# contains "jdm" (SemBiometricFeature.FP_FEATURE_USE_AOSP_HAL) -> "Fingerprint HAL not available" (boot 16).
# renoir's FPC sensor sits in the power key, not under the display. Rewrite in place (keeps the label).
python3 -I - "$S/system/etc/floating_feature.xml" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
for tag, old, new in (('COMMON_CONFIG_DEVICE_MANUFACTURING_TYPE', 'in_house', 'jdm'),
                      ('BIOAUTH_CONFIG_FINGERPRINT_FEATURES', 'ultrasonic_display_phone', 'side')):
    a = '<SEC_FLOATING_FEATURE_%s>%s</' % (tag, old)
    assert s.count(a) == 1, tag
    s = s.replace(a, '<SEC_FLOATING_FEATURE_%s>%s</' % (tag, new))
with open(p, 'r+') as f: f.write(s); f.truncate()
PY

echo "== system: Bluetooth audio via TrebleDroid's system-side provider (sysbta) + own alias"
# Samsung's Bluetooth stack needs an AIDL BluetoothAudio provider ("BluetoothAudio AIDL implementation does not
# exist"; renoir only has QTI/AOSP HIDL bluetooth.audio@2.0) and then aborted in its legacy QTI path
# ("Check failed: btAudio != nullptr") as soon as A2DP audio started (AirPods dropped). TrebleDroid's sysbta
# (Apache-2.0, device_phh_treble/bluetooth/audio, prebuilt from GSI ci-20250617, see work/input/sysbta) provides it
# system-side together with a system audio HAL 6.0 that hosts audio.sysbta.default. It registers ".../sysbta";
# Samsung's stack only knows ".../default" -> shims/btaudio_alias adds the same binder under that name.
SB=$P/work/input/sysbta
[ -f $SB/bin/hw/android.hardware.bluetooth.audio-service-system ] && [ -f $P/input/shims/btaudio_alias ] \
  || { echo "missing work/input/sysbta or btaudio_alias (shims/build.sh)"; exit 1; }
for d in lib64/hw:system_lib_file bin/hw:system_file; do   # Samsung's system has no lib64/hw
  [ -d $S/system/${d%%:*} ] || { install -d -m 0755 -o root -g root $S/system/${d%%:*}; label ${d##*:} $S/system/${d%%:*}; }
done
for f in $(cd $SB && find lib64 -type f); do
  install -m 0644 -o root -g root $SB/$f $S/system/$f; label system_lib_file $S/system/$f
done
install -m 0755 $SB/bin/hw/android.hardware.bluetooth.audio-service-system $S/system/bin/hw/
install -m 0755 $P/input/shims/btaudio_alias $S/system/bin/hw/btaudio_alias
chown 0:2000 $S/system/bin/hw/android.hardware.bluetooth.audio-service-system $S/system/bin/hw/btaudio_alias   # root:shell
label hal_audio_sysbta_exec $S/system/bin/hw/android.hardware.bluetooth.audio-service-system $S/system/bin/hw/btaudio_alias
cat > $S/system/etc/init/oneui-renoir-btaudio.rc <<'RC'
# TrebleDroid's sysbta service (device_phh_treble/bluetooth/audio/hal) + our alias as ".../default"
service system.bt-audio-hal /system/bin/hw/android.hardware.bluetooth.audio-service-system
    class hal
    user audioserver
    group audio camera drmrpc inet media mediadrm net_bt net_bt_admin net_bw_acct wakelock context_hub
    capabilities BLOCK_SUSPEND
    ioprio rt 4
    task_profiles ProcessCapacityHigh HighPerformance
    onrestart restart audioserver
    onrestart restart system.bt-audio-alias

service system.bt-audio-alias /system/bin/hw/btaudio_alias
    class hal
    user audioserver
    group audio
RC
cat > $S/system/etc/vintf/manifest/oneui-renoir-btaudio.xml <<'XML'
<manifest version="1.0" type="framework">
    <hal format="aidl">
        <name>android.hardware.bluetooth.audio</name>
        <version>4</version>
        <fqname>IBluetoothAudioProviderFactory/sysbta</fqname>
        <fqname>IBluetoothAudioProviderFactory/default</fqname>
    </hal>
    <hal>
        <name>android.hardware.audio</name>
        <transport>hwbinder</transport>
        <fqname>@6.0::IDevicesFactory/sysbta</fqname>
    </hal>
</manifest>
XML
chmod 0644 $S/system/etc/init/oneui-renoir-btaudio.rc $S/system/etc/vintf/manifest/oneui-renoir-btaudio.xml
label system_file $S/system/etc/init/oneui-renoir-btaudio.rc $S/system/etc/vintf/manifest/oneui-renoir-btaudio.xml
# ".../sysbta" has no service context in Samsung's policy (only ".../default")
echo 'android.hardware.bluetooth.audio.IBluetoothAudioProviderFactory/sysbta u:object_r:hal_audio_service:s0' \
  >> $SE/etc/selinux/system_ext_service_contexts

echo "== system: vibrator proxy (shims/vibrator_proxy): IVibrator/default -> Xiaomi's vibratorfeature + ISehVibrator stub"
# One UI only uses IVibrator/default and needs the Samsung ISehVibrator extension on it (boot 5: SIGSEGV in
# AidlHalWrapper::supportsHapticEngine with Xiaomi's HAL registered as default). See the source for details.
[ -f $P/input/shims/vibrator_proxy ] || { echo "run shims/build.sh first"; exit 1; }
install -m 0755 $P/input/shims/vibrator_proxy $S/system/bin/hw/vibrator_proxy
chown 0:2000 $S/system/bin/hw/vibrator_proxy
label hal_vibrator_proxy_exec $S/system/bin/hw/vibrator_proxy
cat > $S/system/etc/init/oneui-renoir-vibrator.rc <<'RC'
service system.vibrator-proxy /system/bin/hw/vibrator_proxy
    class hal
    user system
    group system
RC
cat > $S/system/etc/vintf/manifest/oneui-renoir-vibrator.xml <<'XML'
<manifest version="1.0" type="framework">
    <hal format="aidl">
        <name>android.hardware.vibrator</name>
        <fqname>IVibrator/default</fqname>
    </hal>
</manifest>
XML
chmod 0644 $S/system/etc/init/oneui-renoir-vibrator.rc $S/system/etc/vintf/manifest/oneui-renoir-vibrator.xml
label system_file $S/system/etc/init/oneui-renoir-vibrator.rc $S/system/etc/vintf/manifest/oneui-renoir-vibrator.xml

echo "== system_ext: selinux domain for Samsung apps with OEM uids (5000-5999)"
# A Samsung vendor maps these uids (com.samsung.cmh 5004, scloud/scpm 5009, rubin 5010); without an entry zygote
# aborts: "seapp_context_lookup: No match for app with uid 5004 ... username oem_5004" (boot 10). Run them like the
# platform apps with uid system.
echo 'user=oem_* seinfo=platform domain=system_app type=system_app_data_file' >> $SE/etc/selinux/system_ext_seapp_contexts

echo "== vendor: LineageOS renoir overlays (cutout, corners, brightness curve, refresh rates)"
for a in FrameworkOverlayRenoir FrameworkOverlaySM8350 SystemUIOverlayRenoir SystemUIOverlaySM8350 \
         WifiOverlayRenoir WifiOverlaySM8350 SettingsProviderOverlayRenoir; do
  install -m 0644 -o root -g root "$P/input/lineage-overlays/$a.apk" "$V/overlay/$a.apk"
  label vendor_overlay_file "$V/overlay/$a.apk"
done
echo "== vendor: own overlays (overlays/, prebuilt in input/oneui-overlays by tools/build_overlays.sh)"
for d in $P/overlays/*/; do
  a=$(basename $d)
  [ -f $P/input/oneui-overlays/$a.apk ] || { echo "run tools/build_overlays.sh first ($a)"; exit 1; }
  install -m 0644 -o root -g root $P/input/oneui-overlays/$a.apk "$V/overlay/$a.apk"
  label vendor_overlay_file "$V/overlay/$a.apk"
done

echo "== vendor build.prop: Android 15+ init no longer reads /vendor/default.prop -> merge it"
{ echo; echo "# --- merged from /vendor/default.prop (oneui-renoir)"; cat $V/default.prop; } >> $V/build.prop
rm -f $V/default.prop

echo "== fstab: no AVB/dm-verity, no MIUI mi_ext overlays (first-stage copy is in vendor_boot)"
for f in $V/etc/fstab.default $V/etc/fstab.emmc; do python3 -I $P/tools/vendorboot_fstab.py --fstab "$f" "$f"; done

if [ "${VIBRATOR_DEFAULT:-0}" = 1 ]; then
echo "== vibrator: Xiaomi's HAL registers IVibrator/vibratorfeature, Android looks for /default (see nothing-renoir)"
VB=$V/bin/hw/vendor.xiaomi.hardware.vibratorfeature.service
python3 -I - "$VB" <<'PY'
import sys
f = open(sys.argv[1], 'r+b'); d = f.read()
old = b'/vibratorfeature\0'; assert d.count(old) == 1, 'instance string not found once'
f.seek(d.index(old)); f.write(b'/default\0'.ljust(len(old), b'\0'))
# No IVibratorExt binder extension: frameworks that probe the extension for their own interface
# (Nothing's RichTap, possibly Samsung's) then fall back to the plain IVibrator calls.
SETEXT = 0xa2f8; assert d[SETEXT:SETEXT + 4] == bytes.fromhex('f2510094'), 'setExtension call moved'
f.seek(SETEXT); f.write(bytes.fromhex('00008052')); f.close()
PY
VX=$V/etc/vintf/manifest/vendor.xiaomi.hardware.vibratorfeature.service.xml
sed 's|IVibrator/vibratorfeature|IVibrator/default|' $VX > $W/vib.xml; cat $W/vib.xml > $VX; rm $W/vib.xml
grep -q 'IVibrator/default' $VX
else
  # Boot 5: with Xiaomi's HAL registered as IVibrator/default, Samsung's libvibratorservice asks it for Samsung's
  # haptic-engine extension and dereferences null (AidlHalWrapper::supportsHapticEngine, system_server SIGSEGV loop).
  # Unpatched, the HAL stays at IVibrator/vibratorfeature: no vibration, but system_server boots (as on Mystic/lisa).
  echo "== vibrator: Xiaomi HAL left unpatched (VIBRATOR_DEFAULT=1 enables the Nothing-port patch)"
fi

echo "== audio policy: drop the Multiroute device Android 16 no longer knows (found in nothing-renoir)"
# audioserver loads /vendor/etc/audio/sku_<sku>_qssi/audio_policy_configuration.xml; its AUDIO_DEVICE_OUT_MULTIROUTE
# port was removed in Android 16, so the parser drops the whole file (-22) and falls back to speaker only
# (no Bluetooth/USB/wired audio). Remove the port and its route; rewrite in place to keep the selinux label.
python3 -I - "$V/etc/audio/sku_shima_qssi/audio_policy_configuration.xml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
port = re.compile(r'\n[ \t]*<devicePort tagName="Multiroute" type="AUDIO_DEVICE_OUT_MULTIROUTE".*?</devicePort>', re.S)
route = re.compile(r'\n[ \t]*<route type="mix" sink="Multiroute"\s+sources="[^"]*"/>')
s, n1 = port.subn('', s); s, n2 = route.subn('', s)
assert (n1, n2) == (1, 1) and 'MULTIROUTE' not in s and 'Multiroute' not in s, (n1, n2)
with open(p, 'r+') as f: f.write(s); f.truncate()
PY

echo "== audio: Samsung's audioserver reads *_sec.xml configs only (a Samsung vendor ships them)"
# libaudiopolicycomponents looks for audio_policy_configuration_sec.xml ("Audio policy configuration file name is
# empty" -> speaker-only fallback), libeffectsconfig for audio_effects_sec.xml (not found -> AudioPolicyEffects
# aborts audioserver, boot 10). Provide renoir's own files under those names (the lisa reference vendor has
# Samsung-flavoured copies). Policy: the full QTI one fixed above (absolute XIncludes).
install -m 0644 -o root -g root $V/etc/audio/sku_shima_qssi/audio_policy_configuration.xml $V/etc/audio_policy_configuration_sec.xml
install -m 0644 -o root -g root $V/etc/audio_effects.xml $V/etc/audio_effects_sec.xml
# A2DP output goes to TrebleDroid's sysbta module (see the Bluetooth section): drop the QTI A2DP offload ports
# of the primary module and replace the QTI "bluetooth_qti" module (its HIDL session is not the one Samsung's stack
# uses) with sysbta's module. A2DP input (sink mode) is dropped with it.
python3 -I - "$V/etc/audio_policy_configuration_sec.xml" "$P/work/input/sysbta/etc/sysbta_audio_policy_configuration.xml" <<'EOF'
import re, sys
p, sb = sys.argv[1:3]; s = open(p).read()
mod = open(sb).read()
mod = mod[mod.index('<module'):mod.rindex('</module>') + len('</module>')]
pm = re.search(r'<module name="primary".*?</module>', s, re.S).group(0)
pm2, n1 = re.subn(r'\n[ \t]*<devicePort tagName="BT A2DP (Out|Headphones|Speaker)".*?</devicePort>', '', pm, flags=re.S)
pm2, n2 = re.subn(r'\n[ \t]*<route type="mix" sink="BT A2DP (Out|Headphones|Speaker)"\s+sources="[^"]*"\s*/>', '', pm2)
assert (n1, n2) == (3, 3), (n1, n2)
s = s.replace(pm, pm2)
s, n3 = re.subn(r'<module name="bluetooth_qti".*?</module>', lambda m: mod, s, flags=re.S)
assert n3 == 1, n3
with open(p, 'r+') as f: f.write(s); f.truncate()
print('audio policy: A2DP -> sysbta')
EOF
label vendor_configs_file $V/etc/audio_policy_configuration_sec.xml $V/etc/audio_effects_sec.xml
# Boot 12: distorted sound. Samsung's mixer then runs in the primary/deep-buffer HAL format (24-bit packed here);
# the lisa reference uses 16-bit for those outputs. Rewrite in place (keeps the label).
python3 -I - "$V/etc/audio_policy_configuration_sec.xml" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read(); n = 0
for port in ('primary output', 'deep_buffer', 'virtual_deep_buffer'):
    m = re.search(r'<mixPort name="%s".*?</mixPort>' % port, s, re.S)
    assert m and 'AUDIO_FORMAT_PCM_24_BIT_PACKED' in m.group(0), port
    s = s[:m.start()] + m.group(0).replace('AUDIO_FORMAT_PCM_24_BIT_PACKED', 'AUDIO_FORMAT_PCM_16_BIT') + s[m.end():]; n += 1
with open(p, 'r+') as f: f.write(s); f.truncate()
print('16-bit outputs:', n)
PY

echo "== display config: brightness via HWC (renoir's lights path is broken, see nothing-renoir)"
mkdir -p $V/etc/displayconfig
install -m 0644 -o root -g root $P/configs/displayconfig/display_port_130.xml $V/etc/displayconfig/display_port_130.xml
# Samsung's DisplayDeviceConfig ignores display_port_<n>.xml and only reads displayconfig/default.xml (else the S23
# config.xml arrays + the broken lights path: odd brightness, boot 12/14).
install -m 0644 -o root -g root $P/configs/displayconfig/display_port_130.xml $V/etc/displayconfig/default.xml
label vendor_configs_file $V/etc/displayconfig $V/etc/displayconfig/display_port_130.xml $V/etc/displayconfig/default.xml
# /vendor/etc/displayconfig/default.xml was not picked up (boot 15: still "<config.xml>"); Samsung looks in /product first
mkdir -p $PR/etc/displayconfig
install -m 0644 -o root -g root $P/configs/displayconfig/display_port_130.xml $PR/etc/displayconfig/default.xml
label system_file $PR/etc/displayconfig $PR/etc/displayconfig/default.xml

echo "== USB: AOSP configfs gadget rules (Samsung's copy is all commented out; see configs/init/oneui-renoir-usb.rc)"
install -m 0644 -o root -g root $P/configs/init/oneui-renoir-usb.rc $V/etc/init/oneui-renoir-usb.rc
label vendor_configs_file $V/etc/init/oneui-renoir-usb.rc
# configs/init/oneui-renoir-data.rc (pre-create /data/sec/geodb) is NOT installed: from system_ext, init's mkdir on
# the existing /data/sec failed its encryption check and init rebooted into MIUI recovery offering a wipe (boot 17).

echo "== fingerprint: enroll timeout shim preloaded into mfp-daemon (shims/fpc_timeout, built by shims/build.sh)"
# Samsung always sends enroll timeout 0; renoir's FPC HAL then waits 0 ms for the finger (FPC_ERROR_TIMEDOUT,
# boots 17/18). The shim turns 0 into AOSP's 60 s. Rewrite the rc in place (keeps its selinux label).
[ -f $P/input/shims/libfpc_timeout_shim.so ] || { echo "run shims/build.sh first"; exit 1; }
install -m 0644 -o root -g root $P/input/shims/libfpc_timeout_shim.so $V/lib64/libfpc_timeout_shim.so
label vendor_file $V/lib64/libfpc_timeout_shim.so
python3 -I - "$V/etc/init/init.mfp-daemon.rc" <<'PY'
import sys
p = sys.argv[1]; s = open(p).read()
a = '    seclabel u:r:vendor_mfp-daemon:s0\n'
assert s.count(a) == 1 and 'LD_PRELOAD' not in s
s = s.replace(a, a + '    setenv LD_PRELOAD /vendor/lib64/libfpc_timeout_shim.so\n')
with open(p, 'r+') as f: f.write(s); f.truncate()
PY

echo "== brightness: lights HAL shim (shims/lights_scale, built by shims/build.sh)"
# lights.qcom.so takes the MIUI backlight path when ro.product.manufacturer is "Xiaomi" (inherited from the vendor):
# zig-zag brightness, black at the low end (boots 20/21). The shim reports "samsung" to the lights HAL only.
[ -f $P/input/shims/liblights_scale_shim.so ] || { echo "run shims/build.sh first"; exit 1; }
install -m 0644 -o root -g root $P/input/shims/liblights_scale_shim.so $V/lib64/liblights_scale_shim.so
label vendor_file $V/lib64/liblights_scale_shim.so
python3 -I - "$V/etc/init/android.hardware.lights-qti.rc" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
a = 'service vendor.light-qti /vendor/bin/hw/android.hardware.lights-service.qti\n'
assert s.count(a) == 1 and 'LD_PRELOAD' not in s
s = s.replace(a, a + '    setenv LD_PRELOAD /vendor/lib64/liblights_scale_shim.so\n')
with open(p, 'r+') as f: f.write(s); f.truncate()
EOF

echo "== remove Xiaomi payment/security services that need MIUI's framework"
for a in MipayService SoterService IFAAService CACertService; do rm -rf "$V/app/$a"; done

echo "== product: S23 framework overlay without cutout/status bar sizes (tools/patch_s23_rro.sh, ./build.sh runs it)"
# Product overlays outrank the LineageOS renoir overlays; with Samsung's original the S23 centre "notch" is drawn
# (boot 12). Removing it entirely crashes system_server on the brightness map (boot 13).
RRO=framework-res__dm1qxxx__auto_generated_rro_product.apk
[ -f $P/work/input/$RRO ] || { echo "run tools/patch_s23_rro.sh first"; exit 1; }
cat $P/work/input/$RRO > $PR/overlay/$RRO   # rewrite in place: keeps the selinux label

echo "== product: FRP partition path (Samsung's /dev/block/persistent doesn't exist on renoir)"
# Boot 7: PersistentDataBlockService could not open ro.frp.pst -> "init timeout" in boot phase 500 -> system_server
# crash loop ("Optimizing apps" over and over). renoir's frp partition is labelled frp_block_device by its vendor.
# Rewrite Samsung's line in place (keeps the file's selinux label).
sed 's|^ro\.frp\.pst=.*|ro.frp.pst=/dev/block/bootdevice/by-name/frp|' $PR/etc/build.prop > $W/product.prop
cat $W/product.prop > $PR/etc/build.prop; rm $W/product.prop
grep -qx 'ro.frp.pst=/dev/block/bootdevice/by-name/frp' $PR/etc/build.prop

echo "== product: device props"
# product's build.prop is loaded after system's, so these win.
cat >> $PR/etc/build.prop <<'PROPS'

# --- oneui-renoir device values
ro.sf.lcd_density=440
ro.config.media_vol_steps=25
ro.config.media_vol_default=15
# No Knox/TIMA on this hardware (as in the Mystic GSI)
ro.config.knox=false
ro.config.dmverity=false
# CSC normally comes from Samsung's optics partition; without it every ro.csc.* is empty and Galaxy Store says it
# is not available on this device (boot 12). DBT = Germany, unbranded (part of the EUX firmware we use).
ro.csc.sales_code=DBT
ro.csc.countryiso_code=DE
ro.csc.country_code=GERMANY
# Galaxy Store still refused with 2300:1004 (its countrySearchEx call) after ro.csc.*; it also reads these.
persist.omc.sales_code=DBT
ro.product_ship=true
PROPS

if [ "$DEBUG" = 1 ]; then
  echo "== DEBUG: adb without auth from early boot (Mac key), no rescue party, boot logcat"
  install -m 0644 -o root -g root ${ADB_KEY:-$P/work/.vm/adbkey.pub} $PR/etc/security/adb_keys   # ./build.sh: ADB_KEY
  label adb_keys_file $PR/etc/security/adb_keys
  cat >> $PR/etc/build.prop <<'PROPS'

# --- oneui-renoir debug (DEBUG=1 builds only)
ro.adb.secure=0
persist.sys.usb.config=mtp,adb
persist.sys.disable_rescue=true
# kernel messages into logcat (-b kernel) and so into the /metadata boot log: boot-time USB/driver issues stay
# readable after the ring buffer has wrapped
ro.logd.kernel=true
PROPS
  cat >> $V/build.prop <<'PROPS'

# --- oneui-renoir debug (DEBUG=1 builds only)
ro.adb.secure=0
persist.sys.usb.config=mtp,adb
persist.service.adb.enable=1
persist.sys.disable_rescue=true
PROPS
  cat > $V/etc/init/oneui-renoir-debug.rc <<'RC'
# Full logcat of every boot in /metadata (unencrypted ext4, 11 MB; TWRP mounts it), readable when USB/adb never
# comes up: adb pull /metadata/oneui-logcat.txt (+ .1). At most 2 x 1.5 MB, so vold's keys there keep their room.
service oneui_bootlog /system/bin/logcat -b all -v threadtime -f /metadata/oneui-logcat.txt -r 1536 -n 1
    user root
    group log
    seclabel u:r:oneui_bootlog:s0
    disabled
on post-fs-data
    start oneui_bootlog

# kernel log for adb shell (dmesg) in debug builds
on boot
    write /proc/sys/kernel/dmesg_restrict 0

# adb also in Samsung's charging-only mode (sys.usb.state stays "sec_charging" for the framework)
on property:sys.usb.config=sec_charging && property:sys.usb.configfs=1
    start adbd
on property:sys.usb.ffs.ready=1 && property:sys.usb.config=sec_charging && property:sys.usb.configfs=1
    write /config/usb_gadget/g1/configs/b.1/strings/0x409/configuration "adb"
    symlink /config/usb_gadget/g1/functions/ffs.adb /config/usb_gadget/g1/configs/b.1/f1
    write /config/usb_gadget/g1/UDC ${sys.usb.controller}
RC
  chmod 0644 $V/etc/init/oneui-renoir-debug.rc
  label vendor_configs_file $V/etc/init/oneui-renoir-debug.rc
  cat >> $V/etc/selinux/vendor_sepolicy.cil <<'CIL'
;; oneui-renoir debug: dmesg for adb shell
(allow shell kernel (system (syslog_read)))
(allow shell kmsg_device (chr_file (read open getattr)))
;; oneui-renoir debug: boot logcat into /metadata (oneui-renoir-debug.rc), own permissive domain
(type oneui_bootlog)
(roletype r oneui_bootlog)
(typeattributeset domain (oneui_bootlog))
(typepermissive oneui_bootlog)
(allow init oneui_bootlog (process (transition siginh rlimitinh noatsecure)))
(allow init logcat_exec (file (read open getattr execute map)))
(allow oneui_bootlog logcat_exec (file (read open getattr execute entrypoint map)))
CIL
fi

echo "== sepolicy: Samsung's vold opens a generic netlink socket while setting up FBE (denied 100x on boot 2)"
cat >> $V/etc/selinux/vendor_sepolicy.cil <<'CIL'
;; oneui-renoir: Samsung vold (FBE key setup)
(allow vold self (netlink_socket (create bind read write getattr setopt)))
;; Samsung vold reports FBE state in security.fbe.* (exported_system_prop here; a Samsung vendor labels and allows
;; it) and Samsung init waits for security.fbe.global_de: denied on boot 2 -> "Timed out waiting for loading
;; global de", stuck on the Mi logo. sys.is_vold_shutdown is system_prop.
(allow vold exported_system_prop (property_service (set)))
(allow vold system_prop (property_service (set)))
;; Samsung framework parts set properties a Samsung vendor allows them (boot 8). Fatal: Samsung's wifi in
;; system_server sets vendor.wifi.dualconcurrent.interface (wifi_log_prop here) and crashes when denied.
(allow system_server wifi_log_prop (property_service (set)))
(allow cameraserver exported_system_prop (property_service (set)))
(allow bootanim audio_prop (property_service (set)))
(allow bootanim ctl_bootanim_prop (property_service (set)))
;; Boot 10: Samsung IMS (system_app) sets ril.* (radio_prop here) and crashes when denied.
(allow system_app radio_prop (property_service (set)))
;; Boot 10: SystemUI (platform_app) crash loop "Unable to open socket for UEventObserver"; Samsung's plat policy
;; has no such rule for platform_app, a Samsung vendor adds it.
(allow platform_app self (netlink_kobject_uevent_socket (create bind read setopt getopt)))
;; Boot 14: Samsung Core Services (platform_app) creates /data/sec/geodb (sec_data_file) -> AccessDeniedException
;; crash (e.g. when Chrome uses its search). A Samsung vendor allows it.
(allow platform_app sec_data_file (dir (search getattr read open write add_name remove_name create)))
(allow platform_app sec_data_file (file (create getattr read write open append lock unlink rename map)))
;; dumpstate aborts on /data/log (dumplog_data_file) after every app crash ("Permission denied", removeOldFiles).
(allow dumpstate dumplog_data_file (dir (search getattr read open write add_name remove_name create)))
(allow dumpstate dumplog_data_file (file (create getattr read write open append unlink rename)))
;; mfp-daemon gets the fingerprint timeout shim via LD_PRELOAD; the domain transition would set AT_SECURE and the
;; linker would drop LD_PRELOAD.
(allow init vendor_mfp-daemon (process (noatsecure)))
;; the lights HAL gets the backlight rescale shim via LD_PRELOAD (same reason)
(allow init hal_light_default (process (noatsecure)))
;; TrebleDroid's system-side Bluetooth audio HAL (sysbta) and our alias (device_phh_treble sepolicy/hal_audio_sysbta.te
;; in CIL). Enforcing: the hal_audio_server/halserverdomain attributes cover it (no denials while permissive).
(type hal_audio_sysbta)
(roletype r hal_audio_sysbta)
(typeattributeset domain (hal_audio_sysbta))
(typeattributeset coredomain (hal_audio_sysbta))
(typeattributeset hal_audio_server (hal_audio_sysbta))
(typeattributeset halserverdomain (hal_audio_sysbta))
(typeattributeset hal_allocator_client (hal_audio_sysbta))
(type hal_audio_sysbta_exec)
(roletype object_r hal_audio_sysbta_exec)
(typeattributeset exec_type (hal_audio_sysbta_exec))
(typeattributeset system_file_type (hal_audio_sysbta_exec))
(typeattributeset file_type (hal_audio_sysbta_exec))
(allow init hal_audio_sysbta_exec (file (read getattr map execute open)))
(allow init hal_audio_sysbta (process (transition siginh rlimitinh noatsecure)))
(allow hal_audio_sysbta hal_audio_sysbta_exec (file (read getattr map execute open entrypoint)))
(typetransition init hal_audio_sysbta_exec process hal_audio_sysbta)
;; vibrator proxy (shims/vibrator_proxy): serves IVibrator/default, uses Xiaomi's IVibrator/vibratorfeature.
;; Enforcing: the hal_vibrator_* attributes cover it (no denials while permissive).
(type hal_vibrator_proxy)
(roletype r hal_vibrator_proxy)
(typeattributeset domain (hal_vibrator_proxy))
(typeattributeset coredomain (hal_vibrator_proxy))
(typeattributeset hal_vibrator_server (hal_vibrator_proxy))
(typeattributeset hal_vibrator_client (hal_vibrator_proxy))
(typeattributeset halserverdomain (hal_vibrator_proxy))
(typeattributeset halclientdomain (hal_vibrator_proxy))
(type hal_vibrator_proxy_exec)
(roletype object_r hal_vibrator_proxy_exec)
(typeattributeset exec_type (hal_vibrator_proxy_exec))
(typeattributeset system_file_type (hal_vibrator_proxy_exec))
(typeattributeset file_type (hal_vibrator_proxy_exec))
(allow init hal_vibrator_proxy_exec (file (read getattr map execute open)))
(allow init hal_vibrator_proxy (process (transition siginh rlimitinh noatsecure)))
(allow hal_vibrator_proxy hal_vibrator_proxy_exec (file (read getattr map execute open entrypoint)))
(typetransition init hal_vibrator_proxy_exec process hal_vibrator_proxy)
CIL

echo "== odm: the edited vendor policy must be compiled on boot -> drop the precompiled one"
rm -f $O/etc/selinux/precompiled_sepolicy*

echo "== sepolicy: compile Samsung's policy + renoir vendor like init does, fix until it builds"
mkdir -p $P/sepolicy
bash $P/scripts/fix_sepolicy.sh $V $S $SE $PR $P/sepolicy/fixes.log
cp $V/etc/selinux/vendor_sepolicy.cil $P/sepolicy/vendor_sepolicy.cil

echo "== every changed/new file keeps a selinux label"
bad=0
for p in system system_ext product vendor odm; do
  m=/mnt/oui_m_$p
  while IFS= read -r -d '' f; do
    rel=${f#$W/$p/u}
    [ -c "$f" ] && continue                                   # whiteout (deleted file)
    if ! getfattr --only-values -n security.selinux "$m$rel" >/dev/null 2>&1; then
      echo "unlabelled: /$p$rel"; bad=1
    fi
  done < <(find $W/$p/u -print0)
  [ "$(stat -c '%u:%g %a' $m)" = "$(stat -c '%u:%g %a' $(lower $p))" ] || { echo "root owner/mode differ: /$p"; bad=1; }
done
[ $bad = 0 ]

echo "== pack (erofs $Z, fixed timestamps)"
# PACK="vendor odm" repacks only those (the other images in work/out must be from the same sources)
for p in ${PACK:-system_ext product vendor odm system}; do
  mp=/$p; [ $p = system ] && mp=/
  # renoir's 5.4 erofs can't read inline data crossing a 4 KiB block boundary (boot 19: the /system/lib64/libm.so
  # symlink landed on one -> 64-bit binaries failed -> boringssl self test reboot loop). mkfs.erofs 1.9 always
  # inlines symlinks (-E noinline_data only covers regular files), so check the image and, if an inode crosses,
  # add an empty pad file (shifts the inode layout) and pack again.
  etc=/mnt/oui_m_$p   # pad at the image root: sorts before every directory, so it shifts all inodes
  for try in 0 1 2 3 4 5 6 7; do
    mkfs.erofs -z$Z -E noinline_data -T 1230768000 --mount-point=$mp "$OUT/$p.img" /mnt/oui_m_$p >/dev/null
    mkdir -p /root/oneui-pack-chk; mount -o loop,ro "$OUT/$p.img" /root/oneui-pack-chk
    ok=0; bash $P/tools/erofs_inline_check.sh "$OUT/$p.img" /root/oneui-pack-chk > /root/oneui-pack-chk.log || ok=$?
    umount /root/oneui-pack-chk
    [ $ok = 0 ] && break
    echo "$p: inline data across a block boundary: $(head -1 /root/oneui-pack-chk.log) -> pad $try"
    [ $try = 7 ] && { echo "could not avoid the boundary"; exit 1; }
    # one more empty pad inode per try (the number of inodes shifts the layout, their size does not)
    : > $etc/.0oneui_erofs_pad_$try; chmod 0644 $etc/.0oneui_erofs_pad_$try
    setfattr -n security.selinux -v "$(getfattr --only-values -n security.selinux $etc)" $etc/.0oneui_erofs_pad_$try
  done
  echo "$p.img $(stat -c %s "$OUT/$p.img")"
done
for p in system system_ext product vendor odm; do umount /mnt/oui_m_$p; done
total=$(( $(stat -c %s $OUT/system.img) + $(stat -c %s $OUT/system_ext.img) + $(stat -c %s $OUT/product.img) + $(stat -c %s $OUT/vendor.img) + $(stat -c %s $OUT/odm.img) ))
echo "== total $total of 9073118412 bytes (group qti_dynamic_partitions_a)"
echo "== done -> $OUT"
