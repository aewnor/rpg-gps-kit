#!/usr/bin/env python3
"""Renderiza una zona del mapa fuente (TMJ) a PNG para revisión.

Uso: render_preview.py salida.png [x0 y0 w h] [--collision] [--scale N]
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def main():
    args = [a for a in sys.argv[1:] if not a.startswith('--')]
    out = args[0]
    x0, y0, w, h = (int(v) for v in args[1:5]) if len(args) >= 5 else (0, 0, 640, 640)
    show_coll = '--collision' in sys.argv
    scale = 1
    if '--scale' in sys.argv:
        scale = int(sys.argv[sys.argv.index('--scale') + 1])
    tmj = json.load(open(os.path.join(ROOT, 'maps/source/overworld.tmj')))
    atlas = Image.open(os.path.join(ROOT, 'assets/runtime/tiles.png')).convert('RGBA')
    coll_img = Image.open(os.path.join(ROOT, 'assets/runtime/collision.png')).convert('RGBA')
    cols = atlas.width // 16
    coll_first = tmj['tilesets'][1]['firstgid']
    cache = {}

    def tile(gid):
        if gid not in cache:
            if gid >= coll_first:
                c = gid - coll_first
                cache[gid] = coll_img.crop(((c % 8) * 16, (c // 8) * 16, (c % 8) * 16 + 16, (c // 8) * 16 + 16))
            else:
                i = gid - 1
                cache[gid] = atlas.crop(((i % cols) * 16, (i // cols) * 16, (i % cols) * 16 + 16, (i // cols) * 16 + 16))
        return cache[gid]

    img = Image.new('RGBA', (w * 16, h * 16), (0, 0, 0, 255))
    W = tmj['width']
    layers = {l['name']: l for l in tmj['layers']}

    def draw_layer(name):
        data = layers[name]['data']
        for y in range(y0, y0 + h):
            row = y * W
            for x in range(x0, x0 + w):
                g = data[row + x] & 0x1FFFFFFF
                if g:
                    t = tile(g)
                    img.alpha_composite(t, ((x - x0) * 16, (y - y0) * 16))

    for name in ('ground', 'ground_detail', 'structures'):
        draw_layer(name)
    for o in layers['objects']['objects']:
        if o['type'] != 'landmark':
            continue
        props = {p['name']: p['value'] for p in o['properties']}
        spr = Image.open(os.path.join(ROOT, 'assets/runtime/sprites', props['sprite'] + '.png')).convert('RGBA')
        px, py = int(o['x']) - x0 * 16, int(o['y']) - y0 * 16
        if -spr.width < px < img.width and -spr.height < py < img.height:
            img.alpha_composite(spr, (max(0, px), max(0, py)),
                                (max(0, -px), max(0, -py)))
    for name in ('cover_low', 'bridge', 'overhead'):
        draw_layer(name)
    if show_coll:
        draw_layer('collision')
    if scale != 1:
        img = img.resize((img.width // scale, img.height // scale), Image.LANCZOS if scale > 1 else Image.NEAREST)
    img.save(out)
    print(out, img.size)


if __name__ == '__main__':
    main()
