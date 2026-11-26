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

Usage : /usr/bin/python3 Art/import_companions.py [dossier_source] [compagnons…]
Le nombre d'images par animation doit correspondre à CompanionKind.frames() (World.swift) :
idle = 4, walk = 8, attack = 6.
"""
import glob, json, os, sys
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
DEFAULT_SRC = "/private/tmp/claude-501/-Users-guillaumeprost--claude-spares-spare-y9MfRV/9d2a61a2-ca35-4d2e-af55-baad01a235ec/scratchpad/companions"

# Nombre d'images retenu par animation (doit coller à CompanionKind.frames()).
COUNTS = {"idle": 4, "walk": 8, "sit": 4, "sleep": 4, "attack": 6}
# Animations « posées » : on garde les dernières images (posture installée), pas le
# début du mouvement, pour que la boucle montre l'animal assis / endormi et non en
# train de s'asseoir / se coucher en boucle.
SETTLED = {"sit", "sleep"}
KINDS = ["wolf", "panther", "bear", "fox", "stag"]


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


# Retouches par compagnon. SOURCE : animation PixelLab à utiliser à la place de celle du même nom
# (le cerf reste debout dans ses clips « assis » et « endormi » : on prend la fin de `liedown`).
# START : première image retenue (l'idle du cerf n'a ses grands bois qu'à partir de la 7e).
SOURCE = {}
START = {("stag", "idle"): 6}
# Poses dessinées à part (Art/pixellab/companions/<kind>_<anim>.png), à la place d'une animation
# PixelLab ratée : le cerf couché du clip `lie-down` avait des pattes démesurées, tendues devant lui.
# Une seule image suffit : assis ou endormi, le jeu n'en montre qu'une et le fait respirer.
STILLS = os.path.join(ROOT, "Art", "pixellab", "companions")
# Ours et panthère : PixelLab les a rendus avec un liseré blanc autour du corps (surtout en
# marche) et, pour l'ours, des pattes arrière en aplat noir. Valeur : couleur qui remplace ces
# aplats noirs, ou None pour les laisser (la panthère est noire, cela ne se voit pas).
DEFRINGE = {"bear": (74, 42, 24, 255), "panther": None}


def still(kind, anim):
    path = os.path.join(STILLS, f"{kind}_{anim}.png")
    return Image.open(path).convert("RGBA") if os.path.exists(path) else None


def clean(img, fill):
    """Retire le liseré clair collé au bord du corps et les pixels perdus loin de lui, et
    remplace les aplats noirs par `fill`."""
    img = img.copy()
    px, (w, h) = img.load(), img.size
    def clear(x, y):
        return not (0 <= x < w and 0 <= y < h) or px[x, y][3] < 40
    for _ in range(12):   # le liseré s'épaissit par endroits (entre la queue et la patte) : on le ronge
        edge = [(x, y) for y in range(h) for x in range(w)
                if px[x, y][3] >= 40 and min(px[x, y][:3]) > 185
                and any(clear(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        if not edge:
            break
        for x, y in edge:
            px[x, y] = (0, 0, 0, 0)
    inner = [(x, y) for y in range(h) for x in range(w)
             if px[x, y][3] >= 40 and max(px[x, y][:3]) < 28
             and not any(clear(x + dx, y + dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1))]
    for x, y in inner if fill else []:
        px[x, y] = fill
    if fill is None:
        # Animal sans blanc (panthère) : le peu de clair qui reste, enfermé dans le corps, est fondu.
        for y in range(h):
            for x in range(w):
                if px[x, y][3] >= 40 and min(px[x, y][:3]) > 185:
                    px[x, y] = (38, 40, 56, 255)
    # Pixels perdus : un petit amas détaché du corps n'appartient pas à l'animal.
    seen = set()
    for y0 in range(h):
        for x0 in range(w):
            if (x0, y0) in seen or px[x0, y0][3] == 0:
                continue
            blob, todo = [], [(x0, y0)]
            seen.add((x0, y0))
            while todo:
                x, y = todo.pop()
                blob.append((x, y))
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        n = (x + dx, y + dy)
                        if 0 <= n[0] < w and 0 <= n[1] < h and n not in seen and px[n[0], n[1]][3] > 0:
                            seen.add(n)
                            todo.append(n)
            if len(blob) < 8:
                for x, y in blob:
                    px[x, y] = (0, 0, 0, 0)
    return img


def anim_frames(src_kind, anim):
    kind = os.path.basename(src_kind)
    drawn = still(kind, anim)
    if drawn is not None:
        return [drawn] * COUNTS[anim]
    folder = SOURCE.get((kind, anim), anim)
    paths = sorted(glob.glob(os.path.join(src_kind, "*", "animations", folder, "west", "frame_*.png")))
    imgs = [Image.open(p).convert("RGBA") for p in paths][START.get((kind, anim), 0):]
    if anim in SETTLED:
        # Les dernières images : la posture installée (assis / couché).
        return imgs[-COUNTS[anim]:] if len(imgs) >= COUNTS[anim] else imgs
    return pick(imgs, COUNTS[anim])


def present_anims(src_kind):
    """Animations réellement présentes pour ce compagnon (toutes ne le sont pas)."""
    kind = os.path.basename(src_kind)
    return [a for a in COUNTS if still(kind, a) is not None
            or glob.glob(os.path.join(src_kind, "*", "animations", SOURCE.get((kind, a), a), "west", "frame_*.png"))]


def write_table():
    """Largeur réelle de chaque animal debout, en pixels : le cadre de ses images est bien plus
    large que lui (il faut la place du bond de l'attaque), et le jeu se cale sur son corps."""
    rows = []
    for kind in KINDS:
        path = os.path.join(ASSETS, f"companion_{kind}_idle_1.imageset", f"companion_{kind}_idle_1.png")
        if os.path.exists(path):
            box = Image.open(path).convert("RGBA").getbbox()
            # Pose de repos : la plus large de « assis » et « endormi » (dernière image, celle du jeu).
            rest = 0
            for anim in SETTLED:
                last = os.path.join(ASSETS, f"companion_{kind}_{anim}_{COUNTS[anim]}.imageset",
                                    f"companion_{kind}_{anim}_{COUNTS[anim]}.png")
                if os.path.exists(last):
                    b = Image.open(last).convert("RGBA").getbbox()
                    rest = max(rest, b[2] - b[0])
            rows.append((kind, box[2] - box[0], rest or box[2] - box[0]))
    with open(os.path.join(ROOT, "IdleRPG", "CompanionArt.swift"), "w") as fh:
        fh.write("// Fichier généré par Art/import_companions.py : ne pas modifier à la main.\n")
        fh.write("import CoreGraphics\n\n")
        fh.write("/// Largeur du corps de chaque compagnon debout, en pixels de ses images.\n")
        fh.write("enum CompanionArt {\n    static let bodyWidth: [String: CGFloat] = [\n")
        for kind, width, _ in rows:
            fh.write(f'        "{kind}": {width},\n')
        fh.write("    ]\n")
        fh.write("    /// Largeur une fois assis ou couché : certains s'allongent de tout leur long.\n")
        fh.write("    static let restWidth: [String: CGFloat] = [\n")
        for kind, _, rest in rows:
            fh.write(f'        "{kind}": {rest},\n')
        fh.write("    ]\n}\n")


def main(kind, src):
    src_kind = os.path.join(src, kind)
    anims = {anim: anim_frames(src_kind, anim) for anim in present_anims(src_kind)}
    if kind in DEFRINGE:
        anims = {anim: [clean(f, DEFRINGE[kind]) for f in fs] for anim, fs in anims.items()}

    # PixelLab ne pose pas l'animal au même endroit d'une animation à l'autre : debout il flotte
    # une vingtaine de pixels au-dessus du bas de l'image, assis il le touche, et il glisse de côté.
    # On recale donc chaque animation : pattes au sol, milieu du corps au milieu du cadre.
    # Repère pris sur la pose installée (dernière image) pour assis/endormi, sur la première
    # image pour l'attaque (elle part de la pose debout), sur la médiane sinon. Le mouvement
    # propre à l'animation (pas, bond de l'attaque) est conservé.
    placed = {}
    for anim, fs in anims.items():
        boxes = [f.getbbox() for f in fs]
        centers = sorted((b[0] + b[2]) / 2 for b in boxes)
        if anim in SETTLED:
            ref_x, ground = (boxes[-1][0] + boxes[-1][2]) / 2, boxes[-1][3]
        elif anim == "attack":
            ref_x, ground = (boxes[0][0] + boxes[0][2]) / 2, max(b[3] for b in boxes)
        else:
            ref_x, ground = centers[len(centers) // 2], max(b[3] for b in boxes)
        # Chaque image rognée, avec sa place par rapport au repère (milieu du corps, sol).
        placed[anim] = [(f.crop(b), b[0] - ref_x, b[1] - ground) for f, b in zip(fs, boxes)]

    # Cadre commun, symétrique autour du corps (le miroir tourne autour de lui), pieds en bas.
    half = int(max(max(-dx, dx + im.width) for fs in placed.values() for im, dx, _ in fs)) + 1
    cw, ch = half * 2, int(max(-dy for fs in placed.values() for _, _, dy in fs))

    # Nettoie les anciennes images de ce compagnon.
    for d in os.listdir(ASSETS):
        if d.startswith(f"companion_{kind}_") and d.endswith(".imageset"):
            folder = os.path.join(ASSETS, d)
            for f in os.listdir(folder):
                os.remove(os.path.join(folder, f))
            os.rmdir(folder)

    for anim, fs in placed.items():
        for n, (im, dx, dy) in enumerate(fs, 1):
            canvas = Image.new("RGBA", (cw, ch), (0, 0, 0, 0))
            # Ce qui passerait sous le sol (une patte qui glisse en se couchant) est coupé.
            canvas.paste(im, (int(round(half + dx)), int(round(ch + dy))))
            write_imageset(f"companion_{kind}_{anim}_{n}", canvas)

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
    # Compagnons à (ré)installer : tous par défaut, ou ceux nommés après le dossier source.
    for k in sys.argv[2:] or KINDS:
        main(k, src)
    write_table()
