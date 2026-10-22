#!/usr/bin/env bash
# Build work/out/super.img (Android sparse, written directly: no raw super on disk) from the images of
# assemble_oui.sh and verify it by sha256. Runs inside the VM (tools/vm.sh < scripts/build_super_oui.sh).
# vendor_boot: renoir stock + fstab without AVB/mi_ext + AVB footer, built in the sibling project
# (nothing-renoir/work/out/vendor_boot.img); the first-stage fstab does not depend on the ROM.
#
# ONLY="vendor product" builds a delta super (metadata + those partitions, the rest DONT_CARE): flashing it leaves
# the other partitions on the phone as they are. Only used when every other partition has exactly the start/size
# recorded at the last flash (work/out/super.flashed.layout, written by flash_super.sh); otherwise a full super.
set -euo pipefail
P=${P:-/media/psf/Home/Desktop/oneui-renoir}
NR=${NR:-/media/psf/Home/Desktop/nothing-renoir}
O=$P/work/out
PARTS="system system_ext product vendor odm"
args=""; for p in $PARTS; do args="$args ${p}_a=$O/$p.img"; done
mk() {  # shellcheck disable=SC2086
  python3 -I $P/tools/lpmake.py "$@" --layout=$O/super.layout $NR/work/super-stock-head.bin $O/super.img $args
}
check=$PARTS
bash $P/scripts/preflight.sh || { echo "preflight failed: not building super"; exit 1; }
if [ -n "${ONLY:-}" ] && [ -f $O/super.flashed.layout ]; then
  only=$(for p in $ONLY; do printf '%s_a,' $p; done); only=${only%,}
  mk --only=$only
  same=1
  for p in $PARTS; do
    case " $ONLY " in *" $p "*) continue ;; esac
    [ "$(grep "^${p}_a " $O/super.layout)" = "$(grep "^${p}_a " $O/super.flashed.layout)" ] || { echo "layout of $p changed"; same=0; }
  done
  if [ $same = 1 ]; then check=$ONLY; else echo "== falling back to a full super"; mk --sparse; fi
else
  [ -n "${ONLY:-}" ] && echo "== no super.flashed.layout yet: full super"
  mk --sparse
fi
echo "== verify ($check)"
# shellcheck disable=SC2086
python3 -I $P/tools/sparse_lpextract.py --sha256 $check < $O/super.img | grep -v '^sparse:\|^done' | sort -k2 > $O/super.sha256
(cd $O && for p in $check; do echo "$(sha256sum < $p.img | cut -d' ' -f1)  $p"; done) | sort -k2 | diff - $O/super.sha256 \
  && echo "all partitions OK"
cp $NR/work/out/vendor_boot.img $O/vendor_boot.img
ls -l $O
