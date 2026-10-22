#!/usr/bin/env bash
# Read the last boot's logs without Android's adb: wait for the bootloader (Power+Vol-down), RAM-boot TWRP (nothing
# is flashed, no slot switch), pull the /metadata logcat of oneui-renoir-debug.rc and pstore into work/logs/<name>.
# Usage: scripts/twrp_logs.sh boot12
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PT=${PT:-$HOME/Library/Android/sdk/platform-tools}
TWRP=${TWRP:-$HOME/Desktop/nothing-renoir/input/recovery/twrp-3.7.0_11-0-renoir.img}
D=$ROOT/work/logs/${1:?usage: twrp_logs.sh <logdir name>}
export ADB_LIBUSB=1
mkdir -p "$D"
echo "== waiting for the bootloader (phone: hold Power + Vol-down until FASTBOOT shows) ..."
until "$PT/fastboot" devices | grep -q fastboot; do sleep 1; done
echo "== RAM-boot TWRP (nothing gets flashed)"
"$PT/fastboot" boot "$TWRP"
# TWRP's USB never comes up by itself on renoir: every time, Mount -> Disable MTP -> Enable MTP, then replug.
echo "== phone: in TWRP Mount -> Disable MTP -> Enable MTP, then unplug and replug the cable. Waiting for adb ..."
until [ "$("$PT/adb" get-state 2>/dev/null || true)" = recovery ]; do sleep 2; done
echo "== mounting /metadata and pulling logs to $D"
"$PT/adb" shell 'mountpoint -q /metadata || mount /metadata' || true
"$PT/adb" shell 'ls -la /metadata/ /sys/fs/pstore/' || true
for f in /metadata/oneui-logcat.txt /metadata/oneui-logcat.txt.1 /sys/fs/pstore/console-ramoops-0 /sys/fs/pstore/pmsg-ramoops-0; do
  "$PT/adb" pull "$f" "$D/" || true
done
ls -la "$D"
echo "== done. Phone stays in TWRP; reboot it with: adb reboot"
