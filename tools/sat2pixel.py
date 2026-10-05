#!/usr/bin/env python3
"""Imagen de satélite → pixel art del juego (capas de una zona del editor).

  python3 tools/sat2pixel.py --zone 564,847,19,21 [--png vista.png]      # ortofoto PNOA del mapa
  python3 tools/sat2pixel.py --image foto.jpg --size 40x30 [--png ...]   # imagen propia

Cada tile (1 m² de ortofoto = 4×4 px) se clasifica por color: agua (piscina o mar), césped, copas
de árbol, tejados (teja, pizarra, marrón o azotea), asfalto, pavimento, tierra o arena. Después:
  · filtro de moda 3×3 para quitar ruido,
  · tejados conexos ≥ 3 tiles → edificio con tejado autotile y fachada abajo (con una puerta si
    delante se puede pasar),
  · árboles separados entre sí sobre las copas,
  · agua con borde autotile.
Lo usan el editor (POST /api/sat2pixel) y este CLI. Devuelve las capas con nombres de tile.
"""
import argparse
import base64
import io
import json
import os
import sys

import numpy as np
from PIL import Image
from scipy import ndimage

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PNOA = os.path.join(ROOT, 'cartography/sat/pnoa.jpg')
PX = 4  # px de ortofoto por tile

# clases
WATER, POOL, GRASS, CANOPY, ROOF_T, ROOF_S, ROOF_B, ROOF_F, ASPHALT, PAVING, DRY, SAND = range(12)
GROUND = {WATER: 'sea', POOL: 'pool', GRASS: 'g_grass', CANOPY: 'g_grass', ASPHALT: 'g_asphalt',
          PAVING: 'g_urban', DRY: 'g_dry', SAND: 'g_beach'}
ROOF = {ROOF_T: 'terra', ROOF_S: 'slate', ROOF_B: 'brown', ROOF_F: 'flat'}
BN, BE, BS, BW = 1, 2, 4, 8


def classify(rgb, tex):
    """rgb: (h, w, 3) media por tile; tex: desviación de la luminancia dentro del tile → clases."""
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    mx, mn = rgb.max(-1), rgb.min(-1)
    lum = rgb.mean(-1)
    sat = (mx - mn) / np.maximum(mx, 1)
    exg = 2 * g - r - b
    blue_ish = b > r + 10
    cls = np.full(r.shape, DRY, np.uint8)                       # tierra / solar (beige, ocre)
    gray = sat < 0.13
    cls[gray & (lum < 200)] = ASPHALT                           # calles: en la ortofoto, gris claro
    cls[gray & (lum >= 200) & (r >= b)] = PAVING                # aceras y plazas (gris cálido muy claro)
    cls[(lum >= 212) & (sat < 0.12)] = ROOF_F                   # azoteas blancas
    cls[(sat < 0.2) & (lum < 70)] = ASPHALT                     # sombra o asfalto oscuro
    roof_t = (r > g + 18) & (r > b + 38) & (sat > 0.28)
    cls[roof_t] = ROOF_T                                        # teja
    cls[(r > b + 25) & (r > g + 8) & (lum < 110) & (sat > 0.3) & ~roof_t] = ROOF_B
    cls[exg > 22] = GRASS
    cls[((exg > 8) & (lum < 95)) | ((exg > -10) & (lum < 88) & ~blue_ish)] = CANOPY   # copas y su sombra
    blue = (b > r + 22) & (b >= g - 6)
    cls[blue & (lum >= 120)] = POOL
    cls[blue & (lum < 120)] = WATER
    return cls


def mode3(cls, keep=(POOL, WATER, CANOPY)):
    """Moda 3×3 (sin tocar el agua pequeña: una piscina de 2×3 se quedaría sin agua)."""
    h, w = cls.shape
    n = cls.max() + 1
    counts = np.zeros((n, h, w), np.int16)
    for k in range(n):
        counts[k] = ndimage.uniform_filter((cls == k).astype(np.float32), 3, mode='nearest') * 9 + 0.01
    out = counts.argmax(0).astype(np.uint8)
    for k in keep:
        out[cls == k] = k
    return out


def mask(m, y, x):
    h, w = m.shape
    v = 0
    for dy, dx, bit in ((-1, 0, BN), (0, 1, BE), (1, 0, BS), (0, -1, BW)):
        yy, xx = y + dy, x + dx
        if not (0 <= yy < h and 0 <= xx < w) or m[yy, xx]:
            v |= bit
    return v


def convert(img, w, h, tiles, seed=7):
    """img: PIL RGB que cubre exactamente el área; w×h tiles → capas del editor."""
    big = np.asarray(img.convert('RGB').resize((w * PX, h * PX), Image.BOX), np.float32)
    rgb = big.reshape(h, PX, w, PX, 3).mean((1, 3))
    blk = big.reshape(h, PX, w, PX, 3)
    tex = blk.mean(-1).std((1, 3))
    cls = mode3(classify(rgb, tex))
    rng = np.random.default_rng(seed)
    n = w * h
    L = {k: [''] * n for k in ('ground', 'detail', 'structures', 'overhead')}

    def name(base):  # variante _0.._2 si existe
        for v in (rng.integers(0, 3), 0):
            if f'{base}_{v}' in tiles:
                return f'{base}_{v}'
        return base if base in tiles else 'g_grass_0'

    roofs = np.isin(cls, list(ROOF))
    lab, nb = ndimage.label(roofs)
    sizes = ndimage.sum(roofs, lab, range(nb + 1))
    # un tejado es pequeño y compacto; una mancha enorme o deshilachada es un campo rojizo
    bad = np.zeros(nb + 1, bool)
    for k, sl in enumerate(ndimage.find_objects(lab), 1):
        if sl is None:
            continue
        box = (sl[0].stop - sl[0].start) * (sl[1].stop - sl[1].start)
        bad[k] = sizes[k] < 3 or sizes[k] > 260 or sizes[k] / box < 0.55
    small = roofs & bad[lab]
    cls[small] = PAVING
    lab[small] = 0
    water = np.isin(cls, [WATER, POOL])
    wlab, nw = ndimage.label(water)
    wsize = ndimage.sum(water, wlab, range(nw + 1))
    dry_near = ndimage.uniform_filter((cls == DRY).astype(np.float32), 7, mode='nearest')
    green_near = ndimage.uniform_filter((cls == GRASS).astype(np.float32), 7, mode='nearest')
    for y in range(h):
        for x in range(w):
            c = cls[y, x]
            i = y * w + x
            if c in (WATER, POOL):
                kind = 'sea' if (c == WATER and wsize[wlab[y, x]] > 40) else 'pool'
                L['ground'][i] = f'{kind}_{mask(water, y, x)}_0'
            elif c in ROOF:
                L['ground'][i] = name('g_urban')
            elif c == CANOPY:  # bajo la copa, el suelo de alrededor (olivos sobre tierra, pinos sobre hierba)
                L['ground'][i] = name('g_dry' if dry_near[y, x] > green_near[y, x] else 'g_grass')
            else:
                L['ground'][i] = name(GROUND[c])
    # edificios: tejado autotile + fachada en la fila de abajo de cada columna
    walls = ['white', 'white', 'ochre', 'sand', 'salmon', 'stone']
    for b in range(1, nb + 1):
        cells = np.argwhere(lab == b)
        if not len(cells):
            continue
        rk = ROOF[int(np.bincount(cls[lab == b]).argmax())]
        wc = walls[int(rng.integers(0, len(walls)))]
        bm = lab == b
        door = False
        for y, x in sorted(map(tuple, cells), key=lambda p: (-p[0], p[1])):
            i = y * w + x
            facade = y + 1 >= h or not bm[y + 1, x]
            if facade:
                lft = x > 0 and bm[y, x - 1] and (y + 1 >= h or not bm[y + 1, x - 1])
                rgt = x + 1 < w and bm[y, x + 1] and (y + 1 >= h or not bm[y + 1, x + 1])
                pos = 'm' if lft and rgt else 'r' if lft else 'l' if rgt else 's'
                kind = 'win'
                if not door and y + 1 < h and cls[y + 1, x] not in ROOF and cls[y + 1, x] not in (WATER, POOL) \
                        and (not rgt or rng.random() < .4):
                    kind, door = 'door', True
                L['structures'][i] = f'f_{wc}_{pos}_{kind}'
            else:
                # tejados de pendiente: vertiente norte, cumbrera en la fila central y vertiente sur
                col = [yy for yy in range(h) if bm[yy, x] and yy + 1 < h and bm[yy + 1, x]]
                part = None
                if rk in ('terra', 'slate', 'brown') and len(col) >= 2:
                    ridge = col[0] + (col[-1] - col[0]) // 2
                    part = 'n' if y < ridge else 'k' if y == ridge else 's'
                nm = f'r_{rk}_{part}_{mask(bm, y, x)}' if part else f'r_{rk}_{mask(bm, y, x)}'
                L['structures'][i] = nm if nm in tiles else f'r_{rk}_{mask(bm, y, x)}'
    # árboles sobre las copas, separados
    taken = np.zeros((h, w), bool)
    for y, x in np.argwhere(cls == CANOPY):
        if y == 0 or taken[max(0, y - 1):y + 2, max(0, x - 1):x + 2].any() or L['structures'][y * w + x] \
                or L['structures'][(y - 1) * w + x]:
            continue
        kind = ['pine0', 'pine1', 'olive', 'palm'][int(rng.integers(0, 4))]
        L['structures'][y * w + x] = f'tree_{kind}_bot'
        L['overhead'][(y - 1) * w + x] = f'tree_{kind}_top'
        taken[y, x] = True
    for k in L:  # cualquier nombre que no exista → vacío (o césped en el suelo)
        L[k] = [v if (not v or v in tiles) else ('g_grass_0' if k == 'ground' else '') for v in L[k]]
    L['height'] = [0] * n
    stats = {int(k): int(v) for k, v in zip(*np.unique(cls, return_counts=True))}
    return {'w': w, 'h': h, **L, 'buildings': int((~bad[1:]).sum()), 'classes': stats}


def pnoa_crop(x, y, w, h):
    Image.MAX_IMAGE_PIXELS = None
    im = Image.open(PNOA)
    return im.crop((x * PX, y * PX, (x + w) * PX, (y + h) * PX))


def from_data_url(s):
    raw = base64.b64decode(s.split(',', 1)[1] if ',' in s else s)
    if len(raw) > 12_000_000:
        raise ValueError('imagen demasiado grande')
    im = Image.open(io.BytesIO(raw))
    im.load()
    return im


def preview(area, tiles, path):
    atlas = Image.open(os.path.join(ROOT, 'assets/runtime/tiles.png')).convert('RGBA')
    cols = atlas.width // 16
    w, h = area['w'], area['h']
    out = Image.new('RGBA', (w * 16, h * 16), (0, 0, 0, 255))
    for k in ('ground', 'detail', 'structures', 'overhead'):
        for i, nm in enumerate(area[k]):
            if nm and nm in tiles:
                t = tiles[nm]['id']
                out.alpha_composite(atlas.crop(((t % cols) * 16, (t // cols) * 16, (t % cols) * 16 + 16, (t // cols) * 16 + 16)),
                                    ((i % w) * 16, (i // w) * 16))
    out.save(path)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--zone', help='x,y,w,h en tiles del mapa (ortofoto PNOA)')
    ap.add_argument('--image')
    ap.add_argument('--size', help='WxH en tiles para --image')
    ap.add_argument('--png')
    ap.add_argument('--json')
    a = ap.parse_args()
    tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
    if a.zone:
        x, y, w, h = map(int, a.zone.split(','))
        img = pnoa_crop(x, y, w, h)
    else:
        img = Image.open(a.image)
        w, h = map(int, a.size.lower().split('x'))
    area = convert(img, w, h, tiles)
    print(f'{w}×{h}: {area["buildings"]} edificios, clases {area["classes"]}')
    if a.png:
        preview(area, tiles, a.png)
        img.convert('RGB').resize((w * 16, h * 16), Image.NEAREST).save(a.png.replace('.png', '_sat.png'))
    if a.json:
        json.dump(area, open(a.json, 'w'))
    return 0


if __name__ == '__main__':
    sys.exit(main())
