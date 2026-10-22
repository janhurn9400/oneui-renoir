#!/usr/bin/env python3
"""Extract logical partitions from an Android *sparse* super image read as a stream (stdin), without ever
writing the full super image. Samsung firmware ships super.img (sparse) lz4-compressed inside the AP tar, so:

  unzip -p FW.zip 'AP_*' | tar -xOf - super.img.lz4 | lz4 -dc | sparse_lpextract.py OUTDIR system system_ext product

The liblp metadata sits in the first MiBs of the image; once that part has streamed by, the partition table
(slot 0) is parsed and every later chunk is written straight into the wanted partition images (holes = zeros).
Names match with or without the _a suffix. Prints the partition table.
With --sha256 instead of OUTDIR nothing is written: prints "sha256 name" per wanted partition (to verify a
super we built, e.g. against sha256sum of the input images).
"""
import hashlib
import os
import struct
import sys

SPARSE_MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE, CRC = 0xCAC1, 0xCAC2, 0xCAC3, 0xCAC4
GEO_OFF, GEO_MAGIC, HDR_MAGIC = 4096, 0x616C4467, 0x414C5030
HEAD = 4 << 20          # bytes of the image kept in memory for the metadata
SECTOR = 512


def read_exact(f, n):
    b = f.read(n)
    while len(b) < n:
        more = f.read(n - len(b))
        if not more:
            raise SystemExit(f"unexpected end of stream ({len(b)}/{n} bytes)")
        b += more
    return b


def parse_lp(head):
    magic, _, _, max_size, _, _ = struct.unpack_from("<II32sIII", head, GEO_OFF)
    assert magic == GEO_MAGIC, "no liblp geometry"
    off = GEO_OFF + 2 * 4096                       # primary metadata, slot 0
    magic, _, _, hsize = struct.unpack_from("<IHHI", head, off)
    assert magic == HDR_MAGIC, "bad metadata header"
    tsize = struct.unpack_from("<I", head, off + 44)[0]
    t = head[off + hsize:off + hsize + tsize]
    (po, pn, ps), (eo, en, es) = [struct.unpack_from("<III", head, off + 80 + 12 * i) for i in range(2)]
    exts = [struct.unpack_from("<QIQI", t, eo + i * es) for i in range(en)]
    parts = {}
    for i in range(pn):
        b = po + i * ps
        name = t[b:b + 36].split(b"\0")[0].decode()
        _, first, num, _ = struct.unpack_from("<IIII", t, b + 36)
        runs, pos = [], 0
        for nsec, ttype, tdata, _ in exts[first:first + num]:
            assert ttype == 0, f"{name}: non-linear extent"
            runs.append((tdata * SECTOR, nsec * SECTOR, pos))   # (super offset, length, partition offset)
            pos += nsec * SECTOR
        parts[name] = (runs, pos)
    return parts


class Writer:
    def __init__(self, outdir, wanted, parts):
        self.targets = []
        for name, (runs, size) in sorted(parts.items()):
            print(f"  {name:20s} {size / 2**20:10.1f} MiB")
            base = name[:-2] if name.endswith("_a") else name
            if size and (name in wanted or base in wanted):
                path = os.path.join(outdir, base + ".img")
                f = open(path, "wb")
                f.truncate(size)
                self.targets.append((f, runs))
                wanted.discard(name); wanted.discard(base)
        if wanted:
            raise SystemExit(f"not found or empty: {sorted(wanted)}")

    def write(self, off, data):
        end = off + len(data)
        for f, runs in self.targets:
            for soff, length, poff in runs:
                lo, hi = max(off, soff), min(end, soff + length)
                if lo < hi:
                    f.seek(poff + lo - soff)
                    f.write(data[lo - off:hi - off])

    def close(self):
        for f, _ in self.targets:
            f.close()


class Hasher(Writer):
    """Same selection as Writer, but hashes each partition in order instead of writing it."""

    def __init__(self, wanted, parts):
        self.targets = []
        for name, (runs, size) in sorted(parts.items()):
            base = name[:-2] if name.endswith("_a") else name
            if size and (name in wanted or base in wanted):
                self.targets.append(([hashlib.sha256(), 0, size, base], runs))
                wanted.discard(name); wanted.discard(base)
        if wanted:
            raise SystemExit(f"not found or empty: {sorted(wanted)}")

    def _feed(self, off, length, data):
        end = off + length
        for t, runs in self.targets:
            for soff, rlen, poff in runs:
                lo, hi = max(off, soff), min(end, soff + rlen)
                if lo < hi:
                    p = poff + lo - soff
                    assert p >= t[1], f"{t[3]}: data out of order"
                    self._pad(t, p)
                    t[0].update(data[lo - off:hi - off] if data is not None else bytes(hi - lo))
                    t[1] = p + hi - lo

    @staticmethod
    def _pad(t, upto):
        while t[1] < upto:
            n = min(upto - t[1], 8 << 20)
            t[0].update(bytes(n)); t[1] += n

    def write(self, off, data):
        self._feed(off, len(data), data)

    def close(self):
        for t, _ in self.targets:
            self._pad(t, t[2])
            print(f"{t[0].hexdigest()}  {t[3]}")


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    outdir, wanted = sys.argv[1], set(sys.argv[2:])
    hashing = outdir == "--sha256"
    if not hashing:
        os.makedirs(outdir, exist_ok=True)
    make = (lambda parts: Hasher(wanted, parts)) if hashing else (lambda parts: Writer(outdir, wanted, parts))
    src = sys.stdin.buffer
    magic, _, _, fhs, chs, bs, tblks, tchunks, _ = struct.unpack("<IHHHHIIII", read_exact(src, 28))
    assert magic == SPARSE_MAGIC, "input is not an Android sparse image"
    read_exact(src, fhs - 28)
    print(f"sparse: {tblks * bs / 2**30:.2f} GiB, {tchunks} chunks")
    head, writer, off = bytearray(HEAD), None, 0

    def emit(o, data):
        nonlocal writer
        if writer:
            writer.write(o, data)
            return
        if o < HEAD:
            n = min(len(data), HEAD - o)
            head[o:o + n] = data[:n]

    for c in range(tchunks):
        ctype, _, nblk, total = struct.unpack("<HHII", read_exact(src, 12))
        read_exact(src, chs - 12)
        size = nblk * bs
        if writer is None and off + size >= HEAD:
            # metadata complete once we pass HEAD; data below HEAD is replayed from the buffer
            if ctype == RAW and off < HEAD:
                first = read_exact(src, HEAD - off)
                emit(off, first)
                pre = len(first)
            else:
                pre = 0
            writer = make(parse_lp(bytes(head)))
            writer.write(0, bytes(head))
        else:
            pre = 0
        if ctype == RAW:
            o, left = off + pre, size - pre
            while left:
                n = min(left, 8 << 20)
                emit(o, read_exact(src, n))
                o += n; left -= n
        elif ctype == FILL:
            pat = read_exact(src, 4)
            if pat != b"\0\0\0\0":
                o, left = off, size
                while left:
                    n = min(left, 8 << 20)
                    emit(o, pat * (n // 4))
                    o += n; left -= n
        elif ctype == CRC:
            read_exact(src, 4)
        elif ctype != DONT_CARE:
            raise SystemExit(f"unknown chunk type {ctype:#x}")
        off += size
    if writer is None:
        writer = make(parse_lp(bytes(head)))
        writer.write(0, bytes(head))
    writer.close()
    print("done")


if __name__ == "__main__":
    main()
