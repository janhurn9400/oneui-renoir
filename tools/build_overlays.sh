#!/usr/bin/env bash
# Build our own static RROs (overlays/<Name>/) -> input/oneui-overlays/<Name>.apk (committed, so a build needs no
# Android SDK). Run it after changing overlays/, on a machine with the SDK (build-tools, platforms;android-36).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK=${ANDROID_HOME:-$HOME/Library/Android/sdk}
BT=$(ls -d "$SDK"/build-tools/* | tail -1)
AJ=$SDK/platforms/android-36/android.jar
KS=$ROOT/work/keys/oneui-renoir-rro.jks   # created by tools/patch_s23_rro.sh (static overlays: any key works)
for d in "$ROOT"/overlays/*/; do
  n=$(basename "$d"); T=$(mktemp -d)
  "$BT/aapt2" compile --dir "$d/res" -o "$T/res.zip"
  "$BT/aapt2" link -o "$T/u.apk" -I "$AJ" --manifest "$d/AndroidManifest.xml" "$T/res.zip"
  "$BT/zipalign" -f 4 "$T/u.apk" "$T/a.apk"
  "$BT/apksigner" sign --ks "$KS" --ks-pass pass:oneui-renoir --ks-key-alias rro --out "$ROOT/input/oneui-overlays/$n.apk" "$T/a.apk"
  rm -rf "$T" "$ROOT/input/oneui-overlays/$n.apk.idsig"; echo "built input/oneui-overlays/$n.apk"
done
