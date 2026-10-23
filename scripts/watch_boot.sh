#!/usr/bin/env bash
# Watch a test boot from the Mac: wait for adb, wait for boot_completed, then stream the crash buffer.
A=${ADB:-$(command -v adb || echo "$HOME/Library/Android/sdk/platform-tools/adb")}
echo "== waiting for adb ..."
"$A" wait-for-device
echo "== adb up, waiting for sys.boot_completed ..."
until [ "$("$A" shell getprop sys.boot_completed 2>/dev/null | tr -d '\r')" = 1 ]; do sleep 3; done
echo "== boot_completed. Crashes live (Ctrl-C to stop):"
"$A" logcat -b crash -v time
