#!/usr/bin/env python3
"""Build a raw super image (liblp metadata v10.x) from a template super's metadata + partition images.

The template (head of a stock super.img, >= 64 KiB past the metadata) supplies geometry, header flags,
groups, block device and the partition list with attributes. Only extents change: each given image gets
one linear extent, packed from the first logical sector with the block device alignment; partitions
without an image stay empty (0 extents). Checksums are recomputed; all metadata slots (primary + backup)
get the same metadata, like lpmake does for a factory image.

Usage: lpmake.py TEMPLATE_HEAD OUT_RAW name_a=image.img [name_a=image.img ...]
"""
import hashlib
import os
import struct
import sys

SECTOR = 512
GEO_OFF = 4096
GEO_SIZE = 4096
GEO_MAGIC = 0x616C4467
HDR_MAGIC = 0x414C5030


def parse(head):
    magic, ssize, _, max_size, slots, lbs = struct.unpack_from("<II32sIII", head, GEO_OFF)
    assert magic == GEO_MAGIC
    off = GEO_OFF + 2 * GEO_SIZE
    hdr = bytearray(head[off:off + 256])
    magic, major, minor, hsize = struct.unpack_from("<IHHI", hdr)
    assert magic == HDR_MAGIC
    tsize = struct.unpack_from("<I", hdr, 44)[0]
    tables = head[off + hsize:off + hsize + tsize]
    descs = [struct.unpack_from("<III", hdr, 80 + 12 * i) for i in range(4)]
    return dict(geo=bytes(head[GEO_OFF:GEO_OFF + ssize]), max_size=max_size, slots=slots, lbs=lbs,
                hdr=bytes(hdr[:hsize]), hsize=hsize, tables=tables, descs=descs)


def main():
    if len(sys.argv) < 4:
        raise SystemExit(__doc__)
    tpl = parse(open(sys.argv[1], "rb").read(1 << 22))
    out_path = sys.argv[2]
    images = dict(a.split("=", 1) for a in sys.argv[3:])
    (po, pn, ps), (eo, en, es), (go, gn, gs), (bo, bn, bs) = tpl["descs"]
    t = tpl["tables"]
    assert bn == 1, "single block device expected"
    first_sector, align, align_off, dev_size = struct.unpack_from("<QIIQ", t, bo)
    groups = [(t[go + i * gs:go + i * gs + 36].split(b"\0")[0].decode(),
               *struct.unpack_from("<IQ", t, go + i * gs + 36)) for i in range(gn)]
    parts = []
    for i in range(pn):
        b = po + i * ps
        name = t[b:b + 36].split(b"\0")[0].decode()
        attrs, _, _, group = struct.unpack_from("<IIII", t, b + 36)
        parts.append([name, attrs, group])
    unknown = set(images) - {p[0] for p in parts}
    if unknown:
        raise SystemExit(f"not in template: {sorted(unknown)}")

    # Allocate one linear extent per image, aligned to the block device alignment.
    pos = first_sector * SECTOR
    extents, part_entries, layout, group_use = [], [], [], {}
    for name, attrs, group in parts:
        first = len(extents)
        if name in images:
            size = os.path.getsize(images[name])
            size = (size + tpl["lbs"] - 1) // tpl["lbs"] * tpl["lbs"]
            pos = (pos + align - 1) // align * align
            extents.append(struct.pack("<QIQI", size // SECTOR, 0, pos // SECTOR, 0))
            layout.append((name, pos, size, images[name]))
            group_use[group] = group_use.get(group, 0) + size
            pos += size
        n = len(extents) - first
        part_entries.append(name.encode().ljust(36, b"\0") + struct.pack("<IIII", attrs, first if n else 0, n, group))
    if pos > dev_size:
        raise SystemExit(f"images do not fit: need {pos}, super {dev_size}")
    for gi, used in group_use.items():
        if groups[gi][2] and used > groups[gi][2]:
            raise SystemExit(f"group {groups[gi][0]} over its maximum size")

    ptab = b"".join(part_entries)
    etab = b"".join(extents)
    gtab = t[go:go + gn * gs]
    btab = t[bo:bo + bn * bs]
    tables = ptab + etab + gtab + btab
    descs = [(0, len(part_entries), ps), (len(ptab), len(extents), es),
             (len(ptab) + len(etab), gn, gs), (len(ptab) + len(etab) + len(gtab), bn, bs)]

    hdr = bytearray(tpl["hdr"])
    struct.pack_into("<I", hdr, 44, len(tables))
    hdr[48:80] = hashlib.sha256(tables).digest()
    for i, (o, n, s) in enumerate(descs):
        struct.pack_into("<III", hdr, 80 + 12 * i, o, n, s)
    hdr[12:44] = b"\0" * 32
    hdr[12:44] = hashlib.sha256(bytes(hdr)).digest()
    metadata = bytes(hdr) + tables
    if len(metadata) > tpl["max_size"]:
        raise SystemExit("metadata larger than metadata_max_size")

    geo = bytearray(tpl["geo"])
    geo[8:40] = b"\0" * 32
    geo[8:40] = hashlib.sha256(bytes(geo)).digest()

    with open(out_path, "wb") as f:
        f.truncate(dev_size)  # sparse file: unwritten areas read as zeros
        for o in (GEO_OFF, GEO_OFF + GEO_SIZE):
            f.seek(o)
            f.write(bytes(geo).ljust(GEO_SIZE, b"\0"))
        base = GEO_OFF + 2 * GEO_SIZE
        for slot in range(tpl["slots"]):
            for o in (base + slot * tpl["max_size"],
                      base + tpl["slots"] * tpl["max_size"] + slot * tpl["max_size"]):
                f.seek(o)
                f.write(metadata.ljust(tpl["max_size"], b"\0"))
        for name, start, size, path in layout:
            f.seek(start)
            with open(path, "rb") as src:
                while True:
                    chunk = src.read(64 << 20)
                    if not chunk:
                        break
                    f.write(chunk)
            print(f"{name:<14} @ {start / 2**20:9.1f} MiB  {size / 2**20:8.1f} MiB  <- {os.path.basename(path)}")
    print(f"used {pos / 2**30:.2f} GiB of {dev_size / 2**30:.2f} GiB")


if __name__ == "__main__":
    main()
