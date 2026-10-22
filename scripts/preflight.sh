#!/usr/bin/env bash
# Checks the packed images (work/out) before a super is built, so known classes of boot breakers never reach the
# phone. Runs as root INSIDE the VM; build_super_oui.sh calls it and stops on any failure.
#   1. fsck.erofs on every image
#   2. no inline data crossing a 4 KiB block boundary (renoir's 5.4 erofs can't read it, boot 19)
#   3. every changed/added XML (upper dirs of assemble_oui.sh) is well-formed
#   4. every changed/added ELF finds its NEEDED libraries on the target partitions (or the runtime/VNDK sets)
#   5. every service in a changed/added init rc points to an existing, executable, labelled file
set -uo pipefail
P=${P:-/media/psf/Home/Desktop/oneui-renoir}
OUT=$P/work/out
W=/root/oneui-port
PARTS="system system_ext product vendor odm"
M=/root/oneui-preflight
fail=0
bad() { echo "PREFLIGHT FAIL: $*"; fail=1; }

mkdir -p $M
for p in $PARTS; do
  mkdir -p $M/$p
  mountpoint -q $M/$p && umount $M/$p
  mount -o loop,ro $OUT/$p.img $M/$p || bad "$p.img does not mount"
done

echo "== 1. fsck.erofs"
for p in $PARTS; do fsck.erofs $OUT/$p.img >/dev/null 2>&1 || bad "fsck.erofs $p.img"; done

echo "== 2. no inline data across a 4 KiB block boundary (kernel 5.4 can't read it, boot 19)"
for p in $PARTS; do
  bash $P/tools/erofs_inline_check.sh $OUT/$p.img $M/$p > $M/inline_$p.log || bad "$p: $(head -1 $M/inline_$p.log)"
done

echo "== 3. XML well-formed (changed files)"
for p in $PARTS; do
  [ -d $W/$p/u ] || continue
  while IFS= read -r -d '' f; do
    rel=${f#$W/$p/u}
    python3 -I -c "import sys, xml.dom.minidom as m; m.parse(sys.argv[1])" "$M/$p$rel" 2>/dev/null || bad "XML $p$rel"
  done < <(find $W/$p/u -type f -name '*.xml' -print0)
done

echo "== 4. ELF dependencies (changed files)"
libdirs="$M/system/system/lib64 $M/system_ext/lib64 $M/product/lib64 $M/vendor/lib64 $M/odm/lib64"
for p in $PARTS; do
  [ -d $W/$p/u ] || continue
  while IFS= read -r -d '' f; do
    head -c4 "$f" | grep -q $'\x7fELF' || continue
    readelf -h "$f" 2>/dev/null | grep -q "ELF64" || continue
    for n in $(readelf -d "$f" | sed -n 's/.*NEEDED.*\[\(.*\)\]/\1/p'); do
      case $n in libc.so|libm.so|libdl.so|liblog.so|libc++.so|libdl_android.so|libandroidicu.so|libbinder_ndk.so) continue ;; esac
      found=0; for d in $libdirs $M/vendor/lib64/hw $M/system/system/lib64/hw; do [ -e "$d/$n" ] && { found=1; break; }; done
      [ $found = 1 ] || bad "${f#$W/} needs $n (not on any partition)"
    done
  done < <(find $W/$p/u -type f -print0)
done

echo "== 5. init services in changed rc files"
for p in $PARTS; do
  [ -d $W/$p/u ] || continue
  while IFS= read -r -d '' f; do
    awk '$1=="service" {print $3}' "$f" | while read -r exe; do
      case $exe in /system/*) tgt=$M/system$exe ;; /vendor/*) tgt=$M/vendor${exe#/vendor} ;; /system_ext/*) tgt=$M/system_ext${exe#/system_ext} ;; /product/*) tgt=$M/product${exe#/product} ;; *) continue ;; esac
      [ -x "$tgt" ] || { echo "PREFLIGHT FAIL: service binary $exe missing/not executable (${f#$W/})"; continue; }
      getfattr --only-values -n security.selinux "$tgt" >/dev/null 2>&1 || echo "PREFLIGHT FAIL: $exe unlabelled"
    done
  done < <(find $W/$p/u -type f -name '*.rc' -print0)
done 2>&1 | tee $M/rc.log
grep -q "PREFLIGHT FAIL" $M/rc.log && fail=1

for p in $PARTS; do umount $M/$p; done
[ $fail = 0 ] && echo "== preflight OK" || { echo "== preflight FAILED"; exit 1; }
