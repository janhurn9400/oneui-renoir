#!/usr/bin/env bash
# Bring the phone into the bootloader from wherever it is: Android (adb device), TWRP (adb recovery) or already
# fastboot. Waits (up to 10 min) until one of them shows up; during a boot loop adb is only there for moments.
set -euo pipefail
PT=${PT:-$HOME/Library/Android/sdk/platform-tools}
export ADB_LIBUSB=1
for _ in $(seq 1 300); do
  if "$PT/fastboot" devices | grep -q fastboot; then echo "in fastboot"; exit 0; fi
  state=$("$PT/adb" get-state 2>/dev/null || true)
  if [ "$state" = device ] || [ "$state" = recovery ]; then
    echo "adb ($state) -> reboot bootloader"
    "$PT/adb" reboot bootloader || true
    for _ in $(seq 1 60); do "$PT/fastboot" devices | grep -q fastboot && { echo "in fastboot"; exit 0; }; sleep 2; done
  fi
  sleep 2
done
echo "phone not found (adb/fastboot)"; exit 1
