#!/usr/bin/env bash
# List inline (layout 2) inodes of an erofs image whose inode + xattrs + inline data cross a 4 KiB block boundary.
# renoir's 5.4 kernel can't read those ("erofs_fill_symlink: inline data cross block boundary", boot 19: the
# /system/lib64/libm.so symlink -> 64-bit binaries failed -> boot loop). mkfs.erofs 1.9 inlines symlinks even with
# -E noinline_data. Usage: erofs_inline_check.sh <image> <mounted dir of that image>; prints offenders, exit 1 if any.
set -uo pipefail
img=$1; mnt=$2; bad=0
while IFS= read -r -d '' f; do
  rel=/${f#$mnt/}
  out=$(dump.erofs --path="$rel" "$img" 2>/dev/null) || continue
  lay=$(sed -n 's/.*Layout: \([0-9]*\).*/\1/p' <<<"$out")
  [ "$lay" = 2 ] || continue
  nid=$(sed -n 's/^NID: \([0-9]*\).*/\1/p' <<<"$out")
  isz=$(sed -n 's/^Inode size: \([0-9]*\).*/\1/p' <<<"$out")
  xsz=$(sed -n 's/.*Xattr size: \([0-9]*\).*/\1/p' <<<"$out")
  dsz=$(sed -n 's/^Size: \([0-9]*\).*/\1/p' <<<"$out")
  off=$(( (nid * 32) % 4096 ))
  if [ $(( off + isz + xsz + dsz % 4096 )) -gt 4096 ]; then echo "$rel (nid $nid: $off+$isz+$xsz+$((dsz % 4096)))"; bad=1; fi
done < <(find "$mnt" \( -type l -o \( -type f -size -4096c \) \) -print0)
exit $bad
