#!/usr/bin/env python3
"""Pipeline ortofoto → pixel art → Tiled, para todo el municipio (o un rectángulo).

  python3 tools/sat_pipeline.py retro   [--rect x,y,w,h]   # paleta retro + dithering + rejilla de 16 px
  python3 tools/sat_pipeline.py classes [--rect x,y,w,h]   # superficies por tile desde la imagen retro
  python3 tools/sat_pipeline.py tmx     [--rect x,y,w,h]   # mapa del juego → .tmx + .tsx (Wang sets)
  python3 tools/sat_pipeline.py all                         # las tres cosas, mapa completo

1. retro: la ortofoto PNOA (1 m/px) se reduce a la paleta de 32 colores del juego (tools/pixel.py,
   estilo SNES) con dithering Floyd–Steinberg y se pixela a la rejilla: cada tile de 16 px son 4×4
   bloques de 4 px (un bloque = 1 m). Salida: cartography/derived/sat_retro.png (+ _preview.png).
2. classes: cada tile se clasifica por el histograma de colores de paleta de sus 16 bloques
   (vegetación, tierra, arena, asfalto, pavimento, tejado, agua) → sat_classes.npz y una vista en color,
   con el acuerdo frente al suelo del mapa importado (OSM + Catastro).
3. tmx: exporta el mapa del juego (maps/source/overworld.tmj, ya decorado: transiciones Wang y sombras)
   a cartography/derived/roda.tmx + roda_tiles.tsx (Wang set «Terreny» tipo corner para pintar con
   autotiling en Tiled), con capa de colisión (tejados, agua, vías cerradas) y capa de sombras.
Las transiciones y sombras dentro del juego las pone tools/decorate_map.py (tools/terrain_blend.py).
"""
import argparse
import base64
import json
import os
import sys
import zlib
from xml.sax.saxutils import escape

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(__file__))
from pixel import PALETTE  # noqa: E402
import terrain_blend  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PNOA = os.path.join(ROOT, 'cartography/sat/pnoa.jpg')
OUT = os.path.join(ROOT, 'cartography/derived')
PX = 4  # px de ortofoto por tile
Image.MAX_IMAGE_PIXELS = None

# color de paleta → superficie
SURF = ['vegetacio', 'terra', 'sorra', 'asfalt', 'paviment', 'teulada', 'aigua']
SURF_RGB = [(95, 125, 64), (217, 198, 144), (241, 224, 170), (88, 86, 93), (200, 181, 152), (213, 107, 75),
            (47, 158, 176)]
PAL_SURF = {
    'pine': 0, 'pine2': 0, 'pine3': 0, 'pine4': 0,
    'dry': 1, 'dry2': 1, 'dry3': 1, 'ochre': 1, 'ochre2': 1, 'ochre3': 1, 'stone3': 1,
    'sand': 2, 'sand2': 2,
    'asph': 3, 'asph2': 3, 'asph3': 3, 'ink': 3,
    'stone': 4, 'stone2': 4, 'white2': 4, 'white3': 4,
    'terra': 5, 'terra2': 5, 'terra3': 5, 'red': 5, 'white': 5, 'foam': 5, 'skin': 5,
    'sea': 6, 'sea2': 6, 'sea3': 6, 'blue': 6,
}


# acentos fuera: con ellos el dithering salpica de azul y rojo el asfalto gris
RETRO_SKIP = {'blue', 'red', 'skin', 'foam', 'ink', 'skin2', 'blush', 'pool', 'sun', 'deep'}


def palette_image():
    names = [n for n in PALETTE if n not in RETRO_SKIP]
    flat = []
    for n in names:
        h = PALETTE[n].lstrip('#')
        flat += [int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)]
    flat += flat[-3:] * (256 - len(names))
    p = Image.new('P', (1, 1))
    p.putpalette(flat)
    return p, names


def load_rect(rect):
    im = Image.open(PNOA).convert('RGB')
    if rect:
        x, y, w, h = rect
        im = im.crop((x * PX, y * PX, (x + w) * PX, (y + h) * PX))
    return im


def retro(rect):
    """Ortofoto → índices de la paleta del juego (1 px = 1 m), con dithering."""
    src = load_rect(rect)
    pal, names = palette_image()
    # un poco más de contraste y saturación: la ortofoto es lavada al lado de la paleta del juego
    from PIL import ImageEnhance
    src = ImageEnhance.Color(ImageEnhance.Contrast(src).enhance(1.1)).enhance(1.05)
    q = src.quantize(palette=pal, dither=Image.Dither.FLOYDSTEINBERG)
    q.save(os.path.join(OUT, 'sat_retro.png'))
    # rejilla del juego: 1 m → bloque de 4 px; tile = 16 px; vista reducida para revisar
    w, h = q.size
    prev = q.convert('RGB')
    if w * h <= 600 * 600:
        prev = prev.resize((w * 4, h * 4), Image.NEAREST)
    else:
        prev = prev.resize((min(w, 3200), min(h, 3200)), Image.NEAREST)
    prev.save(os.path.join(OUT, 'sat_retro_preview.png'))
    print(f'retro {w}×{h} px ({len(names)} colores) → cartography/derived/sat_retro.png')
    return np.asarray(q), names


def classes(idx, names, rect):
    h, w = idx.shape[0] // PX, idx.shape[1] // PX
    lut = np.array([PAL_SURF.get(n, 1) for n in names] + [1] * (256 - len(names)), np.uint8)
    surf = lut[idx[:h * PX, :w * PX]].reshape(h, PX, w, PX)
    counts = np.stack([(surf == k).sum((1, 3)) for k in range(len(SURF))], -1)
    cls = counts.argmax(-1).astype(np.uint8)
    # agua solo si domina claramente (el dithering pone motas azules en sombras); el mar profundo es
    # azul marino, más cerca del asfalto oscuro de la paleta: se decide por el color medio del tile
    cls[(cls == 6) & (counts[..., 6] < 9)] = 3
    rgb = np.asarray(load_rect(rect), np.float32)[:h * PX, :w * PX].reshape(h, PX, w, PX, 3).mean((1, 3))
    blue = (rgb[..., 2] > rgb[..., 0] + 18) & (rgb[..., 2] >= rgb[..., 1] - 4) & (rgb.mean(-1) < 150)
    cls[blue] = 6
    np.savez_compressed(os.path.join(OUT, 'sat_classes.npz'), cls=cls, names=np.array(SURF))
    img = np.array(SURF_RGB, np.uint8)[cls]
    Image.fromarray(img).resize((w * 2, h * 2), Image.NEAREST).save(os.path.join(OUT, 'sat_classes.png'))
    stats = {SURF[k]: round(float((cls == k).mean()) * 100, 1) for k in range(len(SURF))}
    print('superficies (%):', stats)
    agreement(cls, rect)
    return cls


def agreement(cls, rect):
    """Acuerdo con el suelo del mapa importado (vegetación / tierra / agua / construido)."""
    tmj = json.load(open(os.path.join(ROOT, 'maps/source/overworld.raw.json')))
    tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
    name_of = {t['id'] + 1: n for n, t in tiles.items()}
    L = {l['name']: np.array(l['data'], np.int64).reshape(tmj['height'], tmj['width'])
         for l in tmj['layers'] if l['type'] == 'tilelayer'}
    x, y, w, h = rect or (0, 0, tmj['width'], tmj['height'])
    G, S = L['ground'][y:y + h, x:x + w], L['structures'][y:y + h, x:x + w]

    def group_ground(n):
        if n.startswith(('sea_', 'pool_')):
            return 6
        if n.startswith(('g_grass', 'g_park', 'g_forest', 'g_scrub', 'g_pitch', 'g_wetland', 'g_cemetery')):
            return 0
        if n.startswith(('g_beach',)):
            return 2
        return 1
    gg = np.vectorize(lambda g: group_ground(name_of.get(int(g), '')), otypes=[np.uint8])(G)
    roof = np.vectorize(lambda g: name_of.get(int(g), '').startswith(('r_', 'f_')), otypes=[bool])(S)
    tree = np.vectorize(lambda g: name_of.get(int(g), '').startswith('tree_'), otypes=[bool])(S)
    ref = gg.copy()
    ref[tree] = 0
    ref[roof] = 5
    cm = cls.copy()
    cm[np.isin(cm, [1, 3, 4])] = 1  # tierra/asfalto/pavimento: el mapa no los distingue en el suelo
    ref[np.isin(ref, [1])] = 1
    ok = {}
    for k, nm in ((0, 'vegetació'), (5, 'teulades'), (6, 'aigua')):
        m = ref == k
        if m.any():
            ok[nm] = round(float((cm[m] == k).mean()) * 100, 1)
    print('acuerdo con el mapa (% de celdas del mapa reconocidas en la ortofoto):', ok)


def tmx(rect):
    """Mapa del juego → Tiled .tmx (capas zlib+base64) + .tsx con el Wang set de terreno."""
    tmj = json.load(open(os.path.join(ROOT, 'maps/source/overworld.tmj')))
    tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))
    W0, H0 = tmj['width'], tmj['height']
    x, y, w, h = rect or (0, 0, W0, H0)
    cf = tmj['tilesets'][1]['firstgid']
    n = tiles['count']
    cols = tiles['columns']
    # tileset con Wang set
    ws = terrain_blend.wangsets(tiles['tiles'])[0]
    tsx = [f'<?xml version="1.0" encoding="UTF-8"?>',
           f'<tileset version="1.10" tiledversion="1.10.2" name="roda" tilewidth="16" tileheight="16" '
           f'tilecount="{n}" columns="{cols}">',
           f' <image source="../../assets/runtime/tiles.png" width="{cols * 16}" height="{16 * ((n + cols - 1) // cols)}"/>',
           ' <wangsets>', f'  <wangset name="{ws["name"]}" type="corner" tile="-1">']
    for c in ws['colors']:
        tsx.append(f'   <wangcolor name="{escape(c["name"])}" color="{c["color"]}" tile="{c["tile"]}" probability="1"/>')
    for t in ws['wangtiles']:
        tsx.append(f'   <wangtile tileid="{t["tileid"]}" wangid="{",".join(map(str, t["wangid"]))}"/>')
    tsx += ['  </wangset>', ' </wangsets>', '</tileset>']
    open(os.path.join(OUT, 'roda_tiles.tsx'), 'w').write('\n'.join(tsx))
    coll_tsx = [f'<?xml version="1.0" encoding="UTF-8"?>',
                '<tileset version="1.10" tiledversion="1.10.2" name="collision" tilewidth="16" tileheight="16" tilecount="64" columns="8">',
                ' <image source="../../assets/runtime/collision.png" width="128" height="128"/>', '</tileset>']
    open(os.path.join(OUT, 'roda_collision.tsx'), 'w').write('\n'.join(coll_tsx))
    layers = {l['name']: l for l in tmj['layers'] if l['type'] == 'tilelayer'}
    titles = {'ground': 'terreny', 'ground_detail': 'ombres i detall', 'structures': 'estructures',
              'overhead': 'per sobre', 'collision': 'col·lisió'}
    out = [f'<?xml version="1.0" encoding="UTF-8"?>',
           f'<map version="1.10" tiledversion="1.10.2" orientation="orthogonal" renderorder="right-down" '
           f'width="{w}" height="{h}" tilewidth="16" tileheight="16" infinite="0" nextlayerid="9" nextobjectid="1">',
           ' <tileset firstgid="1" source="roda_tiles.tsx"/>',
           f' <tileset firstgid="{cf}" source="roda_collision.tsx"/>']
    for i, (key, title) in enumerate(titles.items(), 1):
        d = np.array(layers[key]['data'], np.uint32).reshape(H0, W0)[y:y + h, x:x + w]
        enc = base64.b64encode(zlib.compress(d.astype('<u4').tobytes(), 6)).decode()
        vis = '0' if key == 'collision' else '1'
        out.append(f' <layer id="{i}" name="{title}" width="{w}" height="{h}" visible="{vis}">')
        out.append(f'  <data encoding="base64" compression="zlib">{enc}</data>')
        out.append(' </layer>')
    out.append('</map>')
    path = os.path.join(OUT, 'roda.tmx')
    open(path, 'w').write('\n'.join(out))
    print(f'tmx {w}×{h} → {path} ({os.path.getsize(path) / 1e6:.1f} MB), {len(ws["wangtiles"])} wang tiles')


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('cmd', choices=['retro', 'classes', 'tmx', 'all'])
    ap.add_argument('--rect')
    a = ap.parse_args()
    rect = tuple(map(int, a.rect.split(','))) if a.rect else None
    os.makedirs(OUT, exist_ok=True)
    if a.cmd in ('retro', 'classes', 'all'):
        idx, names = retro(rect)
        if a.cmd != 'retro':
            classes(idx, names, rect)
    if a.cmd in ('tmx', 'all'):
        tmx(rect)
    return 0


if __name__ == '__main__':
    sys.exit(main())
