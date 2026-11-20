#!/usr/bin/env python3
"""Installe les visiteurs du camp (PixelLab) dans Assets.xcassets.

Source : un dossier contenant, pour chaque visiteur, le ZIP PixelLab dézippé :
    <source>/<wounded|gambler|pilgrim>/<état>/animations/<animation>/south-west/frame_NNN.png
La vue de trois quarts « south-west » regarde vers le héros, comme le marchand : pas de miroir en jeu.

Les frames brutes retenues sont copiées dans Art/pixellab/npc/<visiteur>_idle/fN.png, puis
exportées en `npc_<visiteur>_idle_<n>` (4 images, recadrées sur leur cadre commun pour rester
calées d'une image à l'autre). Le jeu les joue dans WorldScene.buildVisitor.

Usage : /usr/bin/python3 Art/import_visitors.py <dossier_source>
"""
import glob, json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
VISITORS = ["wounded", "gambler", "pilgrim"]
FRAMES = 4
DIRECTION = "south-west"

# Personnages PixelLab (80 px, vue de côté, mode v3), animation « breathing-idle ».
IDS = {
    "wounded": "9e4555bb-da79-4032-a2f5-7f58aaba378a",
    "gambler": "c354499b-0835-47d4-bac6-6cafec0b8dc1",
    "pilgrim": "7638df08-2a9a-41a1-b7d5-0c479992b72f",
}


def write_imageset(name, img):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        os.remove(os.path.join(folder, f))
    img.save(os.path.join(folder, f"{name}.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as fh:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, fh, indent=2)


def main(source):
    for visitor in VISITORS:
        found = sorted(glob.glob(os.path.join(source, visitor, "*", "animations", "*", DIRECTION, "frame_*.png")))
        if not found:
            print(visitor, ": aucune frame trouvée, ignoré")
            continue
        # Quatre images réparties sur toute la respiration.
        picks = [found[i * len(found) // FRAMES] for i in range(FRAMES)]
        frames = [Image.open(p).convert("RGBA") for p in picks]
        raw = os.path.join(ROOT, "Art", "pixellab", "npc", f"{visitor}_idle")
        os.makedirs(raw, exist_ok=True)
        for n, frame in enumerate(frames, 1):
            frame.save(os.path.join(raw, f"f{n}.png"))
        boxes = [f.getbbox() for f in frames]
        box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        for n, frame in enumerate(frames, 1):
            write_imageset(f"npc_{visitor}_idle_{n}", frame.crop(box))
        print(visitor, len(found), "frames ->", FRAMES, (box[2] - box[0], box[3] - box[1]))


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(sys.argv[1])
