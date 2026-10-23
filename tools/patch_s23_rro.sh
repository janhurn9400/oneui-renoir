#!/usr/bin/env bash
# Samsung's Galaxy S23 framework-res overlay (product/overlay/framework-res__dm1qxxx__auto_generated_rro_product.apk)
# carries the S23 cutout and status bar sizes. Product overlays outrank /vendor/overlay, so renoir's LineageOS values
# never apply ("notch" drawn at the top centre, boot 12). Removing the whole overlay is no option: system_server then
# crashes on the brightness map (boot 13). So drop only those entries; the vendor overlay fills them in.
# Needs apktool, keytool and zipalign/apksigner/aapt2 (SDK build-tools via BT=<dir>, else from PATH, e.g. Ubuntu's
# apktool/zipalign/apksigner/aapt packages): tools/patch_s23_rro.sh <original.apk> <out.apk>
set -euo pipefail
IN=$1; OUT=$2
BT=${BT:-$(ls -d "${ANDROID_HOME:-$HOME/Library/Android/sdk}"/build-tools/* 2>/dev/null | tail -1)}
bt() { if [ -n "$BT" ]; then "$BT/$1" "${@:2}"; else "$@"; fi; }
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KS=$ROOT/work/keys/oneui-renoir-rro.jks
T=$(mktemp -d); trap 'rm -rf "$T"' EXIT
apktool d -f -o "$T/d" "$IN" >/dev/null
for n in config_mainBuiltInDisplayCutout status_bar_height_portrait status_bar_camera_side_padding status_bar_camera_top_margin \
         config_screenBrightnessExtendedMaximum; do   # S23: 612 -> backlight max 2.4 vs renoir table up to 1.0 (boot 21)
  grep -q "name=\"$n\"" "$T/d/res/values/public.xml" || { echo "missing $n"; exit 1; }
  sed -i.bak "/name=\"$n\"/d" "$T"/d/res/values/*.xml && rm -f "$T"/d/res/values/*.bak
done
# S23 panel brightness tables (backlight 0..612 -> normalised up to 2.4): on renoir the slider went black at the left,
# barely changed and flickered (boot 20). Removed here; overlays/FrameworkOverlayOneUIRenoir sets renoir's own.
python3 -I - "$T/d/res/values" <<'PY2'
import re, sys
d = sys.argv[1]
for n in ('config_screenBrightnessBacklight', 'config_screenBrightnessNits'):
    a = open(d + '/arrays.xml').read()
    a, k = re.subn(r'\n[ \t]*<(integer-array|array) name="%s">.*?</\1>' % n, '', a, flags=re.S)
    assert k == 1, n
    open(d + '/arrays.xml', 'w').write(a)
    pub = open(d + '/public.xml').read()
    pub, k = re.subn(r'\n[ \t]*<public type="array" name="%s" id="[^"]*" />' % n, '', pub)
    assert k == 1, n
    open(d + '/public.xml', 'w').write(pub)
PY2
apktool b -o "$T/u.apk" "$T/d" >/dev/null
if [ ! -f "$KS" ]; then
  mkdir -p "$(dirname "$KS")"
  keytool -genkeypair -keystore "$KS" -storepass oneui-renoir -keypass oneui-renoir -alias rro -keyalg RSA \
    -keysize 2048 -validity 10000 -dname "CN=oneui-renoir test overlays" >/dev/null 2>&1
fi
bt zipalign -f 4 "$T/u.apk" "$T/a.apk"
bt apksigner sign --ks "$KS" --ks-pass pass:oneui-renoir --ks-key-alias rro --out "$OUT" "$T/a.apk"
if [ -n "$BT" ] || command -v aapt2 >/dev/null; then
  bt aapt2 dump resources "$OUT" | grep -c "resource 0x" | sed 's/^/resources left: /'
fi
