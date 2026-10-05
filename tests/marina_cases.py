#!/usr/bin/env python3
"""Puerto deportivo (tools/realdata.marina) con una ortofoto sintética: muelle ancho, dos pantalanes de
dos casillas con barcos blancos al lado y mar abierto fuera del dique (python3 tests/marina_cases.py)."""
import os
import sys

import numpy as np
from scipy import ndimage

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import realdata  # noqa: E402
from semantic import G, D  # noqa: E402

fails = 0


def check(cond, msg):
    global fails
    print(('OK   ' if cond else 'FAIL ') + msg)
    if not cond:
        fails += 1


H, W = 40, 40
WATER, QUAY, BOAT = (30, 70, 110), (160, 155, 150), (245, 245, 245)
rgb = np.zeros((H, W, 3), np.uint8)
rgb[:, :] = WATER
mask = np.zeros((H, W), bool)
mask[5:35, 5:35] = True
rgb[5:12, 5:35] = QUAY                 # muelle de 7 casillas arriba
rgb[5:35, 30:35] = QUAY                # dique a la derecha (da al mar abierto)
for x0 in (12, 21):                    # dos pantalanes de 2 casillas que bajan del muelle
    rgb[12:28, x0:x0 + 2] = QUAY
    rgb[14:26:3, x0 + 2:x0 + 4] = BOAT  # barcos amarrados al lado
ground = np.full((H, W), G['URBAN'], np.uint8)
ground[~mask] = G['SEA']
ground[:5, :] = G['DRY']               # tierra al norte
d0 = np.zeros((H, W), np.uint8)
rd = {'rgb': rgb}
water, quay, piers, rocks = realdata.marina(rd, ground, d0, mask, G['SEA'], D['PIER'])

pier = d0 == D['PIER']
check(piers > 0 and pier.sum() == piers, f'hay pantalanes ({piers} casillas)')
for x0 in (12, 21):
    cols = pier[14:26, x0 - 1:x0 + 3].sum(axis=1)
    check((cols == 1).all(), f'el pantalán de x={x0} es de una casilla de ancho')
    check(pier[26, x0 - 1:x0 + 3].any() or pier[25, x0 - 1:x0 + 3].any(), f'el pantalán de x={x0} llega hasta el final')
quay_m = mask & (ground != G['SEA'])
lab, _ = ndimage.label(quay_m | pier)
check(len(set(lab[pier]) | set(lab[quay_m])) == 1, 'pantalanes unidos al muelle (todo conectado a pie)')
check((ground[14:26, 14:20] == G['SEA']).all(), 'los barcos blancos quedan en el agua, no en tierra')
check(rocks > 0 and (ground[5:35, 34] == G['ROCK']).any(), 'escollera en la cara del dique que da al mar')
check(not (ground[5:12, 9:28] == G['ROCK']).any(), 'sin rocas en el muelle interior')
check((d0[7, 8:28] == D['PEDESTRIAN']).all(), 'el muelle es de paviment, no de madera')
# una balsa cerrada por el muelle (sin salida al mar) no puede quedar como mar aislado
rgb2 = rgb.copy(); rgb2[7:10, 26:29] = WATER
g2 = np.full((H, W), G['URBAN'], np.uint8); g2[~mask] = G['SEA']; g2[:5, :] = G['DRY']
d2 = np.zeros((H, W), np.uint8)
realdata.marina({'rgb': rgb2}, g2, d2, mask, G['SEA'], D['PIER'])
lab2, _ = ndimage.label(g2 == G['SEA'])
check(len(set(lab2[g2 == G['SEA']])) == 1, 'sin mar aislado dentro del muelle')
print('TODAS LAS PRUEBAS DEL PUERTO OK' if not fails else f'{fails} FALLOS')
sys.exit(1 if fails else 0)
