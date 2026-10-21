#!/usr/bin/env bash
# Pull system/system_ext/product out of a Samsung firmware zip (samloader download) without unpacking the
# AP tar or writing the ~14 GB super image: zip -> AP tar -> super.img.lz4 -> lz4 -> tools/sparse_lpextract.py.
# Runs inside the VM: tools/vm.sh < scripts/extract_firmware.sh
# Env: FW=<zip> (default: the only *_fac.zip in work/dl), OUT=<dir> (default work/fw), PARTS="system system_ext product"
set -euo pipefail
P=${P:-/media/psf/Home/Desktop/oneui-renoir}
FW=${FW:-$(ls $P/work/dl/*_fac.zip)}
OUT=${OUT:-$P/work/fw}
PARTS=${PARTS:-system system_ext product}
mkdir -p "$OUT"
echo "== $(basename "$FW")"
unzip -l "$FW"
AP=$(unzip -Z1 "$FW" | grep '^AP_.*\.tar\.md5$')
echo "== $AP contents"
unzip -p "$FW" "$AP" | tar -tvf - | tee "$OUT/ap-contents.txt"
SUPER=$(awk '{print $NF}' "$OUT/ap-contents.txt" | grep -x 'super\.img\.lz4')
echo "== streaming $SUPER -> $PARTS"
unzip -p "$FW" "$AP" | tar -xOf - "$SUPER" | lz4 -dc | python3 -I $P/tools/sparse_lpextract.py "$OUT" $PARTS
for p in $PARTS; do echo "$p: $(file -b "$OUT/$p.img" | cut -c1-80)"; done
ls -l "$OUT"
