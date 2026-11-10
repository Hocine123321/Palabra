"""Makes the web app icons from the phone app's icon. Run once by hand (needs Pillow); the PNGs are committed.
    python3 web/scripts/make-icons.py"""
import os
from PIL import Image

root = os.path.join(os.path.dirname(__file__), "..", "..")
source = Image.open(os.path.join(root, "Palabra", "Assets.xcassets", "AppIcon.appiconset", "icon-1024.png")).convert("RGB")
out = os.path.join(os.path.dirname(__file__), "..", "public", "icons")
os.makedirs(out, exist_ok=True)
for name, size in [("icon-192.png", 192), ("icon-512.png", 512), ("icon-maskable-512.png", 512)]:
    source.resize((size, size), Image.LANCZOS).save(os.path.join(out, name), optimize=True)
print("wrote", out)
