"""Lectura de extractos OSM y conversión geográfica → tiles.

Proyección local equirectangular esférica del plan (sección «Conversión a grid»).
Sin dependencias GIS: ElementTree + aritmética.
"""
import gzip
import math
import xml.etree.ElementTree as ET

import json
import os

R = 6371000.0
# La ubicación del juego vive en data/world.json (la escribe tools/new_location.py): esquina noroeste del mapa,
# latitud de referencia (centro), metros por tile y lado en tiles. Valores por defecto: Roda de Berà.
_WORLD = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'world.json')
try:
    with open(_WORLD, encoding='utf-8') as _f:
        _w = json.load(_f)
except (OSError, ValueError):
    _w = {}
ORIGIN_LON = float(_w.get('origin_lon', 1.425))
ORIGIN_LAT = float(_w.get('origin_lat', 41.215))
REF_LAT = float(_w.get('reference_lat', 41.1875))
M_PER_TILE = float(_w.get('meters_per_tile_approx', 4.0))   # metros por tile (a 10 las calles no se reconocían)
MAP_TILES = int(_w.get('width_tiles', 1600))                 # 1600 tiles = 6,4 km de lado


def m2t(meters):
    """Metros → tiles (flotante)."""
    return meters / M_PER_TILE
K_LAT = math.pi * R / 180.0
K_LON = K_LAT * math.cos(math.radians(REF_LAT))


def to_tile_f(lon, lat):
    """Coordenadas de tile en coma flotante (origen noroeste, X este, Y sur)."""
    return ((lon - ORIGIN_LON) * K_LON / M_PER_TILE,
            (ORIGIN_LAT - lat) * K_LAT / M_PER_TILE)


def to_tile(lon, lat):
    x, y = to_tile_f(lon, lat)
    return math.floor(x), math.floor(y)


def from_tile(tx, ty):
    """Centro de un tile → lon/lat."""
    return (ORIGIN_LON + (tx + 0.5) * M_PER_TILE / K_LON,
            ORIGIN_LAT - (ty + 0.5) * M_PER_TILE / K_LAT)


class OSM:
    def __init__(self, path):
        opener = gzip.open if path.endswith('.gz') else open
        with opener(path, 'rb') as f:
            root = ET.parse(f).getroot()
        self.nodes = {}
        self.node_tags = {}
        for n in root.iter('node'):
            nid = n.get('id')
            self.nodes[nid] = (float(n.get('lon')), float(n.get('lat')))
            tags = {t.get('k'): t.get('v') for t in n.findall('tag')}
            if tags:
                self.node_tags[nid] = tags
        self.ways = {}
        for w in root.iter('way'):
            tags = {t.get('k'): t.get('v') for t in w.findall('tag')}
            refs = [nd.get('ref') for nd in w.findall('nd')]
            self.ways[w.get('id')] = (tags, refs)
        self.relations = {}
        for r in root.iter('relation'):
            tags = {t.get('k'): t.get('v') for t in r.findall('tag')}
            members = [(m.get('type'), m.get('ref'), m.get('role')) for m in r.findall('member')]
            self.relations[r.get('id')] = (tags, members)

    def way_coords(self, wid):
        _, refs = self.ways[wid]
        return [self.nodes[r] for r in refs if r in self.nodes]

    def way_tiles(self, wid):
        return [to_tile_f(*c) for c in self.way_coords(wid)]

    def multipolygon_rings(self, rid):
        """Devuelve (outer_rings, inner_rings) en lon/lat uniendo miembros abiertos."""
        _, members = self.relations[rid]
        result = {'outer': [], 'inner': []}
        for role in ('outer', 'inner'):
            segs = [self.ways[ref][1] for typ, ref, rl in members
                    if typ == 'way' and (rl or 'outer') == role and ref in self.ways]
            for ring in join_segments(segs):
                pts = [self.nodes[r] for r in ring if r in self.nodes]
                if len(pts) >= 3:
                    result[role].append(pts)
        return result['outer'], result['inner']


def join_segments(segs):
    """Une listas de refs por extremos comunes. Devuelve anillos o cadenas abiertas."""
    segs = [list(s) for s in segs if len(s) >= 2]
    out = []
    while segs:
        cur = segs.pop(0)
        changed = True
        while changed and cur[0] != cur[-1]:
            changed = False
            for i, s in enumerate(segs):
                if s[0] == cur[-1]:
                    cur += s[1:]
                elif s[-1] == cur[-1]:
                    cur += s[::-1][1:]
                elif s[-1] == cur[0]:
                    cur = s + cur[1:]
                elif s[0] == cur[0]:
                    cur = s[::-1] + cur[1:]
                else:
                    continue
                segs.pop(i)
                changed = True
                break
        out.append(cur)
    return out
