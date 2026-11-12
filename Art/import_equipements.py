#!/usr/bin/env python3
"""Installe les équipements de la planche « Feu / Glace / Ombre / Bijoux » (Art/sheets/12_equipements_elements.jpg).

Usage : python3 Art/import_equipements.py <Assets.xcassets du jeu> [contrôle.png]

Les numéros sont ceux de l'image de contrôle de slicer.py :
    python3 Art/slicer.py <dossier> 12_equipements_elements

Chaque rareté a son élément, assorti à sa couleur dans le jeu :
commun = acier et bois, rare = glace (bleu), épique = ombre (violet), légendaire = feu (orange).
Une image s'appelle eq_<emplacement>[_<classe>]_<rareté>_<variante> ; la liste des variantes
est recopiée dans Item.swift (`ItemSlot.looks`). Les raretés sans dessin dans la planche
(anneau d'ombre, bottes d'ombre et de feu) sont teintées à partir d'un autre dessin.
"""
import colorsys, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import import_sheets as imp

SHEET = '12_equipements_elements'

# Emplacement -> rareté (0 à 3) -> liste de (numéros, options).
# Les bâtons 97 à 100 sont écartés : leurs halos se touchent, la découpe mélange les voisins.
# Option 'hue' : rotation de teinte en degrés ; 'key' : détourage par la couleur (trous des anneaux, cordes d'arc).
KEY = {'key': True}
GEAR = {
    'weapon_warrior': [
        [[32], [18], [48]],
        [[24], [25], [41], [26], [59], [60]],
        [[123], [124], [139], [140], [125], [141]],
        [[16], [17], [33], [19], [21], [35]],
    ],
    'weapon_archer': [
        [([80], KEY), ([81], KEY), ([82], KEY), ([83], KEY)],
        [([43], KEY), ([84], {'key': True, 'hue': 0, 'cool': True})],
        [([127], KEY), ([143], KEY), ([155], KEY), ([156], KEY)],
        [([64], KEY), ([65], KEY), ([66], KEY), ([67], KEY), ([68], KEY)],
    ],
    'weapon_mage': [
        [[96], [85], [86]],
        [[44], [45], [46], [47]],
        [[158], [171], [173], [144], [174]],
        [[37], [38], [39], [101], [87], [71]],
    ],
    'amulet': [
        [([132], KEY), ([134], KEY)],
        [([135], KEY), ([136], KEY)],
        [([138], KEY), ([133], KEY)],
        [([131], KEY), ([137], KEY)],
    ],
    'ring': [
        [([149], KEY)],
        [([150], KEY)],
        [([149], {'key': True, 'hue': 70})],
        [([148], KEY), ([147], KEY)],
    ],
    'armor': [
        [[89], [95]],
        [[73], [74], [75], [88], [78]],
        [[169], [170]],
        [[72], ([73], {'hue': -170, 'warm': True})],
    ],
    'helmet': [
        [([160], {'grey': True}), ([63], {'grey': True})],
        [([63], KEY), ([162], KEY)],
        [([160], KEY), ([176], KEY), ([161], KEY), ([151], KEY)],
        [([163], KEY), ([153], KEY)],
    ],
    'boots': [
        [[178]],
        [[179]],
        [([179], {'hue': 70})],
        [([178], {'hue': -25, 'warm': True})],
    ],
}


def tint(rows, opts):
    """Fait tourner la teinte des pixels colorés (les gris et le noir ne bougent pas)."""
    shift = opts.get('hue', 0) / 360
    out = []
    for row in rows:
        row = bytearray(row)
        for i in range(0, len(row), 4):
            if row[i + 3] == 0:
                continue
            r, g, b = row[i] / 255, row[i + 1] / 255, row[i + 2] / 255
            h, l, s = colorsys.rgb_to_hls(r, g, b)
            if opts.get('grey'):
                # Version d'acier ordinaire : presque plus de couleur.
                s *= 0.12
            elif opts.get('cool'):
                # Acier -> acier givré : un voile bleu sur les gris.
                h, s = 0.56, max(s, 0.35)
            elif opts.get('warm'):
                h, s = (h + shift) % 1, max(s, 0.45)
                if l > 0.25:
                    h = 0.07
            else:
                h = (h + shift) % 1
            r, g, b = colorsys.hls_to_rgb(h, l, s)
            row[i], row[i + 1], row[i + 2] = round(r * 255), round(g * 255), round(b * 255)
        out.append(row)
    return out


def cut(numbers, opts):
    """Découpe la boîte trouvée par slicer.py, sans le rognage de import_sheets.crop :
    sur fond noir il coupait les objets fins (lances, bâtons, arcs) à leur partie claire."""
    s = imp.sheet(SHEET)
    boxes = [s['comps'][i] for i in numbers]
    k = 4
    box = (max(min(b[0] for b in boxes) - k, 0), max(min(b[1] for b in boxes) - k, 0),
           min(max(b[2] for b in boxes) + k, s['w']), min(max(b[3] for b in boxes) + k, s['h']))
    w, h, rows = imp.crop(SHEET, box, dict(opts, notrim=True))
    alpha = lambda row: any(row[3::4])
    top = next(y for y in range(h) if alpha(rows[y]))
    bottom = next(y for y in range(h - 1, -1, -1) if alpha(rows[y])) + 1
    cols = [x for x in range(w) if any(rows[y][4 * x + 3] for y in range(top, bottom))]
    x0, x1 = cols[0], cols[-1] + 1
    rows = [bytearray(r[4 * x0:4 * x1]) for r in rows[top:bottom]]
    return x1 - x0, bottom - top, rows


def sprites():
    result = {}
    for slot, rarities in GEAR.items():
        for rarity, looks in enumerate(rarities):
            for index, look in enumerate(looks):
                numbers, opts = look if isinstance(look, tuple) else (look, {})
                w, h, rows = cut(numbers, opts)
                if 'hue' in opts or opts.get('cool') or opts.get('warm') or opts.get('grey'):
                    rows = tint(rows, opts)
                result[f'eq_{slot}_{rarity}_{index + 1}'] = (w, h, rows)
    return result


def main():
    assets = sys.argv[1]
    found = sprites()
    for name, (w, h, rows) in found.items():
        imp.write_imageset(assets, name, w, h, rows)
    if len(sys.argv) > 2:
        imp.contact_sheet(sys.argv[2], found, cols=8)
    print(len(found), 'équipements exportés')
    for slot, rarities in GEAR.items():
        print(f'  {slot}:', [len(r) for r in rarities])


if __name__ == '__main__':
    main()
