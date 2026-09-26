#!/usr/bin/env python3
"""Generate the 1024 px app icon: cream ground, terracotta disc, serif n-tilde."""
import pathlib

from PIL import Image, ImageDraw, ImageFont

OUT = pathlib.Path(__file__).resolve().parent.parent / "Palabra/Assets.xcassets/AppIcon.appiconset/icon-1024.png"
S = 1024
TOP, BOTTOM = (0xFB, 0xF7, 0xEE), (0xF3, 0xEB, 0xDC)

img = Image.new("RGB", (S, S), TOP)
d = ImageDraw.Draw(img)
for y in range(S):
    t = y / S
    d.line([(0, y), (S, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))
r = 330
d.ellipse([S / 2 - r, S / 2 - r, S / 2 + r, S / 2 + r], fill=(0xB8, 0x69, 0x4A))
font = None
for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf", "/System/Library/Fonts/NewYork.ttf"):
    if pathlib.Path(p).exists():
        font = ImageFont.truetype(p, 470)
        break
if font is None:
    font = ImageFont.load_default(size=470)
d.text((S / 2, S / 2 + 10), "ñ", font=font, fill=TOP, anchor="mm")
OUT.parent.mkdir(parents=True, exist_ok=True)
img.save(OUT)
print("wrote", OUT)
