#!/usr/bin/env bash
# One UI 8.0 for renoir: flash everything from the bootloader (Linux and macOS). ERASES ALL DATA.
# Phone: stock MIUI V14.0.7.0.TKIMIXM firmware, unlocked bootloader, power off -> hold Power + Volume down -> USB.
set -euo pipefail
cd "$(dirname "$0")"
FB=${FASTBOOT:-$( [ -x platform-tools/fastboot ] && echo platform-tools/fastboot || command -v fastboot || true )}
[ -n "$FB" ] || { echo "fastboot not found: install Android platform-tools or put them into ./platform-tools"; exit 1; }
for f in images/super.img images/vendor_boot.img images/vbmeta.img images/vbmeta_system.img; do
  [ -f "$f" ] || { echo "missing $f"; exit 1; }
done
echo "Waiting for the phone in fastboot mode ..."
until "$FB" devices | grep -q fastboot; do sleep 2; done
product=$("$FB" getvar product 2>&1 | awk -F': *' '/^product:/ {print $2}')
[ "$product" = renoir ] || { echo "this is not a Mi 11 Lite 5G / renoir (product: '$product')"; exit 1; }
"$FB" getvar is-userspace 2>&1 | grep -q 'is-userspace: no' \
  || { echo "phone is in fastbootd: reboot to the bootloader (fastboot reboot bootloader)"; exit 1; }
printf '\nThis flashes One UI 8.0 and ERASES ALL DATA on the phone. Type YES to continue: '
read -r ok; [ "$ok" = YES ] || { echo "cancelled"; exit 1; }
"$FB" --disable-verity --disable-verification flash vbmeta_ab images/vbmeta.img
"$FB" --disable-verity --disable-verification flash vbmeta_system_ab images/vbmeta_system.img
"$FB" flash vendor_boot_ab images/vendor_boot.img
"$FB" flash super images/super.img
# userdata and metadata belong together (metadata holds the /data encryption keys)
"$FB" erase userdata
"$FB" erase metadata
# Xiaomi's bootloader may still be writing super in the background: wait until it answers again
for _ in $(seq 1 90); do "$FB" getvar product 2>&1 | grep -q '^product: renoir' && break; sleep 5; done
slot=$("$FB" getvar current-slot 2>&1 | awk -F': *' '/^current-slot:/ {print $2}')
if [ "$slot" != a ]; then
  "$FB" reboot bootloader
  for _ in $(seq 1 60); do "$FB" devices | grep -q fastboot && break; sleep 2; done
  "$FB" set_active a
fi
"$FB" reboot
echo "Done. The first boot takes 5-10 minutes. If a fastboot command ever hangs: wait, then replug the cable."
