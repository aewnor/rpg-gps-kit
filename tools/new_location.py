#!/usr/bin/env python3
"""Prepara el kit per a un joc nou a partir d'unes coordenades GPS.

  python3 tools/new_location.py --name "Altafulla" --lat 41.1418 --lon 1.3786 [--size-km 3.2] [--offline]

1. Escriu data/world.json: esquina noroest del mapa, latitud de referència (el centre), 4 m per tile i el costat
   en tiles (múltiple de 32, el tros de mapa del motor). Totes les eines la llegeixen per tools/osmlib.py.
2. Descarrega l'OpenStreetMap del rectangle (Overpass API) → cartography/municipio.osm.gz, i el límit del
   municipi que conté el punt (admin_level 8), si n'hi ha, → cartography/limite.osm.gz.
3. Deixa en blanc les dades que eren d'un altre lloc (monuments, serveis, botigues reals, noms de lloc, retocs
   del mapa, misions del poble): el joc funciona sense i es poden omplir després (vegeu SKILL.md).

Després: make maps && make validate && love .   (o make all, que també refà gràfics)
OSM: © OpenStreetMap contributors, ODbL. Cal citar-ho als crèdits del joc.
"""
import argparse
import gzip
import json
import math
import os
import shutil
import sys
import time
import urllib.parse
import urllib.request

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CART = os.path.join(ROOT, 'cartography')
R = 6371000.0
OVERPASS = ['https://overpass-api.de/api/interpreter', 'https://overpass.kumi.systems/api/interpreter']
UA = {'User-Agent': 'rpg-gps-kit/1.0 (joc local)'}

BLANK = {
    'data/landmarks.json': {},
    'data/place_names.json': {'_doc': 'Noms de lloc que no són a OSM: "way/<id>": {"name": "..."}'},
    'data/locals.json': {'_doc': 'Botigues i locals reals (tools/make_locals.py). Buit: només els d\'OSM.', 'locals': []},
    'maps/source/map-overrides.json': {'_doc': 'Retocs de la importació (tools/import_osm.py)', 'connections': [],
                                       'landmark_offsets': {}, 'ramps_add': [], 'ramps_remove': [], 'level_overrides': {},
                                       'level_overrides_reason': {}, 'buildings_clear': [], 'buildings_add': [],
                                       'extra_features': [], 'parking_pedestrian': {}, 'construction_sites': [],
                                       'fountains': []},
    'maps/source/map-edits.json': {'cells': {}},
    'maps/source/npcs.json': [],
    'maps/source/nuclis.json': {'_doc': 'Nuclis de població (tools/nuclis.py)', 'nuclis': []},
    'maps/source/solar.json': {'_doc': 'Plaques solars detectades (tools/solar_detect.py)', 'attribution': '', 'cells': [],
                               'buildings': {}},
}


def overpass(query, timeout=300):
    data = urllib.parse.urlencode({'data': query}).encode()
    last = None
    for url in OVERPASS:
        for k in range(3):
            try:
                req = urllib.request.Request(url, data=data, headers=UA)
                with urllib.request.urlopen(req, timeout=timeout) as r:
                    return r.read()
            except Exception as e:  # noqa: BLE001
                last = e
                print('  Overpass:', url, e)
                time.sleep(5 + 10 * k)
    raise SystemExit(f'No s\'ha pogut descarregar l\'OSM: {last}')


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('--name', required=True, help='nom del lloc (títol del joc)')
    ap.add_argument('--lat', type=float, required=True)
    ap.add_argument('--lon', type=float, required=True)
    ap.add_argument('--size-km', type=float, default=3.2, help='costat del mapa (per defecte 3,2 km; Roda: 6,4)')
    ap.add_argument('--offline', action='store_true', help='no descarregar (ja hi ha cartography/municipio.osm.gz)')
    a = ap.parse_args()

    tile_m = 4.0
    tiles = max(256, int(round(a.size_km * 1000 / tile_m / 32)) * 32)
    half = tiles * tile_m / 2
    k_lat = math.pi * R / 180.0
    k_lon = k_lat * math.cos(math.radians(a.lat))
    lat0, lon0 = a.lat + half / k_lat, a.lon - half / k_lon     # esquina noroest
    lat1, lon1 = a.lat - half / k_lat, a.lon + half / k_lon     # esquina sud-est

    wpath = os.path.join(ROOT, 'data/world.json')
    w = json.load(open(wpath, encoding='utf-8'))
    w.update({'name': a.name, 'origin_lon': round(lon0, 6), 'origin_lat': round(lat0, 6), 'reference_lat': round(a.lat, 6),
              'center_lat': a.lat, 'center_lon': a.lon, 'width_tiles': tiles, 'height_tiles': tiles,
              'meters_per_tile_approx': tile_m, 'pois': []})
    w['cars'] = {'speed': 60, 'gap': 40, 'count': {}}   # (densitat per ruta: per defecte, una cada ~600 px)
    w.pop('source_bbox_se', None)   # (el mapa nou és tot el rectangle descarregat)
    with open(wpath, 'w', encoding='utf-8') as f:
        json.dump(w, f, ensure_ascii=False, indent=2)
    # identitat de LÖVE (carpeta de partides) pròpia de cada joc: si no, dos jocs compartirien desades
    import re
    import unicodedata
    slug = re.sub(r'[^a-z0-9]+', '-', unicodedata.normalize('NFKD', a.name.lower()).encode('ascii', 'ignore').decode()).strip('-')
    conf = os.path.join(ROOT, 'conf.lua')
    txt = open(conf, encoding='utf-8').read()
    txt = re.sub(r"t\.identity = '[^']*'", f"t.identity = 'rpg-{slug or 'gps'}'", txt)
    txt = re.sub(r"t\.window\.title = '[^']*'", f"t.window.title = '{a.name.replace(chr(39), ' ')}'", txt)
    open(conf, 'w', encoding='utf-8').write(txt)
    print(f'world.json: {a.name}, {tiles}×{tiles} tiles ({tiles * tile_m / 1000:.1f} km), NO {lat0:.5f},{lon0:.5f}')

    os.makedirs(CART, exist_ok=True)
    for rel, v in BLANK.items():
        p = os.path.join(ROOT, rel)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, 'w', encoding='utf-8') as f:
            json.dump(v, f, ensure_ascii=False, indent=1)

    if not a.offline:
        bbox = f'{lat1},{lon0},{lat0},{lon1}'
        print('Descarregant OSM del rectangle', bbox, '...')
        # (rel: només multipolígons; els límits i les rutes portarien mig país)
        raw = overpass(f'[out:xml][timeout:280];(node({bbox});way({bbox});rel({bbox})["type"="multipolygon"];);(._;>;);out body;')
        with gzip.open(os.path.join(CART, 'municipio.osm.gz'), 'wb') as f:
            f.write(raw)
        print(f'  municipio.osm.gz: {len(raw) // 1024} KB')
        print('Límit del municipi ...')
        try:
            raw = overpass(f'[out:xml][timeout:120];is_in({a.lat},{a.lon})->.a;'
                           'rel(pivot.a)["boundary"="administrative"]["admin_level"="8"];(._;>;);out body;', 150)
            with gzip.open(os.path.join(CART, 'limite.osm.gz'), 'wb') as f:
                f.write(raw)
        except SystemExit as e:
            print('  sense límit:', e)
    # fonts que només eren d'un altre lloc
    for rel in ('cartography/world-plan.json', 'cartography/puntos-interes.csv', 'cartography/comerc-rodadebera.json'):
        p = os.path.join(ROOT, rel)
        if os.path.exists(p):
            os.remove(p)
    for d in ('cartography/derived', 'cartography/sat', 'cartography/catastro'):
        shutil.rmtree(os.path.join(ROOT, d), ignore_errors=True)
    print('Fet. Ara: make newmaps (serveis, missions i mapa) && make validate && love .')


if __name__ == '__main__':
    sys.exit(main())
