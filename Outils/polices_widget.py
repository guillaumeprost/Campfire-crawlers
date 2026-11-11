#!/usr/bin/env python3
"""Fabrique les polices animées des widgets à partir des sprites du héros.

Un widget ne peut pas jouer d'animation. Il sait en revanche afficher un chronomètre
qui avance seul, chaque seconde. Chaque police dessine donc les chiffres 0 à 9 comme
les images d'une animation : le widget affiche le chronomètre dans cette police et ne
laisse voir que le dernier chiffre, celui des secondes. Le héros change d'image chaque seconde.

Une police par classe et par animation, au format sbix (images PNG dans la police).
Usage : python3 Outils/polices_widget.py   (à relancer quand les sprites changent)
"""
import glob
import os
import struct
import subprocess
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CATALOG = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
OUT = os.path.join(ROOT, "IdleRPGWidgets", "Polices")
CLASSES = ["warrior", "archer", "mage"]
ANIMATIONS = ["idle", "walk", "attack", "rest", "flee"]
# Les images sont agrandies d'autant avant d'entrer dans la police : nettes même en StandBy.
SCALE = 6
UPEM = 1000


def sprite(cls, anim, n):
    found = glob.glob(os.path.join(CATALOG, f"hero_{cls}_{anim}_{n}.imageset", "*.png"))
    return found[0] if found else None


def png_size(path):
    with open(path, "rb") as f:
        head = f.read(24)
    return struct.unpack(">II", head[16:24])


def checksum(data):
    data += b"\0" * (-len(data) % 4)
    return sum(struct.unpack(f">{len(data) // 4}I", data)) & 0xFFFFFFFF


def build_font(name, pngs, width, height):
    """pngs : dix images PNG, une par chiffre. width, height : taille du sprite d'origine."""
    advance = round(UPEM * width / height)
    num_glyphs = 12  # .notdef, 0-9, deux-points
    advances = [0] + [advance] * 10 + [0]

    head = struct.pack(">HHIIIHHqqhhhhHHhhh", 1, 0, 0x00010000, 0, 0x5F0F3CF5, 0x000B, UPEM,
                       0, 0, 0, 0, advance, UPEM, 0, 8, 2, 0, 0)
    hhea = struct.pack(">HH" + "hhh" + "H" + "hhh" + "hhh" + "hhhh" + "h" + "H", 1, 0, UPEM, 0, 0, advance, 0, 0, advance,
                       1, 0, 0, 0, 0, 0, 0, 0, num_glyphs)
    maxp = struct.pack(">IHHHHHHHHHHHHHH", 0x00010000, num_glyphs, 0, 0, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0)
    os2 = struct.pack(">HhHHHhhhhhhhhhhh10sIIII4sHHHhhhHHIIhhHHH",
                      4, advance, 400, 5, 0, 0, 0, 0, 0, 0, 0, 0, 0, 50, 300, 0, b"\0" * 10,
                      1, 0, 0, 0, b"CCRW", 0x40, 0x30, 0x3A, UPEM, 0, 0, UPEM, 0, 1, 0, 0, 0, 0, 0x30, 1)
    # cmap : '0' à ':' vers les glyphes 1 à 11.
    sub = struct.pack(">HHHHHHH", 4, 32, 0, 4, 4, 1, 0)
    sub += struct.pack(">HH", 0x3A, 0xFFFF) + b"\0\0" + struct.pack(">HH", 0x30, 0xFFFF)
    sub += struct.pack(">HH", (1 - 0x30) & 0xFFFF, 1) + struct.pack(">HH", 0, 0)
    cmap = struct.pack(">HHHHIHHI", 0, 2, 0, 3, 20, 3, 1, 20) + sub
    hmtx = b"".join(struct.pack(">Hh", a, 0) for a in advances)
    loca = b"\0\0" * (num_glyphs + 1)
    glyf = b"\0\0\0\0"
    post = struct.pack(">IIhhIIIII", 0x00030000, 0, -100, 50, 1, 0, 0, 0, 0)

    records, strings = [], b""
    for name_id, text in [(1, name), (2, "Regular"), (4, name), (6, name)]:
        raw = text.encode("utf-16-be")
        for platform, encoding, language in [(0, 3, 0), (3, 1, 0x409)]:
            records.append((platform, encoding, language, name_id, len(raw), len(strings)))
            strings += raw
    records.sort()
    name_table = struct.pack(">HHH", 0, len(records), 6 + 12 * len(records))
    name_table += b"".join(struct.pack(">HHHHHH", *r) for r in records) + strings

    # sbix : une seule série d'images, un em valant la hauteur de l'image.
    glyph_data = [b""] + [struct.pack(">hh4s", 0, 0, b"png ") + open(p, "rb").read() for p in pngs] + [b""]
    strike_header = 4 + 4 * (num_glyphs + 1)
    offsets, cursor = [], strike_header
    for data in glyph_data:
        offsets.append(cursor)
        cursor += len(data)
    offsets.append(cursor)
    strike = struct.pack(">HH", height * SCALE, 72) + b"".join(struct.pack(">I", o) for o in offsets)
    strike += b"".join(glyph_data)
    sbix = struct.pack(">HHII", 1, 1, 1, 12) + strike

    tables = {b"OS/2": os2, b"cmap": cmap, b"glyf": glyf, b"head": head, b"hhea": hhea, b"hmtx": hmtx,
              b"loca": loca, b"maxp": maxp, b"name": name_table, b"post": post, b"sbix": sbix}
    tags = sorted(tables)
    count = len(tags)
    offset = 12 + 16 * count
    directory, body = b"", b""
    for tag in tags:
        data = tables[tag]
        directory += struct.pack(">4sIII", tag, checksum(data), offset + len(body), len(data))
        body += data + b"\0" * (-len(data) % 4)
    font = struct.pack(">IHHHH", 0x00010000, count, 128, 3, count * 16 - 128) + directory + body
    # Ajustement de la somme de contrôle, écrit dans la table head.
    adjust = (0xB1B0AFBA - checksum(font)) & 0xFFFFFFFF
    head_offset = 12 + 16 * count + sum(len(tables[t]) + (-len(tables[t]) % 4) for t in tags[:tags.index(b"head")])
    font = font[:head_offset + 8] + struct.pack(">I", adjust) + font[head_offset + 12:]
    return font


def main():
    os.makedirs(OUT, exist_ok=True)
    tmp = tempfile.mkdtemp()
    jobs, plan = [], []
    for cls in CLASSES:
        for anim in ANIMATIONS:
            frames = []
            n = 1
            while sprite(cls, anim, n):
                frames.append(sprite(cls, anim, n))
                n += 1
            if not frames:
                print(f"  {cls} {anim} : aucun sprite, ignoré")
                continue
            # Dix chiffres pour n images : 0 à 9 parcourent l'animation et rebouclent proprement.
            chosen = [frames[d * len(frames) // 10] for d in range(10)]
            big = []
            for i, path in enumerate(chosen):
                target = os.path.join(tmp, f"{cls}_{anim}_{i}.png")
                jobs += [path, target]
                big.append(target)
            plan.append((cls, anim, big, png_size(frames[0])))
    subprocess.run(["swift", os.path.join(ROOT, "Outils", "agrandir.swift"), str(SCALE)] + jobs, check=True)
    names = []
    for cls, anim, big, (w, h) in plan:
        name = f"CC{cls.capitalize()}{anim.capitalize()}"
        with open(os.path.join(OUT, name + ".ttf"), "wb") as f:
            f.write(build_font(name, big, w, h))
        names.append(name + ".ttf")
        print(f"  {name}.ttf")
    print(f"{len(names)} polices dans {os.path.relpath(OUT, ROOT)}")


if __name__ == "__main__":
    main()
