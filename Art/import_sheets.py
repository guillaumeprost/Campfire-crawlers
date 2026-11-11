#!/usr/bin/env python3
"""Exporte les sprites des planches de Art/sheets vers le catalogue d'assets du jeu.

Usage : python3 Art/import_sheets.py <Assets.xcassets du jeu> <Assets.xcassets de l'extension> [contrôle.png]

Chaque entrée de SPRITES désigne un sprite par les numéros que montre l'image de
contrôle de slicer.py, ou par un rectangle (x0, y0, x1, y1) quand le repérage
automatique ne suffit pas.
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import slicer

HEROES, MON_A, MON_B = '05_heroes', '08_monsters_a', '02_monsters_b'
ITEMS, EXTRA, UI = '04_items_main', '01_items_extra', '06_ui'
CAMP, TERRAIN, TILES, THEMES = '10_camp_shop', '07_terrain', '11_dungeon_tiles', '09_dungeon_themes'

# Poses des héros : quatre images par animation, dans l'ordre de la planche.
HERO_FRAMES = {
    'warrior': {'idle': [9, 10, 11, 12], 'walk': [22, 23, 24, 25], 'attack': [(748, 288, 900, 390), 29, 30, 31], 'hurt': [37], 'flee': [38, 39, 40]},
    'archer': {'idle': [46, 47, 48, 49], 'walk': [60, 61, 62, 63], 'attack': [66, 67, 68, 69], 'hurt': [76], 'flee': [77, 78, 79]},
    'mage': {'idle': [86, 87, 88, 89], 'walk': [100, 101, 102, 103], 'attack': [106, 107, 108, 109], 'hurt': [115], 'flee': [116, 117, 118]},
}

# nom -> (planche, numéros ou rectangle, options)
SPRITES = {
    # Monstres
    'm_rat': (MON_B, (495, 330, 612, 426)),
    'm_bat': (MON_A, [41]),
    'm_spider': (MON_A, [44]),
    'm_spider_brown': (MON_A, [45]),
    'm_slime_green': (MON_A, [15]),
    'm_slime_blue': (MON_A, [16]),
    'm_slime_red': (MON_A, [17]),
    'm_skeleton': (MON_A, [26]),
    'm_skeleton_archer': (MON_A, [28]),
    'm_goblin': (MON_A, [33]),
    'm_imp': (MON_A, [47]),
    'm_orc': (MON_A, [54]),
    'm_ghost': (MON_A, [61]),
    'm_golem': (MON_A, [65]),
    'm_golem_gray': (MON_A, [66]),
    'm_plant': (MON_A, [67]),
    'm_scorpion': (MON_B, (256, 322, 366, 426)),
    'm_werewolf': (MON_B, (255, 520, 370, 645)),
    'm_gargoyle': (MON_B, (28, 515, 135, 645)),
    'm_fire_imp': (MON_B, (30, 652, 150, 750)),
    'm_beholder': (MON_B, (598, 615, 722, 728)),
    # Boss utilisés par les cinq donjons
    'b_golem': (MON_A, [22]),
    'b_lich': (MON_A, [25, 24]),
    'b_minotaur': (MON_A, [50]),
    'b_kraken': (MON_A, [74]),
    'b_dragon': (MON_A, (440, 770, 812, 1058)),
    # Boss en réserve pour de futurs donjons
    'b_necromancer': (MON_A, [51, 40, 53]),
    'b_dark_knight': (MON_A, [52]),
    'b_demon': (MON_A, (836, 752, 1184, 1058)),
    'b_beholder': (MON_A, [75]),
    'b_fire_elemental': (MON_B, [11]),
    'b_minotaur_armored': (MON_B, [12]),
    'b_ogre': (MON_B, [24]),
    'b_chimera': (MON_B, [25]),
    'b_lava_golem': (MON_B, (25, 760, 385, 1060)),
    'b_cerberus': (MON_B, (425, 770, 785, 1060)),
    'b_kraken_armored': (MON_B, (810, 745, 1175, 1045)),
    'b_black_dragon': (MON_B, (1195, 720, 1610, 1060)),
    # Armes par classe, de commune à légendaire
    'w_warrior_0': (ITEMS, [15]), 'w_warrior_1': (ITEMS, [30]), 'w_warrior_2': (ITEMS, [17]), 'w_warrior_3': (ITEMS, [18]),
    'w_archer_0': (ITEMS, [19], {'key': True}), 'w_archer_1': (ITEMS, [20], {'key': True}), 'w_archer_2': (ITEMS, [34], {'key': True}), 'w_archer_3': (ITEMS, [35], {'key': True}),
    'w_mage_0': (ITEMS, [45]), 'w_mage_1': (ITEMS, [47]), 'w_mage_2': (ITEMS, [48]), 'w_mage_3': (ITEMS, [49]),
    # Bijoux et bottes : deux variantes par rareté
    'amulet_0_a': (ITEMS, [84], {'key': True}), 'amulet_0_b': (ITEMS, [92], {'key': True}), 'amulet_1_a': (ITEMS, [93], {'key': True}), 'amulet_1_b': (ITEMS, [94], {'key': True}),
    'amulet_2_a': (ITEMS, [85], {'key': True}), 'amulet_2_b': (ITEMS, [95], {'key': True}), 'amulet_3_a': (ITEMS, [87], {'key': True}), 'amulet_3_b': (ITEMS, [98], {'key': True}),
    'ring_0_a': (ITEMS, [80], {'key': True}), 'ring_0_b': (ITEMS, [100], {'key': True}), 'ring_1_a': (ITEMS, [81], {'key': True}), 'ring_1_b': (ITEMS, [101], {'key': True}),
    'ring_2_a': (ITEMS, [83], {'key': True}), 'ring_2_b': (ITEMS, [102], {'key': True}), 'ring_3_a': (ITEMS, [82], {'key': True}), 'ring_3_b': (ITEMS, [110], {'key': True}),
    'boots_0': (ITEMS, [117]), 'boots_1': (ITEMS, [122]), 'boots_2': (ITEMS, [118]), 'boots_3': (EXTRA, [187]),
    # Provisions de la boutique
    's_potion': (EXTRA, [107]), 's_scroll': (EXTRA, [105]), 's_bedroll': (CAMP, [16]), 's_ration': (UI, [168]),
    # Interface
    'ui_coin': (UI, [145]), 'ui_heart': (UI, [20]), 'ui_bolt': (UI, [35]),
    'ui_tab_map': (UI, [27], {'key': False}), 'ui_tab_bag': (UI, [26], {'key': False}), 'ui_tab_book': (UI, [47, 48], {'key': False}),
    # Effets
    'fx_fireball': (UI, [97]), 'fx_slash': (UI, [85]), 'fx_heal': (UI, [100]), 'fx_levelup': (UI, [101]),
    # Boutique
    # Icônes de la carte et de l'activité en direct
    'shop_sign': (CAMP, [72]), 'camp_fire_1': (CAMP, [10]),
    # Rencontres
    'chest_closed': (CAMP, [62]), 'chest_open': (CAMP, [63]), 'trap_spikes': (TILES, [145]), 'shrine': (CAMP, [61]),
    # Décors de scène. `px` les ramène à la taille de pixel du héros (voir pixelate) :
    # dans le jeu, un pixel de ces images vaut toujours deux points à l'écran.
    'sc_fire_1': (CAMP, (50, 106, 158, 226), {'notrim': True, 'px': 4}),
    'sc_fire_2': (CAMP, (50, 246, 158, 366), {'notrim': True, 'px': 4}),
    'sc_fire_3': (CAMP, (50, 390, 158, 510), {'notrim': True, 'px': 4}),
    'sc_tree_camp': (CAMP, (345, 85, 835, 500), {'erase': [(345, 388, 428, 500), (760, 378, 835, 500)], 'px': 5.2, 'despeckle': 30}),
    'sc_tent': (CAMP, [11], {'px': 5.8}), 'sc_log': (CAMP, [12], {'px': 7}),
    'sc_rocks': (CAMP, (230, 390, 430, 504), {'px': 6}), 'sc_stump': (CAMP, (762, 380, 980, 506), {'px': 6}),
    'sc_bedroll': (CAMP, [16], {'px': 6}), 'sc_backpack': (CAMP, [17], {'px': 6}), 'sc_chest_big': (CAMP, [18], {'px': 6.5}),
    'sc_sign_dungeon': (CAMP, [49], {'px': 3.5}), 'sc_sign_shop': (CAMP, [50], {'px': 3.5}),
    'sc_tree_purple': (CAMP, [36], {'px': 4.5}), 'sc_tree_blue': (CAMP, [37], {'px': 4.5}), 'sc_tree_green': (CAMP, [38], {'px': 4.5}),
    'sc_bush': (CAMP, [30], {'px': 5}), 'sc_bush_spiky': (CAMP, [31], {'px': 5}), 'sc_plant_glow': (CAMP, [32], {'px': 5}),
    'sc_sprout': (CAMP, [33], {'px': 5}), 'sc_mush_purple': (CAMP, [34], {'px': 5}), 'sc_mush_green': (CAMP, [39], {'px': 5}),
    'sc_fern': (CAMP, [40], {'px': 5}), 'sc_fern_glow': (CAMP, [41], {'px': 5}), 'sc_fern_light': (CAMP, [42], {'px': 5}),
    'sc_mush_blue': (CAMP, [43], {'px': 5}), 'sc_mush_teal': (CAMP, [44], {'px': 5}),
    'sc_stall_red': (CAMP, (28, 1705, 326, 1980), {'px': 4.2}), 'sc_stall_green': (CAMP, (330, 1700, 606, 1936), {'px': 4.2}),
    'sc_stall_purple': (CAMP, (608, 1705, 866, 1980), {'px': 4.2}), 'sc_counter': (CAMP, [76], {'px': 4.6}),
    'sc_sack_1': (CAMP, [65], {'px': 5}), 'sc_sack_2': (CAMP, [66], {'px': 5}),
    'sc_merchant': (UI, [153], {'px': 8.6}),
    'sc_crystal': (CAMP, [58], {'px': 7.5}), 'sc_pillar': (TILES, [40], {'px': 3.2}), 'sc_torch': (THEMES, [69], {'px': 3}),
    'sc_ice_crystal': (THEMES, [55], {'px': 3}), 'sc_icicles': (THEMES, [50], {'px': 3}),
    'sc_lava_fall': (THEMES, [44], {'px': 3}), 'sc_fire_pillar': (THEMES, [71], {'px': 3}),
}

# Sprites dont l'extension a besoin pour l'activité en direct.
WIDGET = ['b_golem', 'b_lich', 'b_minotaur', 'b_kraken', 'b_dragon', 'camp_fire_1', 'shop_sign']

_sheets = {}


def sheet(name):
    if name not in _sheets:
        _sheets[name] = slicer.analyse(name)
    return _sheets[name]


def alpha_rows(s, box):
    x0, y0, x1, y1 = box
    return [s['A'][y * s['w'] + x0:y * s['w'] + x1] for y in range(y0, y1)]


def trim(s, box, level=40):
    """Resserre la boîte sur les pixels visibles."""
    x0, y0, x1, y1 = box
    rows = alpha_rows(s, box)
    solid = bytes(1 if i >= level else 0 for i in range(256))
    ys = [i for i, r in enumerate(rows) if r.translate(solid).count(1)]
    if not ys:
        return box
    left, right = x1 - x0, 0
    for r in rows[ys[0]:ys[-1] + 1]:
        m = r.translate(solid)
        a, b = m.find(1), m.rfind(1)
        if a != -1:
            left, right = min(left, a), max(right, b)
    return (x0 + left, y0 + ys[0], x0 + right + 1, y0 + ys[-1] + 1)


def grow(s, box, limit=70):
    """Étend la boîte tant que son bord touche des pixels visibles :
    les parties sombres d'un sprite, ignorées au repérage, sont ainsi récupérées."""
    w, h, A = s['w'], s['h'], s['A']
    solid = bytes(1 if i >= 110 else 0 for i in range(256))
    x0, y0, x1, y1 = box
    for _ in range(limit):
        changed = False
        if y0 > 0 and A[(y0 - 1) * w + x0:(y0 - 1) * w + x1].translate(solid).count(1):
            y0 -= 1; changed = True
        if y1 < h and A[y1 * w + x0:y1 * w + x1].translate(solid).count(1):
            y1 += 1; changed = True
        if x0 > 0 and any(A[y * w + x0 - 1] >= 110 for y in range(y0, y1)):
            x0 -= 1; changed = True
        if x1 < w and any(A[y * w + x1] >= 110 for y in range(y0, y1)):
            x1 += 1; changed = True
        if not changed:
            break
    return (x0, y0, x1, y1)


def crop(name, sel, opts=None):
    """Renvoie (largeur, hauteur, lignes RGBA) pour un sprite."""
    opts = opts or {}
    s = sheet(name)
    w = s['w']
    if isinstance(sel, tuple):
        box = sel if opts.get('opaque') or opts.get('notrim') else trim(s, sel)
    else:
        boxes = [s['comps'][i] for i in sel]
        box = (min(b[0] for b in boxes), min(b[1] for b in boxes), max(b[2] for b in boxes), max(b[3] for b in boxes))
        if opts.get('grow'):
            box = trim(s, grow(s, box))
        else:
            # Les sprites sont serrés les uns contre les autres : on ajoute juste une marge.
            k = opts.get('pad', 6)
            box = trim(s, (max(box[0] - k, 0), max(box[1] - opts.get('pad_top', k), 0), min(box[2] + k, w), min(box[3] + k, s['h'])))
    x0, y0, x1, y1 = box
    # Détourage par la couleur seule : rend aussi transparent le fond enfermé dans un sprite
    # (trou d'un anneau, espace entre un arc et sa corde). Sur fond noir c'est réservé aux
    # sprites qui le demandent, car leurs contours noirs y passeraient aussi.
    dark_sheet = max(s['bg']) < 8
    keyed = opts.get('key', not dark_sheet) and not opts.get('opaque')
    if keyed:
        lo, hi = slicer.thresholds(s['bg'])
        ramp = bytes(max(0, min(255, (i - lo) * 255 // (hi - lo))) for i in range(256))
        tables = [bytes(abs(i - c) for i in range(256)) for c in s['bg']]
    rows = []
    for y in range(y0, y1):
        a, b = y * w + x0, y * w + x1
        row = bytearray(4 * (x1 - x0))
        row[0::4], row[1::4], row[2::4] = s['R'][a:b], s['G'][a:b], s['B'][a:b]
        if opts.get('opaque'):
            row[3::4] = b'\xff' * (x1 - x0)
        elif keyed:
            row[3::4] = bytes(map(max, row[0::4].translate(tables[0]), row[1::4].translate(tables[1]),
                                  row[2::4].translate(tables[2]))).translate(ramp)
        else:
            row[3::4] = s['A'][a:b]
        for ex0, ey0, ex1, ey1 in opts.get('erase', []):
            if ey0 <= y < ey1:
                lo, hi = max(ex0, x0) - x0, min(ex1, x1) - x0
                if hi > lo:
                    row[4 * lo + 3:4 * hi + 3:4] = bytes(hi - lo)
        rows.append(row)
    return x1 - x0, y1 - y0, rows


def pixelate(w, h, rows, factor):
    """Réduit un sprite d'un facteur donné en gardant un aspect pixel art.

    Les planches ont des sprites dessinés à des finesses très différentes. Affichés
    à la même taille, un marchand très détaillé jure à côté d'un héros aux gros pixels.
    On ramène donc les décors à la taille de pixel du héros : chaque bloc de l'image
    d'origine devient un seul pixel, de la couleur la plus fréquente du bloc, ce qui
    garde des aplats et des contours nets au lieu d'un flou."""
    ow, oh = max(1, round(w / factor)), max(1, round(h / factor))
    out = []
    for oy in range(oh):
        y0, y1 = int(oy * h / oh), max(int((oy + 1) * h / oh), int(oy * h / oh) + 1)
        line = bytearray(4 * ow)
        for ox in range(ow):
            x0, x1 = int(ox * w / ow), max(int((ox + 1) * w / ow), int(ox * w / ow) + 1)
            bins, solid, total = {}, 0, 0
            for y in range(y0, min(y1, h)):
                r = rows[y]
                for x in range(x0, min(x1, w)):
                    total += 1
                    i = 4 * x
                    if r[i + 3] >= 128:
                        solid += 1
                        key = (r[i] >> 4, r[i + 1] >> 4, r[i + 2] >> 4)
                        b = bins.setdefault(key, [0, 0, 0, 0])
                        b[0] += 1; b[1] += r[i]; b[2] += r[i + 1]; b[3] += r[i + 2]
            if total and solid * 2 >= total:
                n, sr, sg, sb = max(bins.values(), key=lambda b: b[0])
                line[4 * ox:4 * ox + 4] = bytes((sr // n, sg // n, sb // n, 255))
        out.append(line)
    return ow, oh, out


def mode_color(rows, y, x0, x1):
    """Couleur la plus fréquente d'un tronçon de ligne."""
    counts = {}
    r = rows[y]
    for x in range(x0, x1):
        c = bytes(r[4 * x:4 * x + 3])
        counts[c] = counts.get(c, 0) + 1
    return max(counts, key=counts.get)


def mirrored(rows):
    out = []
    for r in rows:
        m = bytearray(len(r))
        n = len(r) // 4
        for x in range(n):
            m[4 * x:4 * x + 4] = r[4 * (n - 1 - x):4 * (n - x)]
        out.append(m)
    return out


def side_by_side(*parts):
    return [bytearray(b''.join(p[y] for p in parts)) for y in range(len(parts[0]))]


def window(rows, x0, width):
    return [r[4 * x0:4 * (x0 + width)] for r in rows]


SKY_WIDTH = 250   # en pixels de décor : plus large que l'écran le plus large


def smooth_bands(rows, count):
    """Nettoie les `count` premières lignes d'un ciel : là où deux bandes de couleur se touchent,
    la réduction laisse une ligne en dents de scie. Chaque pixel proche de la bande du dessus
    ou du dessous prend la couleur dominante de sa ligne. Étoiles et halo de lune sont épargnés."""
    width = len(rows[0]) // 4
    modes = [mode_color(rows, y, 0, width) for y in range(count + 1)]
    for y in range(1, count):
        for x in range(width):
            c = rows[y][4 * x:4 * x + 3]
            if any(sum(abs(i - j) for i, j in zip(c, modes[n])) < 36 for n in (y - 1, y, y + 1)):
                rows[y][4 * x:4 * x + 3] = modes[y]


def sky_night():
    """Ciel de nuit du camp : le panneau bleu à la lune, dont on retire une bande de ciel vide
    pour que la lune et les montagnes tiennent ensemble à l'écran. Le panneau est trop étroit
    pour la scène : on l'entoure de copies en miroir dont la lune a été effacée. On le coupe
    juste avant un sommet, pour que le miroir dessine un pic et non deux pics jumeaux."""
    x0, y0, x1, y1 = 10, 530, 368, 998
    w, h, rows = crop(TERRAIN, (x0, y0, x1, y1), {'opaque': True})
    rows = rows[:700 - y0] + rows[792 - y0:]
    w, h, moon = pixelate(w, len(rows), rows, 4)
    w = 84
    moon = window(moon, 0, w)
    above = int((700 - y0) / 4)
    plain = [bytearray(r) for r in moon]
    cx, cy, radius = (226 - x0) / 4, (628 - y0) / 4, 24
    for y in range(above):
        base = mode_color(moon, y, 0, 10)
        for x in range(w):
            r, g, b = moon[y][4 * x:4 * x + 3]
            near = (x - cx) ** 2 + (y - cy) ** 2 < radius ** 2
            star = r + g + b > sum(base) + 90
            if near or not star:
                plain[y][4 * x:4 * x + 3] = base
    wide = side_by_side(mirrored(plain), moon, mirrored(plain), plain)
    smooth_bands(wide, above + 3)
    return SKY_WIDTH, h, window(wide, 58, SKY_WIDTH)


def sky_dusk():
    """Ciel du crépuscule : le panorama violet, prolongé vers le haut par une bande étoilée."""
    w, h, pano = pixelate(*crop(TERRAIN, (384, 760, 972, 998), {'opaque': True}), 4)
    # Sur la planche, le coin haut gauche du panorama est recouvert par d'autres vignettes.
    for y in range(18):
        base = mode_color(pano, y, 45, w)
        for x in range(42):
            pano[y][4 * x:4 * x + 3] = base
    sw, sh, strip = pixelate(*crop(TERRAIN, (452, 530, 524, 772), {'opaque': True}), 4)
    top = mode_color(pano, 0, 0, w)
    # La bande étoilée s'arrête là où sa couleur rejoint celle du haut du panorama.
    def gap(y):
        return sum(abs(a - b) for a, b in zip(mode_color(strip, y, 0, sw), top))
    stop = min(range(sh // 2, sh), key=gap)
    wide = side_by_side(mirrored(pano), pano)
    total = len(wide[0]) // 4
    upper = []
    for y in range(stop):
        base = mode_color(strip, y, 0, sw)
        line = bytearray(bytes(base) + b'\xff') * total
        for x in range(total):
            # Les étoiles de la bande, répétées en miroir, décalées d'une rangée sur deux.
            tile, sx = divmod(x, sw)
            sx = sw - 1 - sx if tile % 2 else sx
            sy = (y + 17 * (tile % 3)) % stop
            r, g, b = strip[sy][4 * sx:4 * sx + 3]
            if r + g + b > sum(mode_color(strip, sy, 0, sw)) + 110:
                line[4 * x:4 * x + 3] = bytes((r, g, b))
        upper.append(line)
    rows = upper + wide
    smooth_bands(rows, stop + 12)
    return SKY_WIDTH, len(rows), window(rows, total - SKY_WIDTH, SKY_WIDTH)


def rolled(rows, shift, flip=False):
    """Décale des lignes horizontalement, en boucle."""
    out = []
    for r in rows:
        n = len(r) // 4
        k = 4 * (shift % n)
        line = bytearray(r[k:] + r[:k])
        out.append(mirrored([line])[0] if flip else line)
    return out


def ground_path():
    """Chemin de terre bordé d'herbe, au pixel du héros. La bande de la planche est trop mince
    pour y poser une tente ou un étal : on épaissit l'herbe du fond et un peu celle de devant,
    en répétant ses propres rangées décalées, pour que les décors aient un sol sous eux."""
    w, h, rows = pixelate(*crop(TERRAIN, (10, 204, 472, 276)), 3)
    for y, r in enumerate(rows):   # restes du fond noir de la planche, surtout entre les brins d'herbe du haut
        limit = 170 if y < 3 or y >= h - 2 else 60
        for x in range(w):
            if sum(r[4 * x:4 * x + 3]) < limit:
                r[4 * x:4 * x + 4] = bytes(4)
    for x in range(w):   # pas de trou en bas : on prolonge l'herbe
        for y in range(h - 2, h):
            if not rows[y][4 * x + 3]:
                rows[y][4 * x:4 * x + 4] = rows[y - 1][4 * x:4 * x + 4]
    def lawn(block):
        """Rangées d'herbe sans leurs pixels sombres, qui dessineraient des tirets une fois répétées."""
        out = []
        for r in block:
            base = mode_color(block, block.index(r), 0, w)
            line = bytearray(r)
            for x in range(w):
                if sum(line[4 * x:4 * x + 3]) < sum(base) - 60 or not line[4 * x + 3]:
                    line[4 * x:4 * x + 4] = bytes(base) + b'\xff'
            out.append(line)
        return out
    back, front = lawn(rows[3:6]), lawn(rows[h - 4:h - 2])
    # La rangée 2, sous la lisière, est trouée par le détourage : on ne la reprend pas.
    out = rows[:2] + rolled(back, 41) + rolled(back, 97, flip=True) + rolled(back, 19) + rolled(back, 70)[:1] + rows[3:h - 2]
    out += rolled(front, 53, flip=True) + rows[h - 2:]
    for y in range(2, len(out)):   # sous la lisière, plus aucun trou : on verrait le ciel au travers
        base = bytes(mode_color(out, y, 0, w)) + b'\xff'
        for x in range(w):
            if not out[y][4 * x + 3]:
                out[y][4 * x:4 * x + 4] = base
    return w, len(out), out


def wall_bricks():
    """Mur de donjon au pixel du héros. Il devient trop bas pour la scène : on empile au-dessus
    des rangées de briques reprises du haut de l'image, calées sur la hauteur d'une assise."""
    w, h, pix = pixelate(*crop(TERRAIN, (756, 1082, 1022, 1220), {'opaque': True}), 2.5)
    upper = 34   # au-dessus de la corniche
    def mismatch(k):
        pairs = [(y, y + k) for y in range(upper - k)]
        return sum(abs(a - b) for y0, y1 in pairs for a, b in zip(pix[y0], pix[y1])) / len(pairs)
    period = min(range(8, 18), key=mismatch)
    band = [bytearray(r) for r in pix[:period * (upper // period)]]
    rows = [bytearray(r) for r in band] + band + pix
    return w, len(rows), rows


def cave_back():
    """Paroi de grotte au pixel du héros, prolongée par l'obscurité du plafond."""
    w, h, pix = pixelate(*crop(TERRAIN, (10, 1084, 370, 1272), {'opaque': True}), 2.2)
    dark = bytes(mode_color(pix, 0, 0, w)) + b'\xff'
    for r in pix:   # le bas de l'image est déchiré sur la planche : le noir devient de la roche sombre
        for x in range(w):
            if sum(r[4 * x:4 * x + 3]) < 45:
                r[4 * x:4 * x + 4] = dark
    return w, h + 16, [bytearray(dark * w) for _ in range(16)] + pix


def floor_stones():
    return pixelate(*crop(TILES, (52, 120, 246, 205), {'opaque': True}), 85 / 32)


BACKGROUNDS = {'bg_sky_night': sky_night, 'bg_sky_dusk': sky_dusk, 'bg_ground': ground_path,
               'bg_wall': wall_bricks, 'bg_cave': cave_back, 'bg_floor': floor_stones}


def despeckle(w, h, rows, smallest):
    """Efface les petits îlots isolés. Les lucioles dessinées autour du grand arbre deviennent
    des carrés sombres une fois réduites : le jeu les remplace par de vraies lucioles animées."""
    seen = [[False] * w for _ in range(h)]
    for y in range(h):
        for x in range(w):
            if seen[y][x] or not rows[y][4 * x + 3]:
                continue
            seen[y][x] = True
            stack, island = [(x, y)], []
            while stack:
                cx, cy = stack.pop()
                island.append((cx, cy))
                for nx, ny in ((cx + 1, cy), (cx - 1, cy), (cx, cy + 1), (cx, cy - 1)):
                    if 0 <= nx < w and 0 <= ny < h and not seen[ny][nx] and rows[ny][4 * nx + 3]:
                        seen[ny][nx] = True
                        stack.append((nx, ny))
            if len(island) < smallest:
                for cx, cy in island:
                    rows[cy][4 * cx:4 * cx + 4] = bytes(4)
    return w, h, rows


def hero_frames(hero):
    """Toutes les poses d'un héros sur une même toile, pieds centrés en bas,
    pour que le personnage ne saute pas d'une image à l'autre."""
    frames = {}
    for anim, indices in HERO_FRAMES[hero].items():
        for n, index in enumerate(indices, 1):
            fw, fh, rows = crop(HEROES, index if isinstance(index, tuple) else [index], {'pad': 4, 'pad_top': 1})   # marge réduite en haut : l'image du dessus est toute proche
            feet = rows[int(fh * 0.6):]   # les jambes : un pied seul tout en bas fausserait le centre
            xs = [x for r in feet for x in range(fw) if r[4 * x + 3] >= 128]
            cx = sum(xs) // len(xs) if xs else fw // 2
            frames[f'hero_{hero}_{anim}_{n}'] = (fw, fh, rows, cx)
    half = max(max(cx, fw - cx) for fw, fh, rows, cx in frames.values()) + 2
    height = max(fh for fw, fh, rows, cx in frames.values()) + 2
    out = {}
    fw, fh, rows, cx = frames[f'hero_{hero}_walk_1']
    out[f'hero_{hero}_portrait'] = (fw, fh, rows)   # cadrage serré, sans la toile commune
    for name, (fw, fh, rows, cx) in frames.items():
        left = half - cx
        canvas = [bytearray(8 * half) for _ in range(height)]
        for i, r in enumerate(rows):
            canvas[height - fh + i][4 * left:4 * (left + fw)] = r
        out[name] = (2 * half, height, canvas)
    return out


def write_imageset(assets, name, w, h, rows):
    folder = os.path.join(assets, f'{name}.imageset')
    os.makedirs(folder, exist_ok=True)
    slicer.write_png(os.path.join(folder, f'{name}.png'), w, h, rows)
    contents = {
        'images': [{'idiom': 'universal', 'filename': f'{name}.png', 'scale': '1x'},
                   {'idiom': 'universal', 'scale': '2x'}, {'idiom': 'universal', 'scale': '3x'}],
        'info': {'author': 'xcode', 'version': 1},
    }
    json.dump(contents, open(os.path.join(folder, 'Contents.json'), 'w'), indent=2)


def contact_sheet(path, sprites, cell=132, cols=12):
    """Planche de contrôle : chaque sprite exporté sur un damier, réduit pour tenir dans sa case."""
    names = list(sprites)
    lines = (len(names) + cols - 1) // cols
    W, H = cols * cell, lines * cell
    img = [bytearray(3 * W) for _ in range(H)]
    for y in range(H):
        for x in range(0, W, 12):
            c = b'\x6a\x72\x80' if ((x // 12) + (y // 12)) % 2 else b'\x58\x60\x6e'
            img[y][3 * x:3 * (x + 12)] = c * 12
    for i, name in enumerate(names):
        w, h, rows = sprites[name]
        k = max(1, -(-max(w, h) // (cell - 8)))
        ox, oy = (i % cols) * cell + 4, (i // cols) * cell + 4
        for y in range(0, h, k):
            r, dst = rows[y], img[oy + y // k]
            for x in range(0, w, k):
                a = r[4 * x + 3]
                if a:
                    j = 3 * (ox + x // k)
                    for c in range(3):
                        dst[j + c] = (r[4 * x + c] * a + dst[j + c] * (255 - a)) // 255
    slicer.write_png(path, W, H, img, alpha=False)


def main():
    assets, widgets = sys.argv[1], sys.argv[2]
    sprites = {}
    for hero in HERO_FRAMES:
        sprites.update(hero_frames(hero))
    for name, entry in SPRITES.items():
        opts = entry[2] if len(entry) > 2 else {}
        w, h, rows = crop(entry[0], entry[1], opts)
        if 'px' in opts:
            w, h, rows = pixelate(w, h, rows, opts['px'])
        if 'despeckle' in opts:
            w, h, rows = despeckle(w, h, rows, opts['despeckle'])
        sprites[name] = (w, h, rows)
    for name, build in BACKGROUNDS.items():
        sprites[name] = build()
    for name, (w, h, rows) in sprites.items():
        write_imageset(assets, name, w, h, rows)
    for name in WIDGET + [f'hero_{hero}_portrait' for hero in HERO_FRAMES]:
        w, h, rows = sprites[name]
        write_imageset(widgets, name, w, h, rows)
    if len(sys.argv) > 3:
        contact_sheet(sys.argv[3], sprites)
    print(len(sprites), 'sprites exportés')
    for name in ('hero_warrior_walk_1', 'hero_archer_walk_1', 'hero_mage_walk_1', 'b_dragon', 'b_golem', 'm_rat', *BACKGROUNDS):
        print(' ', name, sprites[name][0], 'x', sprites[name][1])


if __name__ == '__main__':
    main()
