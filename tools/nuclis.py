"""Cascos antiguos compactos (maps/source/nuclis.json): nucli antic de Roda, Roc de Sant Gaietà, Creixell.

En un casco antiguo las calles miden 3-5 m y las casas van en hilera con 4-5 m de fachada. Con las reglas
generales (calles residenciales de 8 m = 2 casillas y sin edificios de 1 casilla de ancho) desaparecían
manzanas enteras y el Roc o el nucli no se reconocían. Aquí:
  - street_m: anchura de calles residenciales/peatonales, caminos y escaleras dentro del círculo
  - merge_blocks: las casas que se tocan se unen en una manzana (un edificio con tejado continuo)
  - en buildings.dress, cada tramo de 2-3 casillas de fachada lleva su color (paleta `walls`) y su puerta
"""
import json
import math
import os

import numpy as np
from scipy import ndimage

from osmlib import m2t, to_tile_f

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PATH = os.path.join(ROOT, 'maps/source/nuclis.json')
NARROW = ('residential', 'living_street', 'service', 'unclassified', 'pedestrian', 'footway', 'steps', 'path',
          'track', 'cycleway', 'bridleway')


def load():
    try:
        with open(PATH, encoding='utf-8') as f:
            data = json.load(f)
    except (OSError, ValueError):
        return []
    out = []
    for n in data.get('nuclis', []):
        cx, cy = to_tile_f(*n['center'])
        out.append(dict(n, cx=cx, cy=cy, r=m2t(n['radius_m'])))
    return out


NUCLIS = load()


def which(x, y):
    """Núcleo (dict) que contiene el punto de tile (x, y), o None."""
    for n in NUCLIS:
        if math.hypot(x - n['cx'], y - n['cy']) < n['r']:
            return n
    return None


def way_nucli(pts, share=0.6):
    """Núcleo de una vía si al menos `share` de sus puntos están dentro."""
    if not pts:
        return None
    for n in NUCLIS:
        inside = sum(1 for x, y in pts if math.hypot(x - n['cx'], y - n['cy']) < n['r'])
        if inside >= share * len(pts):
            return n
    return None


def mask(H, W):
    """Índice de núcleo + 1 por celda (0 = fuera)."""
    m = np.zeros((H, W), np.uint8)
    yy, xx = np.mgrid[0:H, 0:W]
    for i, n in enumerate(NUCLIS, 1):
        m[((xx + .5 - n['cx']) ** 2 + (yy + .5 - n['cy']) ** 2 < n['r'] ** 2) & (m == 0)] = i
    return m


def merge_blocks(bld, binfo, nmask):
    """Une las casas que se tocan (4-vecinos) dentro de un núcleo en una sola manzana. Modifica bld y
    binfo en su sitio; devuelve cuántos edificios se han unido."""
    inside = (bld > 0) & (nmask > 0)
    lab, n = ndimage.label(inside)
    merged = 0
    for k, sl in enumerate(ndimage.find_objects(lab), 1):
        if sl is None:
            continue
        cells = lab[sl] == k
        ids, counts = np.unique(bld[sl][cells], return_counts=True)
        if len(ids) < 2:
            continue
        main = int(ids[np.argmax(counts)])
        info = binfo[main]
        rgbs = [binfo[i].get('rgb') for i in ids if binfo[i].get('rgb')]
        if rgbs:
            info['rgb'] = [float(v) for v in np.mean(rgbs, axis=0)]
        info['floors'] = max(int(binfo[i].get('floors') or 1) for i in ids)
        if info.get('kind') in ('apartments', None, 'yes', 'house', 'residential'):
            info['kind'] = 'house'
        sub = bld[sl]
        sub[cells] = main
        merged += len(ids) - 1
    # el núcleo de cada edificio (paleta y tramos de fachada en buildings.dress)
    for b, sl in enumerate(ndimage.find_objects(bld), 1):
        if sl is None or b >= len(binfo) or binfo[b] is None:
            continue
        nm = nmask[sl][bld[sl] == b]
        if len(nm) and (nm > 0).mean() > 0.5:
            n = NUCLIS[int(np.bincount(nm[nm > 0]).argmax()) - 1]
            binfo[b]['nucli'] = n['id']
            binfo[b]['walls'] = n['walls']
            binfo[b]['nucli_roof'] = n.get('roof', 'terra')
    return merged
