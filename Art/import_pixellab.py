#!/usr/bin/env python3
"""Installe les animations PixelLab des héros dans Assets.xcassets.

Les frames brutes sont dans Art/pixellab/<classe>/<animation>/fN.png (f0 = image de départ
envoyée à PixelLab, ignorée ; f1.. = frames générées). Toutes les frames d'un héros sont
posées sur un même canevas, centré sur son corps pour que le miroir (héros face à gauche)
tourne autour de lui, et assez large pour l'épée, l'arc ou le bâton de l'attaque.

Usage : <python avec Pillow> Art/import_pixellab.py [warrior archer mage extras]
Le nombre de frames par animation doit correspondre à HeroClass.frames() (World.swift).
"""
import json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
EIGHT = [1, 2, 3, 4, 5, 6, 7, 8]
FOUR = [1, 2, 3, 4]
SPECIAL_SHIFT = 12  # décalage du héros dans les frames 128x128 du coup spécial

# animation du jeu -> frames retenues : liste de numéros pris dans le dossier du même nom,
# ou de couples (dossier, numéro). Le repos enchaîne 4 images calmes puis 4 où le héros
# s'occupe (le jeu coupe l'animation en deux moitiés).
# _center : x du milieu du corps dans les frames PixelLab.
# _special : frames retenues dans special/ (coup spécial, animé depuis attack/f0 agrandi).
# _head : (x du centre de la tête, côté du carré, décalage vers le bas) pour le portrait, pris dans idle/f1.
# Le coup doit tomber vers la 3e image (le jeu joue l'attaque à 0,07 s par image).
def busy(folder):
    return [(folder, i) for i in FOUR]


HEROES = {
    "warrior": {
        "walk": EIGHT, "idle": FOUR, "flee": EIGHT, "sleep": FOUR,
        "tavern": [1, 2, 3, 4, 5, 6, 3, 2],  # tête nue ; la mousse se déforme après la 6e image
        "attack": [3, 4, 7, 7, 8, 8],
        "hurt": [2],
        "rest": [("rest", i) for i in FOUR] + busy("sharpen"),
        "_center": 37, "_head": (38, 40, 0),
        "_special": [2, 3, 4, 6, 7, 8, 9, 10, 11, 12],  # grand coup d'épée vertical, l'arc tombe à la 5e image
    },
    "archer": {
        "walk": EIGHT, "idle": FOUR, "flee": EIGHT, "sleep": FOUR, "tavern": EIGHT,
        # Capuche sur la tête pour se battre ; chignon (côtés non rasés) au repos et à la taverne.
        "attack": [3, 5, 6, 7, 8, 8],  # la flèche part à la 4e image (~0,2 s)
        "hurt": [2],
        "rest": [("rest", i) for i in FOUR] + busy("whittle"),
        "_center": 30, "_head": (36, 40, 0),
        "_special": [2, 3, 4, 5, 7, 8, 9, 10, 11, 12],  # flèche verte chargée, lâchée à la 7e image
    },
    "mage": {
        "walk": EIGHT, "idle": FOUR,
        "sleep": FOUR, "tavern": EIGHT,
        "flee": [1, 2, 3, 4, 5, 4, 3, 2],  # le chapeau s'envole après la 5e image
        "attack": [3, 4, 5, 6, 7, 8],  # l'orbe part à la 3e image
        "hurt": [2],
        "rest": [("rest", i) for i in FOUR] + busy("read"),
        "_center": 34, "_head": (37, 44, 4),
        "_special": [2, 3, 4, 5, 6, 8, 9, 11, 12, 12],  # boule de magie bleue, lancée à la 8e image
    },
}


# Personnages non joueurs et feu de camp : nom de l'asset -> (dossier dans Art/pixellab, frames).
# Chaque série est recadrée sur l'union de ses frames, pour rester calée d'une image à l'autre.
EXTRAS = {
    "npc_barmaid_idle": ("npc/barmaid_idle", FOUR),
    "npc_bard_walk": ("npc/bard_walk", EIGHT),
    "npc_bard_play": ("npc/bard_play", EIGHT),
    "merchant_idle": ("npc/merchant_idle", FOUR),
    "merchant_wave": ("npc/merchant_wave", FOUR),
    "fx_campfire": ("npc/fire", EIGHT),
}


def extras():
    # Les séries d'un même personnage (marchand qui attend / salue) partagent un cadre :
    # le jeu change de texture sans changer la taille du sprite.
    loaded = {name: [Image.open(os.path.join(ROOT, "Art", "pixellab", folder, f"f{i}.png")).convert("RGBA")
                     for i in picks] for name, (folder, picks) in EXTRAS.items()}
    groups = {}
    for name, fs in loaded.items():
        groups.setdefault(name.rsplit("_", 1)[0], []).extend(f.getbbox() for f in fs)
    for name, fs in loaded.items():
        boxes = groups[name.rsplit("_", 1)[0]]
        box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        for n, f in enumerate(fs, 1):
            write_imageset(f"{name}_{n}", f.crop(box))
        print(name, len(fs), "frames", (box[2] - box[0], box[3] - box[1]))


def write_imageset(name, img):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        os.remove(os.path.join(folder, f))
    img.save(os.path.join(folder, f"{name}.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as fh:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, fh, indent=2)


def remove_imageset(name):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    if os.path.isdir(folder):
        for f in os.listdir(folder):
            os.remove(os.path.join(folder, f))
        os.rmdir(folder)


def main(hero):
    spec = HEROES[hero]
    src = os.path.join(ROOT, "Art", "pixellab", hero)
    center = spec["_center"]
    def load(anim, pick):
        folder, i = pick if isinstance(pick, tuple) else (anim, pick)
        return Image.open(os.path.join(src, folder, f"f{i}.png")).convert("RGBA")
    frames = {anim: [load(anim, p) for p in picks] for anim, picks in spec.items() if not anim.startswith("_")}

    # Canevas commun : symétrique autour du corps, assez large pour tout ce qui dépasse.
    reach = max(max(center - f.getbbox()[0], f.getbbox()[2] - center)
                for fs in frames.values() for f in fs)
    cw, ch = 2 * reach + 2, max(f.height for fs in frames.values() for f in fs)
    dx = cw // 2 - center

    # Anciennes images de ce héros (planches Gemini, pose fixe Midjourney).
    remove_imageset(f"hero_{hero}")
    for d in os.listdir(ASSETS):
        if d.startswith(f"hero_{hero}_") and d.endswith(".imageset") and not d.startswith(f"hero_{hero}_portrait"):
            remove_imageset(d[: -len(".imageset")])

    for anim, fs in frames.items():
        for n, frame in enumerate(fs, 1):
            canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            canvas.alpha_composite(frame, (dx, ch - frame.height))
            write_imageset(f"hero_{hero}_{anim}_{n}", canvas)
    print(hero, f"canevas {cw}x{ch}", {a: len(f) for a, f in frames.items()})

    # Coup spécial : frames 128x128 (le héros posé à x+12, pieds en bas) pour laisser la place
    # aux effets. Canevas à part, plus grand, toujours centré sur le corps : le jeu les joue
    # sur un sprite dédié à leur taille.
    if "_special" in spec:
        sc = center + SPECIAL_SHIFT
        sfs = [Image.open(os.path.join(src, "special", f"f{i}.png")).convert("RGBA") for i in spec["_special"]]
        sreach = max(max(sc - f.getbbox()[0], f.getbbox()[2] - sc) for f in sfs)
        top = min(f.getbbox()[1] for f in sfs)
        sw, sh = 2 * sreach + 2, 128 - top
        for n, f in enumerate(sfs, 1):
            canvas = Image.new("RGBA", (sw, sh), (0, 0, 0, 0))
            canvas.alpha_composite(f, (sw // 2 - sc, -top))
            write_imageset(f"hero_{hero}_special_{n}", canvas)
        print(hero, f"special {sw}x{sh}", len(sfs))

    # Portrait : la tête de la pose d'attente, agrandie sans lissage.
    idle = Image.open(os.path.join(src, "idle", "f1.png")).convert("RGBA")
    cx, side, dy = spec["_head"]
    top = idle.getbbox()[1] - 2 + dy
    head = idle.crop((cx - side // 2, top, cx + side // 2, top + side))
    write_imageset(f"hero_{hero}_portrait", head.resize((256, 256), Image.NEAREST))


if __name__ == "__main__":
    for h in sys.argv[1:] or [*HEROES, "extras"]:
        extras() if h == "extras" else main(h)
