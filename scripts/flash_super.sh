#!/usr/bin/env bash
# Flash the One UI port super (scripts/build_super_oui.sh) from the bootloader (normal fastboot, no fastbootd).
# Expects renoir's stock firmware/boot/dtbo on the phone (true after MIUI's flash_all or the Nothing port).
# Also writes vbmeta with verification disabled (MIUI's vbmeta images, work/stock).
# Usage: scripts/flash_super.sh [--wipe]    (switching from another ROM needs --wipe)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FB="${FASTBOOT:-$(command -v fastboot || echo "$HOME/Library/Android/sdk/platform-tools/fastboot")}"
OUTDIR=$(cd "${OUTDIR:-$ROOT/work/out}" && pwd)
STOCK=${STOCK:-$ROOT/work/stock}   # scripts/prepare_inputs.sh
SUPER=$OUTDIR/super.img
VBOOT=$OUTDIR/vendor_boot.img   # stock + fstab without AVB/mi_ext (tools/vendorboot_fstab.py)
for f in "$SUPER" "$VBOOT"; do [ -f "$f" ] || { echo "missing $f"; exit 1; }; done
product=$("$FB" getvar product 2>&1 | awk -F': *' '/^product:/ {print $2}')
[ "$product" = renoir ] || { echo "no renoir in fastboot mode (product='$product')"; exit 1; }
"$FB" getvar is-userspace 2>&1 | grep -q 'is-userspace: no' || { echo "reboot to the bootloader first"; exit 1; }
echo "-> vbmeta + vbmeta_system with verification disabled (stock flash_all re-enables it)"
"$FB" --disable-verity --disable-verification flash vbmeta_ab "$STOCK/vbmeta.img"
"$FB" --disable-verity --disable-verification flash vbmeta_system_ab "$STOCK/vbmeta_system.img"
echo "-> flash vendor_boot (both slots)"
"$FB" flash vendor_boot_ab "$VBOOT"
echo "-> flash super"
"$FB" flash super "$SUPER"
# Remember what is on the phone now, so build_super_oui.sh may build a delta super next time (ONLY=...).
[ -f "$OUTDIR/super.layout" ] && cp "$OUTDIR/super.layout" "$OUTDIR/super.flashed.layout"
# userdata and metadata belong together (metadata holds the /data encryption keys): wipe both or neither.
if [ "${1:-}" = "--wipe" ]; then
  echo "-> erase userdata + metadata (clean first boot)"
  "$FB" erase userdata
  "$FB" erase metadata
else
  echo "-> keeping userdata (pass --wipe for a clean first boot)"
fi
# Never chain set_active right after a big super flash: Xiaomi's parallel flashing may still be writing,
# and an interrupted set_active corrupted the LUN 4 GPT once (fixed with: fastboot flash partition:4 gpt_both4.bin).
# Xiaomi's "parallel-download-flash" keeps writing super in the background after "OKAY"; a reboot sent
# right away is dropped. Wait until the bootloader answers a harmless query again (the userdata erase
# above has the same effect), then continue.
echo "-> waiting for the bootloader to finish writing super in the background ..."
for i in $(seq 1 90); do "$FB" getvar product 2>&1 | grep -q '^product: renoir' && break; sleep 5; done
# set_active rewrites slot attributes in the GPT; skip it when slot a is already active (always after flash_all).
slot=$("$FB" getvar current-slot 2>&1 | awk -F': *' '/^current-slot:/ {print $2}')
if [ "$slot" != a ]; then
  "$FB" reboot bootloader
  for i in $(seq 1 60); do "$FB" devices | grep -q fastboot && break; sleep 2; done
  "$FB" set_active a
fi
"$FB" reboot
# The images are rebuilt for every flash anyway; don't keep ~10 GB around (KEEP=1 keeps them).
if [ "${KEEP:-0}" != 1 ]; then
  for p in super system system_ext product vendor odm; do rm -f "$OUTDIR/$p.img"; done
  echo "-> removed the flashed super/partition images from $OUTDIR (KEEP=1 keeps them)"
fi
echo "== done. First boot takes 5-10 minutes."
# If a fastboot command ever hangs: do NOT kill it or force-reboot the phone. Wait, then replug the cable.
