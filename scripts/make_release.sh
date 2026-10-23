#!/usr/bin/env bash
# Pack a flashable zip for users without a build machine: work/out (a full release super from ./build.sh) + MIUI's
# vbmeta images + release/flash_all.{sh,bat} -> work/release/oneui-renoir-<date>.zip. macOS or Linux.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
O=$ROOT/work/out; STOCK=$ROOT/work/stock
[ "$(cat "$O/super.kind" 2>/dev/null)" = full ] || { echo "work/out/super.img is not a full super: run ./build.sh"; exit 1; }
[ "$(cat "$O/build.kind" 2>/dev/null)" = release ] || { echo "not a release build: run DEBUG=0 ./build.sh"; exit 1; }
NAME=oneui-renoir-$(date +%Y%m%d)
D=$ROOT/work/release/$NAME; rm -rf "$D"; mkdir -p "$D/images"
for f in "$O/super.img" "$O/vendor_boot.img" "$STOCK/vbmeta.img" "$STOCK/vbmeta_system.img"; do
  ln "$f" "$D/images/" 2>/dev/null || cp "$f" "$D/images/"
done
cp "$ROOT/release/flash_all.sh" "$ROOT/release/flash_all.bat" "$ROOT/release/README.txt" "$D/"
(cd "$D" && find images -type f | sort | xargs shasum -a 256 > SHA256SUMS)
python3 -I - "$D" "$D.zip" <<'PY'
import os, sys, zipfile
src, out = sys.argv[1], sys.argv[2]
base = os.path.basename(src)
with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=6, allowZip64=True) as z:
    for dp, _, fs in os.walk(src):
        for f in sorted(fs):
            p = os.path.join(dp, f)
            zi = zipfile.ZipInfo.from_file(p, os.path.join(base, os.path.relpath(p, src)))
            zi.compress_type = zipfile.ZIP_DEFLATED
            if f == "flash_all.sh":
                zi.external_attr = 0o100755 << 16
            with open(p, "rb") as fh, z.open(zi, "w", force_zip64=True) as w:
                while b := fh.read(16 << 20):
                    w.write(b)
PY
rm -rf "$D"
(cd "$(dirname "$D")" && shasum -a 256 "$NAME.zip" | tee "$NAME.zip.sha256")
ls -l "$D.zip"
