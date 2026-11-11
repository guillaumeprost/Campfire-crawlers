"""Découpe les planches de héros sur fond magenta (Art/heros/*.jpg) et les exporte.

Étapes : détourage du magenta, repérage des images par composantes, puis export de chaque
animation sur une toile commune, pieds centrés en bas, pour que le héros ne saute pas.
  python3 Art/import_heroes.py annote <dossier>   planches numérotées pour choisir les images
  python3 Art/import_heroes.py export <catalogue> [catalogue du widget]
"""
import json, os, sys
sys.path.insert(0, os.path.dirname(__file__))
import slicer

HERE = os.path.dirname(os.path.abspath(__file__))


def is_bg(r, g, b):
    """Magenta, clair ou foncé (les lignes de sol et de grille sont d'un magenta plus sombre)."""
    return r - g > 70 and b - g > 50 and abs(r - b) < 110


def load(name):
    w, h, R, G, B = slicer.load_rgb(os.path.join(HERE, 'heros', name + '.jpg'))
    solid = bytearray(w * h)
    for i in range(w * h):
        if not is_bg(R[i], G[i], B[i]):
            solid[i] = 1
    return w, h, R, G, B, solid


def components(w, h, solid, gap=4, smallest=150):
    """Boîtes des taches non magenta, fusionnées quand elles se touchent presque."""
    seen = bytearray(w * h)
    boxes = []
    for start in range(w * h):
        if not solid[start] or seen[start]:
            continue
        seen[start] = 1
        stack, n = [start], 0
        x0 = y0 = 10 ** 9
        x1 = y1 = -1
        while stack:
            i = stack.pop()
            n += 1
            y, x = divmod(i, w)
            x0, x1, y0, y1 = min(x0, x), max(x1, x), min(y0, y), max(y1, y)
            for j in (i - 1, i + 1, i - w, i + w, i - w - 1, i - w + 1, i + w - 1, i + w + 1):
                if 0 <= j < w * h and solid[j] and not seen[j]:
                    if abs(j % w - x) <= 1:
                        seen[j] = 1
                        stack.append(j)
        if n >= 12:
            boxes.append([x0, y0, x1 + 1, y1 + 1, n])
    merged = True
    while merged:
        merged = False
        for a in range(len(boxes)):
            for b in range(a + 1, len(boxes)):
                A, B = boxes[a], boxes[b]
                if A[0] - gap < B[2] and B[0] - gap < A[2] and A[1] - gap < B[3] and B[1] - gap < A[3]:
                    boxes[a] = [min(A[0], B[0]), min(A[1], B[1]), max(A[2], B[2]), max(A[3], B[3]), A[4] + B[4]]
                    del boxes[b]
                    merged = True
                    break
            if merged:
                break
    boxes = [b for b in boxes if b[4] >= smallest]
    # Lecture par rangées, puis de gauche à droite.
    boxes.sort(key=lambda b: (b[3], b[0]))
    rows, out = [], []
    for b in boxes:
        if rows and abs(rows[-1][-1][3] - b[3]) < 60:
            rows[-1].append(b)
        else:
            rows.append([b])
    for r in rows:
        out += sorted(r, key=lambda b: b[0])
    return [tuple(b[:4]) for b in out]


def annote(name, folder):
    w, h, R, G, B, solid = load(name)
    boxes = components(w, h, solid)
    rgb = bytearray(3 * w * h)
    rgb[0::3], rgb[1::3], rgb[2::3] = R, G, B
    def put(x, y, c):
        if 0 <= x < w and 0 <= y < h:
            rgb[3 * (y * w + x):3 * (y * w + x) + 3] = c
    for index, (x0, y0, x1, y1) in enumerate(boxes):
        for x in range(x0, x1):
            put(x, y0, b'\x00\xff\x00'); put(x, y1 - 1, b'\x00\xff\x00')
        for y in range(y0, y1):
            put(x0, y, b'\x00\xff\x00'); put(x1 - 1, y, b'\x00\xff\x00')
        text, k = str(index), 4
        for yy in range(y0, y0 + 7 * k):
            for xx in range(x0, x0 + len(text) * 4 * k + k):
                put(xx, yy, b'\x00\x00\x00')
        for ci, ch in enumerate(text):
            for j, bit in enumerate(slicer.DIGITS[ch]):
                if bit == '1':
                    gx, gy = x0 + k + ci * 4 * k + (j % 3) * k, y0 + k + (j // 3) * k
                    for yy in range(gy, gy + k):
                        for xx in range(gx, gx + k):
                            put(xx, yy, b'\xff\xff\x00')
    rows = [rgb[y * 3 * w:(y + 1) * 3 * w] for y in range(h)]
    slicer.write_png(os.path.join(folder, name + '_annote.png'), w, h, rows, alpha=False)
    for i, b in enumerate(boxes):
        print(name, i, b)


def crop(sheet, box):
    """Image détourée : alpha progressif selon l'écart au magenta, sans liseré rose."""
    w, h, R, G, B, solid = sheet
    x0, y0, x1, y1 = box
    rows = []
    for y in range(y0, y1):
        row = bytearray(4 * (x1 - x0))
        for x in range(x0, x1):
            i = y * w + x
            r, g, b = R[i], G[i], B[i]
            # Part de magenta dans le pixel : 1 sur le fond, 0 sur le personnage.
            pink = min(max((min(r, b) - g - 40) / 120, 0), 1)
            a = 0 if is_bg(r, g, b) and pink > 0.6 else int(255 * (1 - pink))
            if a and pink > 0:
                # On retire la teinte magenta mêlée au bord.
                r = int(min(255, max(0, (r - 255 * pink) / max(1 - pink, 0.2))))
                b = int(min(255, max(0, (b - 255 * pink) / max(1 - pink, 0.2))))
            j = 4 * (x - x0)
            row[j:j + 4] = bytes((r, g, b, a))
        rows.append(row)
    return x1 - x0, y1 - y0, rows


def frame(sheet, boxes, spec):
    """Une image de la planche : un numéro de tache, ou une fenêtre [x0, y0, x1, y1] quand
    deux images se touchent par leur arme. Dans une fenêtre, on garde le personnage (la plus
    grande tache) et les morceaux isolés, mais pas ce qui déborde d'une image voisine."""
    if isinstance(spec, int):
        return crop(sheet, boxes[spec])
    erase = []
    if isinstance(spec, dict):
        erase, spec = spec.get('erase', []), spec['box']
    w, h, rows = crop(sheet, tuple(spec))
    x0, y0 = spec[0], spec[1]
    for ex0, ey0, ex1, ey1 in erase:
        for y in range(max(ey0 - y0, 0), min(ey1 - y0, h)):
            for x in range(max(ex0 - x0, 0), min(ex1 - x0, w)):
                rows[y][4 * x + 3] = 0
    solid = bytearray(w * h)
    for y in range(h):
        for x in range(w):
            if rows[y][4 * x + 3] > 60:
                solid[y * w + x] = 1
    seen = bytearray(w * h)
    blobs = []
    for start in range(w * h):
        if not solid[start] or seen[start]:
            continue
        seen[start] = 1
        stack, pixels, edge = [start], [], False
        while stack:
            i = stack.pop()
            pixels.append(i)
            y, x = divmod(i, w)
            edge = edge or x == 0 or x == w - 1
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    nx, ny = x + dx, y + dy
                    if 0 <= nx < w and 0 <= ny < h:
                        j = ny * w + nx
                        if solid[j] and not seen[j]:
                            seen[j] = 1
                            stack.append(j)
        blobs.append((pixels, edge))
    main = max(blobs, key=lambda b: len(b[0]))
    keep = bytearray(w * h)
    for pixels, edge in blobs:
        if pixels is main[0] or (not edge and len(pixels) >= 8):
            for i in pixels:
                keep[i] = 1
    for y in range(h):
        for x in range(w):
            if not keep[y * w + x]:
                rows[y][4 * x + 3] = 0
    # Resserre sur le personnage.
    ys = [y for y in range(h) if any(keep[y * w:(y + 1) * w])]
    xs = [x for x in range(w) if any(keep[y * w + x] for y in ys)]
    return (max(xs) - min(xs) + 1, max(ys) - min(ys) + 1,
            [r[4 * min(xs):4 * (max(xs) + 1)] for r in rows[min(ys):max(ys) + 1]])


def resize(w, h, rows, k):
    """Change l'échelle d'une image : moyenne des pixels couverts, pondérée par l'opacité."""
    ow, oh = max(1, round(w * k)), max(1, round(h * k))
    out = []
    for oy in range(oh):
        y0, y1 = int(oy / k), max(int((oy + 1) / k), int(oy / k) + 1)
        line = bytearray(4 * ow)
        for ox in range(ow):
            x0, x1 = int(ox / k), max(int((ox + 1) / k), int(ox / k) + 1)
            r = g = b = a = n = 0
            for y in range(y0, min(y1, h)):
                row = rows[y]
                for x in range(x0, min(x1, w)):
                    al = row[4 * x + 3]
                    r += row[4 * x] * al; g += row[4 * x + 1] * al; b += row[4 * x + 2] * al
                    a += al; n += 1
            if a:
                line[4 * ox:4 * ox + 4] = bytes((r // a, g // a, b // a, min(255, a // max(n, 1))))
        out.append(line)
    return ow, oh, out


def torso_center(fw, fh, rows):
    xs = [x for r in rows[int(fh * 0.25):int(fh * 0.55)] for x in range(fw) if r[4 * x + 3] > 128]
    return sum(xs) // len(xs) if xs else fw // 2


def feet_center(fw, fh, rows):
    xs = [x for r in rows[int(fh * 0.7):] for x in range(fw) if r[4 * x + 3] > 128]
    return sum(xs) // len(xs) if xs else fw // 2


def canvas(frames, flip=False):
    """Toutes les images d'un personnage sur une même toile : pieds centrés, collés en bas."""
    half = max(max(cx, fw - cx) for fw, fh, rows, cx in frames.values()) + 2
    height = max(fh for fw, fh, rows, cx in frames.values()) + 2
    out = {}
    for name, (fw, fh, rows, cx) in frames.items():
        left = half - cx
        img = [bytearray(8 * half) for _ in range(height)]
        for i, r in enumerate(rows):
            img[height - fh + i][4 * left:4 * (left + fw)] = r
        if flip:
            img = [bytearray(b''.join(bytes(r[4 * x:4 * x + 4]) for x in range(2 * half - 1, -1, -1))) for r in img]
        out[name] = (2 * half, height, img)
    return out


# Index des images sur chaque planche (voir les planches annotées).
ANIMS = json.load(open(os.path.join(HERE, 'heros', 'animations.json'))) if os.path.exists(os.path.join(HERE, 'heros', 'animations.json')) else {}


def export(assets, widgets=None):
    for name, spec in ANIMS.items():
        sheet = load(spec['sheet'])
        boxes = components(sheet[0], sheet[1], sheet[5])
        frames = {}
        reference = None
        for anim, indices in spec['anims'].items():
            source, sboxes = sheet, boxes
            if isinstance(indices, dict):
                # Animation dessinée sur une autre planche, souvent à une autre échelle :
                # on la ramène à la taille des images de la planche principale.
                source = load(indices['sheet'])
                sboxes = components(source[0], source[1], source[5])
                indices = indices['frames']
            cut = [frame(source, sboxes, index) for index in indices]
            if source is not sheet and reference:
                k = reference / sorted(fh for fw, fh, rows in cut)[len(cut) // 2]
                cut = [resize(fw, fh, rows, k) for fw, fh, rows in cut]
            for n, (fw, fh, rows) in enumerate(cut, 1):
                # En marche, les jambes bougent beaucoup : caler sur les pieds ferait
                # avancer et reculer le corps à chaque pas. On cale sur le tronc.
                anchor = torso_center if anim in ('walk', 'flee') else feet_center
                frames[f'{name}_{anim}_{n}'] = (fw, fh, rows, anchor(fw, fh, rows))
            if anim == 'idle':
                reference = sorted(fh for fw, fh, rows in cut)[len(cut) // 2]
        out = canvas(frames, flip=spec.get('flip', False))
        if 'portrait' in spec:
            fw, fh, rows = frame(sheet, boxes, spec['portrait'])
            out[f'{name}_portrait'] = (fw, fh, rows)
        for key, (fw, fh, rows) in out.items():
            write(assets, key, fw, fh, rows)
            if widgets and key.endswith('_portrait'):
                write(widgets, key, fw, fh, rows)
        print(name, len(out), 'images', out[next(iter(out))][:2])


def write(assets, key, w, h, rows):
    folder = os.path.join(assets, key + '.imageset')
    os.makedirs(folder, exist_ok=True)
    for f in os.listdir(folder):
        if f.endswith('.png') and f != key + '.png':
            os.remove(os.path.join(folder, f))
    slicer.write_png(os.path.join(folder, key + '.png'), w, h, rows)
    json.dump({'images': [{'filename': key + '.png', 'idiom': 'universal'}], 'info': {'author': 'xcode', 'version': 1}},
              open(os.path.join(folder, 'Contents.json'), 'w'), indent=2)


if __name__ == '__main__':
    if sys.argv[1] == 'annote':
        for n in ('mage', 'guerrier', 'archer', 'marchand'):
            annote(n, sys.argv[2])
    else:
        export(sys.argv[2], sys.argv[3] if len(sys.argv) > 3 else None)
