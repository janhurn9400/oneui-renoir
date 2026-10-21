#!/usr/bin/env python3
"""Split a raw super.img (dynamic partitions, liblp metadata) into its logical partition images.

Usage: lpunpack.py SUPER.raw OUTDIR [--slot 0]
Prints the partition table; empty partitions (e.g. the *_b slot) are skipped.
"""
import os
import struct
import sys

SECTOR = 512
GEOMETRY_OFFSET = 4096
GEOMETRY_MAGIC = 0x616C4467
HEADER_MAGIC = 0x414C5030


def read_metadata(f, slot):
    f.seek(GEOMETRY_OFFSET)
    magic, _, _, max_size, slot_count, _ = struct.unpack("<II32sIII", f.read(52))
    if magic != GEOMETRY_MAGIC:
        raise SystemExit("no liblp geometry found (is this a raw super image?)")
    # Layout: reserved 4096 | geometry 4096 | backup geometry 4096 | primary metadata slots...
    f.seek(GEOMETRY_OFFSET + 2 * 4096 + slot * max_size)
    hdr = f.read(256)
    magic, major, minor, hdr_size = struct.unpack_from("<IHHI", hdr)
    if magic != HEADER_MAGIC:
        raise SystemExit("bad metadata header magic")
    tables_size = struct.unpack_from("<I", hdr, 44)[0]
    descs = [struct.unpack_from("<III", hdr, 80 + i * 12) for i in range(4)]
    f.seek(GEOMETRY_OFFSET + 2 * 4096 + slot * max_size + hdr_size)
    tables = f.read(tables_size)
    (p_off, p_num, p_sz), (e_off, e_num, e_sz), (g_off, g_num, g_sz), _ = descs
    groups = [tables[g_off + i * g_sz:g_off + i * g_sz + 36].split(b"\0")[0].decode()
              for i in range(g_num)]
    extents = [struct.unpack_from("<QIQI", tables, e_off + i * e_sz) for i in range(e_num)]
    parts = []
    for i in range(p_num):
        base = p_off + i * p_sz
        name = tables[base:base + 36].split(b"\0")[0].decode()
        _, first, count, group = struct.unpack_from("<IIII", tables, base + 36)
        parts.append((name, groups[group], extents[first:first + count]))
    return f"{major}.{minor}", slot_count, parts


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    src, outdir = sys.argv[1], sys.argv[2]
    slot = int(sys.argv[sys.argv.index("--slot") + 1]) if "--slot" in sys.argv else 0
    os.makedirs(outdir, exist_ok=True)
    with open(src, "rb") as f:
        version, slots, parts = read_metadata(f, slot)
        print(f"liblp metadata v{version}, {slots} slot(s)")
        for name, group, exts in parts:
            size = sum(n for n, *_ in exts) * SECTOR
            print(f"  {name:<20} {group:<28} {size / 2**20:9.1f} MiB")
            if not size:
                continue
            with open(os.path.join(outdir, name + ".img"), "wb") as out:
                for num, ttype, data, _ in exts:
                    if ttype == 1:  # zero extent
                        out.seek(num * SECTOR, 1)
                        continue
                    f.seek(data * SECTOR)
                    left = num * SECTOR
                    while left:
                        chunk = f.read(min(64 << 20, left))
                        out.write(chunk)
                        left -= len(chunk)
                out.truncate(size)


if __name__ == "__main__":
    main()
