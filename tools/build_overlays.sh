#!/usr/bin/env bash
# Build our own static RROs (overlays/<Name>/) -> work/input/<Name>.apk. Runs on the Mac (SDK build-tools).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK=$HOME/Library/Android/sdk
BT=$(ls -d "$SDK"/build-tools/* | tail -1)
AJ=$SDK/platforms/android-36/android.jar
KS=$ROOT/work/keys/oneui-renoir-rro.jks   # created by tools/patch_s23_rro.sh
for d in "$ROOT"/overlays/*/; do
  n=$(basename "$d"); T=$(mktemp -d)
  "$BT/aapt2" compile --dir "$d/res" -o "$T/res.zip"
  "$BT/aapt2" link -o "$T/u.apk" -I "$AJ" --manifest "$d/AndroidManifest.xml" "$T/res.zip"
  "$BT/zipalign" -f 4 "$T/u.apk" "$T/a.apk"
  "$BT/apksigner" sign --ks "$KS" --ks-pass pass:oneui-renoir --ks-key-alias rro --out "$ROOT/work/input/$n.apk" "$T/a.apk"
  rm -rf "$T"; echo "built work/input/$n.apk"
done
