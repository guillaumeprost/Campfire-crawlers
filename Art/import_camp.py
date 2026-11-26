#!/usr/bin/env python3
"""Installe les aménagements du camp (PixelLab) dans Assets.xcassets.

Sources : Art/pixellab/camp/camp_<niveau>_<nom>.png, un par niveau du feu de camp (1 à 5).
Chaque image est recadrée au plus juste et installée sous le nom `camp_prop_<niveau>`.
Leur place à l'écran est réglée dans WorldScene.buildCampProps.

Usage : /usr/bin/python3 Art/import_camp.py
"""
import json, os, re
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
SRC = os.path.join(ROOT, "Art", "pixellab", "camp")

for file in sorted(os.listdir(SRC)):
    match = re.fullmatch(r"camp_(\d)_\w+\.png", file)
    if not match:
        continue
    img = Image.open(os.path.join(SRC, file)).convert("RGBA")
    img = img.crop(img.getbbox())
    name = f"camp_prop_{match.group(1)}"
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        os.remove(os.path.join(folder, f))
    img.save(os.path.join(folder, f"{name}.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as fh:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, fh, indent=2)
    print(name, img.size)
