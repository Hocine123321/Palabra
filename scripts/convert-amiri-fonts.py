#!/usr/bin/env python3
"""Builds Palabra/Resources/Fonts/Amiri-{Regular,Bold}.ttf from the @fontsource/amiri subsets the web scene used.

  cd web/books3d && npm ci && cd ../.. && pip install fonttools brotli && python3 scripts/convert-amiri-fonts.py

Each weight is the arabic + latin + latin-ext subsets merged into one TrueType font, so the native page text has the same glyphs
the web scene drew (Amiri, SIL OFL).
"""
import pathlib
import sys

from fontTools.merge import Merger
from fontTools.ttLib import TTFont

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "web/books3d/node_modules/@fontsource/amiri/files"
dst = root / "Palabra/Resources/Fonts"
dst.mkdir(parents=True, exist_ok=True)

for weight, name in ((400, "Regular"), (700, "Bold")):
    parts = []
    for subset in ("latin", "latin-ext", "arabic"):
        path = src / f"amiri-{subset}-{weight}-normal.woff2"
        if not path.exists():
            sys.exit(f"missing {path}")
        font = TTFont(path)
        font.flavor = None
        tmp = dst / f".{subset}-{weight}.ttf"
        font.save(tmp)
        parts.append(str(tmp))
    merged = Merger().merge(parts)
    for record in merged["name"].names:
        if record.nameID in (1, 16):
            record.string = "Amiri"
        elif record.nameID in (2, 17):
            record.string = name
        elif record.nameID == 4:
            record.string = f"Amiri {name}"
        elif record.nameID == 6:
            record.string = f"Amiri-{name}"
    out = dst / f"Amiri-{name}.ttf"
    merged.save(out)
    for p in parts:
        pathlib.Path(p).unlink()
    cmap = merged.getBestCmap()
    print(out.name, f"{out.stat().st_size // 1024} KB", len(cmap), "characters")
