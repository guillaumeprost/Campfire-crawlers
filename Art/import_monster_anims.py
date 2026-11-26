#!/usr/bin/env python3
"""Installe les animations des monstres et boss (PixelLab `animate_image`) dans Assets.xcassets.

Sources : Art/pixellab/monsters_anims/<nom>/<idle|attack|death>/f<N>.png, téléchargées par
Art/fetch_pixellab_jobs.py. f0 est toujours l'image de départ (le sprite fixe du jeu), posée
sur un cadre serré pour l'idle et sur un cadre plus large pour l'attaque et la mort.

Toutes les images d'un monstre sont recalées sur un cadre commun : le milieu du sprite fixe
est au milieu du cadre, ses pieds en bas. Le jeu n'a donc besoin que de la hauteur du sprite
fixe (en pixels de ce cadre) pour garder la créature à la même taille à l'écran : elle est
écrite, avec le nombre d'images, dans IdleRPG/MonsterAnims.swift (fichier généré).

Images : <nom>_idle_1…, <nom>_attack_1…, <nom>_death_1…

Usage : /usr/bin/python3 Art/import_monster_anims.py
"""
import json, os, re
from PIL import Image, ImageOps

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
SRC = os.path.join(ROOT, "Art", "pixellab", "monsters_anims")
SWIFT = os.path.join(ROOT, "IdleRPG", "MonsterAnims.swift")
ANIMS = ("idle", "attack", "death")

# Dessinés tournés vers la droite : on les retourne (comme Art/import_monsters.py).
FACING_RIGHT = {"m_skeleton"}


def bbox(img):
    """Cadre des pixels visibles (on ignore les voiles presque transparents)."""
    return img.getchannel("A").point(lambda a: 255 if a > 40 else 0).getbbox()


def frames(name, anim):
    folder = os.path.join(SRC, name, anim)
    if not os.path.isdir(folder):
        return []
    files = sorted((f for f in os.listdir(folder) if re.fullmatch(r"f\d+\.png", f)), key=lambda f: int(f[1:-4]))
    return [Image.open(os.path.join(folder, f)).convert("RGBA") for f in files]


def write(name, img):
    folder = os.path.join(ASSETS, f"{name}.imageset")
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        os.remove(os.path.join(folder, f))
    img.save(os.path.join(folder, f"{name}.png"))
    with open(os.path.join(folder, "Contents.json"), "w") as fh:
        json.dump({"images": [{"filename": f"{name}.png", "idiom": "universal"}],
                   "info": {"author": "xcode", "version": 1}}, fh, indent=2)


def main():
    table = {}
    for name in sorted(os.listdir(SRC)):
        sets = {a: frames(name, a) for a in ANIMS}
        if not sets["idle"]:
            continue
        # Le sprite fixe sert de repère : milieu et pieds.
        base = bbox(sets["idle"][0])
        base_height = base[3] - base[1]
        placed = {}   # anim -> [(image, décalage x, décalage y)] dans le repère « pieds au milieu »
        left = right = top = 0
        for anim, imgs in sets.items():
            if not imgs:
                continue
            start = bbox(imgs[0])
            # Même sprite dans un cadre plus large : on retrouve où il a été posé.
            ox = (start[0] + start[2]) / 2
            feet = start[3]
            # L'idle garde son image de départ et laisse tomber la dernière (identique) ;
            # attaque et mort commencent à la première image générée.
            keep = imgs[:-1] if anim == "idle" else imgs[1:]
            placed[anim] = []
            for img in keep:
                b = bbox(img)
                if not b:
                    continue
                cut = img.crop(b)
                dx, dy = b[0] - ox, b[1] - feet      # coin haut gauche par rapport aux pieds
                placed[anim].append((cut, dx, dy))
                left, right, top = max(left, -dx), max(right, dx + cut.width), max(top, -dy)
        half = int(max(left, right) + 1)
        height = int(top + 1)
        counts = {}
        for anim in ANIMS:
            # On efface d'abord les anciennes images de cette animation.
            for d in os.listdir(ASSETS):
                if re.fullmatch(rf"{name}_{anim}_\d+\.imageset", d):
                    for f in os.listdir(os.path.join(ASSETS, d)):
                        os.remove(os.path.join(ASSETS, d, f))
                    os.rmdir(os.path.join(ASSETS, d))
            for i, (cut, dx, dy) in enumerate(placed.get(anim, []), start=1):
                canvas = Image.new("RGBA", (half * 2, height), (0, 0, 0, 0))
                canvas.paste(cut, (int(round(half + dx)), int(round(height + dy))))
                if name in FACING_RIGHT:
                    canvas = ImageOps.mirror(canvas)
                write(f"{name}_{anim}_{i}", canvas)
            counts[anim] = len(placed.get(anim, []))
        table[name] = (counts, base_height)
        print(name, counts, "cadre", (half * 2, height), "sprite", base_height)

    with open(SWIFT, "w") as fh:
        fh.write("// Fichier généré par Art/import_monster_anims.py : ne pas modifier à la main.\n")
        fh.write("import CoreGraphics\n\n")
        fh.write("/// Animations disponibles pour chaque créature : nombre d'images par animation, et hauteur\n")
        fh.write("/// (en pixels du cadre des animations) du sprite fixe, pour garder la même taille à l'écran.\n")
        fh.write("enum MonsterAnims {\n")
        fh.write("    static let table: [String: (idle: Int, attack: Int, death: Int, base: CGFloat)] = [\n")
        for name, (c, h) in table.items():
            fh.write(f'        "{name}": ({c["idle"]}, {c["attack"]}, {c["death"]}, {h}),\n')
        fh.write("    ]\n}\n")


if __name__ == "__main__":
    main()
