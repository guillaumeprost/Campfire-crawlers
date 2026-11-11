#!/usr/bin/env python3
"""Génère les images du jeu à partir de sprites.txt.

Usage : python3 build_art.py <Assets.xcassets du jeu> [aperçu.png] [--widgets=<Assets.xcassets de l'extension>]
L'extension ne reçoit que les sprites, sans les décors ni l'icône.
Aucune dépendance : le PNG est écrit à la main.
"""
import json, math, os, random, struct, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))

def rgb(h):
    h = h.lstrip('#')
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), 255)

CLEAR = (0, 0, 0, 0)
PALETTE = {
    '.': CLEAR,
    'k': rgb('1a1c2c'), 'p': rgb('5d275d'), 'v': rgb('a06cd5'),
    'r': rgb('b13e53'), 'R': rgb('7a1f3d'), 'o': rgb('ef7d57'),
    'y': rgb('ffcd75'), 'Y': rgb('e8a020'), 'l': rgb('a7f070'),
    'e': rgb('38b764'), 't': rgb('257179'), 'n': rgb('29366f'),
    'b': rgb('3b5dc9'), 'a': rgb('41a6f6'), 'c': rgb('73eff7'),
    'w': rgb('f4f4f4'), 'g': rgb('94b0c2'), 'G': rgb('566c86'),
    'd': rgb('333c57'), 's': rgb('f0c0a0'), 'S': rgb('e58fa0'),
    'm': rgb('8a5a3c'), 'M': rgb('5a3826'), 'T': rgb('d4a56a'),
}

# ---------------------------------------------------------------- PNG

def write_png(path, pixels, alpha=True):
    h, w = len(pixels), len(pixels[0])
    raw = bytearray()
    for row in pixels:
        raw.append(0)
        for px in row:
            raw.extend(px if alpha else px[:3])
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6 if alpha else 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(bytes(raw), 9))
           + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)

def upscale(pixels, k):
    out = []
    for row in pixels:
        wide = [px for px in row for _ in range(k)]
        out.extend([list(wide) for _ in range(k)])
    return out

# ------------------------------------------------------------ sprites

def load_sprites(path):
    sprites, name, width, mirror, rows = {}, None, 0, False, []
    def flush():
        if name is None:
            return
        half = width // 2 if mirror else width
        for i, row in enumerate(rows):
            if len(row) != half:
                sys.exit(f"{name}: ligne {i} de largeur {len(row)}, attendu {half} : {row!r}")
            for ch in row:
                if ch not in PALETTE:
                    sys.exit(f"{name}: caractère inconnu {ch!r} ligne {i}")
        full = [row + row[::-1] if mirror else row for row in rows]
        sprites[name] = [[PALETTE[ch] for ch in row] for row in full]
    for line in open(path, encoding='utf-8'):
        line = line.rstrip('\n')
        if line.startswith('#') or not line.strip():
            continue
        if line.startswith('@'):
            flush()
            parts = line[1:].split()
            name, width, mirror, rows = parts[0], int(parts[1]), 'mirror' in parts[2:], []
        else:
            rows.append(line)
    flush()
    return sprites

# ------------------------------------------------------------- décors

BG_W, BG_H, GROUND = 180, 120, 32   # sol : les 32 lignes du bas
HORIZON = BG_H - GROUND

def canvas(color=CLEAR):
    return [[color for _ in range(BG_W)] for _ in range(BG_H)]

def put(img, x, y, color):
    """Écrit un pixel ; x boucle pour que le décor se raccorde bord à bord."""
    if 0 <= y < BG_H:
        img[y][x % BG_W] = color

def sky(img, bands):
    """Bandes de couleur avec une ligne tramée à chaque transition."""
    step = HORIZON / len(bands)
    for y in range(HORIZON):
        i = min(int(y / step), len(bands) - 1)
        edge = (y + 1) % int(step) == 0 and i + 1 < len(bands)
        for x in range(BG_W):
            img[y][x] = bands[i + 1] if edge and (x + y) % 2 == 0 else bands[i]

def disc(img, cx, cy, r, color):
    for y in range(cy - r, cy + r + 1):
        for x in range(cx - r, cx + r + 1):
            if (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 1:
                put(img, x, y, color)

def ridge(img, color, base, amp, cycles, phase, jag=0, rng=None):
    """Silhouette continue jusqu'à l'horizon ; renvoie les hauteurs.
    Un nombre entier de cycles garantit le raccord entre les deux bords."""
    tops = []
    for x in range(BG_W):
        a = 2 * math.pi * x / BG_W
        h = base + amp * math.sin(cycles * a + phase) + 0.5 * amp * math.sin((2 * cycles + 1) * a + phase * 1.7)
        if jag and rng:
            h += rng.randint(-jag, jag)
        top = int(HORIZON - h)
        tops.append(top)
        for y in range(max(top, 0), HORIZON):
            img[y][x] = color
    return tops

def triangle(img, cx, top, height, half, color):
    for i in range(height):
        w = int(half * (i + 1) / height)
        for x in range(cx - w, cx + w + 1):
            put(img, x, top + i, color)

def pine(img, cx, base, height, color):
    tiers = 3
    for t in range(tiers):
        th = height // 2
        top = base - height + t * (height // 4)
        triangle(img, cx, top, th, 2 + t * 2 + height // 8, color)
    for y in range(base - 2, base):
        put(img, cx, y, color)

def ground(img, base, top, speck_dark, speck_light, rng):
    for y in range(HORIZON, BG_H):
        for x in range(BG_W):
            img[y][x] = base
    for x in range(BG_W):
        img[HORIZON][x] = top
        if (x * 7 + 3) % 5 < 2:
            img[HORIZON + 1][x] = top
    for _ in range(140):
        x, y = rng.randrange(BG_W), rng.randrange(HORIZON + 3, BG_H)
        c = speck_dark if rng.random() < 0.6 else speck_light
        put(img, x, y, c)
        put(img, x + 1, y, c)

def bg_forest():
    rng = random.Random(1)
    img = canvas()
    sky(img, [rgb('14162a'), rgb('1a2040'), rgb('222c5a'), rgb('2c3c78')])
    for _ in range(45):
        put(img, rng.randrange(BG_W), rng.randrange(HORIZON - 30), rgb('94b0c2') if rng.random() < 0.6 else rgb('f4f4f4'))
    disc(img, 34, 24, 8, rgb('f4f4f4'))
    disc(img, 38, 21, 7, rgb('14162a'))
    ridge(img, rgb('1b3550'), 22, 6, 1, 0.5)
    for x in range(4, BG_W, 9):
        pine(img, x + rng.randint(-2, 2), HORIZON, rng.randint(16, 26), rgb('16324a'))
    for x in range(0, BG_W, 13):
        pine(img, x + rng.randint(-3, 3), HORIZON, rng.randint(22, 36), rgb('0f2434'))
    ground(img, rgb('245238'), rgb('38b764'), rgb('1d4530'), rgb('2f6a46'), rng)
    return img

def bg_desert():
    rng = random.Random(2)
    img = canvas()
    sky(img, [rgb('c9523a'), rgb('e0704a'), rgb('f09a60'), rgb('ffcd75')])
    disc(img, 36, 30, 10, rgb('fff1c1'))
    ridge(img, rgb('c8804a'), 20, 7, 1, 1.0)
    ridge(img, rgb('b06a3a'), 9, 5, 2, 2.4)
    for cx in (22, 76, 121, 163):
        h = rng.randint(10, 16)
        for y in range(HORIZON - h, HORIZON):
            for dx in (-1, 0, 1):
                put(img, cx + dx, y, rgb('3f6b3a'))
        for dx, dy in ((-4, 5), (4, 3)):
            for y in range(HORIZON - h + dy, HORIZON - h + dy + 5):
                put(img, cx + dx, y, rgb('3f6b3a'))
            for x in range(min(cx, cx + dx), max(cx, cx + dx) + 1):
                put(img, x, HORIZON - h + dy + 5, rgb('3f6b3a'))
    ground(img, rgb('dba85a'), rgb('ffd98a'), rgb('c08d44'), rgb('ecc078'), rng)
    return img

def bg_cave():
    rng = random.Random(3)
    img = canvas()
    sky(img, [rgb('15121f'), rgb('1e1830'), rgb('2a2142'), rgb('362b52')])
    for cx in range(3, BG_W, 11):
        triangle_down(img, cx + rng.randint(-3, 3), 0, rng.randint(10, 30), rng.randint(3, 6), rgb('100d18'))
    for cx in range(8, BG_W, 17):
        triangle(img, cx + rng.randint(-4, 4), HORIZON - rng.randint(10, 24), 26, rng.randint(4, 8), rgb('1c1630'))
    for cx in (15, 58, 97, 139, 170):
        c = rgb('73eff7') if rng.random() < 0.5 else rgb('a06cd5')
        h = rng.randint(5, 9)
        triangle(img, cx, HORIZON - h, h, 2, c)
        put(img, cx, HORIZON - h - 1, rgb('f4f4f4'))
    ground(img, rgb('332b44'), rgb('4e4468'), rgb('28213a'), rgb('3e3554'), rng)
    return img

def triangle_down(img, cx, top, height, half, color):
    for i in range(height):
        w = int(half * (height - i) / height)
        for x in range(cx - w, cx + w + 1):
            put(img, x, top + i, color)

def bg_ice():
    rng = random.Random(4)
    img = canvas()
    sky(img, [rgb('4a7fc8'), rgb('6a9fe0'), rgb('95c2f0'), rgb('c8e4fa')])
    tops = ridge(img, rgb('7fa8d8'), 34, 12, 1, 0.3, jag=1, rng=rng)
    for x, top in enumerate(tops):
        for y in range(top, min(top + 5 + (x % 3), HORIZON)):
            img[y][x] = rgb('f4f4f4')
    ridge(img, rgb('b4d2ee'), 12, 5, 2, 1.9)
    for _ in range(60):
        put(img, rng.randrange(BG_W), rng.randrange(HORIZON), rgb('f4f4f4'))
    ground(img, rgb('e4f0fa'), rgb('ffffff'), rgb('c4dcf0'), rgb('f4faff'), rng)
    return img

def bg_volcano():
    rng = random.Random(5)
    img = canvas()
    sky(img, [rgb('140808'), rgb('2c0c0c'), rgb('561410'), rgb('8c2a16')])
    ridge(img, rgb('2a1010'), 16, 5, 1, 0.8, jag=1, rng=rng)
    cx, top, base_half = 48, HORIZON - 62, 44
    for i in range(62):
        w = 6 + int((base_half - 6) * i / 62)
        for x in range(cx - w, cx + w + 1):
            put(img, x, top + i, rgb('1c0c0c'))
    for x in range(cx - 5, cx + 6):
        put(img, x, top, rgb('ffcd75'))
        put(img, x, top + 1, rgb('ef7d57'))
    for i in range(2, 40):
        x = cx + int(3 * math.sin(i * 0.35))
        put(img, x, top + i, rgb('ef7d57'))
        put(img, x + 1, top + i, rgb('b13e53'))
    for _ in range(40):
        put(img, rng.randrange(BG_W), rng.randrange(HORIZON), rgb('ef7d57') if rng.random() < 0.7 else rgb('ffcd75'))
    ground(img, rgb('2a1a18'), rgb('4e2c24'), rgb('1e1210'), rgb('3a2420'), rng)
    for _ in range(9):
        x, y = rng.randrange(BG_W - 12), rng.randrange(HORIZON + 5, BG_H - 2)
        for i in range(rng.randint(5, 11)):
            put(img, x + i, y + (i // 3) % 2, rgb('ef7d57'))
    return img

def bg_meadow():
    """Pré de jour, avec un chemin de terre : sert aux trajets et à la boutique."""
    rng = random.Random(6)
    img = canvas()
    sky(img, [rgb('4f9ae0'), rgb('6fb2ea'), rgb('97caf3'), rgb('c4e3fa')])
    disc(img, 150, 20, 8, rgb('fff1c1'))
    for cx, cy in ((30, 18), (84, 30), (128, 12)):
        for dx, r in ((-7, 4), (0, 6), (8, 4)):
            disc(img, cx + dx, cy, r, rgb('f4f4f4'))
    ridge(img, rgb('6fb87a'), 20, 7, 1, 0.9)
    ridge(img, rgb('4f9f5c'), 9, 4, 2, 2.2)
    for cx in (14, 52, 101, 139, 171):
        h = rng.randint(12, 18)
        for y in range(HORIZON - 5, HORIZON):
            put(img, cx, y, rgb('5a3826'))
        disc(img, cx, HORIZON - 5 - h // 2, h // 2, rgb('2f7d46'))
        disc(img, cx - 2, HORIZON - 7 - h // 2, h // 3, rgb('3f9a58'))
    ground(img, rgb('57a84f'), rgb('8ad36a'), rgb('4a9645'), rgb('6fbf5c'), rng)
    for y in range(HORIZON + 7, HORIZON + 18):
        for x in range(BG_W):
            edge = y in (HORIZON + 7, HORIZON + 17)
            img[y][x] = rgb('b08a52') if edge and (x // 3) % 2 else rgb('cfa468')
    for _ in range(50):
        x, y = rng.randrange(BG_W), rng.randrange(HORIZON + 8, HORIZON + 17)
        put(img, x, y, rgb('b08a52'))
        put(img, x + 1, y, rgb('b08a52'))
    return img

BACKGROUNDS = {
    'bg_meadow': bg_meadow,
    'bg_forest': bg_forest, 'bg_desert': bg_desert, 'bg_cave': bg_cave,
    'bg_ice': bg_ice, 'bg_volcano': bg_volcano,
}

# ------------------------------------------------------------- export

def write_imageset(assets, name, pixels):
    folder = os.path.join(assets, f'{name}.imageset')
    os.makedirs(folder, exist_ok=True)
    write_png(os.path.join(folder, f'{name}.png'), pixels)
    contents = {
        'images': [
            {'idiom': 'universal', 'filename': f'{name}.png', 'scale': '1x'},
            {'idiom': 'universal', 'scale': '2x'},
            {'idiom': 'universal', 'scale': '3x'},
        ],
        'info': {'author': 'xcode', 'version': 1},
    }
    json.dump(contents, open(os.path.join(folder, 'Contents.json'), 'w'), indent=2)

def write_app_icon(assets, hero):
    size, k = 1024, 44
    top, bottom = rgb('3b2a6e'), rgb('14162a')
    img = []
    for y in range(size):
        t = y / (size - 1)
        img.append([tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3)) + (255,)] * size)
    big = upscale(hero, k)
    ox, oy = (size - len(big[0])) // 2, (size - len(big)) // 2
    for y, row in enumerate(big):
        for x, px in enumerate(row):
            if px[3]:
                img[oy + y][ox + x] = px
    folder = os.path.join(assets, 'AppIcon.appiconset')
    os.makedirs(folder, exist_ok=True)
    write_png(os.path.join(folder, 'icon.png'), img, alpha=False)
    contents = {
        'images': [{'idiom': 'universal', 'platform': 'ios', 'size': '1024x1024', 'filename': 'icon.png'}],
        'info': {'author': 'xcode', 'version': 1},
    }
    json.dump(contents, open(os.path.join(folder, 'Contents.json'), 'w'), indent=2)

def write_preview(path, sprites, backgrounds):
    k, cell, cols, pad = 5, 32 * 5 + 10, 7, 6
    names = list(sprites)
    rows = math.ceil(len(names) / cols)
    bg_k = 3
    width = max(cols * cell, 2 * (BG_W * bg_k + pad) + pad)
    height = rows * cell + 3 * (BG_H * bg_k + pad) + pad
    img = [[rgb('4a5568') if ((x // 12) + (y // 12)) % 2 else rgb('3d4656') for x in range(width)] for y in range(height)]
    for i, name in enumerate(names):
        big = upscale(sprites[name], k)
        ox, oy = (i % cols) * cell + pad, (i // cols) * cell + pad
        for y, row in enumerate(big):
            for x, px in enumerate(row):
                if px[3] and oy + y < height and ox + x < width:
                    img[oy + y][ox + x] = px
    for i, (name, pixels) in enumerate(backgrounds.items()):
        big = upscale(pixels, bg_k)
        ox = pad + (i % 2) * (BG_W * bg_k + pad)
        oy = rows * cell + pad + (i // 2) * (BG_H * bg_k + pad)
        for y, row in enumerate(big):
            for x, px in enumerate(row):
                img[oy + y][ox + x] = px
    write_png(path, img, alpha=False)

def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    widgets = next((a.split('=', 1)[1] for a in sys.argv[1:] if a.startswith('--widgets=')), None)
    assets = args[0]
    sprites = load_sprites(os.path.join(HERE, 'sprites.txt'))
    backgrounds = {name: make() for name, make in BACKGROUNDS.items()}
    os.makedirs(assets, exist_ok=True)
    json.dump({'info': {'author': 'xcode', 'version': 1}}, open(os.path.join(assets, 'Contents.json'), 'w'), indent=2)
    for name, pixels in {**sprites, **backgrounds}.items():
        write_imageset(assets, name, pixels)
    write_app_icon(assets, sprites['hero'])
    if widgets:
        os.makedirs(widgets, exist_ok=True)
        json.dump({'info': {'author': 'xcode', 'version': 1}}, open(os.path.join(widgets, 'Contents.json'), 'w'), indent=2)
        for name, pixels in sprites.items():
            write_imageset(widgets, name, pixels)
    if len(args) > 1:
        write_preview(args[1], sprites, backgrounds)
    print(f"{len(sprites)} sprites, {len(backgrounds)} décors")

if __name__ == '__main__':
    main()
