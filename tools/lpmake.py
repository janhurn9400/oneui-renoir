#!/usr/bin/env python3
"""Build a raw super image (liblp metadata v10.x) from a template super's metadata + partition images.

The template (head of a stock super.img, >= 64 KiB past the metadata) supplies geometry, header flags,
groups, block device and the partition list with attributes. Only extents change: each given image gets
one linear extent, packed from the first logical sector with the block device alignment; partitions
without an image stay empty (0 extents). Checksums are recomputed; all metadata slots (primary + backup)
get the same metadata, like lpmake does for a factory image.

Usage: lpmake.py [--sparse] [--only=a,b] [--layout=FILE] TEMPLATE_HEAD OUT name_a=image.img [...]
--sparse writes an Android sparse image straight away (no raw super on disk; gaps become DONT_CARE chunks).
--only=product_a,... (implies --sparse) writes the metadata and only those partitions; everything else is
  DONT_CARE, so flashing it leaves the other partitions on the device untouched ("delta super"). Only valid when
  every other partition keeps the start/size it has on the device (compare the --layout files).
--layout=FILE writes "name start size" per partition with data.
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


def write_sparse(out_path, dev_size, segments, blk=4096, chunk=64 << 20):
    """segments: sorted, non-overlapping (offset, bytes-or-path, length); offsets/lengths block aligned."""
    plan, pos = [], 0
    for off, src, length in segments:
        assert off % blk == 0 and off >= pos
        if off > pos:
            plan.append(("skip", pos, off - pos, None))
        for o in range(0, length, chunk):
            plan.append(("raw", off + o, min(chunk, length - o), (src, o)))
        pos = off + length
    if pos < dev_size:
        plan.append(("skip", pos, dev_size - pos, None))
    assert dev_size % blk == 0
    with open(out_path, "wb") as f:
        f.write(struct.pack("<IHHHHIIII", 0xED26FF3A, 1, 0, 28, 12, blk, dev_size // blk, len(plan), 0))
        opened = {}
        for kind, off, length, ref in plan:
            if kind == "skip":
                f.write(struct.pack("<HHII", 0xCAC3, 0, length // blk, 12))
                continue
            src, o = ref
            if isinstance(src, (bytes, bytearray)):
                data = bytes(src[o:o + length])
            else:
                fh = opened.get(src) or opened.setdefault(src, open(src, "rb"))
                fh.seek(o)
                data = fh.read(length)
            data = data.ljust(length, b"\0")      # last block of an image: zero padding
            f.write(struct.pack("<HHII", 0xCAC1, 0, length // blk, 12 + length))
            f.write(data)
        for fh in opened.values():
            fh.close()


def main():
    args = sys.argv[1:]
    sparse, only, layout_file = False, None, None
    while args and args[0].startswith("--"):
        a = args.pop(0)
        if a == "--sparse":
            sparse = True
        elif a.startswith("--only="):
            only, sparse = set(a[7:].split(",")), True
        elif a.startswith("--layout="):
            layout_file = a[9:]
        else:
            raise SystemExit(f"unknown option {a}")
    if len(args) < 3:
        raise SystemExit(__doc__)
    tpl = parse(open(args[0], "rb").read(1 << 22))
    out_path = args[1]
    images = dict(a.split("=", 1) for a in args[2:])
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

    # Head: reserved 4 KiB | geometry | backup geometry | primary slots | backup slots
    base = GEO_OFF + 2 * GEO_SIZE
    head = bytearray(base + 2 * tpl["slots"] * tpl["max_size"])
    for o in (GEO_OFF, GEO_OFF + GEO_SIZE):
        head[o:o + len(geo)] = geo
    for slot in range(tpl["slots"]):
        for o in (base + slot * tpl["max_size"], base + (tpl["slots"] + slot) * tpl["max_size"]):
            head[o:o + len(metadata)] = metadata
    head = bytes(head).ljust((len(head) + 4095) // 4096 * 4096, b"\0")
    assert len(head) <= first_sector * SECTOR
    for name, start, size, path in layout:
        print(f"{name:<14} @ {start / 2**20:9.1f} MiB  {size / 2**20:8.1f} MiB  <- {os.path.basename(path)}")
    if layout_file:
        with open(layout_file, "w") as lf:
            for name, start, size, _ in layout:
                lf.write(f"{name} {start} {size}\n")
    if only is not None:
        unknown = only - {n for n, _, _, _ in layout}
        if unknown:
            raise SystemExit(f"--only: no image for {sorted(unknown)}")
        layout = [l for l in layout if l[0] in only]
        print(f"delta: metadata + {', '.join(sorted(only))}")
    if sparse:
        write_sparse(out_path, dev_size, [(0, head, len(head))] + [(st, p, sz) for _, st, sz, p in layout])
    else:
        with open(out_path, "wb") as f:
            f.truncate(dev_size)  # sparse file: unwritten areas read as zeros
            f.write(head)
            for name, start, size, path in layout:
                f.seek(start)
                with open(path, "rb") as src:
                    while True:
                        chunk = src.read(64 << 20)
                        if not chunk:
                            break
                        f.write(chunk)
    print(f"used {pos / 2**30:.2f} GiB of {dev_size / 2**30:.2f} GiB")


if __name__ == "__main__":
    main()
