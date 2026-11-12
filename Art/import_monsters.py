#!/usr/bin/env python3
"""Installe les monstres, boss et objets de donjon pixel art (PixelLab) dans Assets.xcassets.

Chaque image brute est dans Art/pixellab/monsters/<nom>.png (m_rat, b_dragon...) ou
Art/pixellab/props/<nom>.png (chest_closed, chest_open...). Le script
recadre au plus juste, retourne celles dessinées tournées vers la droite pour que toutes
regardent à gauche (vers le héros), et remplace l'imageset du même nom. La taille à l'écran
reste réglée dans WorldScene.looks.

Usage : <python avec Pillow> Art/import_monsters.py
"""
import json, os
from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
SRCS = [os.path.join(ROOT, "Art", "pixellab", d) for d in ("monsters", "props")]

# Dessinés tournés vers la droite : on les retourne.
FACING_RIGHT = {"m_skeleton"}


def main():
    files = [(src, f) for src in SRCS for f in sorted(os.listdir(src)) if f.endswith(".png")]
    # Les objets d'une même famille (coffre fermé / ouvert, piège rentré / sorti, images du
    # sanctuaire) partagent un cadre : le jeu change la texture sans changer la taille du sprite.
    family = lambda name: name.split("_")[0]
    boxes = {}
    for src, f in files:
        if src == SRCS[1]:
            boxes.setdefault(family(f[:-4]), []).append(Image.open(os.path.join(src, f)).getbbox())
    shared = {k: (min(b[0] for b in v), min(b[1] for b in v), max(b[2] for b in v), max(b[3] for b in v))
              for k, v in boxes.items()}
    for src, file in files:
        name = file[:-4]
        img = Image.open(os.path.join(src, file)).convert("RGBA")
        img = img.crop(shared[family(name)] if src == SRCS[1] else img.getbbox())
        if name in FACING_RIGHT:
            img = ImageOps.mirror(img)
        folder = os.path.join(ASSETS, f"{name}.imageset")
        os.makedirs(folder, exist_ok=True)
        for f in os.listdir(folder):
            os.remove(os.path.join(folder, f))
        img.save(os.path.join(folder, f"{name}.png"))
        with open(os.path.join(folder, "Contents.json"), "w") as fh:
            json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                       "info": {"author": "xcode", "version": 1}}, fh, indent=2)
        print(name, img.size)


if __name__ == "__main__":
    main()
