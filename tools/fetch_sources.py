"""Descarga y prepara las fuentes oficiales que complementan OSM.

  · Ortofoto PNOA (IGN, CC BY 4.0) por WMS → mosaico 4 px/tile (cartography/sat/pnoa.jpg, no versionado)
  · MDT 5 m (IGN, CC BY 4.0) por WCS → altura por tile
  · Edificios y piscinas del Catastro (INSPIRE, ATOM por municipio) → huellas en coordenadas de tile

Salidas versionadas (compactas): cartography/derived/terrain.npz (altura, color medio del satélite por tile
y estadísticas de vegetación) y cartography/derived/catastro.json.gz.
Uso: python3 tools/fetch_sources.py [--offline]  (--offline reutiliza lo ya descargado)
"""
import gzip
import io
import json
import math
import os
import re
import sys
import time
import urllib.request
import zipfile
import xml.etree.ElementTree as ET

import numpy as np
from PIL import Image

from osmlib import MAP_TILES, ORIGIN_LAT, ORIGIN_LON, from_tile, to_tile_f

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CART = os.path.join(ROOT, 'cartography')
SAT = os.path.join(CART, 'sat')
OUT = os.path.join(CART, 'derived')
PX = 4  # píxeles de ortofoto por tile (1 m/px)
LON0, LAT0 = from_tile(-0.5, -0.5)
LON1, LAT1 = from_tile(MAP_TILES - 0.5, MAP_TILES - 0.5)
MUNICIPIOS = ['43133-RODA DE BERA', '43051-CREIXELL', '43030-BONASTRE', '43165-EL VENDRELL',
              '43113-LA POBLA DE MONTORNES']
UA = {'User-Agent': 'roda-rpg/1.0 (juego local)'}


def get(url, timeout=120):
    for k in range(4):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as r:
                return r.read()
        except Exception as e:  # noqa: BLE001
            if k == 3:
                raise
            print('  reintento', e)
            time.sleep(2 + 3 * k)


# ------------------------------------------------------------------ ortofoto
def fetch_pnoa(offline):
    os.makedirs(SAT, exist_ok=True)
    n = MAP_TILES * PX
    step = 800
    full = Image.new('RGB', (n, n))
    for j in range(0, n, step):
        for i in range(0, n, step):
            f = os.path.join(SAT, f'pnoa_{i}_{j}.jpg')
            if not os.path.exists(f):
                if offline:
                    raise SystemExit(f'falta {f}')
                lo0 = LON0 + (LON1 - LON0) * i / n
                lo1 = LON0 + (LON1 - LON0) * (i + step) / n
                la0 = LAT0 + (LAT1 - LAT0) * j / n
                la1 = LAT0 + (LAT1 - LAT0) * (j + step) / n
                url = ('https://www.ign.es/wms-inspire/pnoa-ma?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetMap'
                       '&LAYERS=OI.OrthoimageCoverage&STYLES=&CRS=EPSG:4326'
                       f'&BBOX={min(la0, la1)},{lo0},{max(la0, la1)},{lo1}&WIDTH={step}&HEIGHT={step}&FORMAT=image/jpeg')
                data = get(url)
                Image.open(io.BytesIO(data)).verify()
                open(f, 'wb').write(data)
                print('  pnoa', i, j)
            full.paste(Image.open(f).convert('RGB'), (i, j))
    full.save(os.path.join(SAT, 'pnoa.jpg'), quality=88)
    return np.asarray(full)


# ------------------------------------------------------------------ relieve
def fetch_mdt(offline):
    os.makedirs(SAT, exist_ok=True)
    f = os.path.join(SAT, 'mdt.tif')
    if not os.path.exists(f):
        if offline:
            raise SystemExit(f'falta {f}')
        url = ('https://servicios.idee.es/wcs-inspire/mdt?SERVICE=WCS&VERSION=2.0.1&REQUEST=GetCoverage'
               f'&CoverageId=Elevacion4258_5&SUBSET=Lat({LAT1 - 0.001},{LAT0 + 0.001})'
               f'&SUBSET=Long({LON0 - 0.001},{LON1 + 0.001})&FORMAT=image/tiff')
        open(f, 'wb').write(get(url, 300))
    im = Image.open(f)
    sx, sy, _ = im.tag_v2[33550]
    _, _, _, lon_tl, lat_tl, _ = im.tag_v2[33922]
    a = np.asarray(im).astype(np.float32)
    a[a < -100] = 0  # sin dato (mar)
    # muestreo bilineal en el centro de cada tile
    ty, tx = np.mgrid[0:MAP_TILES, 0:MAP_TILES].astype(np.float64)
    lon = LON0 + (tx + 0.5) / MAP_TILES * (LON1 - LON0)
    lat = LAT0 + (ty + 0.5) / MAP_TILES * (LAT1 - LAT0)
    fx = np.clip((lon - lon_tl) / sx - 0.5, 0, a.shape[1] - 1.001)
    fy = np.clip((lat_tl - lat) / sy - 0.5, 0, a.shape[0] - 1.001)
    x0, y0 = fx.astype(int), fy.astype(int)
    ax, ay = fx - x0, fy - y0
    e = (a[y0, x0] * (1 - ax) * (1 - ay) + a[y0, x0 + 1] * ax * (1 - ay)
         + a[y0 + 1, x0] * (1 - ax) * ay + a[y0 + 1, x0 + 1] * ax * ay)
    return np.maximum(e, 0)


# ------------------------------------------------------------------ catastro
def utm_to_lonlat(E, N, zone=31):
    """UTM (ETRS89/GRS80) → lon, lat en grados. Fórmulas de Snyder/Karney de orden suficiente (< 1 cm)."""
    a, f = 6378137.0, 1 / 298.257222101
    k0 = 0.9996
    e2 = f * (2 - f)
    ep2 = e2 / (1 - e2)
    x = E - 500000.0
    M = N / k0
    mu = M / (a * (1 - e2 / 4 - 3 * e2 ** 2 / 64 - 5 * e2 ** 3 / 256))
    e1 = (1 - math.sqrt(1 - e2)) / (1 + math.sqrt(1 - e2))
    p1 = (mu + (3 * e1 / 2 - 27 * e1 ** 3 / 32) * math.sin(2 * mu) + (21 * e1 ** 2 / 16 - 55 * e1 ** 4 / 32) * math.sin(4 * mu)
          + (151 * e1 ** 3 / 96) * math.sin(6 * mu) + (1097 * e1 ** 4 / 512) * math.sin(8 * mu))
    C1 = ep2 * math.cos(p1) ** 2
    T1 = math.tan(p1) ** 2
    N1 = a / math.sqrt(1 - e2 * math.sin(p1) ** 2)
    R1 = a * (1 - e2) / (1 - e2 * math.sin(p1) ** 2) ** 1.5
    D = x / (N1 * k0)
    lat = p1 - (N1 * math.tan(p1) / R1) * (D ** 2 / 2 - (5 + 3 * T1 + 10 * C1 - 4 * C1 ** 2 - 9 * ep2) * D ** 4 / 24
                                          + (61 + 90 * T1 + 298 * C1 + 45 * T1 ** 2 - 252 * ep2 - 3 * C1 ** 2) * D ** 6 / 720)
    lon = (D - (1 + 2 * T1 + C1) * D ** 3 / 6 + (5 - 2 * C1 + 28 * T1 - 3 * C1 ** 2 + 8 * ep2 + 24 * T1 ** 2) * D ** 5 / 120) / math.cos(p1)
    return math.degrees(lon) + (zone * 6 - 183), math.degrees(lat)


GML = '{http://www.opengis.net/gml/3.2}'


def parse_polys(elem):
    out = []
    polys = [e for e in elem.iter() if e.tag in (GML + 'Polygon', GML + 'PolygonPatch')]
    for poly in polys:
        rings = []
        for ring_tag in ('exterior', 'interior'):
            for r in poly.iter(GML + ring_tag):
                pl = r.find('.//' + GML + 'posList')
                if pl is None:
                    continue
                v = list(map(float, pl.text.split()))
                pts = []
                for k in range(0, len(v) - 1, 2):
                    lon, lat = utm_to_lonlat(v[k], v[k + 1])
                    x, y = to_tile_f(lon, lat)
                    pts.append((round(x, 2), round(y, 2)))
                rings.append((ring_tag, pts))
        out.append({'outer': next((p for t, p in rings if t == 'exterior'), []),
                    'holes': [p for t, p in rings if t == 'interior']})
    return out


def fetch_catastro(offline):
    d = os.path.join(CART, 'catastro')
    os.makedirs(d, exist_ok=True)
    buildings, pools, parts = [], [], {}
    for m in MUNICIPIOS:
        code = m.split('-')[0]
        f = os.path.join(d, f'BU.{code}.zip')
        if not os.path.exists(f):
            if offline:
                raise SystemExit(f'falta {f}')
            url = ('https://www.catastro.hacienda.gob.es/INSPIRE/Buildings/43/' + m.replace(' ', '%20')
                   + f'/A.ES.SDGC.BU.{code}.zip')
            open(f, 'wb').write(get(url, 300))
        z = zipfile.ZipFile(f)
        names = z.namelist()
        # plantas sobre rasante por edificio (máximo de sus partes)
        bp = next(n for n in names if n.endswith('buildingpart.gml'))
        for _, el in ET.iterparse(z.open(bp)):
            if el.tag.endswith('}BuildingPart'):
                gid = el.get(GML + 'id', '')
                fl = el.find('.//{*}numberOfFloorsAboveGround')
                ref = re.sub(r'_part\d+$', '', gid.replace('ES.SDGC.BU.', ''))
                try:
                    n = int(fl.text) if fl is not None and fl.text else 0
                except ValueError:
                    n = 0
                parts[ref] = max(parts.get(ref, 0), n)
                el.clear()
        bf = next(n for n in names if n.endswith('.building.gml'))
        for _, el in ET.iterparse(z.open(bf)):
            if el.tag.endswith('}Building') and 'Part' not in el.tag:
                ref = el.get(GML + 'id', '').replace('ES.SDGC.BU.', '')
                use = el.find('.//{*}currentUse')
                cond = el.find('.//{*}conditionOfConstruction')
                for p in parse_polys(el):
                    xs = [q[0] for q in p['outer']]
                    ys = [q[1] for q in p['outer']]
                    if not xs or max(xs) < 0 or max(ys) < 0 or min(xs) > MAP_TILES or min(ys) > MAP_TILES:
                        continue
                    buildings.append({'ref': ref, 'use': (use.text if use is not None else '') or '',
                                      'cond': (cond.text if cond is not None else '') or '',
                                      'floors': parts.get(ref, 0), **p})
                el.clear()
        of = next(n for n in names if n.endswith('otherconstruction.gml'))
        for _, el in ET.iterparse(z.open(of)):
            if el.tag.endswith('}OtherConstruction'):
                nat = el.find('.//{*}constructionNature')
                if nat is not None and nat.text == 'openAirPool':
                    for p in parse_polys(el):
                        xs = [q[0] for q in p['outer']]
                        if xs and 0 <= min(xs) and max(xs) <= MAP_TILES:
                            pools.append(p)
                el.clear()
        print(f'  catastro {m}: {len(buildings)} edificios, {len(pools)} piscinas acumulados')
    return {'source': 'Dirección General del Catastro (INSPIRE)', 'buildings': buildings, 'pools': pools}


def main():
    offline = '--offline' in sys.argv
    os.makedirs(OUT, exist_ok=True)
    print('catastro…')
    cat = fetch_catastro(offline)
    with gzip.open(os.path.join(OUT, 'catastro.json.gz'), 'wt') as f:
        json.dump(cat, f, separators=(',', ':'))
    print('relieve…')
    elev = fetch_mdt(offline)
    print('ortofoto…')
    img = fetch_pnoa(offline).astype(np.float32)
    n = MAP_TILES
    blocks = img.reshape(n, PX, n, PX, 3)
    mean = blocks.mean(axis=(1, 3))
    r, g, b = blocks[..., 0], blocks[..., 1], blocks[..., 2]
    exg = 2 * g - r - b                      # índice de verdor por píxel
    lum = (r + g + b) / 3
    canopy = ((exg > 12) & (lum < 95)).mean(axis=(1, 3))   # copa de árbol: verde y oscuro
    green = (exg > 8).mean(axis=(1, 3))
    np.savez_compressed(os.path.join(OUT, 'terrain.npz'), elev=elev.astype(np.float16),
                        rgb=mean.clip(0, 255).astype(np.uint8),
                        canopy=(canopy * 255).astype(np.uint8), green=(green * 255).astype(np.uint8))
    print('ok', 'altura', float(elev.min()), float(elev.max()), 'edificios', len(cat['buildings']),
          'piscinas', len(cat['pools']))


if __name__ == '__main__':
    main()
