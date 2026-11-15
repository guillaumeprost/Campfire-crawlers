#!/usr/bin/env python3
"""Installe les compagnons PixelLab dans Assets.xcassets.

Chaque compagnon est un quadrupède PixelLab (loup, panthère, ours), généré en vue de
côté. On ne garde que la direction `west` (profil tourné vers la gauche, comme le héros,
que la scène retourne au besoin). Les frames d'un compagnon sont posées sur un même
canevas (union des boîtes englobantes, pieds en bas) pour rester calées d'une image à
l'autre et que le miroir tourne autour du corps.

Les ZIP viennent de `https://api.pixellab.ai/mcp/characters/<id>/download`, dézippés
dans un dossier source : `<kind>/<State>/animations/<anim>/west/frame_NNN.png` et
`<kind>/<State>/rotations/{west,south}.png`.

Usage : /usr/bin/python3 Art/import_companions.py [dossier_source]
Le nombre d'images par animation doit correspondre à CompanionKind.frames() (World.swift) :
idle = 4, walk = 8.
"""
import glob, json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
DEFAULT_SRC = "/private/tmp/claude-501/-Users-guillaumeprost--claude-spares-spare-y9MfRV/9d2a61a2-ca35-4d2e-af55-baad01a235ec/scratchpad/companions"

# Nombre d'images retenu par animation (doit coller à CompanionKind.frames()).
COUNTS = {"idle": 4, "walk": 8, "sit": 4, "sleep": 4}
# Animations « posées » : on garde les dernières images (posture installée), pas le
# début du mouvement, pour que la boucle montre l'animal assis / endormi et non en
# train de s'asseoir / se coucher en boucle.
SETTLED = {"sit", "sleep"}
KINDS = ["wolf", "panther", "bear"]


def write_imageset(name, img):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        os.remove(os.path.join(folder, f))
    img.save(os.path.join(folder, f"{name}.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as fh:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, fh, indent=2)


def pick(frames, n):
    """n images réparties uniformément dans la liste (indices arrondis)."""
    if len(frames) <= n:
        return frames
    return [frames[round(i * (len(frames) - 1) / (n - 1))] for i in range(n)]


def anim_frames(src_kind, anim):
    paths = sorted(glob.glob(os.path.join(src_kind, "*", "animations", anim, "west", "frame_*.png")))
    imgs = [Image.open(p).convert("RGBA") for p in paths]
    if anim in SETTLED:
        # Les dernières images : la posture installée (assis / couché).
        return imgs[-COUNTS[anim]:] if len(imgs) >= COUNTS[anim] else imgs
    return pick(imgs, COUNTS[anim])


def present_anims(src_kind):
    """Animations réellement présentes pour ce compagnon (toutes ne le sont pas)."""
    return [a for a in COUNTS if glob.glob(os.path.join(src_kind, "*", "animations", a, "west", "frame_*.png"))]


def main(kind, src):
    src_kind = os.path.join(src, kind)
    anims = {anim: anim_frames(src_kind, anim) for anim in present_anims(src_kind)}

    # Canevas commun à toutes les animations : union des boîtes englobantes.
    boxes = [f.getbbox() for fs in anims.values() for f in fs if f.getbbox()]
    box = (min(b[0] for b in boxes), min(b[1] for b in boxes),
           max(b[2] for b in boxes), max(b[3] for b in boxes))
    cw, ch = box[2] - box[0], box[3] - box[1]

    # Nettoie les anciennes images de ce compagnon.
    for d in os.listdir(ASSETS):
        if d.startswith(f"companion_{kind}_") and d.endswith(".imageset"):
            folder = os.path.join(ASSETS, d)
            for f in os.listdir(folder):
                os.remove(os.path.join(folder, f))
            os.rmdir(folder)

    for anim, fs in anims.items():
        for n, frame in enumerate(fs, 1):
            write_imageset(f"companion_{kind}_{anim}_{n}", frame.crop(box))

    # Portrait : la vue de face (south), rognée et agrandie sans lissage.
    south = Image.open(glob.glob(os.path.join(src_kind, "*", "rotations", "south.png"))[0]).convert("RGBA")
    sb = south.getbbox()
    side = max(sb[2] - sb[0], sb[3] - sb[1]) + 6
    cx, cy = (sb[0] + sb[2]) // 2, (sb[1] + sb[3]) // 2
    head = south.crop((cx - side // 2, cy - side // 2, cx + side // 2, cy + side // 2))
    write_imageset(f"companion_{kind}_portrait", head.resize((256, 256), Image.NEAREST))

    print(kind, f"canevas {cw}x{ch}", {a: len(f) for a, f in anims.items()})


if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else DEFAULT_SRC
    for k in KINDS:
        main(k, src)
