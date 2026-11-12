#!/usr/bin/env python3
"""Détoure les assets générés par Midjourney (fond blanc -> transparent), recadre,
redimensionne, et les installe dans un Assets.xcassets.

Réutilisable pour tous les sprites : persos, monstres, items, props.
Usage (voir __main__) : adapte la liste HEROES puis
    <venv>/bin/python Art/detoure.py <chemin Assets.xcassets>
"""
import json, os, sys
from PIL import Image, ImageDraw


def remove_white_bg(img, thresh=70):
    """Rend transparent le fond clair + l'ombre au sol, en préservant les couleurs
    du perso (contour noir épais). Gère aussi les poches de fond enfermées (ex. le
    triangle entre un arc et sa corde) via un nettoyage des blancs quasi purs."""
    img = img.convert("RGBA")
    w, h = img.size
    rgb = img.convert("RGB")
    px = rgb.load()
    key = (255, 0, 255)

    def light(x, y):
        r, g, b = px[x, y]
        return min(r, g, b) >= 205

    def pure_white(x, y):
        r, g, b = px[x, y]
        return min(r, g, b) >= 238 and max(r, g, b) - min(r, g, b) <= 10

    def flood(x, y, t):
        try:
            ImageDraw.floodfill(rgb, (x, y), key, thresh=t)
        except Exception:
            pass

    # 1) fond extérieur, depuis les bords
    for s in [(0, 0), (w - 1, 0), (0, h - 1), (w - 1, h - 1),
              (w // 2, 0), (w // 2, h - 1), (0, h // 2), (w - 1, h // 2)]:
        flood(*s, thresh)
    # 2) ombre au sol : on sème toute la rangée du bas là où c'est clair
    for x in range(0, w, 6):
        if light(x, h - 1):
            flood(x, h - 1, thresh)
    # 3) poches de fond enfermées : blancs quasi purs, par semis en grille (local)
    for y in range(0, h, 22):
        for x in range(0, w, 22):
            if px[x, y] != key and pure_white(x, y):
                flood(x, y, 48)

    out = img.load()
    for y in range(h):
        for x in range(w):
            if px[x, y] == key:
                out[x, y] = (0, 0, 0, 0)
    return img


def strip_ground_shadow(img, band=0.16):
    """Après recadrage : vire l'ombre au sol (gris clair peu saturé) dans la bande
    basse. Les bottes/objets sombres ou colorés sont préservés."""
    img = img.convert("RGBA")
    w, h = img.size
    px = img.load()
    top = int(h * (1 - band))
    for y in range(top, h):
        for x in range(w):
            r, g, b, a = px[x, y]
            if a and min(r, g, b) >= 188 and max(r, g, b) - min(r, g, b) <= 24:
                px[x, y] = (0, 0, 0, 0)
    return img


def trim(img):
    bbox = img.getbbox()
    return img.crop(bbox) if bbox else img


def fit_height(img, height):
    w, h = img.size
    return img.resize((max(1, round(w * height / h)), height), Image.LANCZOS)


def head_crop(img, size=256):
    """Carré du haut (tête + buste) pour un portrait."""
    w, h = img.size
    side = min(w, h)
    left = (w - side) // 2
    crop = img.crop((left, 0, left + side, side))
    return crop.resize((size, size), Image.LANCZOS)


def install(img, name, xcassets):
    """Écrit un .imageset mono-image (1x)."""
    d = os.path.join(xcassets, name + ".imageset")
    os.makedirs(d, exist_ok=True)
    img.save(os.path.join(d, name + ".png"))
    with open(os.path.join(d, "Contents.json"), "w") as f:
        json.dump({"images": [{"filename": name + ".png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, f, indent=2)
    return d


def process_hero(src, cls, xcassets, body_height=340, mirror=True):
    img = trim(strip_ground_shadow(trim(remove_white_bg(Image.open(src)))))
    body = fit_height(img, body_height)
    if mirror:
        body = body.transpose(Image.FLIP_LEFT_RIGHT)
    install(body, f"hero_{cls}", xcassets)               # corps (pose fixe)
    install(head_crop(img), f"hero_{cls}_portrait", xcassets)  # portrait (tête)
    print(f"  {cls}: corps {body.size}, portrait installé")


if __name__ == "__main__":
    xcassets = sys.argv[1]
    here = os.path.dirname(os.path.abspath(__file__))
    HEROES = [("guerrier", "warrior"), ("archer", "archer"), ("mage", "mage")]
    print("Détourage des héros ->", xcassets)
    for fname, cls in HEROES:
        process_hero(os.path.join(here, "midjourney", fname + ".png"), cls, xcassets)
    print("OK")
