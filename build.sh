#!/usr/bin/env bash
# Build the One UI 8.0 port for renoir from the three public downloads (see README.md):
#
#   SAMSUNG_FW=~/dl/SM-S911B_..._S911BXXS9EZCI_fac.zip \
#   MIUI_TGZ=~/dl/renoir_global_images_V14.0.7.0.TKIMIXM_20231222.0000.00_13.0_global_e21e2a7d85.tgz \
#   GSI=~/dl/system-td-arm64-vanilla.img.xz \
#   ./build.sh
#
# -> work/out/super.img + vendor_boot.img, flashed with scripts/flash_super.sh --wipe.
# Runs in Docker (Dockerfile) on a Linux host; NO_DOCKER=1 runs it directly (as root, on Ubuntu 26.04 or alike).
# DEBUG=1 builds a debug image: adb without authorization for ADB_KEY (default ~/.android/adbkey.pub), boot logcat
# in /metadata. Default is a release build (DEBUG=0).
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
DEBUG=${DEBUG:-0}

if [ "${NO_DOCKER:-0}" != 1 ] && [ "${IN_DOCKER:-0}" != 1 ]; then
  args=(); mounts=()
  for v in SAMSUNG_FW MIUI_TGZ GSI VNDK30_APEX; do
    [ -n "${!v:-}" ] || continue
    f=$(cd "$(dirname "${!v}")" && pwd)/$(basename "${!v}")
    mounts+=(-v "$f:/in/$v:ro"); args+=(-e "$v=/in/$v")
  done
  if [ "$DEBUG" = 1 ]; then
    key=${ADB_KEY:-$HOME/.android/adbkey.pub}
    [ -f "$key" ] || { echo "DEBUG=1 needs ADB_KEY=<adbkey.pub>"; exit 1; }
    mkdir -p "$ROOT/work"; cp "$key" "$ROOT/work/adbkey.pub"
  fi
  docker build -t oneui-renoir-build "$ROOT"
  # the overlayfs upper dirs must not live on the container's own overlay root -> named volume
  exec docker run --rm --privileged -e IN_DOCKER=1 -e DEBUG="$DEBUG" "${args[@]}" "${mounts[@]}" \
    -v "$ROOT:/src" -v oneui-renoir-port:/root/oneui-port oneui-renoir-build ./build.sh
fi

[ "$(id -u)" = 0 ] || { echo "needs root (loop mounts)"; exit 1; }
export P=$ROOT DEBUG
[ "$DEBUG" = 1 ] && export ADB_KEY=${ADB_KEY:-$ROOT/work/adbkey.pub}
modprobe erofs 2>/dev/null || true; modprobe overlay 2>/dev/null || true
bash "$ROOT/scripts/prepare_inputs.sh"
RRO=framework-res__dm1qxxx__auto_generated_rro_product.apk
[ -f "$ROOT/work/input/$RRO" ] || bash "$ROOT/tools/patch_s23_rro.sh" "$ROOT/work/input/s23_rro_orig.apk" "$ROOT/work/input/$RRO"
bash "$ROOT/scripts/assemble_oui.sh"
rm -f "$ROOT/work/out/super.flashed.layout"   # a fresh build is always a full super
bash "$ROOT/scripts/build_super_oui.sh"
echo "== done: flash with scripts/flash_super.sh --wipe (phone in the bootloader, see README.md)"
