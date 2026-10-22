#!/usr/bin/env bash
# Samsung's Galaxy S23 framework-res overlay (product/overlay/framework-res__dm1qxxx__auto_generated_rro_product.apk)
# carries the S23 cutout and status bar sizes. Product overlays outrank /vendor/overlay, so renoir's LineageOS values
# never apply ("notch" drawn at the top centre, boot 12). Removing the whole overlay is no option: system_server then
# crashes on the brightness map (boot 13). So drop only those entries; the vendor overlay fills them in.
# Runs on the Mac (apktool, build-tools): tools/patch_s23_rro.sh <original.apk> <out.apk>
set -euo pipefail
IN=$1; OUT=$2
BT=$(ls -d "$HOME"/Library/Android/sdk/build-tools/* | tail -1)
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KS=$ROOT/work/keys/oneui-renoir-rro.jks
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
apktool d -f -o "$T/d" "$IN" >/dev/null
for n in config_mainBuiltInDisplayCutout status_bar_height_portrait status_bar_camera_side_padding status_bar_camera_top_margin; do
  grep -q "name=\"$n\"" "$T/d/res/values/public.xml" || { echo "missing $n"; exit 1; }
  sed -i '' "/name=\"$n\"/d" "$T"/d/res/values/*.xml
done
apktool b -o "$T/u.apk" "$T/d" >/dev/null
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass oneui-renoir -keypass oneui-renoir -alias rro -keyalg RSA \
    -keysize 2048 -validity 10000 -dname "CN=oneui-renoir test overlays" >/dev/null 2>&1
fi
"$BT/zipalign" -f 4 "$T/u.apk" "$T/a.apk"
"$BT/apksigner" sign --ks "$KS" --ks-pass pass:oneui-renoir --ks-key-alias rro --out "$OUT" "$T/a.apk"
"$BT/aapt2" dump resources "$OUT" | grep -c "resource 0x" | sed 's/^/resources left: /'
