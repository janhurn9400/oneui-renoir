#!/usr/bin/env python3
"""Convert one or more Android sparse images (e.g. super.img or super.img.0..N) into one raw image.

Split sparse files (Xiaomi's super_sparsechunk style) each describe the whole image with DONT_CARE
gaps, so they are written into the same output file at their own offsets.
Usage: sparse2raw.py OUT.img IN.img [IN2.img ...]
"""
import struct
import sys

MAGIC = 0xED26FF3A
RAW, FILL, DONT_CARE, CRC32 = 0xCAC1, 0xCAC2, 0xCAC3, 0xCAC4
BUF = 64 << 20


def is_sparse(path):
    with open(path, "rb") as f:
        head = f.read(4)
    return len(head) == 4 and struct.unpack("<I", head)[0] == MAGIC


def convert(src, out):
    with open(src, "rb") as f:
        magic, major, minor, fhdr, chdr, blk, total_blks, total_chunks, _ = struct.unpack(
            "<IHHHHIIII", f.read(28))
        if magic != MAGIC:
            raise SystemExit(f"{src}: not a sparse image")
        f.seek(fhdr)
        pos = 0
        for _ in range(total_chunks):
            ctype, _, csz, total = struct.unpack("<HHII", f.read(12))
            f.seek(chdr - 12, 1)
            length = csz * blk
            if ctype == RAW:
                out.seek(pos)
                left = length
                while left:
                    data = f.read(min(BUF, left))
                    out.write(data)
                    left -= len(data)
            elif ctype == FILL:
                pattern = f.read(4)
                if pattern != b"\0\0\0\0":
                    out.seek(pos)
                    chunk = pattern * (BUF // 4)
                    left = length
                    while left:
                        n = min(len(chunk), left)
                        out.write(chunk[:n])
                        left -= n
            elif ctype == DONT_CARE:
                pass
            elif ctype == CRC32:
                f.read(4)
            else:
                raise SystemExit(f"{src}: unknown chunk type {ctype:#x}")
            pos += length
        return total_blks * blk


def main():
    if len(sys.argv) < 3:
        raise SystemExit(__doc__)
    size = 0
    with open(sys.argv[1], "wb") as out:
        for src in sys.argv[2:]:
            size = max(size, convert(src, out))
        out.truncate(size)
    print(f"{sys.argv[1]}: {size / 2**30:.2f} GiB")


if __name__ == "__main__":
    main()
