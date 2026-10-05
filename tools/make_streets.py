"""Noms oficials de carrers, places, parcs i escoles (OSM) → data/streets.json, per als cartells «Ets al
carrer…» i les missions d'orientació; també els punts de reciclatge (amenity=recycling) per a les missions. Línies simplificades (Douglas-Peucker, 3 px) en píxels del món (16 px/tile).
Ràpid (no cal refer el mapa): python3 tools/make_streets.py"""
import json
import os

from osmlib import OSM, to_tile_f

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROADS = {'motorway', 'trunk', 'primary', 'secondary', 'tertiary', 'unclassified', 'residential', 'living_street',
         'pedestrian', 'service', 'footway', 'path', 'track', 'steps', 'cycleway', 'road'}
AREAS = {'park', 'garden', 'playground'}


def simplify(pts, tol):
    if len(pts) < 3:
        return pts
    if pts[0] == pts[-1]:
        # anillo cerrado: Douglas-Peucker con extremos iguales lo reducía a un punto (todas las plazas y
        # parques salían con área cero): se parte por el vértice más alejado del primero
        k = max(range(len(pts)), key=lambda i: (pts[i][0] - pts[0][0]) ** 2 + (pts[i][1] - pts[0][1]) ** 2)
        if k == 0:
            return pts[:1]
        return simplify(pts[:k + 1], tol)[:-1] + simplify(pts[k:], tol)
    (x0, y0), (x1, y1) = pts[0], pts[-1]
    dx, dy = x1 - x0, y1 - y0
    L = (dx * dx + dy * dy) ** 0.5 or 1e-9
    best, bi = -1, 0
    for i in range(1, len(pts) - 1):
        d = abs(dy * (pts[i][0] - x0) - dx * (pts[i][1] - y0)) / L
        if d > best:
            best, bi = d, i
    if best <= tol:
        return [pts[0], pts[-1]]
    return simplify(pts[:bi + 1], tol)[:-1] + simplify(pts[bi:], tol)


def px(osm, refs):
    out = []
    for r in refs:
        if r in osm.nodes:
            x, y = to_tile_f(*osm.nodes[r])
            out.append((round(x * 16), round(y * 16)))
    return out


OUTSIDE_TOWN = 'Creixell'   # las áreas de fuera del municipio dentro del mapa son de Creixell (oeste)


def municipality_rings():
    """Anillos exteriores del límite de Roda de Berà en tiles (cartography/limite.osm.gz)."""
    path = os.path.join(ROOT, 'cartography/limite.osm.gz')
    if not os.path.exists(path):
        return []
    lo = OSM(path)
    for rid, (tags, members) in lo.relations.items():
        if tags.get('boundary') == 'administrative' and tags.get('admin_level') == '8':
            outer, _ = lo.multipolygon_rings(rid)
            return [[to_tile_f(*c) for c in r] for r in outer]
    return []


def point_in(x, y, rings):
    ins = False
    for ring in rings:
        for i in range(len(ring)):
            (x1, y1), (x2, y2) = ring[i], ring[i - 1]
            if (y1 > y) != (y2 > y) and x < x1 + (y - y1) * (x2 - x1) / (y2 - y1):
                ins = not ins
    return ins


def main():
    osm = OSM(os.path.join(ROOT, 'cartography/municipio.osm.gz'))
    extra = json.load(open(os.path.join(ROOT, 'data/place_names.json')))
    lines, areas = [], []
    for wid, (tags, refs) in osm.ways.items():
        ov = extra.get('way/' + wid, {})
        name = ov.get('name') or tags.get('name:ca') or tags.get('name')
        if not name:
            continue
        pts = px(osm, refs)
        if len(pts) < 2:
            continue
        closed = refs[0] == refs[-1] and len(refs) >= 4
        kind = None
        if tags.get('place') == 'square' or (tags.get('highway') == 'pedestrian' and closed):
            kind = 'square'
        elif tags.get('amenity') in ('school', 'kindergarten'):
            kind = 'school'
        elif tags.get('leisure') in AREAS or tags.get('landuse') in ('grass', 'village_green') or ov:
            kind = 'park'
        if kind and closed:
            areas.append({'n': name, 'k': kind, 'p': [c for xy in simplify(pts, 3) for c in xy],
                          **({'approx': True} if ov.get('approx') else {})})
        elif tags.get('highway') in ROADS:
            lines.append({'n': name, 'p': [c for xy in simplify(pts, 3) for c in xy]})
    # puerto deportivo (multipolígono): área con nombre para el cartel al entrar
    for rid, (tags, members) in osm.relations.items():
        if tags.get('leisure') != 'marina' or not (tags.get('name:ca') or tags.get('name')):
            continue
        outer, _ = osm.multipolygon_rings(rid)
        for ring in outer:
            pts = [(round(x * 16), round(y * 16)) for x, y in (to_tile_f(*c) for c in ring)]
            areas.append({'n': tags.get('name:ca') or tags['name'], 'k': 'port',
                          'p': [c for xy in simplify(pts, 3) for c in xy]})
    # nombres repetidos (la «Plaça de l'Església» de Roda y la de Creixell): la de fuera del municipio
    # lleva el pueblo entre paréntesis; si no, Streets.area() devolvía la primera (la de Creixell)
    rings = municipality_rings()
    def inside(a):
        xs, ys = a['p'][0::2], a['p'][1::2]
        return point_in(sum(xs) / len(xs) / 16, sum(ys) / len(ys) / 16, rings)

    # lo mismo con los carrers (Carrer Major de Roda y de Creixell): Streets.street() cogía el tramo más largo
    for group in (areas, lines):
        by_name = {}
        for a in group:
            by_name.setdefault(a['n'], []).append(a)
        for name, same in by_name.items():
            flags = [inside(a) for a in same] if rings else []
            if not (any(flags) and not all(flags)):
                continue
            # tramos encadenados (extremos a menos de 20 m) = la misma vía, aunque cruce el límite
            parent = list(range(len(same)))
            def root(i):
                while parent[i] != i:
                    parent[i] = parent[parent[i]]
                    i = parent[i]
                return i
            ends = [[(x, y) for x, y in zip(a['p'][0::2], a['p'][1::2])] for a in same]
            for i in range(len(same)):
                for j in range(i + 1, len(same)):
                    if any((x - u) ** 2 + (y - v) ** 2 < (20 / 4 * 16) ** 2 for x, y in ends[i] for u, v in ends[j]):
                        parent[root(i)] = root(j)
            inside_roots = {root(i) for i, f in enumerate(flags) if f}
            ins_pts = [pt for i, f in enumerate(flags) if f for pt in ends[i]]
            for i, a in enumerate(same):
                # y a más de 500 m (un espigón del Roc que sale del límite sigue siendo el Roc)
                if root(i) not in inside_roots and min((x - u) ** 2 + (y - v) ** 2 for x, y in ends[i]
                                                       for u, v in ins_pts) > (500 / 4 * 16) ** 2:
                    a['n'] = name + ' (' + OUTSIDE_TOWN + ')'
    recycling = []
    for nid, tags in osm.node_tags.items():
        if tags.get('amenity') == 'recycling' and nid in osm.nodes:
            x, y = to_tile_f(*osm.nodes[nid])
            recycling.append([round(x * 16), round(y * 16)])
    recycling.sort()
    lines.sort(key=lambda l: l['n'])
    areas.sort(key=lambda a: a['n'])
    out = {'_doc': 'Generat per tools/make_streets.py a partir de l\'OSM (© OpenStreetMap, ODbL). Coordenades en píxels.',
           'lines': lines, 'areas': areas, 'recycling': recycling}
    with open(os.path.join(ROOT, 'data/streets.json'), 'w') as f:
        json.dump(out, f, ensure_ascii=False, separators=(',', ':'))
    print(f'{len(lines)} trams de carrer amb nom, {len(set(l["n"] for l in lines))} noms; {len(areas)} places, parcs i escoles; {len(recycling)} punts de reciclatge')


if __name__ == '__main__':
    main()
