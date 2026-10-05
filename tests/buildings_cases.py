#!/usr/bin/env python3
"""Pruebas del enderezado y vestido de edificios (tools/buildings.py). Uso: python3 tests/buildings_cases.py"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import buildings as B  # noqa: E402

fails = 0


def check(c, m):
    global fails
    print(('OK   ' if c else 'FAIL ') + m)
    fails += not c


def raster_rect(H, W, cx, cy, w, h, ang):
    """Rectángulo girado `ang` grados rasterizado por el centro de cada celda (como la huella del Catastro)."""
    yy, xx = np.mgrid[0:H, 0:W]
    a = math.radians(ang)
    px, py = xx + .5 - cx, yy + .5 - cy
    u, v = px * math.cos(a) + py * math.sin(a), -px * math.sin(a) + py * math.cos(a)
    return (abs(u) <= w / 2) & (abs(v) <= h / 2)


def is_axis_rect(m):
    ys, xs = np.nonzero(m)
    return len(ys) and m[ys.min():ys.max() + 1, xs.min():xs.max() + 1].all()


H = W = 60
# 1) casa de 7 × 4 girada 25°: sale un rectángulo alineado, mismo centro y casi la misma superficie
bld = np.zeros((H, W), np.int32)
m = raster_rect(H, W, 30, 30, 7, 4, 25)
bld[m] = 1
out, st = B.straighten(bld, np.zeros((H, W), bool))
o = out == 1
check(is_axis_rect(o), f'casa girada 25° → rectángulo alineado ({st})')
check(abs(int(o.sum()) - int(m.sum())) <= max(3, m.sum() * .2), f'superficie conservada ({m.sum()} → {o.sum()})')
ys, xs = np.nonzero(o)
check(abs(xs.mean() - 29.5) < 1.5 and abs(ys.mean() - 29.5) < 1.5, 'mismo centro')
check(np.ptp(xs) + 1 > np.ptp(ys) + 1, 'conserva la orientación (más ancha que alta)')

# 2) una sola fachada: la fila de abajo es continua (antes, una por peldaño de la escalera)
bottoms = {x: ys[xs == x].max() for x in set(xs.tolist())}
check(len(set(bottoms.values())) == 1, 'una única fila de fachada')

# 3) una calle que atraviesa el objetivo: el edificio no la pisa
blocked = np.zeros((H, W), bool)
blocked[:, 31] = True
out, st = B.straighten(bld, blocked)
check(not (out[:, 31] > 0).any(), 'no pisa la calle')
check((out == 1).sum() >= 6 and is_axis_rect(out == 1), 'recortado al mayor rectángulo libre')

# 4) forma en L girada: se endereza sin perder la L (no se convierte en rectángulo)
bld = np.zeros((H, W), np.int32)
L = raster_rect(H, W, 30, 30, 12, 4, 30) | raster_rect(H, W, 30 + 4 * math.cos(math.radians(30)) - 2 * math.sin(math.radians(30)),
                                                      30 + 4 * math.sin(math.radians(30)) + 3, 4, 10, 30)
bld[L] = 2
out, st = B.straighten(bld, np.zeros((H, W), bool))
o = out == 2
fill = o.sum() / ((np.ptp(np.nonzero(o)[0]) + 1) * (np.ptp(np.nonzero(o)[1]) + 1))
check(o.sum() > 0.6 * L.sum() and fill < 0.95, f'forma en L enderezada (relleno {fill:.2f})')

# 5) sin tiras de 1 casilla ni edificios diminutos
bld = np.zeros((H, W), np.int32)
bld[10:16, 10] = 3            # tira vertical de 1 de ancho
bld[40, 40] = 4               # caseta de 1 celda
out, st = B.straighten(bld, np.zeros((H, W), bool))
same_h = np.zeros_like(out, bool)
same_h[:, 1:] |= out[:, 1:] == out[:, :-1]
same_h[:, :-1] |= out[:, :-1] == out[:, 1:]
check(not ((out > 0) & ~same_h).any(), 'sin tiras de 1 casilla de ancho (la tira se ensancha o se quita)')
check(not (out == 4).any(), 'sin casetas sueltas de 1 celda')

# 6) vestido: casa con cumbrera (vertientes n/k/s), puerta hacia la calle y fachada continua
bld = np.zeros((H, W), np.int32)
bld[10:15, 10:16] = 1
binfo = [None, {'kind': 'house', 'rgb': [190, 90, 70], 'floors': 1}]
names = {}
tid = lambda n: names.setdefault(n, len(names) + 1)
walk = lambda y, x: 0 <= y < H and 0 <= x < W and bld[y, x] == 0
out, stats = B.dress(bld, binfo, tid, walk, lambda y, x: False)
inv = {v: k for k, v in names.items()}
row = lambda y: [inv[out[(y, x)]] for x in range(10, 16)]
check(all(n.startswith('f_') for n in row(14)), 'fila de abajo: fachada')
check(sum(n.endswith('_door') for n in row(14)) == 1, 'una puerta')
parts = {n.split('_')[2] for y in range(10, 14) for n in row(y)}
check({'n', 'k', 's'} <= parts, f'tejado de teja con vertientes y cumbrera {sorted(parts)}')
check(binfo[1]['roof'] == 'terra', 'color de tejado de la ortofoto (teja)')

# 7) bloque de pisos: azotea y plantas altas con balcones encima de los bajos
bld = np.zeros((H, W), np.int32)
bld[20:27, 20:28] = 1
binfo = [None, {'kind': 'apartments', 'floors': 5, 'rgb': [200, 200, 200]}]
names.clear()
out, stats = B.dress(bld, binfo, tid, walk, lambda y, x: True)
inv = {v: k for k, v in names.items()}
check(all(inv[out[(25, x)]].endswith('_up') for x in range(20, 28)), 'planta alta de pisos («up»)')
check(binfo[1]['cls'] == 'apartments' and inv[out[(21, 22)]].startswith('r_flat'), 'azotea en los pisos')

# tiendas grandes del OSM con building=yes (Bonpreu, Leroy Merlin): nave de techo plano, no casa de teja
sup = B.style({'kind': 'yes', 'shop': 'supermarket', 'rgb': [200, 90, 70]}, 7, 200)
check(sup['cls'] == 'retail' and sup['roof'] == 'flat', 'supermercado con building=yes: techo plano')
hall = B.style({'kind': 'sports_hall'}, 8, 180)
check(hall['cls'] == 'civic' and hall['roof'] == 'metal', 'pabellón deportivo: cubierta metálica')
casa = B.style({'kind': 'yes', 'rgb': [200, 90, 70]}, 9, 20)
check(casa['cls'] == 'house', 'sin tienda, building=yes sigue siendo casa')

# casas adosadas del catastro (4 parcelas de 2×3 pegadas): una hilera con un color y una puerta por casa
import realdata  # noqa: E402
rb = np.zeros((10, 14), np.int32)
rinfo = [None]
for k in range(4):
    rb[3:6, 2 + 2 * k:4 + 2 * k] = len(rinfo)
    rinfo.append({'src': 'catastro', 'kind': 'house', 'floors': 2})
rb[3:6, 12:14] = len(rinfo); rinfo.append({'src': 'catastro', 'kind': 'house', 'floors': 2})   # suelta (no toca)
rb[3:6, 11] = 0
n_m = realdata.merge_rows(rb, rinfo)
check(n_m == 3 and len(np.unique(rb[3:6, 2:10])) == 1, 'cuatro adosadas → una hilera')
check(rinfo[1].get('walls') and rinfo[1].get('row_houses') == 4, 'la hilera lleva colores por casa')
check(rb[4, 12] == 5, 'la casa separada sigue sola')

print('TODAS LAS PRUEBAS DE EDIFICIOS OK' if not fails else f'{fails} FALLOS')
sys.exit(1 if fails else 0)
