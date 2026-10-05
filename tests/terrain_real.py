#!/usr/bin/env python3
"""Comprobaciones del mapa real tras importar (ejecutar desde tools/): torrentes infranqueables,
bordes de roca sólidos, edificios del Catastro y accesos (cd tools && python3 ../tests/terrain_real.py)."""
import json
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import semantic as sem  # noqa: E402
import walkgraph  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
fails = 0


def check(cond, msg):
    global fails
    print(('OK   ' if cond else 'FAIL ') + msg)
    if not cond:
        fails += 1


d = np.load(os.path.join(ROOT, 'maps/source/semantic.npz'))
coll, d0 = d['coll'], d['d0']
rep = json.load(open(os.path.join(ROOT, 'maps/source/import-report.json')))
tor = d0 == sem.D['TORRENT']
check(tor.sum() > 500, f'hay lecho de torrente ({int(tor.sum())} celdas)')
walk0 = (coll & 3) == 0
check(not (tor & walk0).any(), 'ninguna celda del lecho es transitable a pie (nivel 0)')
# cruzar en línea recta: desde cada orilla, a 1–4 celdas, no se llega a la orilla opuesta sin pasar por el lecho
H, W = coll.shape
ys, xs = np.nonzero(tor)
probe = 0
for k in range(0, len(ys), max(1, len(ys) // 400)):
    y, x = ys[k], xs[k]
    for dy, dx in ((0, 1), (1, 0)):
        a = b = None
        for t in range(1, 6):
            yy, xx = y - dy * t, x - dx * t
            if 0 <= yy < H and 0 <= xx < W and not tor[yy, xx]:
                a = (yy, xx); break
        for t in range(1, 6):
            yy, xx = y + dy * t, x + dx * t
            if 0 <= yy < H and 0 <= xx < W and not tor[yy, xx]:
                b = (yy, xx); break
        if a and b and walk0[a] and walk0[b]:
            seg = [(y + dy * t, x + dx * t) for t in range(-(abs(a[0] - y) + abs(a[1] - x)) + 1,
                                                           abs(b[0] - y) + abs(b[1] - x))]
            if all(not walk0[p] for p in seg if tor[p]):
                probe += 1
check(probe > 50, f'{probe} cruces rectos sondeados: todos bloqueados por el lecho')
ledge_cells = rep.get('ledge_cells', 0)
check(ledge_cells > 10000, f'relieve: {ledge_cells} celdas con borde de roca, niveles {rep.get("terrain_levels")}')
check(rep.get('access_stairs', 0) > 0, f'escaleras de acceso abiertas: {rep.get("access_stairs")}')
check(rep.get('generated_houses', 1) == 0 and rep.get('catastro_buildings', 0) > 5000,
      f'edificios reales del Catastro: {rep.get("catastro_buildings")} (casas inventadas: {rep.get("generated_houses")})')
check(rep.get('pools', 0) > 1000, f'piscinas del Catastro: {rep.get("pools")}')
check(not any('fuera de la zona principal' in w for w in rep['warnings']), 'todos los POI siguen accesibles')
# accesos laterales trampa: celda de doble nivel sin rampa junto a lo que solo se cruza por arriba/abajo
tmj = json.load(open(os.path.join(ROOT, 'maps/source/overworld.tmj')))
lay = {l['name']: l for l in tmj['layers']}
cf = tmj['tilesets'][1]['firstgid']
cc = np.maximum(np.array(lay['collision']['data']).reshape(tmj['height'], tmj['width']) - cf, 0)
w0 = ((cc & 3) == 0) & ((cc & 32) == 0)
traps = 0
for bit in (4, 8):
    over = ((cc & bit) > 0) & ~w0
    P = np.pad(over, 1)
    near = P[:-2, 1:-1] | P[2:, 1:-1] | P[1:-1, :-2] | P[1:-1, 2:]
    traps += int((w0 & ((cc & bit) > 0) & ((cc & 16) == 0) & near).sum())
check(traps == 0, f'accesos laterales a puentes/túneles sin rampa: {traps}')
print('TODAS OK' if not fails else f'FALLOS: {fails}')
sys.exit(1 if fails else 0)
