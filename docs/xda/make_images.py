#!/usr/bin/env python3
"""XDA thread images: banner.png and screenshots.png from cleaned screenshots (IMEI/serial/location/SSID removed).

Usage: python3 docs/xda/make_images.py <dir with 0.jpg..4.jpg>   (macOS: uses the system's Avenir Next font)
Own design in One UI's style; deliberately no Samsung logo (trademark).
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

SRC = sys.argv[1]
OUT = os.path.dirname(os.path.abspath(__file__))
FONT = "/System/Library/Fonts/Avenir Next.ttc"   # faces: 0 Bold, 2 Demi Bold, 5 Medium, 7 Regular


def font(size, face):
    return ImageFont.truetype(FONT, size, index=face)


def gradient(w, h, stops):
    """Diagonal gradient through (position, rgb) stops."""
    img = Image.new("RGB", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            t = (x / w * 0.75 + y / h * 0.25)
            for (p0, c0), (p1, c1) in zip(stops, stops[1:]):
                if p0 <= t <= p1:
                    k = (t - p0) / (p1 - p0)
                    px[x, y] = tuple(int(a + (b - a) * k) for a, b in zip(c0, c1))
                    break
    return img


def glow(img, xy, r, rgb, alpha):
    layer = Image.new("RGBA", img.size, (0, 0, 0, 0))
    ImageDraw.Draw(layer).ellipse((xy[0] - r, xy[1] - r, xy[0] + r, xy[1] + r), fill=rgb + (alpha,))
    img.alpha_composite(layer.filter(ImageFilter.GaussianBlur(r * 0.6)))


def phone(shot, height):
    """Screenshot in a rounded black frame with a soft shadow; returns RGBA."""
    s = Image.open(shot).convert("RGB")
    w = round(height * s.width / s.height)
    s = s.resize((w, height), Image.LANCZOS)
    bez, rad = max(6, height // 70), height // 16
    W, H = w + 2 * bez, height + 2 * bez
    pad = height // 12
    out = Image.new("RGBA", (W + 2 * pad, H + 2 * pad), (0, 0, 0, 0))
    sh = Image.new("RGBA", out.size, (0, 0, 0, 0))
    ImageDraw.Draw(sh).rounded_rectangle((pad, pad + pad // 3, pad + W, pad + H + pad // 3), rad + bez, fill=(0, 0, 0, 150))
    out.alpha_composite(sh.filter(ImageFilter.GaussianBlur(pad / 2.5)))
    ImageDraw.Draw(out).rounded_rectangle((pad, pad, pad + W, pad + H), rad + bez, fill=(12, 12, 14, 255),
                                          outline=(70, 74, 86, 255), width=2)
    m = Image.new("L", s.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, w - 1, height - 1), rad, fill=255)
    out.paste(s, (pad + bez, pad + bez), m)
    return out


def background(w, h):
    bg = gradient(w, h, [(0.0, (8, 14, 38)), (0.55, (14, 40, 92)), (1.0, (40, 22, 84))]).convert("RGBA")
    glow(bg, (int(w * 0.18), int(h * 0.1)), int(h * 0.55), (40, 110, 255), 90)
    glow(bg, (int(w * 0.85), int(h * 0.95)), int(h * 0.6), (150, 60, 255), 80)
    return bg


def banner():
    W, H = 1800, 640
    img = background(W, H)
    d = ImageDraw.Draw(img)
    x = 110
    d.text((x, 150), "One UI 8.0", font=font(124, 0), fill=(255, 255, 255))
    d.text((x + 4, 300), "for Xiaomi Mi 11 Lite 5G", font=font(52, 2), fill=(214, 226, 255))
    d.text((x + 4, 368), "renoir  ·  Android 16  ·  Galaxy S23 firmware port", font=font(30, 5), fill=(150, 170, 215))
    # pills
    px, py = x + 4, 450
    pills = Image.new("RGBA", img.size, (0, 0, 0, 0))   # translucent: drawn on a layer, then composited
    pd = ImageDraw.Draw(pills)
    for label in ("SELinux enforcing", "Fingerprint", "Bluetooth audio", "Open source"):
        f = font(25, 2)
        tw = d.textlength(label, font=f)
        pd.rounded_rectangle((px, py, px + tw + 44, py + 50), 25, fill=(255, 255, 255, 30), outline=(255, 255, 255, 80), width=2)
        pd.text((px + 22, py + 9), label, font=f, fill=(235, 240, 255, 255))
        px += tw + 60
    img.alpha_composite(pills)
    # two phones on the right, overlapping
    back = phone(os.path.join(SRC, "4.jpg"), 470).rotate(-7, resample=Image.BICUBIC, expand=True)
    front = phone(os.path.join(SRC, "1.jpg"), 520).rotate(5, resample=Image.BICUBIC, expand=True)
    img.alpha_composite(back, (W - back.width - 40, (H - back.height) // 2 + 30))
    img.alpha_composite(front, (W - front.width - 270, (H - front.height) // 2 - 10))
    img.convert("RGB").save(os.path.join(OUT, "banner.png"), optimize=True)


def screenshots():
    shots = [os.path.join(SRC, f"{i}.jpg") for i in (1, 4, 3, 0, 2)]
    ph = [phone(s, 820) for s in shots]
    gap = -30
    W = sum(p.width for p in ph) + gap * (len(ph) - 1) + 120
    H = ph[0].height + 150
    img = background(W, H)
    d = ImageDraw.Draw(img)
    d.text((W // 2, 62), "One UI 8.0 on the Mi 11 Lite 5G", font=font(48, 0), fill=(255, 255, 255), anchor="mm")
    x = 60
    for p in ph:
        img.alpha_composite(p, (x, 110))
        x += p.width + gap
    img.convert("RGB").save(os.path.join(OUT, "screenshots.png"), optimize=True)


banner()
screenshots()
print("wrote", os.path.join(OUT, "banner.png"), os.path.join(OUT, "screenshots.png"))
