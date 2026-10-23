#!/usr/bin/env bash
# Take everything the build needs from three public downloads and check it against configs/inputs.sha256.
# Runs as root on Linux (loop mounts); ./build.sh calls it inside the Docker container.
#
#   SAMSUNG_FW=<SM-S911B S911BXXS9EZCI firmware zip>        -> work/fw/{system,system_ext,product}.img
#   MIUI_TGZ=<renoir_global_images_V14.0.7.0.TKIMIXM_*.tgz> -> work/stock/ (vendor, odm, vendor_boot, vbmeta*,
#                                                              super metadata head, vendor_boot with the port's fstab)
#   GSI=<system-td-arm64-vanilla.img.xz, TrebleDroid ci-20250617> -> work/input/sysbta/, com.android.vndk.v30.apex
#   VNDK30_APEX=<com.android.vndk.v30.apex> (optional: AOSP prebuilt, e.g. from Nothing OS 4.1's system_ext)
#
# Steps whose output already exists and matches are skipped, so a re-run only redoes what is missing.
set -euo pipefail
P=${P:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
W=$P/work; STOCK=$W/stock; IN=$W/input
T=$W/tmp-prepare; mkdir -p "$W/fw" "$STOCK" "$IN" "$T"
trap 'umount "$T"/m 2>/dev/null || true; rm -rf "$T"' EXIT

# ok <path under work/>...: all listed files exist and match configs/inputs.sha256
ok() {
  local f
  for f in "$@"; do
    grep -q "  $f\$" "$P/configs/inputs.sha256" || { echo "not in inputs.sha256: $f"; return 2; }
    [ -f "$W/$f" ] || return 1
  done
  (cd "$W" && grep -E "  ($(IFS='|'; echo "$*"))\$" "$P/configs/inputs.sha256" | sha256sum -c --quiet -) >/dev/null 2>&1
}
need() { [ -n "${!1:-}" ] && [ -f "${!1}" ] || { echo "set $1=<file> ($2)"; exit 1; }; }

echo "== Samsung firmware"
if ok fw/system.img fw/system_ext.img fw/product.img; then echo "work/fw: up to date"; else
  need SAMSUNG_FW "SM-S911B firmware S911BXXS9EZCI, the zip with AP_*.tar.md5"
  FW=$SAMSUNG_FW OUT=$W/fw bash "$P/scripts/extract_firmware.sh"
fi
if ! ok input/s23_rro_orig.apk; then
  # product overlay with the S23 cutout/brightness values; tools/patch_s23_rro.sh strips them (build.sh)
  mkdir -p "$T/m"; mount -o loop,ro "$W/fw/product.img" "$T/m"
  cp "$T/m/overlay/framework-res__dm1qxxx__auto_generated_rro_product.apk" "$IN/s23_rro_orig.apk"
  umount "$T/m"
fi

echo "== renoir stock (MIUI)"
if ok stock/vendor.img stock/odm.img stock/super-head.bin stock/vendor_boot.img stock/vbmeta.img stock/vbmeta_system.img
then echo "work/stock: up to date"; else
  need MIUI_TGZ "renoir MIUI V14.0.7.0.TKIMIXM fastboot ROM (.tgz)"
  tar -xzf "$MIUI_TGZ" -C "$T" --wildcards '*/images/super.img*' '*/images/vendor_boot.img' '*/images/vbmeta*.img'
  I=$(dirname "$(find "$T" -path '*/images/vendor_boot.img' | head -1)")
  cp "$I/vendor_boot.img" "$I/vbmeta.img" "$I/vbmeta_system.img" "$STOCK/"
  supers=$(find "$I" -maxdepth 1 -name 'super.img*' | sort -V)
  if [ "$(echo "$supers" | wc -l)" = 1 ] && python3 -I -c "import sys; sys.exit(open(sys.argv[1],'rb').read(4) != bytes.fromhex('3aff26ed'))" "$supers"; then
    # one sparse image: stream it, never write the raw 9 GB super
    SUPER_HEAD=$STOCK/super-head.bin python3 -I "$P/tools/sparse_lpextract.py" "$STOCK" vendor odm < "$supers"
  else
    # shellcheck disable=SC2086
    python3 -I "$P/tools/sparse2raw.py" "$T/super.raw" $supers
    head -c $((4 << 20)) "$T/super.raw" > "$STOCK/super-head.bin"
    python3 -I "$P/tools/lpunpack.py" "$T/super.raw" "$T/lp"
    mv "$T/lp/vendor"*.img "$STOCK/vendor.img"; mv "$T/lp/odm"*.img "$STOCK/odm.img"
  fi
  rm -rf "${T:?}"/*
fi
if ! ok stock/vendor_boot.port.img; then
  # first-stage fstab without AVB flags and mi_ext, fresh AVB footer (the bootloader refuses images without one)
  python3 -I "$P/tools/vendorboot_fstab.py" "$STOCK/vendor_boot.img" "$T/vb.raw"
  python3 -I "$P/tools/avb_footer.py" "$STOCK/vendor_boot.img" "$T/vb.raw" "$STOCK/vendor_boot.port.img"
fi

echo "== TrebleDroid GSI: sysbta (system-side Bluetooth audio) and the VNDK v30 apex"
mapfile -t gsi_files < <(awk '$2 ~ /^input\/(sysbta\/|com\.android\.vndk)/ {print $2}' "$P/configs/inputs.sha256")
if ok "${gsi_files[@]}"; then echo "work/input: up to date"; else
  need GSI "system-td-arm64-vanilla.img.xz from github.com/TrebleDroid/treble_experimentations release ci-20250617"
  case $GSI in *.xz) xz -dc -T0 "$GSI" > "$T/gsi.img" ;; *) cp "$GSI" "$T/gsi.img" ;; esac
  mkdir -p "$T/m"; mount -o loop,ro "$T/gsi.img" "$T/m"
  R=$T/m/system; [ -d "$R/lib64" ] || R=$T/m
  for f in "${gsi_files[@]}"; do
    case $f in
      input/sysbta/*) src=$R/${f#input/sysbta/} ;;
      *) src=$(find "$T/m" -name "$(basename "$f")" | head -1)   # AOSP prebuilt; VNDK30_APEX=<file> if not in the GSI
         [ -n "${VNDK30_APEX:-}" ] && src=$VNDK30_APEX ;;
    esac
    [ -f "$src" ] || { echo "not in the GSI: $f"; exit 1; }
    install -D -m 0644 "$src" "$W/$f"
  done
  chmod 0755 "$IN/sysbta/bin/hw/"*
  umount "$T/m"
fi

echo "== verify (configs/inputs.sha256)"
(cd "$W" && grep -v '^#' "$P/configs/inputs.sha256" | sha256sum -c --quiet -) \
  || { echo "inputs differ from the tested ones: check the download versions above"; exit 1; }
echo "== inputs OK"
