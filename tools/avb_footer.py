#!/usr/bin/env python3
"""Give a modified boot-type image an AVB hash footer, reusing the stock image's footer as template.

Copies the stock vbmeta blob (unsigned, ALGORITHM NONE as on Xiaomi's vendor_boot), updates the hash
descriptor's image_size and digest (sha256(salt + image)), and writes footer + vbmeta like avbtool
add_hash_footer: image | vbmeta at original_size | zero padding | 64-byte footer at partition end.
Usage: avb_footer.py STOCK.img MODIFIED.img OUT.img
"""
import hashlib
import struct
import sys

FOOTER = 64


def main():
    stock, mod, out = sys.argv[1:4]
    s = open(stock, "rb").read()
    img = open(mod, "rb").read()
    part_size = len(s)
    f = s[-FOOTER:]
    assert f[:4] == b"AVBf", "stock image has no AVB footer"
    fmaj, fmin, orig, voff, vsize = struct.unpack_from(">IIQQQ", f, 4)
    vb = bytearray(s[voff:voff + vsize])
    assert vb[:4] == b"AVB0"
    auth_size, aux_size, algo = struct.unpack_from(">QQI", vb, 12)
    if algo != 0 or auth_size != 0:
        raise SystemExit("template vbmeta is signed; this tool only handles unsigned (NONE) footers")
    desc_off, desc_size = struct.unpack_from(">QQ", vb, 96)
    pos = 256 + auth_size + desc_off
    end = pos + desc_size
    done = False
    while pos < end:
        tag, nbf = struct.unpack_from(">QQ", vb, pos)
        if tag == 2:  # hash descriptor
            image_size, = struct.unpack_from(">Q", vb, pos + 16)
            algo_name = bytes(vb[pos + 24:pos + 56]).split(b"\0")[0].decode()
            name_len, salt_len, dig_len = struct.unpack_from(">III", vb, pos + 56)
            body = pos + 16 + 116
            salt = bytes(vb[body + name_len:body + name_len + salt_len])
            assert algo_name == "sha256" and dig_len == 32, algo_name
            digest = hashlib.sha256(salt + img).digest()
            struct.pack_into(">Q", vb, pos + 16, len(img))
            vb[body + name_len + salt_len:body + name_len + salt_len + dig_len] = digest
            print(f"hash descriptor: image_size {image_size} -> {len(img)}, digest updated")
            done = True
        pos += 16 + nbf
    assert done, "no hash descriptor in template"
    if len(img) + len(vb) + FOOTER > part_size:
        raise SystemExit("image too large for partition")
    # vbmeta right after the (block-aligned) image, footer in the last 64 bytes, like avbtool.
    new_voff = (len(img) + 4095) // 4096 * 4096
    outb = bytearray(part_size)
    outb[:len(img)] = img
    outb[new_voff:new_voff + len(vb)] = vb
    footer = bytearray(FOOTER)
    footer[:4] = b"AVBf"
    struct.pack_into(">IIQQQ", footer, 4, fmaj, fmin, len(img), new_voff, len(vb))
    outb[-FOOTER:] = footer
    open(out, "wb").write(outb)
    print(f"footer: original_size={len(img)} vbmeta_offset={new_voff} vbmeta_size={len(vb)} partition={part_size}")


if __name__ == "__main__":
    main()
