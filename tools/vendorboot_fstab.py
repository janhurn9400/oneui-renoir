#!/usr/bin/env python3
"""Patch the first-stage fstabs inside a vendor_boot (header v3/v4) like OemPorts10T does:
drop AVB flags (avb, avb=..., avb_keys=...) and the MIUI mi_ext mount + overlay lines.

Usage: vendorboot_fstab.py IN_vendor_boot.img OUT_vendor_boot.img
Also usable on a plain fstab file: vendorboot_fstab.py --fstab IN OUT
The ramdisk is gzip (as on renoir stock); cpio newc entries are rewritten in order, only fstab* contents change.
"""
import gzip
import os
import re
import struct
import sys


def patch_fstab(text):
    out = []
    for line in text.splitlines(keepends=True):
        s = line.strip()
        if s and not s.startswith("#"):
            fields = s.split()
            if "mi_ext" in s or (fields[0] == "overlay" and len(fields) > 2 and fields[2] == "overlay"):
                continue
            if len(fields) >= 5:
                flags = [f for f in fields[4].split(",")
                         if f != "avb" and not f.startswith("avb=") and not f.startswith("avb_keys=")]
                line = line.replace(fields[4], ",".join(flags), 1)
        out.append(line)
    return "".join(out)


def cpio_entries(data):
    off = 0
    while True:
        hdr = data[off:off + 110]
        assert hdr[:6] in (b"070701", b"070702"), hdr[:6]
        fields = [int(hdr[6 + i * 8:14 + i * 8], 16) for i in range(13)]
        namesize, filesize = fields[11], fields[6]
        name = data[off + 110:off + 110 + namesize - 1].decode()
        doff = (off + 110 + namesize + 3) & ~3
        body = data[doff:doff + filesize]
        yield hdr, fields, name, body
        off = (doff + filesize + 3) & ~3
        if name == "TRAILER!!!":
            return


def cpio_build(entries):
    out = bytearray()
    for hdr, fields, name, body in entries:
        fields = list(fields)
        fields[6] = len(body)
        fields[11] = len(name) + 1
        out += hdr[:6] + b"".join(b"%08X" % v for v in fields)
        out += name.encode() + b"\0"
        out += b"\0" * (-len(out) % 4)
        out += body
        out += b"\0" * (-len(out) % 4)
    return bytes(out)


def main():
    if sys.argv[1] == "--fstab":
        src, dst = sys.argv[2:4]
        text = patch_fstab(open(src).read())  # read before opening dst: src may be dst
        with open(dst, "w") as f:  # same inode -> owner/mode/selinux xattr stay
            f.write(text)
        return
    src, dst = sys.argv[1:3]
    d = open(src, "rb").read()
    assert d[:8] == b"VNDRBOOT"
    ver, page, _, _, rsize = struct.unpack_from("<IIIII", d, 8)
    off = 8 + 20 + 2048 + 4 + 16
    hsize, dtbsize = struct.unpack_from("<II", d, off)
    pages = lambda n: (n + page - 1) // page * page
    rstart = pages(hsize)
    ramdisk = gzip.decompress(d[rstart:rstart + rsize])
    dtb = d[rstart + pages(rsize):rstart + pages(rsize) + dtbsize]
    rest_off = rstart + pages(rsize) + pages(dtbsize)
    if ver >= 4:  # v4 has a ramdisk table + bootconfig after dtb; keep this tool v3-only
        raise SystemExit("vendor_boot v4 not supported")
    entries, changed = [], []
    for hdr, fields, name, body in cpio_entries(ramdisk):
        if re.search(r"(^|/)fstab\.[^/]+$", name):
            new = patch_fstab(body.decode()).encode()
            if new != body:
                changed.append(name)
            body = new
        entries.append((hdr, fields, name, body))
    new_rd = gzip.compress(cpio_build(entries), 9, mtime=0)
    header = bytearray(d[:hsize])
    struct.pack_into("<I", header, 8 + 16, len(new_rd))
    # Optional extra kernel cmdline args (vendor cmdline field: 2048 bytes at offset 28).
    extra = os.environ.get("VB_CMDLINE_ADD", "").strip()
    if extra:
        cmd = bytes(header[28:28 + 2048]).split(b"\0")[0].decode()
        if extra not in cmd:
            cmd = (cmd + " " + extra).strip()
        if len(cmd) >= 2048:
            raise SystemExit("cmdline too long")
        header[28:28 + 2048] = cmd.encode().ljust(2048, b"\0")
        print("cmdline +", extra)
    img = bytes(header) + b"\0" * (pages(hsize) - hsize)
    img += new_rd + b"\0" * (pages(len(new_rd)) - len(new_rd))
    img += dtb + b"\0" * (pages(dtbsize) - dtbsize)
    if len(img) > len(d):
        raise SystemExit("patched image larger than original")
    # No padding: the bootloader needs an AVB footer with the real size ->
    # avbtool add_hash_footer --partition_size <partition> afterwards (scripts/build_vendor_boot.sh).
    open(dst, "wb").write(img)
    print("patched:", ", ".join(changed), f"| ramdisk {rsize} -> {len(new_rd)} bytes, rest at {rest_off}")


if __name__ == "__main__":
    main()
