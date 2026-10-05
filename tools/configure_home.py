#!/usr/bin/env python3
"""Configura la casa del jugador en el directorio de datos LOCAL de LÖVE (nunca en el repositorio).

Uso:
  configure_home.py --lonlat LON,LAT               # coordenadas
  configure_home.py --street "Nom del carrer"     # extremo de la calle (OSM) más cercano al centro
  configure_home.py --tile 315,302
  configure_home.py --clear                      # volver al spawn público
Opciones: --dir RUTA (por defecto ~/.local/share/love/roda-rpg)

Valida escena, límites, colisión y acceso a pie desde spawn_public_centre; si falla, NO escribe y
explica por qué (el juego también lo valida al arrancar y usa el spawn público con aviso).
"""
import argparse
import json
import math
import os
import sys

import numpy as np

import compile_maps
import walkgraph
from osmlib import OSM, to_tile, from_tile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--lonlat')
    ap.add_argument('--street')
    ap.add_argument('--tile')
    ap.add_argument('--clear', action='store_true')
    ap.add_argument('--dir', default=os.path.expanduser('~/.local/share/love/roda-rpg'))
    a = ap.parse_args()
    os.makedirs(a.dir, exist_ok=True)
    path = os.path.join(a.dir, 'home.json')
    if a.clear:
        if os.path.exists(path):
            os.remove(path)
        print('Casa eliminada: el juego usará spawn_public_centre.')
        return 0
    m = compile_maps.compile_map(os.path.join(ROOT, 'maps/source/overworld.tmj'))
    coll = m['coll']
    H, W = coll.shape
    spawn = next(o for o in m['objects'] if o['type'] == 'spawn' and o['name'] == 'spawn_public_centre')
    sx, sy = int(spawn['x'] // 16), int(spawn['y'] // 16)
    if a.tile:
        tx, ty = (int(v) for v in a.tile.split(','))
    elif a.lonlat:
        lon, lat = (float(v) for v in a.lonlat.split(','))
        tx, ty = to_tile(lon, lat)
    elif a.street:
        osm = OSM(os.path.join(ROOT, 'cartography/municipio.osm.gz'))
        ends = []
        for wid, (t, refs) in osm.ways.items():
            if a.street.lower() in (t.get('name') or '').lower() and t.get('highway'):
                for r in (refs[0], refs[-1]):
                    ends.append(to_tile(*osm.nodes[r]))
        if not ends:
            print('Calle no encontrada en el extracto OSM.')
            return 1
        tx, ty = min(ends, key=lambda p: (p[0] - sx) ** 2 + (p[1] - sy) ** 2)
    else:
        ap.print_help()
        return 1
    if not (0 <= tx < W and 0 <= ty < H):
        print(f'({tx},{ty}) fuera de los límites del mapa.')
        return 1
    # la casa ocupa una celda transitable: buscar la más cercana si la exacta está bloqueada
    best = None
    for r in range(0, 6):
        for y in range(ty - r, ty + r + 1):
            for x in range(tx - r, tx + r + 1):
                if 0 <= x < W and 0 <= y < H and coll[y, x] == 0 and (best is None or
                        (x - tx) ** 2 + (y - ty) ** 2 < (best[0] - tx) ** 2 + (best[1] - ty) ** 2):
                    best = (x, y)
        if best:
            break
    if not best:
        print('No hay ninguna celda transitable cerca.')
        return 1
    if m['comp'][best[1], best[0]] != m['comp'][sy, sx]:
        print('La casa no tiene acceso a pie desde el centro.')
        return 1
    lon, lat = from_tile(*best)
    cfg = {'configured': True, 'scene': 'overworld', 'tile_x': int(best[0]), 'tile_y': int(best[1]),
           'lon': round(lon, 6), 'lat': round(lat, 6)}
    with open(path, 'w') as f:
        json.dump(cfg, f, indent=1)
    os.chmod(path, 0o600)
    moved = '' if best == (tx, ty) else f' (ajustada desde {tx},{ty})'
    print(f'Casa configurada en tile {best}{moved}. Archivo local: {path}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
