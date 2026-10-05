#!/usr/bin/env python3
"""Placas solares reales als teulats, a partir de l'ortofoto PNOA de màxima resolució de l'IGN (WMS públic,
CC BY 4.0: «PNOA cedido por © Instituto Geográfico Nacional»).

  python3 tools/solar_detect.py            # baixa els blocs que faltin (memòria cau) i detecta
  python3 tools/solar_detect.py --offline  # només amb els blocs ja baixats

Es demana l'ortofoto per blocs de 96 × 96 caselles a 16 px per casella (0,25 m/px) només on hi ha edificis
(maps/source/semantic.npz). Una casella d'edifici és placa si molts dels seus píxels són blau fosc i saturat
(les teules, els terrats grisos i les piscines no ho són). Sortida: maps/source/solar.json
{cells: [[x, y]…], buildings: {id_edifici: nombre de caselles}}, que llegeix tools/decorate_map.py.
"""
import io
import json
import math
import os
import sys
import time
import urllib.request

import numpy as np
from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import osmlib  # noqa: E402

CACHE = os.path.join(ROOT, 'cartography/sat/hr')
OUT = os.path.join(ROOT, 'maps/source/solar.json')
BLOCK = 96          # caselles per bloc
PXT = 16            # píxels per casella (0,25 m/px)
WMS = ('https://www.ign.es/wms-inspire/pnoa-ma?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap'
       '&LAYERS=OI.OrthoimageCoverage&STYLES=&CRS=EPSG:4326&BBOX={bbox}&WIDTH={w}&HEIGHT={h}&FORMAT=image/jpeg')
MIN_FRAC = 0.25     # fracció de píxels de placa perquè la casella es dibuixi amb placa
MIN_AREA = 0.8      # caselles equivalents de placa (≈ 13 m²) perquè l'edifici en tingui: menys és soroll


def block_bbox(bx, by):
    lon0, lat0 = osmlib.from_tile(bx, by)
    lon1, lat1 = osmlib.from_tile(bx + BLOCK, by + BLOCK)
    return min(lat0, lat1), min(lon0, lon1), max(lat0, lat1), max(lon0, lon1)


def fetch(bx, by, offline):
    path = os.path.join(CACHE, f'blk_{bx}_{by}.jpg')
    if os.path.exists(path):
        return Image.open(path).convert('RGB')
    if offline:
        return None
    la0, lo0, la1, lo1 = block_bbox(bx, by)
    url = WMS.format(bbox=f'{la0},{lo0},{la1},{lo1}', w=BLOCK * PXT, h=BLOCK * PXT)
    for attempt in range(3):
        try:
            data = urllib.request.urlopen(urllib.request.Request(url, headers={'User-Agent': 'roda-rpg/1.0 (joc familiar)'}),
                                          timeout=60).read()
            im = Image.open(io.BytesIO(data)).convert('RGB')
            os.makedirs(CACHE, exist_ok=True)
            im.save(path, quality=90)
            time.sleep(1.0)     # amb calma: és un servei públic
            return im
        except Exception as e:  # noqa: BLE001
            print(f'  bloc {bx},{by}: {e}; reintent {attempt + 1}')
            time.sleep(5 * (attempt + 1))
    return None


def panel_mask(a):
    """Píxels de placa: blau marí fosc (b−r entre 8 i 40, verd com el vermell), no el gris dels terrats
    (b < r), ni les teules, ni el turquesa de les piscines (verd i blau molt per sobre del vermell)."""
    r, g, b = a[..., 0].astype(int), a[..., 1].astype(int), a[..., 2].astype(int)
    lum = (r + g + b) / 3
    return (b - r >= 8) & (b - r <= 40) & (g - r <= 12) & (lum > 35) & (lum < 115)


def main():
    offline = '--offline' in sys.argv
    sm = np.load(os.path.join(ROOT, 'maps/source/semantic.npz'))
    bld = sm['bld']
    H, W = bld.shape
    cells, per_b = [], {}
    blocks = [(bx, by) for by in range(0, H, BLOCK) for bx in range(0, W, BLOCK)
              if (bld[by:by + BLOCK, bx:bx + BLOCK] > 0).sum() >= 30]
    print(f'{len(blocks)} blocs amb edificis')
    for k, (bx, by) in enumerate(blocks):
        im = fetch(bx, by, offline)
        if im is None:
            continue
        a = np.asarray(im.resize((BLOCK * PXT, BLOCK * PXT)))
        pm = panel_mask(a)
        frac = pm.reshape(BLOCK, PXT, BLOCK, PXT).mean(axis=(1, 3))
        sub = bld[by:by + BLOCK, bx:bx + BLOCK]
        ys, xs = np.nonzero((frac[:sub.shape[0], :sub.shape[1]] >= 0.08) & (sub > 0))
        for y, x in zip(ys.tolist(), xs.tolist()):
            b = int(sub[y, x])
            per_b.setdefault(b, []).append((bx + x, by + y, float(frac[y, x])))
        if (k + 1) % 10 == 0:
            print(f'  {k + 1}/{len(blocks)} blocs')
    good = {}
    for b, cs in per_b.items():
        area = sum(f for _, _, f in cs)
        strong = [(x, y) for x, y, f in cs if f >= MIN_FRAC]
        if area >= MIN_AREA and strong:
            cells.extend(strong)
            good[str(b)] = round(area, 1)
    with open(OUT, 'w') as f:
        json.dump({'_doc': __doc__.strip().splitlines()[0], 'attribution': 'PNOA cedido por © Instituto Geográfico Nacional',
                   'cells': sorted(cells), 'buildings': good}, f, indent=0)
    print(f'placas: {len(cells)} caselles en {len(good)} edificis → {os.path.relpath(OUT, ROOT)}')


if __name__ == '__main__':
    main()
