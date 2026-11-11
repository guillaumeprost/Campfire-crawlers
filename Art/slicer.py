#!/usr/bin/env python3
"""Découpe les planches de sprites (JPEG à fond sombre) en images détourées.

Sans dépendance : `sips` convertit le JPEG en BMP, le reste est fait à la main.
  analyse(planche)  -> retire le fond, repère chaque sprite, met le résultat en cache
  annote(planche)   -> image de contrôle avec le numéro de chaque sprite
"""
import os, pickle, struct, subprocess, sys, zlib

HERE = os.path.dirname(os.path.abspath(__file__))
SHEETS = os.path.join(HERE, 'sheets')
CACHE = os.environ.get('SLICER_CACHE', '/tmp/slicer-cache')
VERSION = 3              # à augmenter quand le détourage change : invalide le cache


STRONG = 50              # écart au fond à partir duquel un pixel compte pour repérer un sprite
MERGE_GAP = 10           # un petit fragment à moins de 10 px d'un sprite lui est rattaché


def thresholds(bg):
    """Écart au fond : en dessous du premier seuil transparent, au-dessus du second opaque.
    Sur fond noir on ne peut pas distinguer un contour noir, donc on mord un peu plus.
    Sur fond bleu nuit ou gris, les contours noirs s'en détachent : seuils serrés."""
    return (10, 30) if max(bg) < 8 else (8, 18)


CELL = 4                 # grille grossière pour regrouper les morceaux d'un sprite


def write_png(path, w, h, rows, alpha=True):
    """rows : liste d'octets, une ligne par élément (RGBA ou RGB)."""
    raw = b''.join(b'\x00' + bytes(r) for r in rows)
    def chunk(tag, data):
        return struct.pack('>I', len(data)) + tag + data + struct.pack('>I', zlib.crc32(tag + data) & 0xffffffff)
    png = (b'\x89PNG\r\n\x1a\n'
           + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 6 if alpha else 2, 0, 0, 0))
           + chunk(b'IDAT', zlib.compress(raw, 6)) + chunk(b'IEND', b''))
    with open(path, 'wb') as f:
        f.write(png)


def load_rgb(jpg):
    os.makedirs(CACHE, exist_ok=True)
    bmp = os.path.join(CACHE, os.path.basename(jpg) + '.bmp')
    if not os.path.exists(bmp):
        subprocess.run(['sips', '-s', 'format', 'bmp', jpg, '--out', bmp], check=True, capture_output=True)
    data = open(bmp, 'rb').read()
    off = int.from_bytes(data[10:14], 'little')
    w = int.from_bytes(data[18:22], 'little', signed=True)
    h = int.from_bytes(data[22:26], 'little', signed=True)
    bpp = int.from_bytes(data[28:30], 'little') // 8
    bottom_up, h = h > 0, abs(h)
    stride = (w * bpp + 3) // 4 * 4
    R, G, B = bytearray(w * h), bytearray(w * h), bytearray(w * h)
    for y in range(h):
        src = off + (h - 1 - y if bottom_up else y) * stride
        row = data[src:src + w * bpp]
        B[y * w:(y + 1) * w] = row[0::bpp]
        G[y * w:(y + 1) * w] = row[1::bpp]
        R[y * w:(y + 1) * w] = row[2::bpp]
    return w, h, R, G, B


def analyse(name):
    """Renvoie un dict : w, h, R, G, B, A (alpha), comps (boîtes des sprites, ordre de lecture)."""
    cache = os.path.join(CACHE, f'{name}.v{VERSION}.pickle')
    if os.path.exists(cache):
        return pickle.load(open(cache, 'rb'))
    jpg = os.path.join(SHEETS, name + '.jpg')
    w, h, R, G, B = load_rgb(jpg)
    n = w * h

    # Couleur du fond : moyenne des quatre coins.
    corner = [y * w + x for y in list(range(6)) + list(range(h - 6, h)) for x in list(range(6)) + list(range(w - 6, w))]
    bg = [sum(C[i] for i in corner) // len(corner) for C in (R, G, B)]

    T_LO, T_HI = thresholds(bg)

    # Écart de chaque pixel à la couleur du fond.
    D = bytearray(map(max, R.translate(bytes(abs(i - bg[0]) for i in range(256))),
                      G.translate(bytes(abs(i - bg[1]) for i in range(256))),
                      B.translate(bytes(abs(i - bg[2]) for i in range(256)))))

    # Remplissage depuis les bords : seul le fond relié à l'extérieur est retiré,
    # les zones sombres à l'intérieur d'un sprite restent opaques.
    cand = bytearray(D.translate(bytes(1 if i < T_HI else 0 for i in range(256))))
    visited = bytearray(n)
    stack = []
    for x in range(w):
        stack.append(x); stack.append((h - 1) * w + x)
    for y in range(h):
        stack.append(y * w); stack.append(y * w + w - 1)
    while stack:
        i = stack.pop()
        if not cand[i]:
            continue
        y = i // w
        start, end = y * w, y * w + w
        left = cand.rfind(0, start, i) + 1
        if left == 0:
            left = start
        right = cand.find(0, i, end)
        if right == -1:
            right = end
        span = right - left
        cand[left:right] = bytes(span)
        visited[left:right] = b'\x01' * span
        for a in (left - w, left + w):
            if a < 0 or a >= n:
                continue
            b = a + span
            p = cand.find(1, a, b)
            while p != -1:
                stack.append(p)
                q = cand.find(0, p, b)
                if q == -1:
                    break
                p = cand.find(1, q, b)

    soft = D.translate(bytes(max(0, min(255, (i - T_LO) * 255 // (T_HI - T_LO))) for i in range(256)))
    mask = int.from_bytes(visited.translate(bytes([0, 255] + [0] * 254)), 'big')
    full = (1 << (8 * n)) - 1
    A = bytearray(((int.from_bytes(soft, 'big') & mask) | (mask ^ full)).to_bytes(n, 'big'))

    # Repérage des sprites sur une grille grossière. On ne retient ici que ce qui
    # tranche nettement sur le fond, pour que deux sprites voisins ne fusionnent pas.
    fg = D.translate(bytes(1 if i >= STRONG else 0 for i in range(256)))
    cw, ch = (w + CELL - 1) // CELL, (h + CELL - 1) // CELL
    occ = bytearray(cw * ch)
    for y in range(h):
        row = fg[y * w:(y + 1) * w]
        p = row.find(1)
        base = (y // CELL) * cw
        while p != -1:
            c = p // CELL
            occ[base + c] = 1
            p = row.find(1, (c + 1) * CELL)
    comps = []
    for start in range(cw * ch):
        if not occ[start]:
            continue
        occ[start] = 0
        todo = [start]
        x0 = x1 = start % cw
        y0 = y1 = start // cw
        while todo:
            c = todo.pop()
            cx, cy = c % cw, c // cw
            x0, x1, y0, y1 = min(x0, cx), max(x1, cx), min(y0, cy), max(y1, cy)
            for dy in (-1, 0, 1):
                ny = cy + dy
                if ny < 0 or ny >= ch:
                    continue
                for dx in (-1, 0, 1):
                    nx = cx + dx
                    if 0 <= nx < cw and occ[ny * cw + nx]:
                        occ[ny * cw + nx] = 0
                        todo.append(ny * cw + nx)
        box = (x0 * CELL, y0 * CELL, min((x1 + 1) * CELL, w), min((y1 + 1) * CELL, h))
        if box[2] - box[0] >= 14 and box[3] - box[1] >= 14:
            comps.append(box)

    # Les fragments (étincelles, pattes sombres détachées) rejoignent le sprite voisin.
    comps.sort(key=lambda b: -(b[2] - b[0]) * (b[3] - b[1]))
    merged = []
    for b in comps:
        area = (b[2] - b[0]) * (b[3] - b[1])
        host = None
        for i, m in enumerate(merged):
            if (area < 0.2 * (m[2] - m[0]) * (m[3] - m[1])
                    and b[0] < m[2] + MERGE_GAP and b[2] > m[0] - MERGE_GAP
                    and b[1] < m[3] + MERGE_GAP and b[3] > m[1] - MERGE_GAP):
                host = i
                break
        if host is None:
            merged.append(b)
        else:
            m = merged[host]
            merged[host] = (min(m[0], b[0]), min(m[1], b[1]), max(m[2], b[2]), max(m[3], b[3]))
    comps = merged

    # Ordre de lecture : par lignes, puis de gauche à droite.
    comps.sort(key=lambda b: (b[1] + b[3]) / 2)
    rows = []
    for b in comps:
        cy = (b[1] + b[3]) / 2
        if rows and cy < rows[-1]['bottom'] - 0.35 * (rows[-1]['bottom'] - rows[-1]['top']):
            rows[-1]['items'].append(b)
            rows[-1]['top'] = min(rows[-1]['top'], b[1])
            rows[-1]['bottom'] = max(rows[-1]['bottom'], b[3])
        else:
            rows.append({'top': b[1], 'bottom': b[3], 'items': [b]})
    comps = [b for row in rows for b in sorted(row['items'])]

    result = dict(w=w, h=h, R=R, G=G, B=B, A=A, comps=comps, bg=bg)
    pickle.dump(result, open(cache, 'wb'))
    return result


DIGITS = {'0': '111101101101111', '1': '010110010010111', '2': '111001111100111', '3': '111001111001111',
          '4': '101101111001001', '5': '111100111001111', '6': '111100111101111', '7': '111001010010010',
          '8': '111101111101111', '9': '111101111001111'}


def annote(name, out_prefix, parts=2):
    """Écrit des images de contrôle : chaque sprite encadré et numéroté."""
    s = analyse(name)
    w, h = s['w'], s['h']
    rgb = bytearray(3 * w * h)
    rgb[0::3], rgb[1::3], rgb[2::3] = s['R'], s['G'], s['B']

    def put(x, y, c):
        if 0 <= x < w and 0 <= y < h:
            i = 3 * (y * w + x)
            rgb[i:i + 3] = c

    for index, (x0, y0, x1, y1) in enumerate(s['comps']):
        for x in range(x0, x1):
            put(x, y0, b'\x00\xff\x00'); put(x, y1 - 1, b'\x00\xff\x00')
        for y in range(y0, y1):
            put(x0, y, b'\x00\xff\x00'); put(x1 - 1, y, b'\x00\xff\x00')
        text, k = str(index), 3
        tw = len(text) * 4 * k + k
        for yy in range(y0, y0 + 5 * k + 2 * k):
            for xx in range(x0, x0 + tw):
                put(xx, yy, b'\x00\x00\x00')
        for ci, chd in enumerate(text):
            for j, bit in enumerate(DIGITS[chd]):
                if bit == '1':
                    gx, gy = x0 + k + ci * 4 * k + (j % 3) * k, y0 + k + (j // 3) * k
                    for yy in range(gy, gy + k):
                        for xx in range(gx, gx + k):
                            put(xx, yy, b'\xff\xff\x00')
    step = h // parts
    paths = []
    for p in range(parts):
        top, bottom = p * step, (h if p == parts - 1 else (p + 1) * step + 30)
        rows = [rgb[3 * y * w:3 * (y + 1) * w] for y in range(top, min(bottom, h))]
        path = f'{out_prefix}_{p + 1}.png'
        write_png(path, w, len(rows), rows, alpha=False)
        paths.append(path)
    return paths


if __name__ == '__main__':
    out = sys.argv[1]
    os.makedirs(out, exist_ok=True)
    for name in sys.argv[2:]:
        s = analyse(name)
        print(name, s['w'], s['h'], 'fond', s['bg'], len(s['comps']), 'sprites')
        annote(name, os.path.join(out, name))
