#!/usr/bin/env python3
"""Vista general del mapa para el editor (web/editor/overview.jpg, 2 px por tile, no versionada).

Cada tile se reduce a 2 × 2 píxeles con su color medio real (atlas) y se componen las capas igual
que en el juego; encima se trazan las vías vectoriales. Así el editor enseña el mapa de verdad
con poco zoom, en lugar del minimapa de 320 px.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw

sys.path.insert(0, os.path.dirname(__file__))
from pixel import rgba  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
K = 2  # píxeles por tile


def _c(name):
    return rgba(name)[:3]


STYLE = {  # color (paleta común) y anchura mínima (px) de cada clase vectorial
    'MOTORWAY': (_c('asph3'), 2), 'ROAD_MAIN': (_c('asph2'), 2), 'ROAD': (_c('asph'), 1),
    'PEDESTRIAN': (_c('white'), 1), 'FOOTWAY': (_c('white'), 1), 'STEPS': (_c('stone'), 1),
    'PLATFORM': (_c('white2'), 1), 'PATH': (_c('dry2'), 1), 'TRACK': (_c('dry3'), 1),
    'STREAM': (_c('sea2'), 1), 'TORRENT': (_c('stone3'), 2), 'RAIL': (_c('asph3'), 1),
    'RAIL_HS': (_c('white3'), 1),
}


def render(K, min_classes=None, scale_w=True):
    """Compone el mapa con el color medio real de cada tile (K×K px por tile) y traza las vías encima.
    min_classes: si se da, solo esas clases vectoriales (para el minimapa)."""
    tmj = json.load(open(os.path.join(ROOT, 'maps/source/overworld.tmj')))
    W, H = tmj['width'], tmj['height']
    atlas = np.asarray(Image.open(os.path.join(ROOT, 'assets/runtime/tiles.png')).convert('RGBA')).astype(np.float32)
    cols = atlas.shape[1] // 16
    n = cols * (atlas.shape[0] // 16)
    # tabla id → bloque K×K premultiplicado
    tiles = atlas.reshape(atlas.shape[0] // 16, 16, cols, 16, 4).transpose(0, 2, 1, 3, 4).reshape(n, 16, 16, 4)
    a = tiles[..., 3:4] / 255.0
    pre = np.concatenate([tiles[..., :3] * a, a], -1)
    lut = pre.reshape(n, K, 16 // K, K, 16 // K, 4).mean(axis=(2, 4))  # n, K, K, 4
    lut = np.concatenate([np.zeros((1, K, K, 4), np.float32), lut])     # gid 0 = vacío
    out = np.zeros((H, W, K, K, 3), np.float32)
    layers = {l['name']: l for l in tmj['layers']}
    for name in ('ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead'):
        if name not in layers or 'data' not in layers[name]:
            continue
        g = (np.array(layers[name]['data'], np.int64) & 0x1FFFFFFF).reshape(H, W)
        g[g > n] = 0
        blk = lut[g]
        out = out * (1 - blk[..., 3:4]) + blk[..., :3]
    img = out.transpose(0, 2, 1, 3, 4).reshape(H * K, W * K, 3).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(img)
    d = ImageDraw.Draw(im)
    lines = json.load(open(os.path.join(ROOT, 'maps/runtime/overworld/lines.json')))
    order = list(STYLE)
    for it in sorted(lines, key=lambda it: (it['l'], order.index(it['c']) if it['c'] in order else 0)):
        st = STYLE.get(it['c'])
        if not st or it['l'] < 0 or (min_classes is not None and it['c'] not in min_classes):
            continue
        p = it['p']
        pts = [(p[i] / 16 * K, p[i + 1] / 16 * K) for i in range(0, len(p) - 1, 2)]
        if len(pts) >= 2:
            w = max(st[1], round(it['w'] / 16 * K)) if scale_w else st[1]
            d.line(pts, fill=st[0], width=w, joint='curve')
    return im


def main():
    im = render(K)
    path = os.path.join(ROOT, 'web/editor/overview.jpg')
    im.save(path, quality=86, optimize=True)
    print('overview', im.size, os.path.getsize(path) // 1024, 'KB')


if __name__ == '__main__':
    main()
