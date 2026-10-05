#!/usr/bin/env python3
"""¿Cuadran los colores del mapa con los de la ortofoto? Compara, por clase de suelo y para tejados,
calles y mar, la mediana del color real del satélite (cartography/derived/terrain.npz) con el color medio
del tile que pone el juego (assets/runtime/tiles.png).

La paleta del juego es la del satélite «estilizada» (más saturación y luz para que se lea a 1×), así que
se compara el tono (hue) y la luminosidad relativa, no el color exacto: el tono debe quedar a menos de
TOL_HUE grados y el orden de claro a oscuro de las clases debe ser el mismo.

Uso: python3 tools/palette_check.py   (sale con código 1 si alguna clase se desvía)
"""
import colorsys
import json
import os
import sys

import numpy as np
from PIL import Image

import semantic as S

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
TOL_HUE = 25
CHECK = {  # clase del satélite → tile que la representa en el juego
    'FOREST': 'g_forest_1', 'SCRUB': 'g_scrub_1', 'DRY': 'g_dry_1', 'GRASS': 'g_grass_1', 'FARM': 'g_farm_1',
    'URBAN': 'g_urban_1', 'PARK': 'g_park_1', 'QUARRY': 'g_quarry_1', 'BEACH': 'g_beach_1', 'SEA': 'sea_15_0',
}
LOW_SAT = 0.12   # por debajo, el tono no significa nada (grises): solo se compara la luz


def tile_mean(tiles, atlas, name):
    t = tiles[name]['id']
    cols = atlas.width // 16
    a = np.asarray(atlas.crop(((t % cols) * 16, (t // cols) * 16, (t % cols) * 16 + 16, (t // cols) * 16 + 16)),
                   np.float32)
    w = a[..., 3:4] / 255
    return (a[..., :3] * w).sum((0, 1)) / max(1e-6, w.sum())


def hsv(c):
    return colorsys.rgb_to_hsv(*(np.asarray(c, float) / 255))


def main():
    tpath = os.path.join(ROOT, 'cartography/derived/terrain.npz')
    if not os.path.exists(tpath):   # sense ortofoto (lloc nou fora d'Espanya o sense fetch_sources.py): res a comparar
        print('paleta: sense ortofoto (cartography/derived/terrain.npz), no es compara')
        return
    z = np.load(tpath)
    sem = np.load(os.path.join(ROOT, 'maps/source/semantic.npz'))
    g, bld, d0 = sem['ground'], sem['bld'], sem['d0']
    rgb = z['rgb'].astype(np.float32)
    tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
    atlas = Image.open(os.path.join(ROOT, 'assets/runtime/tiles.png')).convert('RGBA')
    rows, bad = [], 0
    for cls, tname in CHECK.items():
        m = (g == S.G[cls]) & (bld == 0) & (d0 == 0)
        if m.sum() < 50:
            continue
        sat = np.median(rgb[m], 0)
        game = tile_mean(tiles, atlas, tname)
        hs, ss, vs = hsv(sat)
        hg, sg, vg = hsv(game)
        dh = min(abs(hs - hg), 1 - abs(hs - hg)) * 360
        ok = dh <= TOL_HUE or ss < LOW_SAT or sg < LOW_SAT
        bad += not ok
        rows.append((cls, sat, game, dh, vs, vg, ok))
    # orden de luminosidad: la clase más clara del satélite debe ser también de las más claras en el juego
    vs_rank = np.argsort(np.argsort([r[4] for r in rows]))
    vg_rank = np.argsort(np.argsort([r[5] for r in rows]))
    print(f'{"clase":9} {"satélite":9} {"juego":9} {"Δtono":>6} {"rango luz sat/juego":>20}')
    for (cls, sat, game, dh, vs, vg, ok), rs, rg in zip(rows, vs_rank, vg_rank):
        hx = lambda c: '#%02x%02x%02x' % tuple(int(v) for v in c)
        flag = 'ok' if ok and abs(int(rs) - int(rg)) <= 3 else 'REVISAR'
        bad += abs(int(rs) - int(rg)) > 3
        print(f'{cls:9} {hx(sat)}   {hx(game)}   {dh:5.1f}°  {int(rs):>8} / {int(rg):<8} {flag}')
    print('paleta coherente con la ortofoto' if not bad else f'{bad} clases a revisar')
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
