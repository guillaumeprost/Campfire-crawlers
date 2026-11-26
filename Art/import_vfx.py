#!/usr/bin/env python3
"""Installe les effets visuels (atelier VFX de PixelLab) dans Assets.xcassets.

Sources : Art/pixellab/vfx/<nom>/sheet.png + sheet.json (export « spritesheet » de l'atelier,
format Aseprite : `frames[i].frame` = rectangle dans la planche, `duration` en ms,
`meta.anchor` = point d'ancrage en pixels depuis le coin haut gauche).

Les images finales entièrement vides sont écartées. Images : fx_<nom>_1…
Le nombre d'images, la cadence et l'ancrage sont écrits dans IdleRPG/FXAnims.swift (généré).

Usage : /usr/bin/python3 Art/import_vfx.py
"""
import json, os, re
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "IdleRPG", "Assets.xcassets")
SRC = os.path.join(ROOT, "Art", "pixellab", "vfx")
SWIFT = os.path.join(ROOT, "IdleRPG", "FXAnims.swift")
# Images de début écartées : l'ombre s'ouvre sur un disque plein, trop lourd à l'écran.
SKIP = {"shadow": 2}


def main():
    rows = []
    for name in sorted(os.listdir(SRC)):
        sheet, meta = os.path.join(SRC, name, "sheet.png"), os.path.join(SRC, name, "sheet.json")
        if not (os.path.exists(sheet) and os.path.exists(meta)):
            continue
        data = json.load(open(meta))
        img = Image.open(sheet).convert("RGBA")
        frames = []
        for f in data["frames"]:
            r = f["frame"]
            frames.append(img.crop((r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"])))
        frames = frames[SKIP.get(name, 0):]
        while frames and frames[-1].getbbox() is None:
            frames.pop()
        for d in os.listdir(ASSETS):
            if re.fullmatch(rf"fx_{name}_\d+\.imageset", d):
                for f in os.listdir(os.path.join(ASSETS, d)):
                    os.remove(os.path.join(ASSETS, d, f))
                os.rmdir(os.path.join(ASSETS, d))
        for i, frame in enumerate(frames, start=1):
            folder = os.path.join(ASSETS, f"fx_{name}_{i}.imageset")
            os.makedirs(folder, exist_ok=True)
            frame.save(os.path.join(folder, f"fx_{name}_{i}.png"))
            with open(os.path.join(folder, "Contents.json"), "w") as fh:
                json.dump({"images": [{"filename": f"fx_{name}_{i}.png", "idiom": "universal"}],
                           "info": {"author": "xcode", "version": 1}}, fh, indent=2)
        w, h = frames[0].size
        anchor = data["meta"]["anchor"]
        fps = round(1000 / data["frames"][0]["duration"], 1)
        # Ancrage SpriteKit : origine en bas à gauche.
        rows.append((name, len(frames), fps, round(anchor["x"] / w, 3), round(1 - anchor["y"] / h, 3), h))
        print(name, len(frames), "images", (w, h), fps, "i/s")

    with open(SWIFT, "w") as fh:
        fh.write("// Fichier généré par Art/import_vfx.py : ne pas modifier à la main.\n")
        fh.write("import CoreGraphics\n\n")
        fh.write("/// Effets visuels animés : nombre d'images, cadence, point d'ancrage (repère SpriteKit)\n")
        fh.write("/// et hauteur d'une image en pixels.\n")
        fh.write("enum FXAnims {\n")
        fh.write("    static let table: [String: (count: Int, fps: Double, anchor: CGPoint, height: CGFloat)] = [\n")
        for name, n, fps, ax, ay, h in rows:
            fh.write(f'        "{name}": ({n}, {fps}, CGPoint(x: {ax}, y: {ay}), {h}),\n')
        fh.write("    ]\n}\n")


if __name__ == "__main__":
    main()
