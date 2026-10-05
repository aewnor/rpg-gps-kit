#!/usr/bin/env python3
"""Detalles urbanos sobre el mapa importado (se ejecuta entre import_osm.py y compile_maps.py).

Modifica maps/source/overworld.tmj en su sitio (rápido; no hace falta reimportar):
  · puentes y pasos inferiores: barandillas (PARAPET), sombra del tablero (SHADOW) y boca oscura (SHADE)
  · pasos de peatones (ZEBRA + objeto 'crosswalk': los coches paran si estás encima)
  · aparcamientos de superficie con plazas y coches aparcados (objetos 'parked_car')
  · parques: césped, parterres, bancos, farolas, papeleras y fuente; parques infantiles con columpio y tobogán
  · nodos OSM: bancos, árboles, farolas, papeleras
  · farolas a lo largo de las calles con casas (las enciende el ciclo día/noche)
  · paradas de bus (marquesina + objeto 'bus_stop': viaje rápido entre paradas)
Nunca bloquea pasillos: un objeto sólido solo va en una celda libre con casi todo su entorno libre.
"""
import json
import math
import os
import random

import numpy as np

import semantic as sem
import terrain_blend
import walkgraph
from osmlib import OSM, to_tile_f, m2t

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
TMJ = os.path.join(ROOT, 'maps/source/overworld.tmj')
RAW = os.path.join(ROOT, 'maps/source/overworld.raw.json')   # copia sin decorar (no versionada)
OVERRIDES = json.load(open(os.path.join(ROOT, 'maps/source/map-overrides.json')))
DECO_TYPES = {'farm_pen', 'farmer', 'beach_flag', 'errand', 'sailboat', 'solar_house', 'fountain', 'crosswalk', 'parked_car', 'bus_stop', 'pickup', 'park', 'signboard', 'prop', 'school', 'spot'}
WALK, SOLID = 0, 1
N, E, S_, W_ = 1, 2, 4, 8   # veïns per a les peces amb vora (marquesines)
D, G = sem.D, sem.G
rng = random.Random(20261002)


class Map:
    def __init__(self):
        cur = json.load(open(TMJ))
        decorated = any(o['type'] in DECO_TYPES for l in cur['layers'] if l['type'] == 'objectgroup' for o in l['objects'])
        if not decorated:      # recién importado: guardar la copia limpia
            with open(RAW + '.tmp', 'w') as f:
                json.dump(cur, f, separators=(',', ':'))
            os.replace(RAW + '.tmp', RAW)
        elif not os.path.exists(RAW):
            raise SystemExit('el mapa ya está decorado y no hay copia limpia: ejecuta antes tools/import_osm.py')
        self.tmj = cur if not decorated else json.load(open(RAW))
        self.W, self.H = self.tmj['width'], self.tmj['height']
        self.tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
        self.name_of = {t['id'] + 1: n for n, t in self.tiles.items()}
        self.cf = self.tmj['tilesets'][1]['firstgid']
        self.layers = {l['name']: l for l in self.tmj['layers']}
        self.L = {}
        for name in ('ground', 'ground_detail', 'structures', 'overhead', 'collision'):
            self.L[name] = np.array(self.layers[name]['data'], np.int64).reshape(self.H, self.W)
        self.coll = np.where(self.L['collision'] > 0, self.L['collision'] - self.cf, 0)
        sm = np.load(os.path.join(ROOT, 'maps/source/semantic.npz'))
        self.d0, self.bld, self.ground = sm['d0'], sm['bld'], sm['ground']
        self.objects = self.layers['objects']['objects']
        self.next_id = 1 + max(o['id'] for l in self.tmj['layers'] if l['type'] == 'objectgroup' for o in l['objects'])
        self.placed = np.zeros((self.H, self.W), bool)

    def gid(self, name):
        return self.tiles[name]['id'] + 1

    def is_name(self, layer, x, y, prefix):
        n = self.name_of.get(int(self.L[layer][y, x]) & 0x1FFFFFFF, '')
        return n.startswith(prefix)

    def free(self, x, y, strict=True):
        """Celda vacía y transitable, fuera de vías y no delante de una fachada."""
        if not (1 <= x < self.W - 1 and 1 <= y < self.H - 1):
            return False
        if self.coll[y, x] != WALK or self.L['structures'][y, x] or self.L['ground_detail'][y, x] or self.d0[y, x]:
            return False
        if self.placed[y, x] or self.is_name('structures', x, y - 1, 'f_') or self.is_name('structures', x, y + 1, 'f_'):
            return False
        if strict:  # no estrangular pasillos: casi todo el entorno 3×3 libre
            around = sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                         if (dx or dy) and self.coll[y + dy, x + dx] == WALK and not self.placed[y + dy, x + dx])
            if around < 7:
                return False
        return True

    def put(self, x, y, name, layer='structures', solid=True):
        self.L[layer][y, x] = self.gid(name)
        if solid:
            self.coll[y, x] = SOLID
            self.placed[y, x] = True

    def obj(self, type_, x, y, props=None, name=''):
        o = {'id': self.next_id, 'name': name or f'{type_}_{self.next_id}', 'type': type_, 'x': round(x, 1),
             'y': round(y, 1), 'width': 0, 'height': 0, 'rotation': 0, 'visible': True, 'point': True,
             'properties': [{'name': k, 'type': 'int' if isinstance(v, int) and not isinstance(v, bool) else
                             'bool' if isinstance(v, bool) else 'float' if isinstance(v, float) else 'string', 'value': v}
                            for k, v in (props or {}).items()]}
        self.next_id += 1
        self.objects.append(o)
        return o

    def line(self, cls, level, w, pts, closed=False):
        lobjs = self.layers['lines']['objects']
        x0, y0 = pts[0]
        lobjs.append({'id': self.next_id, 'name': '', 'type': 'line', 'x': x0, 'y': y0, 'width': 0, 'height': 0,
                      'rotation': 0, 'visible': True,
                      'polyline': [{'x': round(px - x0, 1), 'y': round(py - y0, 1)} for px, py in pts],
                      'properties': [{'name': 'cls', 'type': 'string', 'value': cls},
                                     {'name': 'level', 'type': 'int', 'value': level},
                                     {'name': 'w', 'type': 'int', 'value': int(w)},
                                     {'name': 'closed', 'type': 'bool', 'value': closed},
                                     {'name': 'osm', 'type': 'string', 'value': 'deco'}]})
        self.next_id += 1

    def sync_tileset(self):
        """tiles.tsj (lo escribe import_osm.py) al número de tiles actual del atlas."""
        p = os.path.join(ROOT, 'maps/source/tiles.tsj')
        tsj = json.load(open(p))
        n = len(self.tiles)
        tsj['tilecount'] = n
        tsj['imageheight'] = 16 * ((n + 31) // 32)
        tsj['wangsets'] = terrain_blend.wangsets(self.tiles)   # autotiling de terreno en Tiled
        # animacions dels tiles nous (les fonts): el compilador les llegeix del tileset
        props = {p['id']: p for p in tsj.get('tiles', [])}
        for name, t in self.tiles.items():
            if t.get('anim') and name.endswith('_0') and t['id'] not in props:
                tsj.setdefault('tiles', []).append({'id': t['id'], 'properties': [{'name': 'name', 'type': 'string', 'value': name}]})
                props[t['id']] = tsj['tiles'][-1]
            if t.get('anim') and name.endswith('_0') and 'animation' not in props[t['id']]:
                base = name[:-2]
                props[t['id']]['animation'] = [{'tileid': self.tiles[f'{base}_{f}']['id'], 'duration': 250}
                                               for f in range(t['anim'])]
        with open(p, 'w') as f:
            json.dump(tsj, f, indent=1)

    def save(self):
        self.sync_tileset()
        for name in ('ground', 'ground_detail', 'structures', 'overhead'):
            self.layers[name]['data'] = [int(v) for v in self.L[name].ravel()]
        self.layers['collision']['data'] = [int(self.cf + c) for c in self.coll.ravel()]
        tmp = TMJ + '.tmp'
        with open(tmp, 'w') as f:
            json.dump(self.tmj, f, separators=(',', ':'), default=lambda v: v.item())
        os.replace(tmp, TMJ)


# ------------------------------------------------------------------ geometría de líneas
def read_lines(m):
    out = []
    for o in m.layers['lines']['objects']:
        p = {q['name']: q['value'] for q in o.get('properties', [])}
        if p.get('osm') == 'deco':
            continue
        pts = [(o['x'] + q['x'], o['y'] + q['y']) for q in o['polyline']]
        xs, ys = [q[0] for q in pts], [q[1] for q in pts]
        out.append({'cls': p['cls'], 'level': p.get('level', 0), 'w': p.get('w', 16), 'pts': pts,
                    'bb': (min(xs), min(ys), max(xs), max(ys))})
    return out


def seg_inter(a, b, c, d):
    """Intersección de los segmentos ab y cd → (t en ab, punto) o None."""
    r = (b[0] - a[0], b[1] - a[1])
    s = (d[0] - c[0], d[1] - c[1])
    den = r[0] * s[1] - r[1] * s[0]
    if abs(den) < 1e-9:
        return None
    t = ((c[0] - a[0]) * s[1] - (c[1] - a[1]) * s[0]) / den
    u = ((c[0] - a[0]) * r[1] - (c[1] - a[1]) * r[0]) / den
    if 0 <= t <= 1 and 0 <= u <= 1:
        return t, (a[0] + t * r[0], a[1] + t * r[1])
    return None


def cumlen(pts):
    acc = [0.0]
    for p, q in zip(pts, pts[1:]):
        acc.append(acc[-1] + math.dist(p, q))
    return acc


def sub_polyline(pts, s0, s1):
    acc = cumlen(pts)
    s0, s1 = max(0, s0), min(acc[-1], s1)

    def at(s):
        for i in range(len(pts) - 1):
            if acc[i + 1] >= s:
                seg = acc[i + 1] - acc[i] or 1
                k = (s - acc[i]) / seg
                return (pts[i][0] + (pts[i + 1][0] - pts[i][0]) * k, pts[i][1] + (pts[i + 1][1] - pts[i][1]) * k), i
        return pts[-1], len(pts) - 2
    p0, i0 = at(s0)
    p1, i1 = at(s1)
    return [p0] + pts[i0 + 1:i1 + 1] + [p1]


def crossings(m, lines):
    """Barandillas/sombras de puentes y bocas de pasos inferiores donde se cruzan niveles."""
    kinds = {'ROAD', 'ROAD_MAIN', 'MOTORWAY', 'PEDESTRIAN', 'FOOTWAY', 'PATH', 'TRACK', 'STEPS', 'RAIL', 'RAIL_HS',
             'TORRENT', 'STREAM', 'PLATFORM'}
    n = 0
    for a in lines:
        if a['level'] == 0 or a['cls'] not in kinds:
            continue
        for b in lines:
            if b is a or b['cls'] not in kinds or b['level'] != a['level'] + (-1 if a['level'] > 0 else 1):
                continue
            if b['bb'][0] > a['bb'][2] or b['bb'][2] < a['bb'][0] or b['bb'][1] > a['bb'][3] or b['bb'][3] < a['bb'][1]:
                continue
            acc_a, acc_b = cumlen(a['pts']), cumlen(b['pts'])
            for i in range(len(a['pts']) - 1):
                for j in range(len(b['pts']) - 1):
                    hit = seg_inter(a['pts'][i], a['pts'][i + 1], b['pts'][j], b['pts'][j + 1])
                    if not hit:
                        continue
                    t, p = hit
                    sa = acc_a[i] + t * (acc_a[i + 1] - acc_a[i])
                    sb = acc_b[j] + math.dist(b['pts'][j], p)
                    if a['level'] > 0:   # a = puente sobre b
                        span = b['w'] / 2 + 12
                        deck = sub_polyline(a['pts'], sa - span, sa + span)
                        m.line('SHADOW', 1, a['w'], deck)
                        m.line('PARAPET', 1, a['w'], deck)
                    else:                # a = paso inferior bajo b
                        half = b['w'] / 2
                        for s0, s1 in ((sa - half - 16, sa - half + 1), (sa + half - 1, sa + half + 16)):
                            m.line('SHADE', -1, a['w'], sub_polyline(a['pts'], s0, s1))  # bocas del paso
                        if b['cls'] not in ('RAIL', 'RAIL_HS', 'TORRENT', 'STREAM'):
                            m.line('PARAPET', 0, b['w'], sub_polyline(b['pts'], sb - a['w'] / 2 - 8, sb + a['w'] / 2 + 8))
                    n += 1
    return n


def nearest_line(lines, x, y, classes, level=0, maxd=24):
    best = None
    for it in lines:
        if it['cls'] not in classes or it['level'] != level:
            continue
        bb = it['bb']
        if x < bb[0] - maxd or x > bb[2] + maxd or y < bb[1] - maxd or y > bb[3] + maxd:
            continue
        for p, q in zip(it['pts'], it['pts'][1:]):
            vx, vy = q[0] - p[0], q[1] - p[1]
            L2 = vx * vx + vy * vy or 1
            t = max(0, min(1, ((x - p[0]) * vx + (y - p[1]) * vy) / L2))
            px, py = p[0] + t * vx, p[1] + t * vy
            d = math.hypot(px - x, py - y)
            if d <= maxd and (best is None or d < best[0]):
                ln = math.sqrt(L2)
                best = (d, it, (px, py), (vx / ln, vy / ln))
    return best


def crosswalks(m, lines, osm):
    n = 0
    for nid, tags in osm.node_tags.items():
        if tags.get('highway') != 'crossing' or nid not in osm.nodes:
            continue
        tx, ty = to_tile_f(*osm.nodes[nid])
        x, y = tx * 16, ty * 16
        hit = nearest_line(lines, x, y, ('ROAD', 'ROAD_MAIN'), 0, 14)
        if not hit:
            continue
        _, it, (px, py), (ux, uy) = hit
        half = it['w'] / 2
        nx, ny = -uy, ux
        m.line('ZEBRA', 0, 12, [(px - nx * half, py - ny * half), (px + nx * half, py + ny * half)])
        m.obj('crosswalk', px, py, {'r': int(half + 6)})
        n += 1
    return n


# ------------------------------------------------------------------ áreas
def area_cells(osm, wid):
    pts = osm.way_tiles(wid)
    if len(pts) < 3:
        return None
    return sem.local_cells([pts], 'poly', 1, 0.5)


def parkings(m, osm):
    n_cells = n_cars = 0
    areas = []
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('amenity') != 'parking' or tags.get('parking') in ('underground', 'multi-storey', 'rooftop'):
            continue
        loc = area_cells(osm, wid)
        if loc is None:
            continue
        if wid in OVERRIDES.get('parking_pedestrian', {}):   # a l'OSM és aparcament però és una plaça per a vianants
            y0, x0, msk = loc
            for cy, cx in zip(*np.nonzero(msk)):
                x, y = x0 + cx, y0 + cy
                if m.coll[y, x] == WALK and not m.L['structures'][y, x] and not m.bld[y, x] and not m.d0[y, x]:
                    m.put(x, y, f'g_cobble_{(x + y) % 3}', 'ground', solid=False)
            continue
        areas.append((wid, loc))
    # aparcamientos que el OSM no tiene (map-overrides.json → extra_features, rectángulos en casillas)
    for i, f in enumerate(OVERRIDES.get('extra_features', [])):
        if f.get('type') == 'parking':
            x0, y0, x1, y1 = f['rect']
            areas.append((f'extra{i}', (y0, x0, np.ones((y1 - y0 + 1, x1 - x0 + 1), bool)), f.get('surface')))
    areas = [a if len(a) == 3 else (a[0], a[1], None) for a in areas]
    for wid, (y0, x0, msk), surface in areas:
        pk = set()
        for cy, cx in zip(*np.nonzero(msk)):
            x, y = x0 + cx, y0 + cy
            if m.coll[y, x] == WALK and not m.L['structures'][y, x] and not m.bld[y, x] and not m.d0[y, x]:
                if surface == 'dirt':     # aparcament de terra (el del camp de futbol): terra trepitjada amb roderes
                    m.put(x, y, f'g_site_{(x * 7 + y * 3) % 3}', 'ground', solid=False)
                else:
                    m.put(x, y, f'g_parking_{(x // 2) % 2}', 'ground', solid=False)
                pk.add((x, y))
                n_cells += 1
        # coches aparcados: en los aparcamientos más altos que anchos van en horizontal (2 celdas de ancho,
        # filas alternas); en el resto, en vertical (2 celdas de alto), con hueco entre ellos.
        # Colores 1-14: 4 clásicos + 8 modelos car2 + 2 furgonetas van2 (world_scene draw_car)
        horiz = msk.shape[0] > msk.shape[1] * 1.2
        prng = random.Random(wid)
        for cy, cx in zip(*np.nonzero(msk)):
            x, y = x0 + cx, y0 + cy
            if horiz:
                if y % 2 or prng.random() > 0.45:
                    continue
                cells = [(x, y), (x + 1, y)]
                around = [(x + k, y + dy) for k in (0, 1) for dy in (-1, 1)]
            else:
                if x % 2 or prng.random() > 0.45:
                    continue
                cells = [(x, y), (x, y + 1)]
                around = [(x + dx, y + k) for k in (0, 1) for dx in (-1, 1)]
            if not all((cx_, cy_) in pk and m.free(cx_, cy_, strict=False) for cx_, cy_ in cells):
                continue
            if any(m.placed[ay, ax] for ax, ay in around):
                continue
            for cx_, cy_ in cells:
                m.coll[cy_, cx_] = SOLID
                m.placed[cy_, cx_] = True
            if horiz:
                m.obj('parked_car', (x + 1) * 16, y * 16 + 8, {'color': prng.randrange(1, 15), 'orient': 'h'})
            else:
                m.obj('parked_car', x * 16 + 8, (y + 1) * 16, {'color': prng.randrange(1, 15), 'orient': 'v'})
            n_cars += 1
    return n_cells, n_cars


PARK_CLASSES = ('grass', 'tree', 'paving', 'earth')


def park_classes(rd, cells):
    """Classe de cada casella d'un parc o plaça a partir de l'ortofoto (realdata: canopy, green, rgb):
    copa d'arbre, gespa, paviment (clar o a l'ombra) o terra (sauló). Filtre de majoria 3×3 perquè no
    quedi «pebre» de caselles soltes."""
    raw = {}
    for x, y in cells:
        can, grn = float(rd['canopy'][y, x]), float(rd['green'][y, x])
        lum = float(rd['rgb'][y, x].astype(np.float32).mean())
        if can >= 0.45:
            c = 'tree'
        elif grn >= 0.5:
            c = 'grass'
        elif lum >= 170 or lum < 110:
            c = 'paving'
        else:
            c = 'earth'
        raw[(x, y)] = c
    out = {}
    for (x, y), c in raw.items():
        votes = {}
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                k = raw.get((x + dx, y + dy))
                if k:
                    votes[k] = votes.get(k, 0) + (2 if dx == dy == 0 else 1)
        out[(x, y)] = max(votes, key=lambda k: (votes[k], k == c))
    return out


def parks(m, osm, rd=None, names=None):
    """Parcs, jardins i places reconstruïts amb l'ortofoto real (gespa, arbres, paviment i sauló on de
    debò n'hi ha) dins del polígon de l'OSM; bancs i fanals a la vora entre gespa i camí, font als grans
    i un objecte 'park' amb el nom (data/place_names.json per als que l'OSM no anomena)."""
    stats = {'parks': 0, 'benches': 0, 'lamps': 0, 'fountains': 0, 'flowers': 0, 'play': 0, 'trees': 0,
             'named': 0, 'cells': {c: 0 for c in PARK_CLASSES}}
    names = names or {}
    for wid, (tags, refs) in osm.ways.items():
        lei = tags.get('leisure')
        ov = names.get('way/' + wid, {})
        square = tags.get('place') == 'square' or (tags.get('highway') == 'pedestrian' and tags.get('area') == 'yes')
        if lei not in ('park', 'garden', 'playground') and not square and tags.get('landuse') != 'village_green' and not ov:
            continue
        loc = area_cells(osm, wid)
        if loc is None:
            continue
        y0, x0, msk = loc
        cells = [(x0 + cx, y0 + cy) for cy, cx in zip(*np.nonzero(msk))
                 if 1 <= x0 + cx < m.W - 1 and 2 <= y0 + cy < m.H - 1]
        if not cells:
            continue
        if lei == 'playground':
            for x, y in cells:
                if m.free(x, y, strict=False):
                    m.put(x, y, 'g_sandpit_0', 'ground', solid=False)
            free = [c for c in cells if m.free(*c)]
            rng.shuffle(free)
            kit = ['o_swing', 'o_slide', 'o_seesaw', 'o_springrider', 'o_climb', 'o_swing', 'o_springrider']
            n_kit = max(3, min(len(kit), len(cells) // 10))
            for name in kit[:n_kit] + ['o_bench']:
                if free:
                    x, y = free.pop()
                    if m.free(x, y):
                        m.put(x, y, name); stats['play'] += 1
            continue
        stats['parks'] += 1
        cls = park_classes(rd, cells) if rd is not None else {c: 'grass' for c in cells}
        lum = {c: float(rd['rgb'][c[1], c[0]].astype(np.float32).mean()) for c in cells} if rd is not None else {}
        q = np.percentile(list(lum.values()), [33, 66]) if lum else (0, 0)
        for (x, y), c in cls.items():
            if not m.free(x, y, strict=False) or m.is_name('ground', x, y, 'pool'):
                continue
            v = 0 if lum.get((x, y), 128) < q[0] else (2 if lum.get((x, y), 128) > q[1] else 1)
            stats['cells'][c] += 1
            if c == 'paving':
                m.put(x, y, f'g_cobble_{v}', 'ground', solid=False)
            elif c == 'earth':
                m.put(x, y, f'g_dry_{v}', 'ground', solid=False)
            else:
                m.put(x, y, f'g_park_{v}', 'ground', solid=False)
        # arbres on l'ortofoto mostra copes (si encara no n'hi ha cap a prop: l'import ja en posa)
        for (x, y), c in cls.items():
            if c != 'tree' or not m.free(x, y) or m.L['overhead'][y - 1, x] or m.L['structures'][y - 1, x]:
                continue
            if any(m.is_name('structures', x + dx, y + dy, 'tree_') for dx in (-1, 0, 1) for dy in (-1, 0, 1)):
                continue
            kind = 'olive' if rng.random() < .5 else ('palm' if rng.random() < .5 else 'pine0')
            m.put(x, y, f'tree_{kind}_bot')
            m.L['overhead'][y - 1, x] = m.gid(f'tree_{kind}_top')
            stats['trees'] += 1
        # vora gespa / camí: bancs i fanals; flors a la gespa
        edge = lambda x, y: cls.get((x, y)) == 'grass' and any(
            cls.get((x + dx, y + dy)) in ('paving', 'earth') or m.d0[y + dy, x + dx] in (D['FOOTWAY'], D['PATH'], D['PEDESTRIAN'])
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        k = 0
        for x, y in cells:
            if not m.free(x, y):
                continue
            if edge(x, y):
                k += 1
                if k % 6 == 0:
                    m.put(x, y, 'o_bench'); stats['benches'] += 1
                elif k % 9 == 4:
                    m.put(x, y, 'o_lamp'); stats['lamps'] += 1
                elif k % 13 == 7:
                    m.put(x, y, 'o_bin')
            elif cls.get((x, y)) == 'grass' and rng.random() < 0.04:
                m.put(x, y, 'g_flowers_%d' % rng.randrange(3), 'ground', solid=False); stats['flowers'] += 1
        if len(cells) > 200:
            grass = [c for c in cells if cls.get(c) == 'grass' and m.free(*c) and not edge(*c)]
            rng.shuffle(grass)
            for x, y in grass[:max(1, len(cells) // 400)]:
                if m.free(x, y):
                    m.put(x, y, 'o_picnic'); stats['play'] += 1
        cx = sum(c[0] for c in cells) / len(cells)
        cy = sum(c[1] for c in cells) / len(cells)
        if len(cells) > 120:
            for x, y in sorted(cells, key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2)[:40]:
                if m.free(x, y) and cls.get((x, y)) in ('paving', 'earth', 'grass'):
                    m.put(x, y, 'o_fountain'); stats['fountains'] += 1
                    break
        name = ov.get('name') or tags.get('name:ca') or tags.get('name')
        if name:
            m.obj('park', cx * 16 + 8, cy * 16 + 8, {'label': name, 'kind': 'square' if square else 'park',
                                                      'cells': len(cells), 'approx': bool(ov.get('approx'))})
            stats['named'] += 1
    return stats


# ------------------------------------------------------------------ fase 6: escoles, parc viari i tanques
def fence_pieces(m, cells, kind, stats_key, stats):
    """Col·loca tanques de tipus `kind` (wood | wall | mesh) a `cells` triant la peça segons els veïns."""
    S = set(cells)
    for x, y in cells:
        if not m.free(x, y, strict=False):
            continue
        hz = (x - 1, y) in S or (x + 1, y) in S
        vt = (x, y - 1) in S or (x, y + 1) in S
        part = 'h' if hz and not vt else ('v' if vt and not hz else 'c')
        m.put(x, y, f'o_{kind}_{part}')
        stats[stats_key] = stats.get(stats_key, 0) + 1


def poly_cells(osm, wid, m):
    loc = area_cells(osm, wid)
    if loc is None:
        return set()
    y0, x0, msk = loc
    return {(x0 + cx, y0 + cy) for cy, cx in zip(*np.nonzero(msk)) if 2 <= x0 + cx < m.W - 2 and 2 <= y0 + cy < m.H - 2}


def doors_in(m, cells):
    out = []
    for x, y in cells:
        if m.is_name('structures', x, y, 'f_') and 'door' in m.name_of.get(int(m.L['structures'][y, x]) & 0x1FFFFFFF, ''):
            out.append((x, y))
    return out


STREET = None


def schools(m, osm, rd):
    """Recintes escolars reconstruïts amb l'ortofoto: pati (formigó), pistes vermelles i verdes amb línies i
    cistelles, gespa, i la tanca de reixa del perímetre amb dues portes (una davant de l'edifici principal)."""
    st = {'schools': 0, 'yard': 0, 'court_red': 0, 'court_green': 0, 'grass': 0, 'mesh': 0, 'gates': 0, 'baskets': 0}
    street = {D['FOOTWAY'], D['PEDESTRIAN'], D['ROAD'], D['ROAD_MAIN'], D['PATH']}
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('amenity') not in ('school', 'kindergarten'):
            continue
        cells = poly_cells(osm, wid, m)
        if len(cells) < 20:
            continue
        st['schools'] += 1
        raw = {}
        for x, y in cells:
            if m.bld[y, x] or not m.free(x, y, strict=False) or m.d0[y, x]:
                continue
            r, g, b = (int(v) for v in rd['rgb'][y, x])
            grn, can = float(rd['green'][y, x]), float(rd['canopy'][y, x])
            if r > g + 22 and r > b + 30 and r > 100:
                c = 'red'
            elif g > r + 10 and g > b + 6 and can < 0.35 and grn >= 0.5:
                c = 'green' if (max(r, g, b) - min(r, g, b)) > 45 else 'grass'
            elif can >= 0.45 or grn >= 0.6:
                c = 'grass'
            else:
                c = 'yard'
            raw[(x, y)] = c
        cls = {}
        for (x, y), c in raw.items():      # majoria 3×3
            votes = {}
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    k = raw.get((x + dx, y + dy))
                    if k:
                        votes[k] = votes.get(k, 0) + (2 if dx == dy == 0 else 1)
            cls[(x, y)] = max(votes, key=lambda k: (votes[k], k == c))
        # pistes massa petites: pati
        for col in ('red', 'green'):
            cc = [c for c, k in cls.items() if k == col]
            if len(cc) < 12:
                for c in cc: cls[c] = 'yard'
        for (x, y), c in cls.items():
            v = (x * 7 + y * 3) % 2
            if c in ('red', 'green'):
                S = {q for q, k in cls.items() if k == c}
                up, dn = (x, y - 1) not in S, (x, y + 1) not in S
                lf, rt = (x - 1, y) not in S, (x + 1, y) not in S
                if up or dn: name = f'g_court_{c}_line_h'
                elif lf or rt: name = f'g_court_{c}_line_v'
                else: name = f'g_court_{c}_{v}'
                m.put(x, y, name, 'ground', solid=False)
                st['court_' + c] += 1
            elif c == 'grass':
                m.put(x, y, f'g_park_{v}', 'ground', solid=False); st['grass'] += 1
            else:
                m.put(x, y, f'g_yard_{v}', 'ground', solid=False); st['yard'] += 1
        # cistelles als extrems de les pistes vermelles grans
        red = [c for c, k in cls.items() if k == 'red']
        if len(red) >= 40:
            xs = [c[0] for c in red]; ys = [c[1] for c in red]
            cx = (min(xs) + max(xs)) // 2
            for y in (min(ys), max(ys)):
                if (cx, y) in cls and m.free(cx, y):
                    m.put(cx, y, 'o_basket'); st['baskets'] += 1
        # perímetre: cel·les del recinte que toquen l'exterior
        border = [(x, y) for x, y in cells if any((x + dx, y + dy) not in cells
                                                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        border = [c for c in border if m.free(c[0], c[1], strict=False)]
        # portes: la cel·la del perímetre que dona al carrer més propera a la porta de l'edifici, i una altra
        front = [c for c in border if any(int(m.d0[c[1] + dy, c[0] + dx]) in street
                                          for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        doors = doors_in(m, cells) or doors_in(m, {(x, y) for x, y in cells for _ in (0,)})
        target = (doors[0][0], doors[0][1] + 1) if doors else (sum(c[0] for c in cells) / len(cells), sum(c[1] for c in cells) / len(cells))
        gates = set()
        cand = sorted(front or border, key=lambda c: (c[0] - target[0]) ** 2 + (c[1] - target[1]) ** 2)
        if cand:
            g1 = cand[0]
            g2 = max(cand, key=lambda c: (c[0] - g1[0]) ** 2 + (c[1] - g1[1]) ** 2)
            for g in (g1, g2):
                for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)):
                    gates.add((g[0] + dx, g[1] + dy))
                st['gates'] += 1
        fence_pieces(m, [c for c in border if c not in gates], 'mesh', 'mesh', st)
        if doors:   # rètol de l'escola damunt de la porta principal
            m.obj('signboard', doors[0][0] * 16 + 8, (doors[0][1] - 1) * 16 + 4, {'sprite': 'sign_escola', 'extra': '',
                                                                               'service_id': '', 'flag': False})
        name = tags.get('name')
        if name:
            m.obj('school', sum(c[0] for c in cells) / len(cells) * 16 + 8, sum(c[1] for c in cells) / len(cells) * 16 + 8,
                  {'label': name})
    return st


def pitches(m, osm, rd):
    """Pistes esportives a l'aire lliure (leisure=pitch fora de les escoles) segons el color real de
    l'ortofoto: pista dura blava/grisa o vermella amb línies i cistelles; si és gespa, camp de gespa."""
    st = {'pitches': 0, 'baskets': 0}
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('leisure') != 'pitch' or tags.get('sport') in ('soccer', 'football'):
            continue
        cells = [c for c in poly_cells(osm, wid, m) if not m.bld[c[1], c[0]] and not m.d0[c[1], c[0]]
                 and m.free(c[0], c[1], strict=False) and not m.is_name('ground', c[0], c[1], 'g_court')]
        if len(cells) < 12:
            continue
        r, g, b = np.array([rd['rgb'][y, x] for x, y in cells], np.float32).mean(0)
        sport = tags.get('sport', '')
        if g > r + 5 and g > b + 10 and len(cells) > 200:
            continue                                   # camp de gespa gran: es queda el camp
        S = set(cells)
        st['pitches'] += 1
        if sport in ('boules', 'skateboard'):          # petanca de sauló; skatepark de formigó
            for x, y in cells:
                v = (x * 7 + y * 3) % 2
                m.put(x, y, f'g_sandpit_{v}' if sport == 'boules' else f'g_skate_{v}', 'ground', solid=False)
            continue
        col = 'red' if r > g + 12 else ('green' if sport == 'tennis' or (g > r + 5 and g > b + 10) else 'blue')
        for x, y in cells:
            up, dn = (x, y - 1) not in S, (x, y + 1) not in S
            lf, rt = (x - 1, y) not in S, (x + 1, y) not in S
            mid_h = y == (min(c[1] for c in cells) + max(c[1] for c in cells)) // 2
            pre = f'g_court_{col}_'
            if up or dn or mid_h: name = pre + 'line_h'
            elif lf or rt: name = pre + 'line_v'
            else: name = pre + str((x * 7 + y * 3) % 2)
            m.put(x, y, name, 'ground', solid=False)
            st['court_' + col] = st.get('court_' + col, 0) + 1
        xs = [c[0] for c in cells]; ys = [c[1] for c in cells]
        cx = (min(xs) + max(xs)) // 2
        if len(cells) >= 40 and 'basketball' in tags.get('sport', 'basketball'):
            for y in (min(ys) + 1, max(ys) - 1):
                if (cx, y) in S and m.free(cx, y):
                    m.put(cx, y, 'o_basket'); st['baskets'] += 1
    return st


def silena(m, osm, names):
    """Parc de la Silena (a l'OSM «Parc Educació Vial»): els carrers petits (highway=raceway) com a calçades
    d'asfalt amb línia, passos de zebra, senyals i semàfors petits, i l'skatepark amb rampes."""
    st = {'miniroad': 0, 'zebra': 0, 'signs': 0, 'skate': 0}
    park = None
    for key, ov in names.items():
        if isinstance(ov, dict) and ov.get('name') == 'Parc de la Silena':
            park = key.split('/')[1]
    if not park or park not in osm.ways:
        return st
    pcells = poly_cells(osm, park, m)
    if not pcells:
        return st
    xs = [c[0] for c in pcells]; ys = [c[1] for c in pcells]
    bx0, by0, bx1, by1 = min(xs) - 3, min(ys) - 3, max(xs) + 3, max(ys) + 3
    road = {}
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('highway') != 'raceway':
            continue
        pts = [to_tile_f(*osm.nodes[r]) for r in refs if r in osm.nodes]
        if not pts or not all(bx0 <= p[0] <= bx1 and by0 <= p[1] <= by1 for p in pts):
            continue
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = int(max(abs(bx - ax), abs(by - ay)) * 2) + 1
            horiz = abs(bx - ax) >= abs(by - ay)
            for i in range(n + 1):
                x, y = ax + (bx - ax) * i / n, ay + (by - ay) * i / n
                for w in (0, 1):
                    c = (int(x), int(y) + w) if horiz else (int(x) + w, int(y))
                    road.setdefault(c, set()).add('h' if horiz else 'v')
    for (x, y), dirs in road.items():
        # l'import deixa els raceway com a «pendents» (sòlids i sense dibuix): aquí passen a ser calçada
        if int(m.d0[y, x]) == D['PENDING'] or (m.coll[y, x] & 32):
            m.d0[y, x] = 0
            m.coll[y, x] = WALK
            m.L['ground_detail'][y, x] = 0
        if not m.free(x, y, strict=False):
            continue
        if len(dirs) > 1:
            name = 'g_asphalt_1'
        else:
            name = 'g_miniroad_h' if 'h' in dirs else 'g_miniroad_v'
        m.put(x, y, name, 'ground', solid=False)
        st['miniroad'] += 1
    # la resta de cel·les «pendents» del parc (corbes dels raceway): també calçada transitable
    for x in range(bx0, bx1 + 1):
        for y in range(by0, by1 + 1):
            if int(m.d0[y, x]) == D['PENDING'] or (m.coll[y, x] & 32):
                m.d0[y, x] = 0
                m.coll[y, x] = WALK
                m.L['ground_detail'][y, x] = 0
                if not m.L['structures'][y, x]:
                    m.put(x, y, 'g_asphalt_1', 'ground', solid=False)
                    road.setdefault((x, y), {'h', 'v'})
                    st['miniroad'] += 1
    # zebres i senyals: cada 9 cel·les de calçada recta, una zebra; al costat, un senyal
    k = 0
    for (x, y), dirs in sorted(road.items()):
        if len(dirs) != 1 or not m.free(x, y, strict=False):
            continue
        k += 1
        if k % 9 == 4:
            m.put(x, y, 'g_minizebra', 'ground', solid=False); st['zebra'] += 1
        elif k % 13 == 7:
            for dx, dy in ((0, -1), (0, 2), (-1, 0), (2, 0)):
                q = (x + dx, y + dy)
                if q not in road and q in pcells and m.free(*q):
                    m.put(q[0], q[1], ('o_sign_stop', 'o_sign_round', 'o_minilight')[st['signs'] % 3]); st['signs'] += 1
                    break
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('sport') == 'skateboard' or (tags.get('name') or '').lower().startswith('skate'):
            cells = poly_cells(osm, wid, m)
            if not cells or not any(c in pcells for c in cells):
                continue
            ys2 = [c[1] for c in cells]
            for x, y in cells:
                if m.free(x, y, strict=False):
                    ramp = y in (min(ys2), max(ys2))
                    m.put(x, y, 'g_skate_ramp' if ramp else f'g_skate_{(x + y) % 2}', 'ground', solid=False)
                    st['skate'] += 1
    return st


def open_fences(m, before, main_b, rounds=40):
    """Si alguna tanca (o la reixa d'una escola) deixa cel·les aïllades de la zona principal, s'hi obre una
    porta: es treuen les cel·les de tanca que separen la zona aïllada de la principal (primer les que hi
    toquen directament; si no n'hi ha, les que en són a 2 o 3 cel·les), fins que no en queda cap."""
    opened = 0
    reach = 1
    for _ in range(rounds):
        after = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
        main_a = np.bincount(after[before == main_b].ravel()).argmax()
        lost = (before == main_b) & (after != main_a) & ~m.placed
        if lost.sum() == 0:
            break
        def grow(mask, r):
            for _ in range(r):
                P = np.pad(mask, 1)
                mask = mask | P[:-2, 1:-1] | P[2:, 1:-1] | P[1:-1, :-2] | P[1:-1, 2:]
            return mask
        near_lost = grow(lost, reach)
        near_main = grow(after == main_a, reach)
        ys, xs = np.nonzero(near_lost & near_main & m.placed)
        cut = 0
        for y, x in zip(ys, xs):
            n = m.name_of.get(int(m.L['structures'][y, x]) & 0x1FFFFFFF, '')
            if n.startswith(('o_wall_', 'o_wood_', 'o_mesh_')):
                m.L['structures'][y, x] = 0
                m.coll[y, x] = WALK
                m.placed[y, x] = False
                cut += 1
        opened += cut
        if cut == 0:
            if reach >= 3:
                break
            reach += 1
    return opened


def plot_fences(m):
    """Tanques de parcel·la a les cases aïllades (urbanitzacions): mur arrebossat a la façana del carrer i
    tanca de fusta amb els veïns, amb una porta davant de la porta de casa. La parcel·la és la franja de 3
    cel·les lliures al voltant de cada casa (repartida entre veïns, com un Voronoi)."""
    from collections import deque
    st = {'houses': 0, 'wall': 0, 'wood': 0, 'gates': 0}
    from scipy import ndimage
    lab, n = ndimage.label(m.bld > 0)
    sizes = np.bincount(lab.ravel())
    owner = np.zeros((m.H, m.W), np.int32)
    dist = np.full((m.H, m.W), 99, np.int8)
    q = deque()
    ys, xs = np.nonzero((lab > 0) & (sizes[lab] <= 120) & (sizes[lab] >= 6))
    for y, x in zip(ys, xs):
        owner[y, x] = lab[y, x]; dist[y, x] = 0; q.append((x, y))
    # ni tanques a tocar de ponts, túnels i rampes (2 cel·les): els accessos a un altre nivell queden lliures
    from scipy import ndimage as _nd
    near_level = _nd.binary_dilation((m.coll & ~3) > 0, iterations=2)

    def plot_ok(x, y):
        return (m.coll[y, x] == WALK and not near_level[y, x] and not m.d0[y, x] and not m.L['structures'][y, x]
                and not m.placed[y, x]
                and m.ground[y, x] in (G['URBAN'], G['GRASS'], G['PARK']))
    while q:
        x, y = q.popleft()
        if dist[y, x] >= 3:
            continue
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 2 <= nx < m.W - 2 and 2 <= ny < m.H - 2 and dist[ny, nx] == 99 and m.bld[ny, nx] == 0 and plot_ok(nx, ny):
                dist[ny, nx] = dist[y, x] + 1; owner[ny, nx] = owner[y, x]; q.append((nx, ny))
    street = {D['FOOTWAY'], D['PEDESTRIAN'], D['ROAD'], D['ROAD_MAIN'], D['PATH'], D['TRACK']}
    # cel·les de tanca: només la façana del carrer (vora de la parcel·la que toca el carrer) i, als costats,
    # un tros curt de tanca de fusta (les cel·les de vora del costat de cada cel·la de façana). Així mai no es
    # tanca cap pati del tot: res no queda aïllat.
    fence = {}
    border = {}
    for y, x in zip(*np.nonzero((owner > 0) & (dist > 0) & (dist < 99))):
        o = owner[y, x]
        nb = [(x + dx, y + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))]
        out = [(a, b) for a, b in nb if owner[b, a] != o]
        if out:
            border[(x, y)] = (o, any(int(m.d0[b, a]) in street for a, b in out))
    for (x, y), (o, on_street) in border.items():
        if on_street:
            fence.setdefault(o, []).append(((x, y), True))
        else:
            near_front = any(border.get((x + dx, y + dy), (None, False))[1] and border[(x + dx, y + dy)][0] == o
                             for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy)
            if near_front:
                fence.setdefault(o, []).append(((x, y), False))
    wall_cells, wood_cells = [], []
    for o, cells in fence.items():
        bys, bxs = np.nonzero(lab == o) if False else (None, None)
        # porta: la cel·la de tanca més propera a la porta de la casa (o al centre)
        house = [(x, y) for (x, y), _ in cells]
        door = None
        yy, xx = np.nonzero(lab[max(0, min(c[1] for c in house) - 4):min(m.H, max(c[1] for c in house) + 4),
                                max(0, min(c[0] for c in house) - 4):min(m.W, max(c[0] for c in house) + 4)] == o)
        if len(yy):
            oy0 = max(0, min(c[1] for c in house) - 4); ox0 = max(0, min(c[0] for c in house) - 4)
            hc = [(int(x) + ox0, int(y) + oy0) for y, x in zip(yy, xx)]
            ds = doors_in(m, hc)
            door = (ds[0][0], ds[0][1] + 1) if ds else (sum(c[0] for c in hc) / len(hc), max(c[1] for c in hc) + 1)
        if door is None:
            continue
        st['houses'] += 1
        streetside = [c for c, s in cells if s] or [c for c, _ in cells]
        g = min(streetside, key=lambda c: (c[0] - door[0]) ** 2 + (c[1] - door[1]) ** 2)
        gate = {g, (g[0] + 1, g[1]), (g[0] - 1, g[1]), (g[0], g[1] + 1), (g[0], g[1] - 1)}
        st['gates'] += 1
        for c, s in cells:
            if c in gate:
                continue
            (wall_cells if s else wood_cells).append(c)
    fence_pieces(m, wall_cells, 'wall', 'wall', st)
    fence_pieces(m, wood_cells, 'wood', 'wood', st)
    return st


def special_signs(m):
    """Edificis especials recognoscibles: rètol a la façana de cada servei (Policia amb llum blava, CAP amb
    creu verda, Ajuntament amb escut i bandera, súpers amb el seu rètol i carros, Correus amb bústia groga).
    Objectes 'signboard' (el joc els dibuixa i els anima) i 'prop' (sòlids al mapa de col·lisions)."""
    st = {'signs': 0, 'props': 0}
    SIGN = {'police': 'sign_police', 'doctor': 'sign_cap', 'post': 'sign_correus', 'townhall': 'sign_ajuntament'}
    landmarks = [o for o in m.objects if o['type'] == 'landmark']
    def props_of(o):
        return {q['name']: q['value'] for q in o.get('properties', [])}
    services = [o for o in m.objects if o['type'] == 'service']
    for o in services:
        p = props_of(o)
        kind, sid = p.get('service'), p.get('service_id')
        sign = SIGN.get(kind) or ((kind in ('shop', 'super')) and ('sign_' + sid)) or None
        if not sign:
            continue
        tx, ty = int(o['x'] // 16), int(o['y'] // 16)
        best = None
        # Ajuntament: l'edifici monumental (landmark) si és a prop
        if kind == 'townhall':
            lm = min(landmarks, key=lambda l: (l['x'] - o['x']) ** 2 + (l['y'] - o['y']) ** 2, default=None)
            if lm and (lm['x'] + lm.get('width', 32) / 2 - o['x']) ** 2 + (lm['y'] - o['y']) ** 2 < (14 * 16) ** 2:
                best = (int((lm['x'] + lm.get('width', 32) / 2) // 16), int((lm['y'] + lm.get('height', 32) - 10) // 16))
        # porta o aparador més proper (l'entrada de l'edifici); si no n'hi ha, la façana més propera per sobre
        bd = 0 if best else 1e9
        for y in range(max(1, ty - 9), min(m.H - 1, ty + 10)):
            for x in range(max(1, tx - 9), min(m.W - 1, tx + 10)):
                n = m.name_of.get(int(m.L['structures'][y, x]) & 0x1FFFFFFF, '')
                if not n.startswith('f_') or not ('_door' in n or '_shop' in n or '_arch' in n):
                    continue
                d = (x - tx) ** 2 + (y - ty) ** 2 + (0 if '_door' in n else 4)
                if d < bd:
                    best, bd = (x, y), d
        if best is None:
            for dy in range(1, 7):
                for dx in (0, -1, 1, -2, 2, -3, 3):
                    x, y = tx + dx, ty - dy
                    if 0 < x < m.W and 0 < y < m.H and m.is_name('structures', x, y, 'f_'):
                        best = (x, y)
                        break
                if best:
                    break
        if best is None and kind == 'townhall':
            lm = min(landmarks, key=lambda l: (l['x'] - o['x']) ** 2 + (l['y'] - o['y']) ** 2, default=None)
            if lm:
                best = (int((lm['x'] + lm.get('width', 32) / 2) // 16), int(lm['y'] // 16) + 1)
        if best is None:
            best = (tx, ty - 2)
        extra = {'police': 'siren', 'doctor': 'cross_cap', 'townhall': 'shield_roda'}.get(kind, '')
        m.obj('signboard', best[0] * 16 + 8, best[1] * 16 + 4, {'sprite': sign, 'extra': extra, 'service_id': sid or '',
                                                                'flag': kind == 'townhall'})
        st['signs'] += 1
        # cotxe de la Policia Local i ambulància aparcats a prop de l'entrada (parked_car colors 15 i 16)
        svc = {'police': 15, 'doctor': 16}.get(kind)
        if svc:
            spots = sorted(((x - tx) ** 2 + (y - ty) ** 2, x, y) for y in range(ty - 6, ty + 7) for x in range(tx - 6, tx + 6)
                           if m.free(x, y) and m.free(x + 1, y) and not m.placed[y, x:x + 2].any())
            if spots:
                _, x, y = spots[0]
                m.coll[y, x:x + 2] = SOLID
                m.placed[y, x:x + 2] = True
                m.obj('parked_car', (x + 1) * 16, y * 16 + 8, {'color': svc, 'orient': 'h'})
                st['props'] += 1
        # bústia groga al costat del carter; dos carros al costat de la caixera
        want = {'post': ['mailbox_correus'], 'shop': ['cart', 'cart'], 'super': ['cart', 'cart']}.get(kind, [])
        for spr in want:
            for dx, dy in ((2, 0), (-2, 0), (3, 0), (-3, 0), (2, 1), (-2, 1), (1, 1), (-1, 1)):
                x, y = tx + dx, ty + dy
                if m.free(x, y) and not m.placed[y, x]:
                    m.coll[y, x] = SOLID
                    m.placed[y, x] = True
                    m.obj('prop', x * 16 + 8, y * 16 + 8, {'sprite': spr})
                    st['props'] += 1
                    break
    return st


CAVE_LONLAT = (1.4402913, 41.1843924)   # boca de la Cova de Roda (coordenades reals donades)


def cave_entrances(m, comp, main):
    """Fase 6: la boca de la Cova de Roda a les coordenades reals i el cau del Drac al cim transitable més alt
    (lluny de les vores del mapa). Cada entrada és una roca de 3 × 2 (sòlida) amb la boca al mig (porta cap a
    l'escena), un punt de tornada davant i un objecte 'spot' amb el nom (missions i mapa)."""
    hgt = np.array(m.layers['height']['data'], np.int64).reshape(m.H, m.W) & 1023
    reach = comp == main

    def fits(x, y):
        block = [(x + dx, y + dy) for dy in (-1, 0) for dx in (-1, 0, 1)]
        if not all(3 <= cx < m.W - 3 and 3 <= cy < m.H - 4 for cx, cy in block):
            return False
        if any(m.coll[cy, cx] != WALK or m.L['structures'][cy, cx] or m.placed[cy, cx] or m.d0[cy, cx] for cx, cy in block):
            return False
        front = [(x, y + 1), (x, y + 2), (x - 1, y + 1), (x + 1, y + 1)]
        return all(reach[fy, fx] and m.coll[fy, fx] == WALK and not m.L['structures'][fy, fx] for fx, fy in front)

    def near(x0, y0, radius, score):
        best = None
        for y in range(max(3, y0 - radius), min(m.H - 4, y0 + radius + 1)):
            for x in range(max(3, x0 - radius), min(m.W - 3, x0 + radius + 1)):
                if fits(x, y):
                    sc = score(x, y)
                    if best is None or sc < best[0]:
                        best = (sc, x, y)
        return best and best[1:]

    def place(x, y, sid, label, door_props):
        for dx, n in ((-1, 'o_cave_rock_tl'), (0, 'o_cave_rock_tm'), (1, 'o_cave_rock_tr')):
            m.put(x + dx, y - 1, n)
        m.put(x - 1, y, 'o_cave_rock_l'); m.put(x + 1, y, 'o_cave_rock_r')
        m.put(x, y, 'o_cave_mouth', solid=False)
        m.placed[y, x] = True
        m.L['ground_detail'][y + 1, x] = 0
        d = m.obj('door', x * 16, y * 16, dict(door_props, return_spawn='spawn_' + sid + '_door'), name='door_' + sid)
        d['width'], d['height'] = 16, 16
        d.pop('point', None)
        m.obj('spawn', x * 16 + 8, (y + 1) * 16 + 10, {'public': True}, name='spawn_' + sid + '_door')
        m.obj('spot', x * 16 + 8, (y + 1) * 16 + 8, {'label': label, 'height_m': int(hgt[y, x])}, name=sid)
        return {'tile': [x, y], 'height_m': int(hgt[y, x])}

    out = {}
    cx, cy = (int(v) for v in to_tile_f(*CAVE_LONLAT))
    p = near(cx, cy, 10, lambda x, y: (x - cx) ** 2 + (y - cy) ** 2)
    if p:
        out['cova_roda'] = place(p[0], p[1], 'cova_roda', 'Cova de Roda', {
            'target_scene': 'cova_roda_1', 'target_spawn': 'spawn_entrance', 'requires_item': 'llanterna',
            'locked_text': 'Està molt fosc! Sense una llanterna no hi pots entrar.'})
        out['cova_roda']['offset'] = [p[0] - cx, p[1] - cy]
    # cim: la cel·la transitable més alta de la zona principal (a 24 cel·les de les vores); sense relleu (lloc nou
    # sense MDT), el cau va al camp com les altres entrades (més avall)
    flat = int(hgt.max()) == 0
    e = np.where(reach & (m.coll == WALK), hgt, -1)
    e[:24, :] = -1; e[-24:, :] = -1; e[:, :24] = -1; e[:, -24:] = -1
    ty, tx = np.unravel_index(int(np.argmax(e)), e.shape)
    p = None if flat else near(int(tx), int(ty), 12, lambda x, y: -int(hgt[y, x]) * 4 + abs(x - tx) + abs(y - ty))
    if p:
        out['cau_drac'] = place(p[0], p[1], 'cau_drac', 'Cau del Drac', {
            'target_scene': 'cau_drac', 'target_spawn': 'spawn_entrance', 'requires_item': 'cristall_drac',
            'min_level': 5, 'locked_text': 'Una roca segellada amb un forat en forma de cristall...'})
        out['cau_drac']['summit_m'] = int(hgt[ty, tx])
    # lloc nou (tools/new_location.py): sense la cova real ni els monuments de Roda, les entrades de la Cova, la
    # Pedrera, la masmorra del castell i les profunditats es posen al camp, lluny de les cases, en quatre direccions
    if not any(o['type'] == 'poi' and o['name'] == 'cucurull' for o in m.objects):
        from scipy import ndimage as _nd
        far = _nd.distance_transform_edt(m.bld == 0)
        sx, sy = m.W // 2, m.H // 2
        sp0 = next((o for o in m.objects if o['name'] == 'spawn_public_centre'), None)
        if sp0:
            sx, sy = int(sp0['x'] // 16), int(sp0['y'] // 16)
        cand = [(x, y) for y in range(8, m.H - 8, 3) for x in range(8, m.W - 8, 3) if far[y, x] >= 6 and fits(x, y)]
        if len(cand) < 12:   # poble molt dens: també a prop de cases
            cand = [(x, y) for y in range(8, m.H - 8, 2) for x in range(8, m.W - 8, 2) if fits(x, y)]
        wanted = [('cova_roda', 'Cova', 0.30, 0.0, {'target_scene': 'cova_roda_1', 'target_spawn': 'spawn_entrance',
                   'requires_item': 'llanterna', 'locked_text': 'Està molt fosc! Sense una llanterna no hi pots entrar.'}),
                  ('pedrera', 'Cova de la Pedrera', 0.22, 1.6, {'target_scene': 'cova_pedrera', 'target_spawn': 'spawn_entrance'}),
                  ('castell', 'Masmorra del castell', 0.34, 3.2, {'target_scene': 'masmorra_castell',
                   'target_spawn': 'spawn_entrance', 'min_level': 3,
                   'locked_text': 'Una porta vella i pesada. Torna quan siguis més fort (nivell 3).'}),
                  ('cucurull', 'Les profunditats', 0.38, 4.7, {'target_scene': 'torre_cucurull', 'target_spawn': 'spawn_entrance'}),
                  ('cau_drac', 'Cau del Drac', 0.42, 5.9, {'target_scene': 'cau_drac', 'target_spawn': 'spawn_entrance',
                   'requires_item': 'cristall_drac', 'min_level': 5,
                   'locked_text': 'Una roca segellada amb un forat en forma de cristall...'})]
        import math as _m
        for sid, label, frac, ang, props in wanted:
            if sid in out or not cand:
                continue
            r0 = frac * min(m.W, m.H)
            tx, ty = sx + r0 * _m.cos(ang), sy + r0 * _m.sin(ang)
            best = min(cand, key=lambda c: (c[0] - tx) ** 2 + (c[1] - ty) ** 2)
            out[sid] = place(best[0], best[1], sid, label, props)
            cand = [c for c in cand if (c[0] - best[0]) ** 2 + (c[1] - best[1]) ** 2 > 100]
        return out
    # Les profunditats del Cucurull (tools/make_tower.py, 2026-10-05): una paret amb una estrella al peu de la
    # torre tapa la boca; en tocar-la s'obre (src/systems/puzzles.lua). Sense marca al mapa: és secreta.
    poi = next((o for o in m.objects if o['type'] == 'poi' and o['name'] == 'cucurull'), None)
    if poi:
        lx, ly = int(poi['x'] // 16), int(poi['y'] // 16)
        # lluny dels personatges fixos (en Jaume, el guarda, es passeja davant la torre i taparia la paret)
        fixed = [(n['x'], n['y']) for n in json.load(open(os.path.join(ROOT, 'maps/source/npcs.json')))]
        crowd = lambda x, y: any(abs(x - nx) <= 4 and abs(y - ny) <= 4 for nx, ny in fixed)
        p = near(lx, ly, 10, lambda x, y: (x - lx) ** 2 + (y - ly) ** 2 + (10000 if crowd(x, y) else 0))
        if p:
            out['torre_cucurull'] = place(p[0], p[1], 'cucurull', 'Les profunditats del Cucurull', {
                'target_scene': 'torre_cucurull', 'target_spawn': 'spawn_entrance', 'secret_flag': 'cucurull_secret'})
            for o in [o for o in m.objects if o['type'] == 'spot' and o['name'] == 'cucurull']:
                m.objects.remove(o)
            s_ = m.obj('secret', p[0] * 16, p[1] * 16, {'flag': 'cucurull_secret',
                       'say': "La pedra de l'estrella s'enfonsa amb un soroll sord...|S'ha obert un passadís cap a "
                               "les profunditats del Cucurull!"}, name='secret_cucurull')
            s_['width'], s_['height'] = 16, 16
            s_.pop('point', None)
            for dx, dy in ((-2, 1), (2, 1), (-2, 2), (2, 2)):
                sx, sy = p[0] + dx, p[1] + dy
                if m.coll[sy, sx] == WALK and not m.L['structures'][sy, sx]:
                    m.obj('sign', sx * 16 + 8, sy * 16 + 8, {'say': "Diuen els avis que sota la Torre del Cucurull hi ha "
                          "sales antigues.|Busca la pedra de l'estrella..."}, name='sign_cucurull_secret')
                    break
    return out


def shield_chest(m):
    """Fase 6: l'Escut de Roda en un cofre de ferro al costat de l'Ermita de Berà (progressió: espasa → escut
    trobat al mapa → bastó màgic a la cova)."""
    lm = next((o for o in m.objects if o['type'] == 'landmark' and o['name'] == 'ermita_bera'), None)
    if not lm:
        return None
    x0, y0 = int((lm['x'] + lm.get('width', 32) / 2) // 16), int((lm['y'] + lm.get('height', 32)) // 16) + 2
    for r in range(0, 10):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                x, y = x0 + dx, y0 + dy
                if max(abs(dx), abs(dy)) == r and m.free(x, y):
                    m.placed[y, x] = True
                    o = m.obj('chest', x * 16, y * 16, {'tier': 'iron', 'item': 'shield_roda', 'flag': 'cofre_escut_roda'},
                              name='cofre_escut_roda')
                    o['width'], o['height'] = 16, 16
                    o.pop('point', None)
                    return [x, y]
    return None


def osm_nodes(m, osm):
    st = {'bench': 0, 'tree': 0, 'lamp': 0, 'bin': 0}
    for nid, tags in osm.node_tags.items():
        if nid not in osm.nodes:
            continue
        x, y = (int(v) for v in to_tile_f(*osm.nodes[nid]))
        if not (1 <= x < m.W - 1 and 2 <= y < m.H - 1):
            continue
        a, nat, hw = tags.get('amenity'), tags.get('natural'), tags.get('highway')
        if a == 'bench' and m.free(x, y):
            m.put(x, y, 'o_bench'); st['bench'] += 1
        elif a == 'waste_basket' and m.free(x, y):
            m.put(x, y, 'o_bin'); st['bin'] += 1
        elif hw == 'street_lamp' and m.free(x, y):
            m.put(x, y, 'o_lamp'); st['lamp'] += 1
        elif a == 'drinking_water':      # font d'aigua (s'hi pot beure: src/systems/rest.lua)
            for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1)):
                if m.free(x + dx, y + dy, strict=False):
                    m.put(x + dx, y + dy, 'o_drinking')
                    m.obj('fountain', (x + dx) * 16 + 8, (y + dy) * 16 + 8, {})
                    st['fountain'] = st.get('fountain', 0) + 1
                    break
        elif nat == 'tree' and m.free(x, y) and not m.L['overhead'][y - 1, x] and not m.L['structures'][y - 1, x]:
            kind = 'palm' if rng.random() < .4 else 'pine0'
            m.put(x, y, f'tree_{kind}_bot')
            m.L['overhead'][y - 1, x] = m.gid(f'tree_{kind}_top')
            st['tree'] += 1
    return st


def barraques(m, osm):
    """Barraques de pedra seca (nodos OSM historic=ruins): construcción de piedra en seco típica de los
    campos del municipio. 2 × 2 tiles: cúpula (overhead) y muro con portal (sólido), cerca de su nodo."""
    n = 0
    for nid, tags in osm.node_tags.items():
        name = tags.get('name', '').lower()
        if tags.get('historic') != 'ruins' or 'barra' not in name or nid not in osm.nodes:
            continue
        x0, y0 = (int(v) for v in to_tile_f(*osm.nodes[nid]))
        done = False
        for r in range(0, 4):
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    x, y = x0 + dx, y0 + dy
                    if done or max(abs(dx), abs(dy)) != r or not (2 <= x < m.W - 3 and 2 <= y < m.H - 2):
                        continue
                    if not (m.free(x, y, strict=False) and m.free(x + 1, y, strict=False)):
                        continue
                    if m.L['overhead'][y - 1, x] or m.L['overhead'][y - 1, x + 1] or \
                            m.L['structures'][y - 1, x] or m.L['structures'][y - 1, x + 1]:
                        continue
                    m.put(x, y, 'o_barraca_bl'); m.put(x + 1, y, 'o_barraca_br')
                    m.L['overhead'][y - 1, x] = m.gid('o_barraca_tl')
                    m.L['overhead'][y - 1, x + 1] = m.gid('o_barraca_tr')
                    done = True
        n += done
    return n


def market(m, osm):
    """Mercat Setmanal: paradas con toldo alrededor de su nodo OSM, en filas y dejando pasillos."""
    node = next((nid for nid, t in osm.node_tags.items() if t.get('amenity') == 'marketplace'
                 and nid in osm.nodes), None)
    if not node:
        return 0
    cx, cy = (int(v) for v in to_tile_f(*osm.nodes[node]))
    ok_detail = {0, D['PEDESTRIAN'], D['FOOTWAY'], D['ROAD']}
    cand = sorted(((x - cx) ** 2 + (y - cy) ** 2, x, y) for y in range(cy - 10, cy + 11) for x in range(cx - 10, cx + 11))
    placed = []
    for _, x, y in cand:
        if len(placed) >= 8:
            break
        if not (1 <= x < m.W - 1 and 1 <= y < m.H - 1) or m.coll[y, x] != WALK or m.placed[y, x]:
            continue
        if m.L['structures'][y, x] or self_is_facade(m, x, y) or int(m.d0[y, x]) not in ok_detail:
            continue
        if any(abs(px - x) <= 1 and abs(py - y) == 1 for px, py in placed):   # pasillo entre filas
            continue
        around = sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                     if (dx or dy) and m.coll[y + dy, x + dx] == WALK and not m.placed[y + dy, x + dx])
        if around < 6:
            continue
        m.put(x, y, f'o_stall_{len(placed) % 3}')
        placed.append((x, y))
    return len(placed)


def self_is_facade(m, x, y):
    return m.is_name('structures', x, y - 1, 'f_') or m.is_name('structures', x, y + 1, 'f_')


def mountain_chests(m, n_max=30, min_alt=50, spacing=35):
    """Cofres de fusta a la muntanya (data/loot.json 'wood'): terreny natural a més de `min_alt` m, al costat
    d'un camí (que es puguin trobar) i separats entre ells. Objecte 'chest' amb tier i flag propis."""
    from scipy import ndimage
    t = os.path.join(ROOT, 'cartography/derived/terrain.npz')
    if not os.path.exists(t):
        return 0
    elev = ndimage.uniform_filter(np.load(t)['elev'].astype(np.float32), 5)
    natural = np.isin(m.ground, [G['FOREST'], G['SCRUB'], G['DRY'], G['ROCK']])
    trail = ndimage.binary_dilation(np.isin(m.d0, [D['PATH'], D['TRACK']]), iterations=2)
    ys, xs = np.nonzero(natural & trail & (elev >= min_alt))
    r = random.Random(77)
    order = list(range(len(xs)))
    r.shuffle(order)
    placed = []
    for k in order:
        x, y = int(xs[k]), int(ys[k])
        if len(placed) >= n_max:
            break
        if any((x - px) ** 2 + (y - py) ** 2 < spacing ** 2 for px, py in placed) or not m.free(x, y):
            continue
        m.placed[y, x] = True
        o = m.obj('chest', x * 16, y * 16, {'tier': 'wood', 'flag': f'cofre_fusta_{len(placed) + 1}'},
                  name=f'cofre_fusta_{len(placed) + 1}')
        o['width'], o['height'] = 16, 16
        o.pop('point', None)
        placed.append((x, y))
    return len(placed)


def collectibles(m, n_each=40):
    """Col·leccionables per vendre als súpers: petxines a la platja i pinyes al pinar (objectes 'pickup')."""
    r = random.Random(33)
    out = {}
    for item, ground, near_tree in (('petxina', [G['BEACH']], False), ('pinya', [G['FOREST']], True)):
        ys, xs = np.nonzero(np.isin(m.ground, ground))
        order = list(range(len(xs)))
        r.shuffle(order)
        n = 0
        for k in order:
            if n >= n_each:
                break
            x, y = int(xs[k]), int(ys[k])
            if not m.free(x, y, strict=False):
                continue
            if near_tree and not any(m.is_name('structures', x + dx, y + dy, 'tree_')
                                     for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                continue
            n += 1
            m.obj('pickup', x * 16 + 8, y * 16 + 8, {'item': item}, name=f'{item}_{n}')
        out[item] = n
    return out


def street_lamps(m, lines):
    """Farolas cada ~7 celdas a un lado de las calles con casas cerca, alternando acera."""
    from scipy import ndimage
    town = ndimage.binary_dilation(m.bld > 0, iterations=4)
    n = 0
    for it in lines:
        if it['cls'] not in ('ROAD', 'ROAD_MAIN', 'PEDESTRIAN') or it['level'] != 0:
            continue
        pts, side, carry = it['pts'], 1, 50.0
        for p, q in zip(pts, pts[1:]):
            L = math.dist(p, q)
            if L == 0:
                continue
            ux, uy = (q[0] - p[0]) / L, (q[1] - p[1]) / L
            d = carry
            while d < L:
                off = it['w'] / 2 + 9
                x = p[0] + ux * d - uy * off * side
                y = p[1] + uy * d + ux * off * side
                cx, cy = int(x // 16), int(y // 16)
                if 0 < cx < m.W - 1 and 0 < cy < m.H - 1 and town[cy, cx] and m.free(cx, cy) \
                        and not m.placed[max(0, cy - 3):cy + 4, max(0, cx - 3):cx + 4].any():
                    m.put(cx, cy, 'o_lamp')
                    n += 1
                    side = -side
                d += 112
            carry = d - L
    return n


def street_name_near(osm, tx, ty, named):
    best = None
    for name, pts in named:
        for x, y in pts:
            d = (x - tx) ** 2 + (y - ty) ** 2
            if d < 900 and (best is None or d < best[0]):
                best = (d, name)
    return best[1] if best else None


def bus_stops(m, osm, lines):
    stops = []
    seen = set()
    named = [(t['name'], osm.way_tiles(w)) for w, (t, r) in osm.ways.items()
             if t.get('highway') in ('primary', 'secondary', 'tertiary', 'residential', 'unclassified', 'trunk')
             and t.get('name')]
    for nid, tags in osm.node_tags.items():
        if tags.get('highway') != 'bus_stop' or nid not in osm.nodes:
            continue
        tx, ty = to_tile_f(*osm.nodes[nid])
        name = tags.get('name') or street_name_near(osm, tx, ty, named) or 'Parada'
        base, k = name, 2
        while name in seen:
            name = f'{base} ({k})'
            k += 1
        best = None
        for r in range(0, 6):
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    if max(abs(dx), abs(dy)) != r:
                        continue
                    x, y = int(tx) + dx, int(ty) + dy
                    if m.free(x, y, strict=False) and m.free(x + 1, y, strict=False) and \
                            m.coll[y + 1, x] == WALK and m.coll[y + 1, x + 1] == WALK and not m.placed[y + 1, x:x + 2].any():
                        best = (x, y)
                        break
                if best: break
            if best: break
        if not best:
            continue
        x, y = best
        m.put(x, y, 'o_busstop_l'); m.put(x + 1, y, 'o_busstop_r')
        m.obj('bus_stop', (x + 1) * 16, (y + 1) * 16 + 8, {'label': name}, name=f'bus_{len(stops) + 1}')
        stops.append(name)
        seen.add(name)
    return stops


def fix_side_entries(m):
    """Accesos laterales a puentes y pasos inferiores: una celda transitable a nivel 0 y a otro nivel
    (tablero o túnel) que linda con la parte que pasa sobre/bajo un obstáculo (vía, torrente, autopista)
    pasa a ser rampa. Si no, quien entra de lado al tablero a nivel 0 queda atrapado contra el obstáculo
    (caso de la Av. de l'Avenc con el puente de Carrer de la Via)."""
    c = m.coll
    walk0 = ((c & 3) == 0) & ((c & 32) == 0)
    n = 0
    for bit in (4, 8):
        over = ((c & bit) > 0) & ~walk0           # solo transitable a ese nivel
        P = np.pad(over, 1)
        near = P[:-2, 1:-1] | P[2:, 1:-1] | P[1:-1, :-2] | P[1:-1, 2:]
        fix = walk0 & ((c & bit) > 0) & ((c & 16) == 0) & near
        c[fix] |= 16
        n += int(fix.sum())
    # tramos del tablero (o del túnel) que ya van por tierra firme: entre dos rampas, transitables a ese nivel
    # y también a nivel 0, sin nada debajo. Quien llegaba por el puente seguía «arriba» y no podía girar a
    # la acera: muro invisible (Av. de l'Avenc al norte del puente de Carrer de la Via, 2026-10-05).
    from scipy import ndimage
    for bit in (4, 8):
        run = ((c & bit) > 0) & ((c & 16) == 0)
        lab, k = ndimage.label(run)
        if not k:
            continue
        over = ndimage.sum(run & ~walk0, lab, index=np.arange(1, k + 1))
        land = np.zeros(k + 1, bool)
        land[1:] = over == 0
        fix = land[lab] & run
        c[fix] |= 16
        n += int(fix.sum())
    return n


# ------------------------------------------------------------------ gasolineres, hípica i rètols de botigues
def _signboard(m, x, y, sprite):
    m.obj('signboard', x * 16 + 8, y * 16 + 4, {'sprite': sprite, 'extra': '', 'service_id': '', 'flag': False})


def canopies(m, osm):
    """Marquesines (building=roof): coberta a l'overhead una fila més amunt que la planta (sembla alçada),
    pilars als cantons i, si hi ha una benzinera a prop (amenity=fuel), sortidors i rètol."""
    st = {'canopies': 0, 'pumps': 0, 'signs': 0}
    fuels = [to_tile_f(*osm.nodes[n]) for n, t in osm.node_tags.items() if t.get('amenity') == 'fuel' and n in osm.nodes]
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('amenity') == 'fuel':
            pts = osm.way_tiles(wid)
            if pts:
                fuels.append((sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts)))
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('building') != 'roof':
            continue
        cells = set(poly_cells(osm, wid, m))
        if len(cells) < 4:
            continue
        st['canopies'] += 1
        for x, y in cells:
            mask = sum(b for b, (dx, dy) in ((N, (0, -1)), (E, (1, 0)), (S_, (0, 1)), (W_, (-1, 0))) if (x + dx, y + dy) in cells)
            if not m.L['overhead'][y - 1, x]:
                m.L['overhead'][y - 1, x] = m.gid(f'o_canopy_{mask}')
            if m.coll[y, x] == WALK and not m.L['structures'][y, x] and not m.d0[y, x]:
                m.put(x, y, f'g_yard_{(x + y) % 2}', 'ground', solid=False)
        xs = [c[0] for c in cells]; ys = [c[1] for c in cells]
        cx, cy = (min(xs) + max(xs)) / 2, (min(ys) + max(ys)) / 2
        fuel = any((fx - cx) ** 2 + (fy - cy) ** 2 < 15 ** 2 for fx, fy in fuels)
        for x, y in ((min(xs), max(ys)), (max(xs), max(ys))):
            if (x, y) in cells and m.free(x, y, strict=False):
                m.put(x, y, 'o_canopy_pillar')
        if fuel:
            # una illa de sortidors cada tres columnes, a la fila de baix (la coberta, una fila amunt, no la tapa)
            my = max(ys)
            for x in range(min(xs) + 1, max(xs), 3):
                if (x, my) in cells and m.free(x, my, strict=False):
                    m.put(x, my, 'o_fuel_pump'); st['pumps'] += 1
            # rètol: a la vora sud, fora de la marquesina
            for dx in (0, 1, -1, 2, -2):
                x, y = int(cx) + dx, max(ys) + 2
                if m.free(x, y, strict=False):
                    _signboard(m, x, y, 'sign_benzinera'); st['signs'] += 1
                    break
    return st


SHOP_SIGNS = {'Leroy Merlin': 'sign_leroy', 'Pagès': 'sign_garden'}


def shop_signs(m, osm):
    """Rètol damunt de la porta de les grans botigues sense personatge de servei."""
    n = 0
    for wid, (tags, refs) in osm.ways.items():
        sprite = SHOP_SIGNS.get(tags.get('name'))
        if not sprite or not tags.get('shop'):
            continue
        cells = poly_cells(osm, wid, m)
        if not cells:
            continue
        doors = doors_in(m, cells)
        if not doors:
            xs = [c[0] for c in cells]; ys = [c[1] for c in cells]
            doors = [((min(xs) + max(xs)) // 2, max(ys))]
        x, y = doors[0]
        _signboard(m, x, y - 1, sprite); n += 1
    return n


def clear_area(m, x0, y0, x1, y1):
    """Treu arbres, tanques i objectes solts (no edificis ni vies) d'un rectangle per refer-lo."""
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if m.bld[y, x] or m.d0[y, x]:
                continue
            n = m.name_of.get(int(m.L['structures'][y, x]) & 0x1FFFFFFF, '')
            if n and not n.startswith(('f_', 'r_')):
                if n.startswith('tree_'):
                    m.L['overhead'][y - 1, x] = 0
                m.L['structures'][y, x] = 0
                m.coll[y, x] = WALK
                m.placed[y, x] = False


def extra_features(m):
    """Llocs que no són a l'OSM (map-overrides.json → extra_features): la pista de sorra de l'hípica amb
    tanca de fusta, cavalls i rètol, i el rètol del Poliesportiu."""
    st = {'arena': 0, 'horses': 0, 'signs': 0}
    for f in OVERRIDES.get('extra_features', []):
        x0, y0, x1, y1 = f['rect']
        if f.get('type') == 'arena':
            tree = lambda x, y: m.is_name('structures', x, y, 'tree_')
            cells = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)
                     if (m.coll[y, x] == WALK or tree(x, y)) and not m.bld[y, x] and not m.d0[y, x]]
            for x, y in cells:
                if tree(x, y):          # la pista és de sorra neta: fora els arbres
                    m.L['structures'][y, x] = 0
                    m.L['overhead'][y - 1, x] = 0
                    m.coll[y, x] = WALK
                m.put(x, y, f'g_sandpit_{(x * 3 + y) % 3}', 'ground', solid=False)
            st['arena'] += len(cells)
            S = set(cells)
            border = [c for c in cells if any((c[0] + dx, c[1] + dy) not in S for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
            gate = min(border, key=lambda c: (c[0] - (x0 + x1) / 2) ** 2 + (c[1] - y1) ** 2) if border else None
            fence_pieces(m, [c for c in border if gate is None or abs(c[0] - gate[0]) + abs(c[1] - gate[1]) > 1], 'wood', 'arena', st)
            inner = [c for c in cells if c not in border and m.free(*c)]
            prng = random.Random(x0 * 7 + y0)
            prng.shuffle(inner)
            for k, (x, y) in enumerate(inner[:f.get('horses', 3)]):
                m.coll[y, x] = SOLID; m.placed[y, x] = True
                m.obj('prop', x * 16 + 8, y * 16 + 8, {'sprite': ('horse_brown', 'horse_white', 'horse_chestnut')[k % 3]})
                st['horses'] += 1
        if f.get('type') == 'solar':      # placas solars al mig del teulat
            roof = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)
                    if m.is_name('structures', x, y, 'r_') and m.is_name('structures', x - 1, y, 'r_')
                    and m.is_name('structures', x + 1, y, 'r_')]
            for x, y in roof[:f.get('panels', 8)]:
                m.L['structures'][y, x] = m.gid('r_solar')
            st['solar'] = st.get('solar', 0) + min(len(roof), f.get('panels', 8))
        if f.get('type') == 'football':   # camp de gespa artificial amb línies, porteries i grades
            clear_area(m, x0, y0, x1, y1)
            cx, cy = (x0 + x1) // 2, (y0 + y1) // 2
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    if x in (x0, x1): n = 'g_turf_line_v'
                    elif y in (y0, y1, cy): n = 'g_turf_line_h'
                    else: n = f'g_turf_{(x // 2 + y) % 2}'
                    m.put(x, y, n, 'ground', solid=False)
            m.put(cx, cy, 'g_turf_spot', 'ground', solid=False)
            for gy in (y0 + 1, y1 - 1):
                for k, p in enumerate('lmr'):
                    m.put(cx - 1 + k, gy, f'o_goal_{p}')
            side = f.get('stands', 'left')
            sx_ = x0 - 2 if side == 'left' else x1 + 2
            for y in range(y0 + 2, y1 - 1):
                if m.coll[y, sx_] == WALK and not m.bld[y, sx_] and not m.d0[y, sx_]:
                    m.L['structures'][y, sx_] = 0
                    m.put(sx_, y, 'o_bleacher')
            st['football'] = st.get('football', 0) + 1
        if f.get('type') == 'tennis':     # pistes de tennis en quadrícula amb camins entre mig
            clear_area(m, x0, y0, x1, y1)
            cw, chh = 6, 11
            n_c = 0
            for gy in range(y0, y1 - chh + 2, chh + 1):
                for gx in range(x0, x1 - cw + 2, cw + 1):
                    col = ('green', 'blue', 'red')[n_c % 3] if f.get('mixed') else 'green'
                    for y in range(gy, gy + chh):
                        for x in range(gx, gx + cw):
                            if x in (gx, gx + cw - 1): nm = f'g_court_{col}_line_v'
                            elif y in (gy, gy + chh - 1, gy + chh // 2): nm = f'g_court_{col}_line_h'
                            else: nm = f'g_court_{col}_{(x + y) % 2}'
                            m.put(x, y, nm, 'ground', solid=False)
                    n_c += 1
            for y in range(y0, y1 + 1):          # camins entre pistes
                for x in range(x0, x1 + 1):
                    if not m.is_name('ground', x, y, 'g_court'):
                        m.put(x, y, f'g_yard_{(x + y) % 2}', 'ground', solid=False)
            st['tennis_courts'] = st.get('tennis_courts', 0) + n_c
        if f.get('type') == 'playground':   # parc infantil amb sorra, jocs i arbres al voltant
            clear_area(m, x0, y0, x1, y1)
            cells = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
            ring = [c for c in cells if c[0] in (x0, x1) or c[1] in (y0, y1)]
            for x, y in cells:
                m.put(x, y, f'g_park_{(x + y) % 3}' if (x, y) in ring else f'g_sandpit_{(x * 3 + y) % 3}', 'ground', solid=False)
            for k, (x, y) in enumerate(ring):
                if k % 3 == 0 and m.free(x, y) and not m.L['overhead'][y - 1, x]:
                    kind = ('olive', 'pine0', 'palm')[k % 3]
                    m.put(x, y, f'tree_{kind}_bot'); m.L['overhead'][y - 1, x] = m.gid(f'tree_{kind}_top')
            inner = [c for c in cells if c not in ring]
            kit = ['o_swing', 'o_slide', 'o_climb', 'o_seesaw', 'o_springrider', 'o_swing', 'o_bench', 'o_bench']
            prng = random.Random(x0 * 31 + y0)
            prng.shuffle(inner)
            for name in kit:
                for x, y in inner:
                    if m.free(x, y):
                        m.put(x, y, name); break
            st['playgrounds'] = st.get('playgrounds', 0) + 1
        if f.get('type') == 'round_park':   # plaça rodona: anell de camí, arbres, bancs i font
            cx, cy, r = (x0 + x1) / 2, (y0 + y1) / 2, min(x1 - x0, y1 - y0) / 2
            clear_area(m, x0, y0, x1, y1)
            for y in range(y0, y1 + 1):
                for x in range(x0, x1 + 1):
                    d = math.hypot(x - cx, y - cy)
                    if d > r + 0.5:
                        continue
                    if abs(d - r * 0.7) < 0.8: m.put(x, y, f'g_cobble_{(x + y) % 3}', 'ground', solid=False)
                    else: m.put(x, y, f'g_park_{(x + y) % 3}', 'ground', solid=False)
            for k in range(10):
                a = k * math.pi / 5
                for rr, name in ((r * 0.95, 'tree'), (r * 0.45, 'o_bench')):
                    x, y = int(round(cx + rr * math.cos(a))), int(round(cy + rr * math.sin(a)))
                    if name == 'tree' and m.free(x, y) and not m.L['overhead'][y - 1, x]:
                        m.put(x, y, 'tree_olive_bot'); m.L['overhead'][y - 1, x] = m.gid('tree_olive_top')
                    elif name == 'o_bench' and k % 2 == 0 and m.free(x, y):
                        m.put(x, y, 'o_bench')
            if m.free(int(cx), int(cy)):
                m.put(int(cx), int(cy), 'o_fountain')
            st['round_parks'] = st.get('round_parks', 0) + 1
        if f.get('sign'):
            sx, sy = f.get('sign_at', ((x0 + x1) // 2, y1 + 1))
            if f.get('type') == 'sign':     # rètol d'un edifici: damunt de la porta més propera
                doors = doors_in(m, [(x, y) for y in range(y0, y1 + 2) for x in range(x0, x1 + 1)])
                if doors:
                    dx_, dy_ = min(doors, key=lambda d: (d[0] - sx) ** 2 + (d[1] - sy) ** 2)
                    sx, sy = dx_, dy_ - 1
            _signboard(m, sx, sy, f['sign']); st['signs'] += 1
    return st


# ------------------------------------------------------------------ piscines públiques
def swim_pools(m, osm):
    """Les piscines públiques (leisure=swimming_pool amb «Municipal» al nom) es poden nedar: l'aigua
    queda transitable i el joc hi fa nedar el jugador (World:update_swim). Les privades, no."""
    n = 0
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('leisure') != 'swimming_pool' or 'unicipal' not in tags.get('name', ''):
            continue
        for x, y in poly_cells(osm, wid, m):
            if m.is_name('ground', x, y, 'pool_') and not m.L['structures'][y, x]:
                m.coll[y, x] = WALK
                n += 1
    return n


# ------------------------------------------------------------------ locals i comerços reals
def locals_(m):
    """Rètol de cada local del directori de l'Ajuntament (data/locals.json) damunt de la porta o l'aparador
    més proper (a 8 casselles com a molt) que encara no en tingui; els xiringuitos, caseta i para-sols
    a la sorra de la platja més propera."""
    data = json.load(open(os.path.join(ROOT, 'data/locals.json')))['locals']
    st = {'signs': 0, 'beachbars': 0, 'no_door': 0}
    door_ids = {gid for gid, n in m.name_of.items() if n.startswith('f_') and ('_door' in n or '_shop' in n or '_arch' in n)}
    struct = m.L['structures'] & 0x1FFFFFFF
    is_door = np.isin(struct, list(door_ids))
    used = np.zeros_like(is_door)
    for o in m.objects:                   # portes que ja tenen rètol (serveis, escoles, botigues)
        if o['type'] == 'signboard':
            ox, oy = int(o['x'] // 16), int(o['y'] // 16)
            used[oy, max(0, ox - 2):ox + 3] = True
    beach = m.ground == G['BEACH']
    for l in data:
        tx, ty = l['tile']
        if l['kind'] == 'beachbar':
            best = None
            for r in range(0, 15):
                for y in range(ty - r, ty + r + 1):
                    for x in range(tx - r, tx + r + 1):
                        if max(abs(x - tx), abs(y - ty)) != r or not (2 < x < m.W - 3 and 2 < y < m.H - 2):
                            continue
                        if beach[y, x] and all(m.free(x + dx, y, strict=False) and beach[y, x + dx] for dx in (-1, 0, 1)):
                            best = (x, y); break
                    if best: break
                if best: break
            if not best:
                st['no_door'] += 1
                continue
            x, y = best
            for dx in (-1, 0, 1):    # sòlid el posa el joc (World:rebuild_blockers) només si el local es mostra
                m.placed[y, x + dx] = True
            m.obj('prop', x * 16 + 8, y * 16 + 8, {'sprite': 'chiringuito', 'local_id': l['id']})
            _signboard(m, x, y + 1, 'sign_local_' + l['id'])
            # qui atén el xiringuito (s'hi pot parlar: és l'«entrada» del local)
            for dx, dy in ((0, 2), (1, 2), (-1, 2)):
                if beach[y + dy, x + dx] and m.free(x + dx, y + dy, strict=False):
                    m.obj('npc', (x + dx) * 16 + 8, (y + dy) * 16 + 8,
                          {'sprite': 'npc_tourist', 'say_name': 'El cambrer · ' + l['name'], 'facing': 'down', 'wander': 1,
                           'local_id': l['id'],
                           'say': 'Un granissat de llimona? Fa molta calor!|Recorda: crema solar i aigua fresca.'},
                          name='beachbar_' + l['id'])
                    break
            prng = random.Random(l['id'])
            for k, (dx, dy) in enumerate(((-3, 2), (3, 2), (0, 4), (-2, 5))):
                px, py = x + dx, y + dy
                if 0 < px < m.W - 1 and 0 < py < m.H - 1 and beach[py, px] and m.free(px, py, strict=False):
                    m.placed[py, px] = True
                    m.obj('prop', px * 16 + 8, py * 16 + 8, {'sprite': prng.choice(('parasol_red', 'parasol_blue')),
                                                              'local_id': l['id']})
            st['beachbars'] += 1
            continue
        y0, y1, x0, x1 = max(0, ty - 8), min(m.H, ty + 9), max(0, tx - 8), min(m.W, tx + 9)
        ys, xs = np.nonzero(is_door[y0:y1, x0:x1] & ~used[y0:y1, x0:x1])
        if not len(ys) and l['kind'] == 'industry':
            # naus del polígon (coordenades aproximades): la porta més propera una mica més lluny
            y0, y1, x0, x1 = max(0, ty - 20), min(m.H, ty + 21), max(0, tx - 20), min(m.W, tx + 21)
            ys, xs = np.nonzero(is_door[y0:y1, x0:x1] & ~used[y0:y1, x0:x1])
        if not len(ys):     # només es mostren els locals on es pot entrar (rètol damunt d'una porta)
            st['no_door'] += 1
            continue
        k = int(np.argmin((xs + x0 - tx) ** 2 + (ys + y0 - ty) ** 2))
        x, y = int(xs[k] + x0), int(ys[k] + y0)
        half = (len(l['sign']) * 4 + 6) // 32 + 1      # el rètol fa ~4 px per lletra: no en posem un altre al costat
        used[y, max(0, x - half):x + half + 1] = True
        _signboard(m, x, y, 'sign_local_' + l['id'])
        st['signs'] += 1
    return st


# ------------------------------------------------------------------ Port de Roda de Berà
PORT_BEACONS = ((1212, 1356, 'o_beacon_g'), (1226, 1330, 'o_beacon_r'))   # bocana (punta del dic i moll de ponent)


def port(m, osm):
    """Barcos amarrados de popa a los pantalanes (realdata.marina los deja de una casilla), norays y
    salvavidas en el borde del muelle y los dos faros de la bocana."""
    polys = [(o, i) for t, o, i, _ in sem.polygon_features(osm) if t.get('leisure') == 'marina']
    stats = {'boats': 0, 'bollards': 0, 'lifebuoys': 0, 'beacons': 0}
    if not polys:
        return stats
    mk = sem.rasterize_polys(polys)
    pier = mk & (m.d0 == D['PIER'])
    sea = mk & (m.ground == G['SEA'])
    used = np.zeros_like(mk)
    kinds = [k + c for k in 'sm' for c in 'brg']
    for y, x in sorted(zip(*np.nonzero(pier)), key=lambda c: (c[0], c[1])):
        for dx, dy, d, cells in ((1, 0, 'r', ((1, 0), (2, 0))), (-1, 0, 'l', ((-2, 0), (-1, 0))),
                                 (0, 1, 'd', ((0, 1), (0, 2))), (0, -1, 'u', ((0, -2), (0, -1)))):
            pos = [(x + cx, y + cy) for cx, cy in cells]
            if not all(0 < px < m.W - 1 and 0 < py < m.H - 1 and sea[py, px] and not pier[py, px] for px, py in pos):
                continue
            # un hueco entre barcos y ningún otro pantalán pegado a la proa
            if any(used[py + ey, px + ex] for px, py in pos for ex in (-1, 0, 1) for ey in (-1, 0, 1)):
                continue
            if rng.random() < 0.25:
                continue
            tag = rng.choice(kinds)
            for i, (px, py) in enumerate(pos):
                m.put(px, py, f'o_boat_{tag}_{d}_{i}', solid=False)
                used[py, px] = True
            stats['boats'] += 1
            break
    # muelle de losas de hormigón (las líneas de calle del OSM se dibujan encima)
    quay = mk & (m.d0 == D['PEDESTRIAN']) & (m.coll == WALK)
    for y, x in zip(*np.nonzero(quay & (m.L['structures'] == 0) & (m.L['ground_detail'] == 0))):
        m.put(x, y, f'g_yard_{(x * 7 + y * 3) % 2}', 'ground', solid=False)
    # norays y salvavidas: muelle junto a la dársena, lejos de las entradas a los pantalanes
    k = 0
    for y, x in zip(*np.nonzero(quay)):
        if not any(sea[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
            continue
        if any(pier[y + dy, x + dx] for dx in (-2, -1, 0, 1, 2) for dy in (-2, -1, 0, 1, 2)):
            continue
        inner = sum(1 for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if quay[y + dy, x + dx])
        if inner < 2 or m.L['structures'][y, x] or m.placed[y - 1:y + 2, x - 1:x + 2].any():
            continue
        k += 1
        if k % 5 == 0:
            m.put(x, y, 'o_bollard'); stats['bollards'] += 1
        elif k % 23 == 11:
            m.put(x, y, 'o_lifebuoy'); stats['lifebuoys'] += 1
    for bx, by, name in PORT_BEACONS:
        best = None
        for y in range(by - 6, by + 7):
            for x in range(bx - 6, bx + 7):
                if mk[y, x] and m.coll[y, x] == WALK and not m.L['structures'][y, x] and m.ground[y, x] in (G['ROCK'], G['URBAN']):
                    d = (x - bx) ** 2 + (y - by) ** 2
                    if best is None or d < best[0]:
                        best = (d, x, y)
        if best:
            m.put(best[1], best[2], name); stats['beacons'] += 1
    return stats


def solar_roofs(m):
    """Placas solars reals (maps/source/solar.json, de tools/solar_detect.py amb l'ortofoto de l'IGN): les caselles
    de teulat detectades passen a r_solar i la casa es marca amb un objecte solar_house a cada porta (a dins hi
    haurà inversor, bateries i algun aparell: src/world/procgen.lua opts.solar)."""
    path = os.path.join(ROOT, 'maps/source/solar.json')
    if not os.path.exists(path):
        return {'solar_houses': 0, 'note': 'sense solar.json (tools/solar_detect.py)'}
    d = json.load(open(path))
    S, B = m.L['structures'], m.bld
    by_b = {}
    for x, y in d.get('cells', []):
        if 0 <= x < m.W and 0 <= y < m.H and B[y, x]:
            by_b.setdefault(int(B[y, x]), []).append((x, y))
    st = {'solar_houses': 0, 'panels': 0}
    for b, cs in by_b.items():
        roof = [(x, y) for x, y in cs if m.is_name('structures', x, y, 'r_')]
        if not roof:   # la placa cau a la façana del dibuix: la casella de teulat més propera del mateix edifici
            cand = [(x, y) for y, x in np.argwhere(B == b).tolist() if m.is_name('structures', x, y, 'r_')]
            if not cand:
                continue
            cx, cy = cs[0]
            roof = [min(cand, key=lambda p: (p[0] - cx) ** 2 + (p[1] - cy) ** 2)]
        for x, y in roof:
            S[y, x] = m.gid('r_solar')
        st['panels'] += len(roof)
        doors = [(x, y) for y, x in np.argwhere(B == b).tolist()
                 if m.name_of.get(int(S[y, x]) & 0x1FFFFFFF, '').endswith('_door')]
        for x, y in doors:
            m.obj('solar_house', x * 16 + 8, y * 16 + 8, {'building': int(b)})
        st['solar_houses'] += 1
    return st


# cofres amagats a les zones importants (famílies de data/loot.json): a prop del lloc, en una casella a la qual
# s'arriba però mig tapada (arbres, murs, roques al voltant), perquè calgui buscar-los
HIDDEN_CHESTS = [
    ('poi', 'arc_de_bera', 'roman', 'cofre_arc'), ('poi', 'castell_creixell', 'roman', 'cofre_castell_creixell'),
    ('poi', 'roc_sant_gaieta', 'sea', 'cofre_roc'), ('area', 'Port de Roda de Berà', 'sea', 'cofre_port'),
    ('poi', 'pedrera_elies', 'crystal', 'cofre_pedrera'), ('poi', 'mirador_morella', 'forest', 'cofre_mirador'),
    ('poi', 'cucurull', 'forest', 'cofre_cucurull'), ('area', 'Parc de la Silena', 'forest', 'cofre_silena'),
    ('area', 'Parc Roda de Berà', 'iron', 'cofre_parc_roda'), ('poi', 'ermita_bera', 'silver', 'cofre_ermita'),
    ('area', 'Bosc', 'forest', 'cofre_bosc'), ('poi', 'sant_bartomeu', 'iron', 'cofre_sant_bartomeu'),
]


def _chest_spot(m, comp, main_c, cx, cy, rmax=13):
    """Casella per a un cofre amagat a prop de (cx, cy): transitable, on es pugui arribar i amb força coses al
    voltant (un racó), però no tancada del tot."""
    best, bscore = None, -1
    for r in range(3, rmax + 1):
        for dy in range(-r, r + 1):
            for dx in range(-r, r + 1):
                if max(abs(dx), abs(dy)) != r:
                    continue
                x, y = cx + dx, cy + dy
                if not (2 <= x < m.W - 2 and 2 <= y < m.H - 2) or not m.free(x, y, strict=False):
                    continue
                if comp[y, x] != main_c:
                    continue
                cover = sum(1 for ddy in (-1, 0, 1) for ddx in (-1, 0, 1)
                            if (ddx or ddy) and m.coll[y + ddy, x + ddx] != WALK)
                if cover > 5:   # tancada del tot: no s'hi arribaria
                    continue
                score = cover * 10 - r
                if score > bscore:
                    best, bscore = (x, y), score
        if best and bscore >= 20:
            break
    return best


def hidden_chests(m):
    streets = json.load(open(os.path.join(ROOT, 'data/streets.json')))
    areas = {}
    for a in streets.get('areas', []):
        if len(a.get('p', [])) > len(areas.get(a['n'], {}).get('p', [])):   # la part més gran
            areas[a['n']] = a
    comp = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    sp = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    main_c = comp[int(sp['y'] // 16), int(sp['x'] // 16)]
    placed = []
    for kind, ref, tier, flag in HIDDEN_CHESTS:
        if any(o.get('name') == flag for o in m.objects):
            continue
        if kind == 'poi':
            o = next((o for o in m.objects if o['type'] == 'poi' and o['name'] == ref), None)
            if not o:
                continue
            centres = [(int(o['x'] // 16), int(o['y'] // 16))]
        else:
            a = areas.get(ref)
            if not a:
                continue
            pts = a['p']                       # polígon en píxels: x0, y0, x1, y1…
            centres = [(int(sum(pts[0::2]) / len(pts[0::2]) // 16), int(sum(pts[1::2]) / len(pts[1::2]) // 16))]
            # el centre pot caure a l'aigua (port) o en un lloc tancat: després, els vèrtexs (la vora és terra)
            centres += [(int(pts[k] // 16), int(pts[k + 1] // 16)) for k in range(0, len(pts) - 1, 2)][::3]
        best = None
        for cx, cy in centres:
            best = _chest_spot(m, comp, main_c, cx, cy)
            if best:
                break
        if not best:
            continue
        x, y = best
        m.placed[y, x] = True   # (com els de muntanya: el joc el fa sòlid amb el seu rectangle)
        o = m.obj('chest', x * 16, y * 16, {'tier': tier, 'flag': flag}, name=flag)
        o['width'], o['height'] = 16, 16
        o.pop('point', None)
        placed.append({'flag': flag, 'tier': tier, 'at': [x, y]})
    return placed


# zones revisades: tema del monument (POI) → objecte amagat
POLISH_POIS = {'arc_de_bera': 'moneda_romana', 'castell_creixell': 'rajola_romana', 'ermita_bera': 'moneda_romana',
               'sant_bartomeu': 'rajola_romana', 'roc_sant_gaieta': 'vidre_mari', 'pedrera_elies': 'fossil',
               'mirador_morella': 'agata', 'cucurull': 'agata', 'ajuntament': 'moneda_romana', 'biblioteca': 'agata',
               'roda_de_mar': 'vidre_mari'}


def _spaced(cands, spacing, used, r, limit=None):
    """Tria de `cands` cel·les separades `spacing` entre elles i de les ja triades (`used`)."""
    cands = list(cands)
    r.shuffle(cands)
    out = []
    for x, y in cands:
        if limit is not None and len(out) >= limit:
            break
        if any((x - ux) ** 2 + (y - uy) ** 2 < spacing ** 2 for ux, uy in used + out):
            continue
        out.append((x, y))
    return out


def _hide(m, comp, main_c, cx, cy, item, name, rmin=2, rmax=12):
    """Objecte recollible en un racó (molta cosa al voltant) a prop de (cx, cy), on es pugui arribar."""
    best, bscore = None, -1
    for y in range(max(2, cy - rmax), min(m.H - 2, cy + rmax + 1)):
        for x in range(max(2, cx - rmax), min(m.W - 2, cx + rmax + 1)):
            d = max(abs(x - cx), abs(y - cy))
            if d < rmin or not m.free(x, y, strict=False) or comp[y, x] != main_c:
                continue
            cover = sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1) if (dx or dy) and m.coll[y + dy, x + dx] != WALK)
            if cover > 5:
                continue
            score = cover * 10 - d
            if score > bscore:
                best, bscore = (x, y), score
    if not best:
        return None
    x, y = best
    m.placed[y, x] = True
    m.obj('pickup', x * 16 + 8, y * 16 + 8, {'item': item}, name=name)
    return best


def zone_polish(m):
    """Mejora de las zonas más visitadas (2026-10-05): la playa con sombrillas, toallas, socorristas, duchas, helados
    y castillos de arena; las plazas con adoquines, estatua o fuente, jardineras, bancos, terrazas junto a los
    bares y aparcabicis; y los monumentos con panel informativo y bancos. En cada zona, un objeto escondido."""
    from scipy import ndimage
    r = random.Random(1005)
    st = {}
    seen_slugs = set()   # ids dels objectes amagats a les places (únics)
    inc = lambda k, n=1: st.__setitem__(k, st.get(k, 0) + n)
    comp = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    sp = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    main_c = comp[int(sp['y'] // 16), int(sp['x'] // 16)]
    spawns = [(int(o['x'] // 16), int(o['y'] // 16)) for o in m.objects if o['type'] == 'spawn']
    for x, y in spawns:              # el jugador apareix aquí: res al voltant
        m.placed[max(0, y - 2):y + 3, max(0, x - 2):x + 3] |= (m.coll[max(0, y - 2):y + 3, max(0, x - 2):x + 3] == WALK)
    # --- platja --------------------------------------------------------------------------------------------
    water = (m.coll & 3) == 2
    beach = (m.ground == G['BEACH']) & ((m.coll & 3) == WALK)
    dsea = ndimage.distance_transform_edt(~water)
    dland = ndimage.distance_transform_edt(beach | water)
    ok = lambda x, y: m.free(x, y) and comp[y, x] == main_c

    def cells(lo_s, hi_s, lo_l=1, hi_l=999):
        ys, xs = np.nonzero(beach & (dsea >= lo_s) & (dsea <= hi_s) & (dland >= lo_l) & (dland <= hi_l))
        return [(int(x), int(y)) for x, y in zip(xs, ys) if ok(int(x), int(y))]
    used = []
    for x, y in _spaced(cells(3, 7), 70, used, r):
        m.put(x, y, 'o_lifeguard'); used.append((x, y)); inc('lifeguards')
        for fx, fy in ((x + 1, y), (x - 1, y), (x, y + 1)):   # pal de la bandera al costat (color segons el temps)
            if ok(fx, fy):
                m.obj('beach_flag', fx * 16 + 8, fy * 16 + 14, {}, name=f'bandera_{len(used)}')
                m.placed[fy, fx] = True; used.append((fx, fy)); inc('flags')
                break
    for x, y in _spaced(cells(2, 99, 1, 2), 40, used, r):
        m.put(x, y, 'o_shower'); used.append((x, y)); inc('showers')
    for x, y in _spaced([c for c in cells(2, 99, 1, 3) if all(abs(c[0] - ux) + abs(c[1] - uy) > 3 for ux, uy in used)],
                        110, [], r):
        m.put(x, y, 'o_icecream'); used.append((x, y)); inc('icecream')
    for x, y in _spaced(cells(2, 4), 45, used, r):
        m.put(x, y, 'o_sandcastle'); used.append((x, y)); inc('sandcastles')
    for k, (x, y) in enumerate(_spaced(cells(4, 14, 3), 5, used, r)):
        if r.random() < 0.15 or not ok(x, y):
            continue
        m.put(x, y, f'o_umbrella_{k % 3}')
        used.append((x, y)); inc('umbrellas')
        # al costat, a l'ombra: tovallola (es pot trepitjar) o un parell d'hamaques
        side = [(dx, dy) for dx, dy in ((1, 0), (-1, 0), (0, 1)) if m.free(x + dx, y + dy, strict=False) and beach[y + dy, x + dx]]
        if not side:
            continue
        dx, dy = side[0]
        if k % 3 == 2 and m.free(x + 2 * dx, y + 2 * dy, strict=False) and beach[y + 2 * dy, x + 2 * dx] and dy == 0:
            for j in (1, 2):
                m.put(x + j * dx, y, f'o_lounger_{k % 2}'); inc('loungers')
        else:
            m.put(x + dx, y + dy, f'o_towel_{(x + y) % 2}', solid=False)
            m.placed[y + dy, x + dx] = True
            inc('towels')
    for k, (x, y) in enumerate(_spaced(cells(1, 2), 60, [], r, limit=10)):   # vidres polits a la vora de l'aigua
        if not m.placed[y, x]:
            m.placed[y, x] = True
            m.obj('pickup', x * 16 + 8, y * 16 + 8, {'item': 'vidre_mari'}, name=f'vidre_platja_{k + 1}')
            inc('beach_glass')
    # --- places: adoquins, estàtua o font, jardineres, bancs, terrasses i aparcabicis ------------------------
    from PIL import Image, ImageDraw
    streets = json.load(open(os.path.join(ROOT, 'data/streets.json')))
    for a in streets.get('areas', []):
        if a.get('k') != 'square' and not (a.get('k') == 'park' and a['n'].startswith('Plaça')):
            continue
        pts = np.array(a['p'], float).reshape(-1, 2) / 16
        x0, y0 = np.floor(pts.min(0)).astype(int); x1, y1 = np.ceil(pts.max(0)).astype(int)
        if (x1 - x0) * (y1 - y0) < 16 or (x1 - x0) * (y1 - y0) > 900:
            continue
        im = Image.new('1', (x1 - x0 + 1, y1 - y0 + 1), 0)
        ImageDraw.Draw(im).polygon([(px - x0 - 0.5, py - y0 - 0.5) for px, py in pts], fill=1)
        iy, ix = np.nonzero(np.array(im))
        cs = [(int(x + x0), int(y + y0)) for x, y in zip(ix, iy)
              if 1 <= x + x0 < m.W - 1 and 1 <= y + y0 < m.H - 1 and m.coll[y + y0, x + x0] == WALK]
        if len(cs) < 12:
            continue
        S = set(cs)
        inc('squares')
        for x, y in cs:                                   # paviment d'adoquins (no sota els carrers)
            if not m.d0[y, x] and not m.L['structures'][y, x] and m.ground[y, x] in (G['URBAN'], G['PARK'], G['GRASS'], G['DRY']):
                m.put(x, y, f'g_cobble_{(x + y) % 3}', 'ground', solid=False)
        cx, cy = (sum(c[0] for c in cs) / len(cs), sum(c[1] for c in cs) / len(cs))
        has_fountain = any(m.is_name('structures', x, y, 'o_fountain') for x, y in cs)
        centre = sorted((c for c in cs if ok(*c)), key=lambda c: (c[0] - cx) ** 2 + (c[1] - cy) ** 2)
        if centre and not has_fountain:
            x, y = centre[0]
            m.put(x, y, 'o_statue' if len(cs) % 2 else 'o_fountain'); inc('statues')
        border = [c for c in cs if any((c[0] + dx, c[1] + dy) not in S for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        bord_ok = [c for c in border if ok(*c)]
        for x, y in _spaced(bord_ok, 4, [], r, limit=4):
            if ok(x, y): m.put(x, y, 'o_planter'); inc('planters')
        for x, y in _spaced([c for c in border if ok(*c)], 3, [], r, limit=3):
            if ok(x, y): m.put(x, y, 'o_bench'); inc('benches')
        shopside = [c for c in cs if ok(*c) and any(m.is_name('structures', c[0] + dx, c[1] + dy, 'f_') and
                    'shop' in m.name_of.get(int(m.L['structures'][c[1] + dy, c[0] + dx]) & 0x1FFFFFFF, '')
                    for dx in range(-2, 3) for dy in range(-2, 3))]
        for x, y in _spaced(shopside, 2, [], r, limit=3):
            if ok(x, y): m.put(x, y, 'o_terrace'); inc('terraces')
        rest = [c for c in cs if ok(*c)]
        if rest and len(cs) >= 30:
            x, y = r.choice(rest); m.put(x, y, 'o_bike_rack'); inc('bike_racks')
        import unicodedata
        slug = ''.join(ch for ch in unicodedata.normalize('NFKD', a['n'].lower()) if ch.isascii() and ch.isalnum())[:24]
        # dues places amb el mateix nom (passa a altres pobles): l'id de l'objecte ha de ser únic
        base_slug, k_ = slug, 2
        while slug in seen_slugs:
            slug, k_ = f'{base_slug}{k_}', k_ + 1
        seen_slugs.add(slug)
        if _hide(m, comp, main_c, int(cx), int(cy), 'agata' if len(cs) % 2 else 'moneda_romana', f'amagat_{slug}', 1, 8):
            inc('hidden_items')
    # --- monuments: panell informatiu, bancs i jardineres; un objecte del tema amagat a prop -----------------
    for o in [o for o in m.objects if o['type'] == 'poi' and o['name'] in POLISH_POIS]:
        cx, cy = int(o['x'] // 16), int(o['y'] // 16)
        ring = sorted(((cx + dx, cy + dy) for dy in range(-6, 7) for dx in range(-6, 7)
                       if 2 <= max(abs(dx), abs(dy)) <= 6), key=lambda c: abs(c[0] - cx) + abs(c[1] - cy))
        free_ring = [c for c in ring if ok(*c)]
        if free_ring:
            x, y = free_ring[0]; m.put(x, y, 'o_info'); inc('info_panels')
        for k, (x, y) in enumerate(_spaced([c for c in ring if ok(*c)], 3, [], r, limit=3)):
            if ok(x, y): m.put(x, y, ('o_bench', 'o_planter', 'o_bench')[k]); inc('monument_props')
        if _hide(m, comp, main_c, cx, cy, POLISH_POIS[o['name']], f'amagat_{o["name"]}', 3, 12):
            inc('hidden_items')
    return st


def _site(m, cells, name, r, building=True, comp=None, main_c=None):
    """Una obra: terra de solar, tanca amb porta, (estructura de formigó), grua, maquinària, caseta, obrers,
    rètol i un cofre. `cells`: caselles candidates (s'hi deixen fora vies, edificis i el que no és transitable)."""
    from scipy import ndimage
    st = {}
    inc = lambda k, n=1: st.__setitem__(k, st.get(k, 0) + n)
    name_at = lambda x, y: m.name_of.get(int(m.L['structures'][y, x]) & 0x1FFFFFFF, '')
    S = set()
    for x, y in cells:
        if not (2 <= x < m.W - 2 and 2 <= y < m.H - 2) or m.d0[y, x] or m.bld[y, x]:
            continue
        n = name_at(x, y)
        if n.startswith(('f_', 'r_')) or (m.coll[y, x] & 3) not in (WALK, SOLID) or m.coll[y, x] & 28:
            continue
        if (m.coll[y, x] & 3) == SOLID and not n.startswith(('tree_', 'bush', 'o_')):
            continue
        S.add((x, y))
    g0 = np.zeros((m.H, m.W), bool)                  # sense sortints d'una casella (farien bosses tancades)
    for x, y in S: g0[y, x] = True
    g0 = ndimage.binary_opening(g0, np.ones((3, 3), bool))
    S = {(x, y) for x, y in S if g0[y, x]}
    if len(S) < 12:
        return st
    for x, y in S:                                   # solar net: fora arbres i objectes solts
        n = name_at(x, y)
        if n.startswith('tree_'):
            m.L['overhead'][y - 1, x] = 0
        if n:
            m.L['structures'][y, x] = 0
        m.coll[y, x] = WALK
        m.placed[y, x] = False
        m.L['ground_detail'][y, x] = 0
        m.put(x, y, f'g_site_{(x * 7 + y * 3) % 3}', 'ground', solid=False)
    inc('cells', len(S))
    grid = np.zeros((m.H, m.W), bool)
    for x, y in S: grid[y, x] = True
    lab, nlab = ndimage.label(grid)
    near_facade = lambda x, y: any(name_at(x + dx, y + dy).startswith('f_') and not name_at(x + dx, y + dy).startswith('f_skel')
                                   for dx in (-1, 0, 1) for dy in (-1, 0, 1))
    slug = ''.join(ch for ch in name.lower() if ch.isascii() and ch.isalnum())[:20]
    ys_, xs_ = np.nonzero(grid)
    y0_, y1_, x0_, x1_ = max(0, ys_.min() - 8), ys_.max() + 9, max(0, xs_.min() - 8), xs_.max() + 9
    dist_b = np.full((m.H, m.W), 99.0)
    dist_b[y0_:y1_, x0_:x1_] = ndimage.distance_transform_edt(m.bld[y0_:y1_, x0_:x1_] == 0)
    for k in range(1, nlab + 1):
        ys, xs = np.nonzero(lab == k)
        part = set(zip(xs.tolist(), ys.tolist()))
        if len(part) < 12:
            continue
        # vora = on l'obra toca terreny obert (al costat d'un edifici no cal tanca: tancaria els passadissos)
        border = [c for c in part if any((c[0] + dx, c[1] + dy) not in part and (m.coll[c[1] + dy, c[0] + dx] & 3) == WALK
                                         and not m.bld[c[1] + dy, c[0] + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))]
        # porta: casella de vora amb carrer o camí just a fora (2 caselles d'amplada)
        def gate_score(c):
            outs = [(c[0] + dx, c[1] + dy) for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)) if (c[0] + dx, c[1] + dy) not in part]
            good = [o for o in outs if m.coll[o[1], o[0]] == WALK and (comp is None or comp[o[1], o[0]] == main_c)]
            return (len(good) > 0, any(m.d0[o[1], o[0]] for o in good))
        cand = sorted(border, key=lambda c: gate_score(c), reverse=True)
        if not cand or not gate_score(cand[0])[0]:
            continue
        g0 = cand[0]
        gate = {g0}
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if (g0[0] + dx, g0[1] + dy) in border and gate_score((g0[0] + dx, g0[1] + dy))[0]:
                gate.add((g0[0] + dx, g0[1] + dy)); break
        bset = set(border)
        fence = []
        for x, y in border:
            if (x, y) in gate or near_facade(x, y) or dist_b[y, x] < 3:   # vora d'un edifici: passadís, sense tanca
                continue
            hz = (x - 1, y) in bset or (x + 1, y) in bset
            vt = (x, y - 1) in bset or (x, y + 1) in bset
            m.put(x, y, 'o_sfence_c' if hz and vt else 'o_sfence_h' if hz else 'o_sfence_v' if vt else 'o_sfence_c')
            fence.append((x, y))
        inc('fence', len(fence))
        inner = {c for c in part if c not in bset and all((c[0] + dx, c[1] + dy) not in bset and (c[0] + dx, c[1] + dy) in part
                                                         for dx in (-1, 0, 1) for dy in (-1, 0, 1))}
        free_in = lambda x, y: (x, y) in inner and m.free(x, y)
        gx, gy = sum(c[0] for c in gate) / len(gate), sum(c[1] for c in gate) / len(gate)
        # rètol a la tanca, al costat de la porta
        side = sorted(fence, key=lambda c: abs(c[0] - gx) + abs(c[1] - gy))
        if side:
            sx, sy = side[0]
            m.obj('sign', sx * 16 + 8, sy * 16 + 8,
                  {'say': f"OBRA · {name}|Prohibit el pas a persones alienes a l'obra.|Ús obligatori del casc!"},
                  name=f'sign_obra_{slug}_{k}')
        bx = None
        if building:                                 # estructura de formigó a mig fer
            cx_, cy_ = sum(c[0] for c in inner) / max(1, len(inner)), sum(c[1] for c in inner) / max(1, len(inner))
            for w, h in ((12, 7), (10, 6), (9, 6), (8, 5), (12, 4), (8, 4), (6, 4), (5, 3)):
                best = None
                for (x0, y0) in inner:
                    if all((x, y) in inner for x in range(x0 - 1, x0 + w + 1) for y in range(y0 - 1, y0 + h + 1)):
                        d = (x0 + w / 2 - cx_) ** 2 + (y0 + h / 2 - cy_) ** 2
                        if best is None or d < best[0]:
                            best = (d, x0, y0)
                if best:
                    _, x0, y0 = best
                    for y in range(y0, y0 + h):
                        for x in range(x0, x0 + w):
                            if y < y0 + h - 1:
                                m.put(x, y, f'r_skel_{(x + y) % 2}')
                            else:
                                pos = 's' if w == 1 else 'l' if x == x0 else 'r' if x == x0 + w - 1 else 'm'
                                m.put(x, y, f'f_skel_{pos}')
                    for x in (x0 - 1, x0 + w):           # bastides als costats de la façana
                        y = y0 + h - 1
                        if free_in(x, y) or ((x, y) in inner and not m.placed[y, x]):
                            m.put(x, y, 'o_scaffold'); inc('scaffold')
                            if not m.L['overhead'][y - 1, x]: m.L['overhead'][y - 1, x] = m.gid('o_scaffold_top')
                    bx = (x0, y0, w, h)
                    inc('skeletons')
                    break
        # grua: base dins l'obra i el braç per sobre (capa overhead)
        crane_c = sorted(inner, key=lambda c: (abs(c[0] - (bx[0] + bx[2] + 1)) + abs(c[1] - (bx[1] + bx[3] // 2))) if bx else
                         (c[0] - gx) ** 2 + (c[1] - gy) ** 2, reverse=not bx)
        for x, y in crane_c[:200]:
            if not free_in(x, y) or y < 7:
                continue
            cells_oh = [(x, y - j) for j in range(1, 5)] + [(x + j, y - 5) for j in range(-2, 6)] + \
                       [(x + 4, y - j) for j in range(1, 5)]
            if any(m.L['overhead'][cy, cx] for cx, cy in cells_oh if 0 <= cx < m.W):
                continue
            m.put(x, y, 'o_crane_base')
            for j in range(1, 5): m.L['overhead'][y - j, x] = m.gid('o_crane_mast')
            for j in range(-2, 6):
                m.L['overhead'][y - 5, x + j] = m.gid('o_crane_counter' if j == -2 else 'o_crane_cab' if j == 0 else 'o_crane_jib')
            for j in range(2, 5): m.L['overhead'][y - j, x + 4] = m.gid('o_crane_cable')
            m.L['overhead'][y - 1, x + 4] = m.gid('o_crane_hook')
            inc('cranes')
            break
        # caseta, lavabo i maquinària
        order = sorted(inner, key=lambda c: (c[0] - gx) ** 2 + (c[1] - gy) ** 2)
        for x, y in order:
            if free_in(x, y) and free_in(x + 1, y):
                m.put(x, y, 'o_cabin_l'); m.put(x + 1, y, 'o_cabin_r'); inc('cabins')
                if free_in(x + 3, y): m.put(x + 3, y, 'o_toilet')
                break
        spots = [c for c in inner if free_in(*c)]
        r.shuffle(spots)
        kit = ['o_mixer', 'o_sandpile', 'o_sandpile', 'o_bricks', 'o_bricks', 'o_rebar', 'o_barrow', 'o_cone', 'o_cone']
        if len(inner) > 120:
            kit += ['o_bricks', 'o_rebar', 'o_mixer', 'o_cone']
        for nm in kit:
            for x, y in spots:
                if free_in(x, y):
                    m.put(x, y, nm); inc('props'); break
        for x, y in spots:
            if len(inner) > 90 and free_in(x, y) and free_in(x + 1, y):
                m.put(x, y, 'o_digger_l'); m.put(x + 1, y, 'o_digger_r'); inc('diggers'); break
        # obrers
        talk = [("L'obrer", 'npc_builder', "Compte! Aquí dins cal portar casc.|Fem pisos nous: d'aquí a un any hi viurà gent."),
                ("La cap d'obra", 'npc_builder2', "La grua puja els palets de maons fins a dalt de tot.|Ahir vam perdre un cofre d'eines… "
                                                  "segur que és per aquí, en algun racó de l'obra.")]
        for j, (who, spr, say) in enumerate(talk):
            for x, y in spots:
                if free_in(x, y) and (not bx or abs(x - bx[0]) + abs(y - (bx[1] + bx[3])) < 14):
                    m.placed[y, x] = True
                    m.obj('npc', x * 16 + 8, y * 16 + 8, {'sprite': spr, 'say_name': f'{who} · {name}', 'facing': 'down',
                                                          'wander': 2, 'say': say}, name=f'obrer_{slug}_{k}_{j}')
                    inc('workers'); break
        # cofre d'eines en el racó més allunyat de la porta
        far = sorted((c for c in inner if m.free(c[0], c[1], strict=False)), key=lambda c: -((c[0] - gx) ** 2 + (c[1] - gy) ** 2))
        if far and not st.get('chests'):
            x, y = far[0]
            m.placed[y, x] = True
            o = m.obj('chest', x * 16, y * 16, {'tier': 'iron', 'flag': f'cofre_obra_{slug}'}, name=f'cofre_obra_{slug}')
            o['width'], o['height'] = 16, 16
            o.pop('point', None)
            inc('chests')
    return st


def construction_sites(m, osm):
    """Edificis i solars en obres (2026-10-05): els building=construction de l'OSM es tornen estructures de formigó
    a mig fer (abans eren cases amb teulada i fins i tot plaques); els landuse=construction i els solars de
    map-overrides.json (construction_sites, p. ex. els del camp de futbol) són obres amb tanca, grua i obrers."""
    from scipy import ndimage
    r = random.Random(1010)
    out = {}
    comp = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    sp = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    main_c = comp[int(sp['y'] // 16), int(sp['x'] // 16)]
    name_at = lambda x, y: m.name_of.get(int(m.L['structures'][y, x]) & 0x1FFFFFFF, '')
    # 1) edificis en construcció: estructura de formigó
    ids = set()
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('building') != 'construction':
            continue
        loc = area_cells(osm, wid)
        if loc is None:
            continue
        y0, x0, msk = loc
        ys, xs = np.nonzero(msk)
        v = m.bld[ys + y0, xs + x0]
        v = v[v > 0]
        if len(v):
            ids.add(int(np.bincount(v).argmax()))
    if ids:
        mask = np.isin(m.bld, list(ids))
        mask |= np.roll(mask, 1, axis=0)             # la façana és la fila de sota
        n_sk = 0
        for y, x in zip(*np.nonzero(mask)):
            n = name_at(x, y)
            if n.startswith('r_'):
                m.L['structures'][y, x] = m.gid(f'r_skel_{(x + y) % 2}'); n_sk += 1
            elif n.startswith('f_') and not n.startswith('f_skel'):
                parts = n.split('_')
                pos = parts[2] if len(parts) > 2 and parts[2] in ('l', 'm', 'r', 's') else 'm'
                m.L['structures'][y, x] = m.gid(f'f_skel_{pos}'); n_sk += 1
        gone = [o for o in m.objects if o['type'] in ('solar_house', 'signboard')
                and mask[min(m.H - 1, int(o['y'] // 16)), min(m.W - 1, int(o['x'] // 16))]]
        for o in gone:
            m.objects.remove(o)
        out['skeleton_buildings'] = len(ids)
        out['skeleton_cells'] = n_sk
        # al voltant, l'obra: solar amb tanca, grua i obrers
        ring = ndimage.binary_dilation(np.isin(m.bld, list(ids)), iterations=4)
        lab, nl = ndimage.label(ring)
        for k in range(1, nl + 1):
            ys, xs = np.nonzero(lab == k)
            st = _site(m, list(zip(xs.tolist(), ys.tolist())), 'Pisos en construcció', r, building=False, comp=comp, main_c=main_c)
            out[f'osm_buildings_{k}'] = st
    # 2) solars en obres de l'OSM i 3) els de map-overrides.json
    for wid, (tags, refs) in osm.ways.items():
        if tags.get('landuse') == 'construction':
            loc = area_cells(osm, wid)
            if loc is None:
                continue
            y0, x0, msk = loc
            ys, xs = np.nonzero(msk)
            out[f'landuse_{wid}'] = _site(m, list(zip((xs + x0).tolist(), (ys + y0).tolist())), tags.get('name', 'Obra nova'),
                                          r, comp=comp, main_c=main_c)
    for f in OVERRIDES.get('construction_sites', []):
        x0, y0, x1, y1 = f['rect']
        cells = [(x, y) for y in range(y0, y1 + 1) for x in range(x0, x1 + 1)]
        out[f['name']] = _site(m, cells, f['name'], r, building=f.get('building', True), comp=comp, main_c=main_c)
    return out


def fountains(m):
    """Fonts ornamentals de map-overrides.json (la Plaça dels Pins, la de la Sardana…) i, al final, totes les fonts
    passen a la versió animada (o_fountain_a_*: raig i ones al bassal, 4 fotogrames)."""
    st = {'placed': 0, 'animated': 0}
    old = m.gid('o_fountain')
    for f in OVERRIDES.get('fountains', []):
        cx, cy = f['at']
        if any(int(m.L['structures'][y, x]) & 0x1FFFFFFF in (old, m.gid('o_fountain_a_0'))
               for y in range(cy - 4, cy + 5) for x in range(cx - 4, cx + 5)):
            continue
        spot = sorted(((cx + dx, cy + dy) for dy in range(-4, 5) for dx in range(-4, 5)),
                      key=lambda c: abs(c[0] - cx) + abs(c[1] - cy))
        for x, y in spot:
            if m.free(x, y):
                m.put(x, y, 'o_fountain'); st['placed'] += 1
                break
    a0 = m.gid('o_fountain_a_0')
    hit = (m.L['structures'] & 0x1FFFFFFF) == old
    m.L['structures'][hit] = a0
    st['animated'] = int(hit.sum())
    return st


def gardens(m):
    """Jardins de les cases (2026-10-05): a les parcel·les (terra urbana a prop d'una casa) on l'ortofoto és verda,
    gespa; flors arran de casa, algun seto a la vora i arbres on es veu copa. Abans només es feien jardí les
    parcel·les molt verdes (llindar 0,5 suavitzat 7×7) i la majoria de jardins quedaven de terra."""
    from scipy import ndimage
    import realdata
    rd = realdata.load()
    if rd is None:
        return {}
    st = {'lawn': 0, 'flowers': 0, 'bushes': 0, 'trees': 0}
    grn = ndimage.uniform_filter(rd['green'], 3)
    can = ndimage.uniform_filter(rd['canopy'], 3)
    near_house = ndimage.distance_transform_edt(m.bld == 0) <= 7
    plot = (m.ground == G['URBAN']) & near_house & (m.bld == 0) & (m.d0 == 0) & ((m.coll & 3) == WALK) \
        & (m.L['structures'] == 0) & (m.L['ground_detail'] == 0) & ~m.placed
    garden = plot & (grn > 0.33)
    urban_tile = np.isin(m.L['ground'] & 0x1FFFFFFF, [m.gid(n) for n in m.tiles if n.startswith('g_urban')])
    garden &= urban_tile                              # no als patis, pistes ni aparcaments
    garden = ndimage.binary_opening(garden, iterations=1)
    m.garden_mask = garden                            # errand_spots: on els veïns reguen
    ys, xs = np.nonzero(garden)
    r = random.Random(909)
    for y, x in zip(ys.tolist(), xs.tolist()):
        by_house = any(m.bld[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if by_house and (x * 5 + y * 3) % 4 == 0:
            m.put(x, y, f'g_flowers_{(x + y) % 3}', 'ground', solid=False); st['flowers'] += 1
        else:
            m.put(x, y, f'g_grass_{(x * 7 + y) % 3}', 'ground', solid=False); st['lawn'] += 1
    trees = []
    order = list(zip(ys.tolist(), xs.tolist()))
    r.shuffle(order)
    for y, x in order:
        if can[y, x] > 0.4 and m.free(x, y) and not m.L['overhead'][y - 1, x] and not m.L['structures'][y - 1, x] \
                and not m.bld[y - 1, x] and all((x - tx) ** 2 + (y - ty) ** 2 >= 9 for tx, ty in trees):
            kind = ('olive', 'cypress', 'palm', 'pine1')[(x + 3 * y) % 4]
            m.put(x, y, f'tree_{kind}_bot'); m.L['overhead'][y - 1, x] = m.gid(f'tree_{kind}_top')
            trees.append((x, y)); st['trees'] += 1
    bushes = []
    for y, x in order:
        edge = any(not garden[y + dy, x + dx] and not m.bld[y + dy, x + dx] for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge and m.free(x, y) and r.random() < 0.18 and all(abs(x - bx) + abs(y - by) >= 3 for bx, by in bushes):
            m.put(x, y, f'bush_{(x + y) % 2}'); bushes.append((x, y)); st['bushes'] += 1
    return st


def errand_spots(m):
    """Llocs dels encàrrecs dels veïns (src/systems/errands.lua, 2026-10-05): objectes 'errand' amb `kind`
    bakery (davant dels forns), hair (perruqueries i barberies), pool (dins l'aigua de les piscines municipals,
    s'hi pot nedar), pool_home (a la vora d'una piscina privada), beach (sorra a prop de l'aigua) i garden (un per
    jardí de casa de 6 caselles o més). Sempre en
    caselles transitables de la zona principal, perquè els personatges hi arribin caminant."""
    from scipy import ndimage
    comp = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    sp = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    main_c = comp[int(sp['y'] // 16), int(sp['x'] // 16)]
    walk = ((m.coll & 3) == WALK) & (comp == main_c)
    st = {}
    taken = set()

    def add(kind, x, y, **extra):
        if (x, y) in taken:
            return
        taken.add((x, y))
        m.obj('errand', x * 16 + 8, y * 16 + 8, dict({'kind': kind}, **extra), name=f'errand_{kind}_{st.get(kind, 0) + 1}')
        st[kind] = st.get(kind, 0) + 1

    def near_walk(x, y, rad=3):
        best = None
        for dy in range(-rad, rad + 1):
            for dx in range(-rad, rad + 1):
                xx, yy = x + dx, y + dy
                if 0 <= xx < m.W and 0 <= yy < m.H and walk[yy, xx] and not m.L['structures'][yy, xx]:
                    d = dx * dx + dy * dy + (0 if dy > 0 else 2)    # millor davant (a sota) del rètol
                    if best is None or d < best[0]:
                        best = (d, xx, yy)
        return best and best[1:]
    shops = {'bakery': ('forn', 'fleca', 'bakery', 'pastisser', 'panader'),
             'hair': ('perruq', 'barber', 'hair', 'peluquer')}
    for o in m.objects:
        if o['type'] != 'signboard':
            continue
        spr = next((p['value'] for p in o['properties'] if p['name'] == 'sprite'), '').lower()
        for kind, keys in shops.items():
            if any(k in spr for k in keys):
                c = near_walk(int(o['x'] // 16), int(o['y'] // 16) + 1)
                if c:
                    add(kind, *c, shop=spr.replace('sign_local_', ''))
    # piscines
    pool = np.isin(m.L['ground'] & 0x1FFFFFFF, [m.gid(n) for n in m.tiles if n.startswith('pool_')])
    lab, n = ndimage.label(pool)
    for i in range(1, n + 1):
        ys, xs = np.nonzero(lab == i)
        if len(xs) < 4:
            continue
        swim = [(x, y) for x, y in zip(xs.tolist(), ys.tolist()) if walk[y, x]]
        if swim:                                   # municipal: a dins, i un parell de llocs per nedar
            for x, y in swim[len(swim) // 3::max(1, len(swim) // 3)][:3]:
                add('pool', x, y, swim=True)
            continue
        ring = ndimage.binary_dilation(lab == i) & ~pool & walk   # privada: a la vora (només hi va qui hi viu)
        ry, rx = np.nonzero(ring)
        if len(rx):
            add('pool_home', int(rx[len(rx) // 2]), int(ry[len(rx) // 2]))
    # platja: sorra transitable a 1-4 caselles de l'aigua, separades
    water = (m.coll & 3) == 2
    dsea = ndimage.distance_transform_edt(~water)
    sand = (m.ground == G['BEACH']) & walk & (dsea >= 1.5) & (dsea <= 4) & (m.L['structures'] == 0)
    ys, xs = np.nonzero(sand)
    picked = []
    for x, y in sorted(zip(xs.tolist(), ys.tolist()), key=lambda c: (c[0] * 7 + c[1] * 13) % 101):
        if all((x - a) ** 2 + (y - b) ** 2 >= 10 ** 2 for a, b in picked):
            picked.append((x, y)); add('beach', x, y)
        if len(picked) >= 60:
            break
    # jardins: un lloc per jardí (el més central que encara sigui transitable)
    gm = getattr(m, 'garden_mask', None)
    if gm is not None:
        lab, n = ndimage.label(gm)
        for i in range(1, n + 1):
            ys, xs = np.nonzero((lab == i) & walk & (m.L['structures'] == 0))
            if len(xs) >= 6:
                cx, cy = xs.mean(), ys.mean()
                k = int(np.argmin((xs - cx) ** 2 + (ys - cy) ** 2))
                add('garden', int(xs[k]), int(ys[k]))
    return st


LANDMARK_POI = {'sant_bartomeu': 'church', 'biblioteca': 'library', 'ajuntament': 'townhall', 'ermita_bera': 'chapel'}


def landmark_doors(m):
    """Portes dels edificis monumentals (2026-10-05): l'església de Sant Bartomeu, la biblioteca, l'ajuntament i
    l'ermita són sprites sòlids (landmark) sense porta. Al mig de la fila de baix s'obre una casella transitable
    amb un objecte 'door' (poi = tipus d'interior de src/world/procgen.lua P.poi; el joc el genera i en sortir
    torna davant de la porta). Cal que la casella de davant sigui transitable."""
    st = {}
    for o in [o for o in m.objects if o['type'] == 'landmark']:
        kind = LANDMARK_POI.get(o['name'])
        if not kind:
            continue
        x0, y0 = int(o['x'] // 16), int(o['y'] // 16)
        w, h = max(1, int(o['width'] // 16)), max(1, int(o['height'] // 16))
        by = y0 + h - 1
        best = None
        for dx in sorted(range(w), key=lambda d: abs(d - w // 2)):
            x = x0 + dx
            if 2 <= x < m.W - 2 and by + 1 < m.H - 2 and (m.coll[by + 1, x] & 3) == WALK and not m.L['structures'][by + 1, x]:
                best = x
                break
        if best is None:
            st[o['name']] = 'sense porta'
            continue
        m.coll[by, best] = m.coll[by, best] - (m.coll[by, best] & 3)       # la porta es pot travessar
        m.L['structures'][by, best] = 0
        m.obj('door', best * 16, by * 16, {'poi': kind, 'poi_id': o['name'],
                                          'label': next((p['value'] for p in o.get('properties', []) if p['name'] == 'label'), o['name'])},
              name=f'door_poi_{o["name"]}')
        m.objects[-1].update({'width': 16, 'height': 16, 'point': False})
        m.objects[-1].pop('point', None)
        st[o['name']] = [best, by]
    return st


FARM_NAMES = ['Granja del Ruc', 'Mas del Pi', 'Granja de les Gallines', 'Mas de la Font']


def farms(m, max_farms=4):
    """Granges al sud de l'autopista (2026-10-05, src/systems/farm.lua). Les cases de pagès són els edificis
    aïllats entre conreus i camps secs al sud de l'AP-7 (així surten a l'ortofoto). A cadascuna: un corral de
    fusta amb porta cap a la casa (rucs i cavalls, o porcs i ovelles), un abeurador i bales de palla, gallines
    soltes a la vora de la casa i el pagès (objecte 'farmer') que dona pinso. Objectes 'farm_pen' amb el rectangle
    on es mouen els animals i `animals` = "ruc:2,cavall:1"; un 'spot' per granja per a la brúixola."""
    from scipy import ndimage
    mot = []
    for o in m.layers['lines']['objects']:
        if any(q['name'] == 'cls' and q['value'] == 'MOTORWAY' for q in o.get('properties', [])):
            mot += [((o['x'] + q['x']) / 16, (o['y'] + q['y']) / 16) for q in o['polyline']]
    if not mot:
        return {}
    mx = np.array([a for a, _ in mot]); my = np.array([b for _, b in mot])

    def mot_y(x):
        i = np.argsort(np.abs(mx - x))[:4]
        return my[i].mean()
    rural = np.isin(m.ground, [G['FARM'], G['VINEYARD'], G['DRY'], G['GRASS']])
    comp = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    sp = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    main_c = comp[int(sp['y'] // 16), int(sp['x'] // 16)]
    lab, n = ndimage.label(m.bld > 0)
    cands = []
    for i, sl in enumerate(ndimage.find_objects(lab)):
        if sl is None:
            continue
        y0, y1, x0, x1 = sl[0].start, sl[0].stop, sl[1].start, sl[1].stop
        cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        size = int((lab[sl] == i + 1).sum())
        if size < 4 or not (mot_y(cx) + 3 < cy < mot_y(cx) + 150):
            continue
        win = rural[max(0, y0 - 8):y1 + 8, max(0, x0 - 8):x1 + 8]
        busy = (m.bld[max(0, y0 - 14):y1 + 14, max(0, x0 - 14):x1 + 14] > 0).mean()
        if win.mean() > 0.55 and busy < 0.12:
            cands.append((size, x0, y0, x1, y1))
    cands.sort(reverse=True)
    st = {'farms': 0, 'pens': 0, 'animals': 0, 'fence': 0}
    chosen = []
    r = random.Random(2026)

    def pen_at(px, py, pw, ph):
        for y in range(py, py + ph):
            for x in range(px, px + pw):
                if not (2 <= x < m.W - 2 and 2 <= y < m.H - 2) or not m.free(x, y, strict=False) or not rural[y, x] \
                        or comp[y, x] != main_c or m.bld[y, x]:
                    return False
        return True
    herds = [('ruc:2,cavall:2', 'ovella:3'), ('porc:3', 'ruc:1,cavall:1'), ('cavall:3', 'porc:2,ovella:2'),
             ('ovella:4', 'ruc:2')]
    for size, x0, y0, x1, y1 in cands:
        if len(chosen) >= max_farms:
            break
        if any(abs(x0 - a) < 45 and abs(y0 - b) < 45 for a, b in chosen):
            continue
        k = len(chosen)
        pens = []
        for pw, ph in ((10, 7), (8, 6)):
            best = None
            for dy in range(-14, 15):
                for dx in range(-14, 15):
                    px, py = x0 + dx, y0 + dy
                    gx = max(0, x0 - (px + pw), px - x1); gy = max(0, y0 - (py + ph), py - y1)
                    gap = max(gx, gy)
                    if not 2 <= gap <= 9:
                        continue
                    if any(not (px + pw + 1 < a or a + aw + 1 < px or py + ph + 1 < b or b + ah + 1 < py) for a, b, aw, ah in pens):
                        continue
                    if pen_at(px, py, pw, ph) and (best is None or gap < best[0]):
                        best = (gap, px, py)
            if best:
                pens.append((best[1], best[2], pw, ph))
        if not pens:
            continue
        chosen.append((x0, y0))
        name = FARM_NAMES[k % len(FARM_NAMES)]
        bcx, bcy = (x0 + x1) // 2, (y0 + y1) // 2
        for j, (px, py, pw, ph) in enumerate(pens):
            border = [(x, y) for y in range(py, py + ph) for x in range(px, px + pw)
                      if x in (px, px + pw - 1) or y in (py, py + ph - 1)]
            # porta: la casella de la vora més propera a la casa (no a les cantonades)
            mid = [(x, y) for x, y in border if (x, y) not in ((px, py), (px + pw - 1, py), (px, py + ph - 1), (px + pw - 1, py + ph - 1))]
            gate = min(mid, key=lambda c: (c[0] - bcx) ** 2 + (c[1] - bcy) ** 2)
            fence = [c for c in border if c != gate]
            fence_pieces(m, fence, 'wood', 'fence', st)
            m.placed[py:py + ph, px:px + pw] = True
            ix, iy = px + pw - 2, py + 1            # abeurador i palla a les cantonades de dins
            m.put(ix, iy, 'o_trough'); m.put(px + 1, py + ph - 2, 'o_hay')
            animals = herds[k % len(herds)][j % 2]
            m.obj('farm_pen', (px + 1) * 16, (py + 1) * 16, {'w': (pw - 2) * 16, 'h': (ph - 2) * 16, 'animals': animals,
                                                             'farm': name}, name=f'corral_{k + 1}_{j + 1}')
            st['pens'] += 1; st['animals'] += sum(int(a.split(':')[1]) for a in animals.split(','))
        # gallines soltes i el pagès, a la vora de la casa
        ring = [(x, y) for y in range(y0 - 4, y1 + 4) for x in range(x0 - 4, x1 + 4)
                if 2 <= x < m.W - 2 and 2 <= y < m.H - 2 and m.free(x, y, strict=False) and comp[y, x] == main_c]
        if ring:
            xs_ = [c[0] for c in ring]; ys_ = [c[1] for c in ring]
            m.obj('farm_pen', min(xs_) * 16, min(ys_) * 16, {'w': (max(xs_) - min(xs_) + 1) * 16,
                  'h': (max(ys_) - min(ys_) + 1) * 16, 'animals': 'gallina:5', 'farm': name, 'loose': True},
                  name=f'galliner_{k + 1}')
            st['animals'] += 5
            fx, fy = min(ring, key=lambda c: (c[0] - bcx) ** 2 + (c[1] - (y1 + 1)) ** 2)
            m.obj('farmer', fx * 16 + 8, fy * 16 + 8, {'farm': name, 'n': k + 1}, name=f'pages_{k + 1}')
            m.placed[fy, fx] = True
        m.obj('spot', bcx * 16 + 8, (y1 + 1) * 16 + 8, {'label': name}, name=f'granja_{k + 1}')
        st['farms'] += 1
    return st


def sea_swim(m, depth=2):
    """Banyar-se al mar (2026-10-05): l'aigua a 1-`depth` caselles de la sorra de la platja es pot nedar (com les
    piscines municipals; el joc hi fa nedar el jugador, World:update_swim) si la bandera no és vermella. Uns quants
    llocs d'encàrrec 'beach' amb swim=True perquè els veïns també s'hi banyin. Després de tota la decoració."""
    from scipy import ndimage
    water = ((m.coll & 3) == 2) & np.isin(m.L['ground'] & 0x1FFFFFFF, [m.gid(n) for n in m.tiles if n.startswith('sea_')])
    sand = (m.ground == G['BEACH']) & ((m.coll & 3) == WALK)
    near = ndimage.distance_transform_edt(~sand) <= depth
    swim = water & near & (m.L['structures'] == 0)
    lab, n = ndimage.label(swim)                           # res de trossets solts (escullera, roques)
    sizes = ndimage.sum(swim, lab, range(1, n + 1))
    swim &= np.isin(lab, [i + 1 for i, v in enumerate(sizes) if v >= 8])
    ys, xs = np.nonzero(swim)
    m.coll[swim] = WALK
    picked = []
    for x, y in sorted(zip(xs.tolist(), ys.tolist()), key=lambda c: (c[0] * 11 + c[1] * 7) % 97):
        if all((x - a) ** 2 + (y - b) ** 2 >= 14 ** 2 for a, b in picked):
            picked.append((x, y))
            m.obj('errand', x * 16 + 8, y * 16 + 8, {'kind': 'beach', 'swim': True}, name=f'errand_sea_{len(picked)}')
        if len(picked) >= 30:
            break
    return {'cells': int(swim.sum()), 'spots': len(picked)}


def sail_lanes(m, n_boats=12):
    """Velers que naveguen (src/systems/sailboats.lua): per a cadascun, un circuit tancat de 5 punts en mar
    obert (6-30 caselles de la costa) on cada tram va per aigua. Objecte 'sailboat' amb path "x,y;…" en píxels."""
    from scipy import ndimage
    water = (m.coll & 3) == 2
    dist = ndimage.distance_transform_edt(water)
    band = water & (dist >= 6) & (dist <= 30)
    ys, xs = np.nonzero(band)
    if not len(xs):
        return 0
    r = random.Random(4545)
    starts = []
    order = list(range(len(xs)))
    r.shuffle(order)

    def clear(a, b):
        n = int(max(abs(b[0] - a[0]), abs(b[1] - a[1]))) + 1
        for k in range(n + 1):
            x = int(round(a[0] + (b[0] - a[0]) * k / n)); y = int(round(a[1] + (b[1] - a[1]) * k / n))
            if not water[y, x] or dist[y, x] < 3:
                return False
        return True
    made = 0
    for k in order:
        if made >= n_boats:
            break
        sx, sy = int(xs[k]), int(ys[k])
        if any((sx - a) ** 2 + (sy - b) ** 2 < 45 ** 2 for a, b in starts):
            continue
        pts = [(sx, sy)]
        for _ in range(60):
            if len(pts) >= 5:
                break
            ang = r.random() * 2 * math.pi
            d = r.uniform(12, 36)
            px, py = int(sx + math.cos(ang) * d), int(sy + math.sin(ang) * d)
            if 0 <= px < m.W and 0 <= py < m.H and band[py, px] and clear(pts[-1], (px, py)):
                pts.append((px, py))
        if len(pts) < 4 or not clear(pts[-1], pts[0]):
            continue
        starts.append((sx, sy))
        path = ';'.join(f'{x * 16 + 8},{y * 16 + 8}' for x, y in pts)
        m.obj('sailboat', sx * 16 + 8, sy * 16 + 8, {'path': path, 'color': made % 2 + 1, 'speed': r.randint(14, 24)},
              name=f'veler_{made + 1}')
        made += 1
    return made


def inaccessible_doors(m):
    """Portes on no es pot arribar (davant tancat per tanques, cotxes o un pati sense sortida): si l'edifici té una
    altra porta bona es tornen finestres; una casa petita sense cap porta bona es treu (queda jardí). Els edificis
    amb servei, rètol o monument no es toquen."""
    comp = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    sp = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    main_c = comp[int(sp['y'] // 16), int(sp['x'] // 16)]
    S, B = m.L['structures'], m.bld
    st = {'doors_to_windows': 0, 'houses_removed': 0, 'kept_protected': 0}
    protected = set()
    for o in m.objects:
        if o['type'] in ('door', 'signboard', 'landmark', 'service', 'npc', 'poi'):
            x, y = int(o['x'] // 16), int(o['y'] // 16)
            for dy in range(-2, 3):
                for dx in range(-2, 3):
                    if 0 <= y + dy < m.H and 0 <= x + dx < m.W and B[y + dy, x + dx]:
                        protected.add(int(B[y + dy, x + dx]))
    by_b = {}
    ys, xs = np.nonzero(S)
    for y, x in zip(ys.tolist(), xs.tolist()):
        n = m.name_of.get(int(S[y, x]) & 0x1FFFFFFF, '')
        if not (n.startswith('f_') and n.endswith('_door')):
            continue
        ok = y + 1 < m.H and m.coll[y + 1, x] == WALK and comp[y + 1, x] == main_c
        b = int(B[y, x]) or int(B[y - 1, x]) if y > 0 else int(B[y, x])
        by_b.setdefault(b, []).append((x, y, n, ok))
    grass = [m.gid(f'g_grass_{v}') for v in range(3)]
    for b, ds in by_b.items():
        bad = [d for d in ds if not d[3]]
        if not bad:
            continue
        good = [d for d in ds if d[3]]
        cells = np.argwhere(B == b) if b else np.zeros((0, 2), int)
        if b and not good and len(cells) <= 80 and b not in protected:
            for y, x in cells.tolist():
                S[y, x] = 0
                m.L['overhead'][y, x] = 0
                m.L['ground'][y, x] = grass[(x * 7 + y * 3) % 3]
                m.coll[y, x] = WALK
            # la façana de dalt de la casa (files per sobre del cos) també
            for x, y, _, _ in ds:
                for yy in range(max(0, y - 4), y + 1):
                    if m.name_of.get(int(S[yy, x]) & 0x1FFFFFFF, '').startswith(('f_', 'r_')):
                        S[yy, x] = 0; m.L['overhead'][yy, x] = 0; m.coll[yy, x] = WALK
            st['houses_removed'] += 1
            continue
        if b in protected and not good:
            st['kept_protected'] += 1
        for x, y, n, _ in bad:
            alt = n[:-len('_door')] + '_win'
            if alt in m.tiles:
                S[y, x] = m.gid(alt)
                st['doors_to_windows'] += 1
    return st


def main():
    m = Map()
    osm = OSM(os.path.join(ROOT, 'cartography/municipio.osm.gz'))
    lines = read_lines(m)
    before = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    rep = {'side_entry_ramps': fix_side_entries(m), 'crossings': crossings(m, lines), 'crosswalks': crosswalks(m, lines, osm)}
    rep['bus_stops'] = bus_stops(m, osm, lines)
    rep['parking_cells'], rep['parked_cars'] = parkings(m, osm)
    import realdata
    names = json.load(open(os.path.join(ROOT, 'data/place_names.json')))
    rd = realdata.load() or realdata.neutral(*m.coll.shape)   # (lloc nou sense ortofoto: valors neutres)
    rep['schools'] = schools(m, osm, rd)
    rep['pitches'] = pitches(m, osm, rd)
    rep['parks'] = parks(m, osm, rd, names)
    rep['silena'] = silena(m, osm, names)
    rep['port'] = port(m, osm)
    rep['canopies'] = canopies(m, osm)
    rep['shop_signs'] = shop_signs(m, osm)
    rep['extra_features'] = extra_features(m)
    rep['solar_roofs'] = solar_roofs(m)   # placas reals de l'ortofoto de l'IGN
    rep['construction'] = construction_sites(m, osm)   # obres: estructures, tanques, grues i obrers
    rep['special_signs'] = special_signs(m)
    rep['locals'] = locals_(m)            # després dels serveis: no repeteix porta
    rep['swim_cells'] = swim_pools(m, osm)
    rep['gardens'] = gardens(m)                       # jardins de les cases (ortofoto)
    rep['osm_nodes'] = osm_nodes(m, osm)
    rep['barraques'] = barraques(m, osm)
    m_sp0 = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    rep['market_stalls'] = market(m, osm)
    rep['mountain_chests'] = mountain_chests(m)
    rep['collectibles'] = collectibles(m)
    rep['street_lamps'] = street_lamps(m, lines)
    rep['shield_chest'] = shield_chest(m)
    rep['caves'] = cave_entrances(m, before, before[int(m_sp0['y'] // 16), int(m_sp0['x'] // 16)])
    rep['landmark_doors'] = landmark_doors(m)        # església, biblioteca, ajuntament i ermita
    rep['plot_fences'] = plot_fences(m)          # després dels fanals: les tanques no els treuen lloc
    sp0 = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    rep['fence_gates_opened'] = open_fences(m, before, before[int(sp0['y'] // 16), int(sp0['x'] // 16)])
    rep['inaccessible_doors'] = inaccessible_doors(m)   # després de tanques i portes: la connectivitat final
    rep['hidden_chests'] = hidden_chests(m)             # cofres amagats a les zones importants
    rep['zone_polish'] = zone_polish(m)                 # platja, places i monuments (2026-10-05)
    rep['fountains'] = fountains(m)                     # fonts que falten i totes animades
    rep['farms'] = farms(m)                             # granges al sud de l'autopista
    rep['sailboats'] = sail_lanes(m)                    # velers navegant
    import nature
    rep['nature'] = nature.enrich(m)
    rep['errands'] = errand_spots(m)                    # forns, perruqueries, piscines, platja i jardins
    rep['sea_swim'] = sea_swim(m)                       # banyar-se al mar a tocar de la platja
    if not os.environ.get('RODA_SIN_TEXTURAS'):    # (A/B de rendimiento: sin transiciones ni sombras)
        rep['terrain'] = terrain_blend.blend(m)      # transiciones Wang entre terrenos
        rep['shadows'] = terrain_blend.shadows(m)    # sombras suaves de edificios y árboles
    after = walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    # comprobación: ninguna celda de la zona principal queda separada de ella
    sp = next(o for o in m.objects if o['name'] == 'spawn_public_centre')
    sx, sy = int(sp['x'] // 16), int(sp['y'] // 16)
    main_b, main_a = before[sy, sx], after[sy, sx]
    lost = int(((before == main_b) & (after != main_a) & ~m.placed).sum())
    rep['cells_cut_off'] = lost
    if lost:   # on: per trobar-ho ràpid (grups de caselles aïllades, una mostra de cada)
        from scipy import ndimage as _nd
        lab_, n_ = _nd.label((before == main_b) & (after != main_a) & ~m.placed)
        rep['cut_off_at'] = [[int(v) for v in np.argwhere(lab_ == i)[0][::-1]] + [int((lab_ == i).sum())] for i in range(1, n_ + 1)]
    m.save()
    with open(os.path.join(ROOT, 'maps/source/decorate-report.json'), 'w') as f:
        json.dump(rep, f, indent=1, ensure_ascii=False, default=lambda v: v.item())
    print('decorado', {k: (len(v) if isinstance(v, list) else v) for k, v in rep.items()})
    if lost > 50:
        raise SystemExit(f'ERROR: la decoración aísla {lost} celdas')


if __name__ == '__main__':
    main()
