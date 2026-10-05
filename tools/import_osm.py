#!/usr/bin/env python3
"""Importa OSM → mapa Tiled (maps/source/overworld.tmj + tilesets .tsj).

Uso: python3 tools/import_osm.py
Entrada: cartography/municipio.osm.gz, cartography/limite.osm.gz, maps/source/map-overrides.json,
         data/tiles.json (de make_tiles.py), data/landmarks.json (de make_sprites.py).
Salida: maps/source/overworld.tmj, maps/source/tiles.tsj, maps/source/collision.tsj,
        maps/source/import-report.json
"""
import json
import math
import os
from collections import deque

import numpy as np

import buildings
import nuclis
import realdata
import semantic as sem
import walkgraph
from osmlib import to_tile_f, to_tile, from_tile, ORIGIN_LON, ORIGIN_LAT, MAP_TILES, M_PER_TILE, m2t
from pixel import rng_for

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
W = H = MAP_TILES
D, G = sem.D, sem.G
N, E, S, Wb = 1, 2, 4, 8
DIRS = ((0, -1, N), (1, 0, E), (0, 1, S), (-1, 0, Wb))

# códigos de colisión (ver docs/cartography.md)
WALK, SOLID, WATER, HAZARD = 0, 1, 2, 3
COLL_FIRSTGID = 4097  # firstgid del tileset de colisión en los .tmj
BIT_L1, BIT_LM1, BIT_RAMP, BIT_PENDING = 4, 8, 16, 32

# anclas (monumentos) del plan: opcional; un lugar nuevo empieza sin (tools/new_location.py)
_PLAN = os.path.join(ROOT, 'cartography/world-plan.json')
POIS = json.load(open(_PLAN))['pois'] if os.path.exists(_PLAN) else []
for _p in POIS:  # las anclas del plan estaban a 10 m/tile: recalcular desde lon/lat
    _p['tile_x'], _p['tile_y'] = to_tile(_p['lon'], _p['lat'])


def T(meters):
    return max(1, int(round(m2t(meters))))


def load_json(rel, default=None):
    p = os.path.join(ROOT, rel)
    if not os.path.exists(p):
        return default
    with open(p) as f:
        return json.load(f)


def neighbors_mask(same, y, x):
    m = 0
    for dx, dy, bit in DIRS:
        yy, xx = y + dy, x + dx
        if 0 <= yy < H and 0 <= xx < W:
            if same(yy, xx):
                m |= bit
        else:
            m |= bit
    return m


def dilate(m, r=1):
    out = m.copy()
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            out |= np.roll(np.roll(m, dy, 0), dx, 1)
    return out


def bfs_path(passable, start, goal_fn, limit=4000):
    """BFS 4-conexo desde start hasta la primera celda que cumple goal_fn; devuelve el camino."""
    prev = {start: None}
    q = deque([start])
    while q and len(prev) < limit:
        c = q.popleft()
        if goal_fn(c):
            path = []
            while c:
                path.append(c)
                c = prev[c]
            return path[::-1]
        x, y = c
        for dx, dy, _ in DIRS:
            n = (x + dx, y + dy)
            if n not in prev and 0 <= n[0] < W and 0 <= n[1] < H and passable(n):
                prev[n] = c
                q.append(n)
    return None


def main():
    tiles = load_json('data/tiles.json')['tiles']
    landmarks = load_json('data/landmarks.json', {})
    overrides = load_json('maps/source/map-overrides.json', {})
    tid = lambda name: tiles[name]['id'] + 1  # gid con firstgid = 1

    r = sem.build(os.path.join(ROOT, 'cartography/municipio.osm.gz'),
                  os.path.join(ROOT, 'cartography/limite.osm.gz'))
    ground, detail, bld, binfo = r['ground'], r['detail'], r['bld'], r['binfo']
    osm = r['osm']
    report = {'warnings': [], 'generated_houses': 0}
    rd = realdata.load()  # catastro, ortofoto y relieve (opcional)
    if rd is not None:
        ch, gardens = realdata.ground_from_satellite(rd, ground)
        report['satellite_ground_changed'] = ch
        report['satellite_gardens'] = gardens
        if r['marina'].any():
            report['marina_water'], report['marina_quay'], report['marina_piers'], report['marina_rocks'] = realdata.marina(
                rd, ground, detail[0], r['marina'], G['SEA'], D['PIER'])
    elif r['marina'].any():
        detail[0][r['marina'] & (detail[0] == 0)] = D['PIER']

    # margen fuera del rectángulo descargado → bloqueado
    # (Roda: el extracto llegaba a 1,5 E / 41,16 N; un lugar nuevo de tools/new_location.py cubre todo el mapa)
    _bb = json.load(open(os.path.join(ROOT, 'data/world.json'))).get('source_bbox_se')
    ex, sy = to_tile_f(*_bb) if _bb else (W, H)
    yy, xx = np.mgrid[0:H, 0:W]
    outside = (xx >= int(ex)) | (yy >= int(sy))
    ground[outside & (ground != G['SEA'])] = G['VOID']
    for lv in detail:
        detail[lv][outside] = 0

    # conexiones manuales (map-overrides.json)
    for c in overrides.get('connections', []):
        loc = sem.local_cells([[tuple(p) for p in c['points']]], 'line', c.get('width', 2), 1 / 16)
        sem.paint(detail[c.get('level', 0)], loc, D[c.get('class', 'FOOTWAY')])
        report['warnings'].append(f"override de conexión aplicado: {c.get('reason', '')}")

    d0 = detail[0]
    walk_detail = np.isin(d0, list(sem.WALKABLE_DETAIL))
    blocking_detail = np.isin(d0, [D['RAIL'], D['RAIL_HS'], D['MOTORWAY'], D['PENDING']])

    if rd is not None:
        n_add, n_dup = realdata.catastro_buildings(rd, bld, binfo, ground, d0, detail[1], detail[-1])
        report['catastro_buildings'] = n_add
        report['catastro_duplicates_osm'] = n_dup
    # casas adosadas del catastro: una hilera (fuera de los cascos antiguos)
    if rd is not None:
        report['row_houses_merged'] = realdata.merge_rows(bld, binfo, skip=nuclis.mask(H, W) > 0)
    # retoques de edificios (map-overrides.json, en casillas): huecos del catastro junto al Ajuntament,
    # el pabellón del Poliesportiu (en el OSM solo es la pista) e invernaderos y cuadras que no tiene nadie
    for c in overrides.get('buildings_clear', []):
        x0, y0, x1, y1 = c['rect']
        bld[y0:y1 + 1, x0:x1 + 1] = 0
    for c in overrides.get('buildings_add', []):
        x0, y0, x1, y1 = c['rect']
        bld[y0:y1 + 1, x0:x1 + 1] = len(binfo)
        binfo.append({'src': 'override', 'kind': c['kind'], 'name': c.get('name'), 'amenity': None,
                      'generated': False, 'floors': c.get('floors', 1)})
    report['buildings_override'] = len(overrides.get('buildings_add', []))
    # enderezar: huellas giradas → edificios alineados con la rejilla (tools/buildings.py)
    blocked_b = (d0 > 0) | (detail[1] > 0) | (ground == G['SEA']) | (ground == G['VOID'])
    # cascos antiguos (tools/nuclis.py): casas en hilera unidas en manzanas, sin enderezar (siguen las
    # calles estrechas reales) y sin borrar las tiras de 1 casilla que forman parte de una manzana
    nmask = nuclis.mask(H, W)
    bld[blocked_b & (nmask > 0)] = 0
    report['nucli_merged'] = nuclis.merge_blocks(bld, binfo, nmask)
    in_nucli = np.zeros(len(binfo), bool)
    for i, info in enumerate(binfo):
        in_nucli[i] = bool(info and info.get('nucli'))
    keep_nucli = np.where(in_nucli[bld], bld, 0)
    bld[keep_nucli > 0] = 0
    bld, report['straighten'] = buildings.straighten(bld, blocked_b)
    put = (keep_nucli > 0) & (bld == 0) & ~blocked_b
    bld[put] = keep_nucli[put]
    report['nucli_cells'] = int(put.sum())
    # --- edificios: las calles los recortan; mínimo dos filas (tejado + fachada) ---
    bld[(d0 > 0) | (ground == G['SEA']) | (ground == G['VOID']) | (detail[1] > 0)] = 0
    for y in range(1, H - 1):
        row = bld[y]
        for x in np.nonzero(row)[0]:
            b = row[x]
            if bld[y - 1, x] != b and bld[y + 1, x] != b:
                if bld[y - 1, x] == 0 and d0[y - 1, x] == 0 and ground[y - 1, x] != G['SEA'] and detail[1][y - 1, x] == 0:
                    bld[y - 1, x] = b

    # casas generadas en zonas residenciales sin huella OSM: relleno voraz de manzanas con
    # casas de 2–4 tiles de ancho y 2 de alto, dejando un tile libre entre casas vecinas
    free = (ground == G['URBAN']) & (d0 == 0) & (bld == 0) & (detail[1] == 0) & (detail[-1] == 0)
    if rd is not None:
        free[:] = False  # con el Catastro no hacen falta casas inventadas
        report['pools'] = realdata.pools(rd, ground, bld, d0)
    free &= ~dilate(d0 > 0, 1)          # retranqueo: jardín de 1 tile entre calle y casa
    hrng = rng_for('houses')
    for y in range(1, H - 2):
        x = 1
        while x < W - 2:
            if not (free[y, x] and free[y + 1, x] and free[y, x + 1] and free[y + 1, x + 1]):
                x += 1
                continue
            maxw = 2 + hrng.randrange(3)
            w = 2
            while w < maxw and x + w < W - 1 and free[y, x + w] and free[y + 1, x + w]:
                w += 1
            idx = len(binfo)
            binfo.append({'src': 'generated', 'kind': 'house', 'name': None, 'amenity': None,
                          'generated': True})
            bld[y:y + 2, x:x + w] = idx
            # margen alrededor (pasillo de 1 tile) para que las manzanas se lean como casas
            free[max(0, y - 1):y + 3, max(0, x - 1):x + w + 1] = False
            report['generated_houses'] += 1
            x += w + 1

    # --- hitos (landmarks): huella sólida + sprite como objeto ----------------------
    objects = []
    lm_solid = np.zeros((H, W), bool)
    lm_cells = np.zeros((H, W), bool)
    poi_by_id = {p['id']: p for p in POIS}
    poi_doors = {}
    for lid, lm in landmarks.items():
        poi = poi_by_id.get(lm.get('poi', lid))
        if not poi:
            continue
        ax, ay = poi['tile_x'], poi['tile_y']
        # el sprite del hito sustituye a la huella OSM del mismo elemento (p. ej. la iglesia)
        same = [i for i, b in enumerate(binfo) if b and b['src'] == poi['osm']]
        for i in same:
            ys_, xs_ = np.nonzero(bld == i)
            if len(xs_):
                ax, ay = int(xs_.mean()), int(ys_.max())
            bld[bld == i] = 0
        off = overrides.get('landmark_offsets', {}).get(lid)
        fw, fh = lm['w_tiles'], lm['h_tiles']
        best = None
        for rad in range(0, T(140)):
            for dy in range(-rad, rad + 1):
                for dx in range(-rad, rad + 1):
                    if max(abs(dx), abs(dy)) != rad:
                        continue
                    x0 = ax + dx - fw // 2 + (off[0] if off else 0)
                    y0 = ay + dy - fh + 1 + (off[1] if off else 0)
                    area = (slice(y0, y0 + fh), slice(x0, x0 + fw))
                    if x0 < 0 or y0 < 0 or x0 + fw >= W or y0 + fh + 1 >= H:
                        continue
                    if (d0[area] > 0).any() or (detail[1][area] > 0).any() or lm_cells[area].any():
                        continue
                    if (ground[area] == G['SEA']).any() or (ground[area] == G['VOID']).any():
                        continue
                    dx_, dy_ = x0 + lm['door'][0], y0 + lm['door'][1]
                    if blocking_detail[dy_, dx_] or ground[dy_, dx_] in (G['SEA'], G['WATER'], G['VOID']) \
                            or lm_cells[dy_, dx_] or detail[1][dy_, dx_]:
                        continue
                    best = (x0, y0)
                    break
                if best: break
            if best: break
        if not best:
            report['warnings'].append(f'hito {lid}: sin hueco libre cerca del ancla')
            continue
        x0, y0 = best
        lm_cells[y0:y0 + fh, x0:x0 + fw] = True
        # el hito sustituye a los edificios que pisa (enteros: sin dejar trozos sueltos al lado), salvo las
        # manzanas grandes (cascos antiguos, bloques) que solo tocan de refilón: se recorta lo que queda debajo
        for b_ in np.unique(bld[y0:y0 + fh, x0:x0 + fw]):
            if b_:
                total = int((bld == b_).sum())
                under = int((bld[y0:y0 + fh, x0:x0 + fw] == b_).sum())
                if total >= 40 and under * 2 < total:
                    sub = bld[max(0, y0 - 1):y0 + fh + 1, max(0, x0 - 1):x0 + fw + 1]
                    sub[sub == b_] = 0
                else:
                    bld[bld == b_] = 0
        for (cx, cy) in lm['solid']:
            lm_solid[y0 + cy, x0 + cx] = True
        objects.append({'type': 'landmark', 'name': lid, 'x': x0 * 16, 'y': y0 * 16,
                        'width': fw * 16, 'height': fh * 16,
                        'properties': {'sprite': lm['sprite'], 'poi': poi['id'], 'label': poi['name'],
                                       'osm': poi['osm'], 'overhead_rows': lm.get('overhead_rows', 0)}})
        # acceso: la celda delante de la puerta debe enlazar con la red peatonal
        door = (x0 + lm['door'][0], y0 + lm['door'][1])

        def clear_buildings(cells):
            for cx, cy in cells:
                b = bld[cy, cx]
                if b:
                    bld[bld == b] = 0
        clear_buildings([door])
        if not walk_detail[door[1], door[0]]:
            passable = lambda c: (ground[c[1], c[0]] in sem.WALKABLE_GROUND and not lm_cells[c[1], c[0]]
                                  and (bld[c[1], c[0]] == 0 or binfo[bld[c[1], c[0]]]['generated'])
                                  and not blocking_detail[c[1], c[0]]) or walk_detail[c[1], c[0]]
            path = bfs_path(passable, door, lambda c: walk_detail[c[1], c[0]] and c != door)
            if path:
                clear_buildings(path)
                for cx, cy in path:
                    if d0[cy, cx] == 0:
                        d0[cy, cx] = D['FOOTWAY']
                        walk_detail[cy, cx] = True
                report['warnings'].append(f'hito {lid}: acceso peatonal artístico de {len(path)} celdas')
            else:
                report['warnings'].append(f'hito {lid}: sin acceso peatonal')
        if lm.get('entrance'):
            en = lm['entrance']
            ex0, ey0, ew, eh = en['rect']
            objects.append({'type': 'door', 'name': 'door_' + lid, 'x': (x0 + ex0) * 16, 'y': (y0 + ey0) * 16,
                            'width': ew * 16, 'height': eh * 16,
                            'properties': {k: v for k, v in en.items() if k != 'rect'}})
            objects.append({'type': 'spawn', 'name': en['return_spawn'], 'x': door[0] * 16 + 8,
                            'y': door[1] * 16 + 8, 'point': True, 'properties': {'public': True}})
        objects.append({'type': 'trigger', 'name': 'zone_' + poi['id'], 'x': (door[0] - 2) * 16,
                        'y': (door[1] - 2) * 16, 'width': 5 * 16, 'height': 4 * 16,
                        'properties': {'kind': 'poi', 'poi': poi['id']}})
        poi_doors[poi['id']] = door
        objects.append({'type': 'poi', 'name': poi['id'], 'x': door[0] * 16 + 8, 'y': door[1] * 16 + 8,
                        'point': True, 'properties': {'label': poi['name'], 'osm': poi['osm'],
                                                     'anchor_tile': f"{ax},{ay}"}})

    # --- muros, setos y acantilados de cantera --------------------------------------
    walls = np.zeros((H, W), np.uint8)  # 1 piedra, 2 seto, 3 acantilado
    for wid, (tags, refs) in osm.ways.items():
        kind = {'wall': 1, 'retaining_wall': 1, 'hedge': 2}.get(tags.get('barrier'))
        if kind:
            sem.paint(walls, sem.local_cells([osm.way_tiles(wid)], 'line', 1, 0.3), kind)
    q = ground == G['QUARRY']
    q_edge = q & ~(np.roll(q, 1, 0) & np.roll(q, -1, 0) & np.roll(q, 1, 1) & np.roll(q, -1, 1))
    walls[q_edge] = 3
    walls[(d0 > 0) | (detail[1] > 0) | (detail[-1] > 0) | (bld > 0) | lm_cells] = 0

    # --- niveles de terreno (relieve real) ---------------------------------------
    occupied = (d0 > 0) | (detail[1] > 0) | (detail[-1] > 0) | (bld > 0) | lm_cells | (walls > 0)
    for (dx_, dy_) in poi_doors.values():
        occupied[max(0, dy_ - 1):dy_ + 2, max(0, dx_ - 1):dx_ + 2] = True
    ledge = np.zeros((H, W), np.uint8)
    if rd is not None:
        level = realdata.terrain_levels(rd)
        below_bld = np.zeros((H, W), bool)
        below_bld[1:] = bld[:-1] > 0       # delante de fachadas: siempre libre
        ledge = realdata.ledges(level, ground, ~occupied & ~below_bld & ~realdata.near_town(bld, ground))
        occupied |= ledge > 0
        report['terrain_levels'] = [int(level.min()), int(level.max())]
        report['ledge_cells'] = int((ledge > 0).sum())

    # --- árboles ------------------------------------------------------------------
    trees = np.zeros((H, W), np.uint8)  # 1/2 pino, 3 palmera, 4 olivo, 5/6 arbusto
    near_occ = dilate(walk_detail, 1)
    rng = rng_for('trees')
    if rd is not None:
        below = np.zeros((H, W), bool)
        below[1:] = bld[:-1] > 0
        trees = realdata.trees_from_satellite(rd, ground, occupied | below, near_occ, rng)
    dens = {G['FOREST']: (0.16, 'pine'), G['SCRUB']: (0.08, 'bush'), G['DRY']: (0.012, 'pine'),
            G['PARK']: (0.04, 'palm'), G['URBAN']: (0.01, 'palm'), G['FARM']: (0.02, 'olive'),
            G['WETLAND']: (0.05, 'bush'), G['CEMETERY']: (0.06, 'pine')}
    for y in range(1, H if rd is None else 1):
        for x in range(W):
            g = ground[y, x]
            if g not in dens or occupied[y, x] or near_occ[y, x]:
                continue
            p, kind = dens[g]
            if rng.random() >= p:
                continue
            if kind == 'pine':
                if occupied[y - 1, x] or trees[y - 1, x]:
                    continue
                trees[y, x] = 1 + (rng.random() < .35)
            elif kind == 'palm':
                if occupied[y - 1, x]:
                    continue
                trees[y, x] = 3
            elif kind == 'olive':
                if occupied[y - 1, x]:
                    continue
                trees[y, x] = 4
            else:
                trees[y, x] = 5 + (rng.random() < .5)
    # despejar alrededor de anclas y del área de aparición
    for p in POIS:
        r_ = T(30)
        trees[max(0, p['tile_y'] - r_):p['tile_y'] + r_ + 1, max(0, p['tile_x'] - r_):p['tile_x'] + r_ + 1] = 0

    # --- capas de tiles -----------------------------------------------------------
    L = {name: np.zeros((H, W), np.uint32) for name in
         ('ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead', 'collision')}
    gname = {v: k.lower() for k, v in G.items()}
    vrng = np.random.default_rng(7)
    variant = vrng.integers(0, 3, size=(H, W))
    if rd is not None:
        # variante (oscura, media, clara) según la luminosidad real de la ortofoto dentro de cada
        # clase de suelo: las manchas de color del mapa siguen las del satélite
        from scipy import ndimage as _nd
        lum = _nd.uniform_filter(rd['rgb'].astype(np.float32).mean(-1), 5)
        for gv in np.unique(ground):
            m_ = ground == gv
            if m_.sum() < 30:
                continue
            q1, q2 = np.percentile(lum[m_], [30, 70])
            variant[m_] = np.where(lum[m_] < q1, 0, np.where(lum[m_] > q2, 2, 1))
    sea = ground == G['SEA']
    pool = ground == G['WATER']
    from scipy import ndimage as _nd
    open_sea = _nd.distance_transform_edt(sea | (ground == G['VOID'])) > 7   # mar abierto: azul profundo
    for y in range(H):
        for x in range(W):
            g = ground[y, x]
            if g == G['SEA']:
                m = neighbors_mask(lambda a, b: sea[a, b] or ground[a, b] == G['VOID'], y, x)
                L['ground'][y, x] = tid('seadeep_15_0' if m == 15 and open_sea[y, x] else f'sea_{m}_0')
            elif g == G['WATER']:
                m = neighbors_mask(lambda a, b: pool[a, b], y, x)
                L['ground'][y, x] = tid(f'pool_{m}_0')
            else:
                L['ground'][y, x] = tid(f'g_{gname[g]}_{variant[y, x]}')

    fam_of = {D['ROAD']: 'road', D['ROAD_MAIN']: 'main', D['MOTORWAY']: 'moto', D['PEDESTRIAN']: 'paving',
              D['FOOTWAY']: 'paving', D['PATH']: 'path', D['TRACK']: 'track', D['STREAM']: 'stream',
              D['STEPS']: 'steps', D['PLATFORM']: 'platform', D['PIER']: 'pier'}
    # calzadas conectan entre sí visualmente (sin acera en el cruce)
    road_group = {D['ROAD'], D['ROAD_MAIN'], D['LEVEL_CROSSING']}
    group = lambda v: 'road' if v in road_group else v

    # orientación de las vías férreas según el segmento OSM más próximo
    rail_orient = {}
    for wid, (lv, loc, cls, pts) in r['way_mask'].items():
        if cls not in (D['RAIL'], D['RAIL_HS']):
            continue
        y0, x0, m = loc
        for cy, cx in zip(*np.nonzero(m)):
            px, py = x0 + cx + .5, y0 + cy + .5
            best, ang = 1e9, 0
            for (ax, ay), (bx, by) in zip(pts, pts[1:]):
                vx, vy = bx - ax, by - ay
                L2 = vx * vx + vy * vy or 1
                t = max(0, min(1, ((px - ax) * vx + (py - ay) * vy) / L2))
                d = (ax + t * vx - px) ** 2 + (ay + t * vy - py) ** 2
                if d < best:
                    best, ang = d, math.degrees(math.atan2(vy, vx)) % 180
            o = 'h' if ang < 22.5 or ang >= 157.5 else 'd1' if ang < 67.5 else 'v' if ang < 112.5 else 'd2'
            rail_orient[(lv, y0 + cy, x0 + cx)] = o

    def detail_tile(lv, y, x, arr, bridge=False):
        v = arr[y, x]
        if v == 0:
            return 0
        if v in (D['RAIL'], D['RAIL_HS']):
            o = rail_orient.get((lv, y, x), 'h')
            return tid(f'd_{"railhs" if v == D["RAIL_HS"] else "rail"}_{o}')
        if v == D['LEVEL_CROSSING']:
            return tid('d_crossing')
        if v == D['PENDING']:
            return tid('d_pending')
        fam = fam_of[v]
        if bridge:
            fam = 'bridgemoto' if v == D['MOTORWAY'] else 'bridge' if v in road_group or fam in ('road', 'main') else fam
        gv = group(v)
        m = neighbors_mask(lambda a, b: group(arr[a, b]) == gv, y, x)
        return tid(f'd_{fam}_{m}')

    # las vías lineales se dibujan como vectores (capa 'lines'); en tiles solo quedan las demás
    vector_ids = {D[k] for k in VECTOR_CLASSES} | {D['LEVEL_CROSSING']}
    for y, x in zip(*np.nonzero(d0)):
        if d0[y, x] not in vector_ids:
            L['ground_detail'][y, x] = detail_tile(0, y, x, d0)

    # edificios: tejados (con cumbrera) y fachadas según el tipo (tools/buildings.py)
    def front_walk(y, x):
        return 0 <= y < H and 0 <= x < W and bld[y, x] == 0 and \
            bool(walk_detail[y, x] or ground[y, x] in sem.WALKABLE_GROUND)

    def pedestrian(y, x):
        return 0 <= y < H and 0 <= x < W and d0[y, x] in (D['PEDESTRIAN'], D['FOOTWAY'])
    buildings.clean_thin(bld, report['straighten'])   # restos de hitos y accesos
    dressed, report['building_classes'] = buildings.dress(bld, binfo, tid, front_walk, pedestrian)
    for (y, x), g in dressed.items():
        L['structures'][y, x] = g

    wname = {1: 'stone', 2: 'hedge', 3: 'cliff'}
    for y, x in zip(*np.nonzero(walls)):
        k = walls[y, x]
        m = neighbors_mask(lambda a, b: walls[a, b] == k, y, x)
        L['structures'][y, x] = tid(f'w_{wname[k]}_{m}')

    for y, x in zip(*np.nonzero(ledge)):
        L['structures'][y, x] = tid(f'w_ledge_{ledge[y, x]}')

    # cipreses: en los cementerios y alguno en jardines urbanos
    cyp = (trees > 0) & (trees < 5) & ((ground == G['CEMETERY']) |
                                        ((ground == G['URBAN']) & (vrng.random((H, W)) < .08)))
    trees[cyp] = 7
    tnames = {1: 'pine0', 2: 'pine1', 3: 'palm', 4: 'olive', 7: 'cypress'}
    for y, x in zip(*np.nonzero(trees)):
        k = trees[y, x]
        if k in (5, 6):
            L['structures'][y, x] = tid(f'bush_{k - 5}')
        else:
            L['structures'][y, x] = tid(f'tree_{tnames[k]}_bot')
            if y > 0:
                L['overhead'][y - 1, x] = tid(f'tree_{tnames[k]}_top')

    # --- colisión por nivel ---------------------------------------------------------
    walkable = lambda v: v in sem.WALKABLE_DETAIL
    coll = np.zeros((H, W), np.uint8)
    solid0 = (bld > 0) | (walls > 0) | (trees > 0) | lm_solid | (ground == G['VOID']) | (ledge > 0)
    coll[:] = WALK
    coll[(ground == G['SEA']) | (ground == G['WATER'])] = WATER
    coll[np.isin(d0, list(sem.WALKABLE_DETAIL))] = WALK
    coll[d0 == D['TORRENT']] = WATER   # lecho del torrente: solo se cruza por puentes y calles
    coll[np.isin(d0, [D['RAIL'], D['RAIL_HS'], D['PENDING']])] = SOLID
    coll[d0 == D['MOTORWAY']] = HAZARD
    coll[solid0] = SOLID
    w1 = np.isin(detail[1], list(sem.WALKABLE_DETAIL))
    wm1 = np.isin(detail[-1], list(sem.WALKABLE_DETAIL))
    coll[w1] |= BIT_L1
    coll[wm1] |= BIT_LM1
    coll[d0 == D['PENDING']] |= BIT_PENDING

    # rampas: extremos de puentes/túneles transitables que tocan suelo transitable,
    # excluyendo la huella (dilatada) de lo que cruzan a otro nivel
    node_ways = {}
    for wid, (tags, refs) in osm.ways.items():
        for ref in refs:
            node_ways.setdefault(ref, set()).add(wid)
    ramps = np.zeros((H, W), bool)
    ramp_report = []
    for wid, (lv, loc, cls, pts) in r['way_mask'].items():
        if lv == 0 or cls not in sem.WALKABLE_DETAIL:
            continue
        tags, refs = osm.ways[wid]
        y0, x0, m = loc
        foot = np.zeros((H, W), bool)
        foot[y0:y0 + m.shape[0], x0:x0 + m.shape[1]] = m
        crossed = np.zeros((H, W), bool)
        my_nodes = set(refs)
        for owid, (olv, oloc, ocls, opts) in r['way_mask'].items():
            if olv == lv or owid == wid or (lv == -1 and ocls in (D['TORRENT'], D['STREAM'])):
                continue  # los pasos inferiores que siguen un cauce no pasan «bajo» él: necesitan rampa
            if my_nodes & set(osm.ways[owid][1]):
                continue
            oy, ox, om = oloc
            if oy > y0 + m.shape[0] or ox > x0 + m.shape[1] or oy + om.shape[0] < y0 or ox + om.shape[1] < x0:
                continue
            of = np.zeros((H, W), bool)
            of[oy:oy + om.shape[0], ox:ox + om.shape[1]] = om
            if (of & foot).any():
                crossed |= of
        crossed_raw = crossed
        crossed = dilate(crossed, 1)
        bit = BIT_L1 if lv == 1 else BIT_LM1
        n_before = int(ramps.sum())
        # todo el tablero/túnel que NO está sobre lo que cruza es acceso (terraplén o trinchera):
        # rampa; sobre lo cruzado solo se pasa por arriba (o por abajo)
        zone = foot & ~crossed & ((coll & 3) == WALK) & ((coll & bit) > 0)
        ramps |= zone
        for end, inner in ((pts[0], pts[1] if len(pts) > 1 else pts[0]), (pts[-1], pts[-2] if len(pts) > 1 else pts[-1])):
            ex_, ey_ = end
            found = False
            for cy in range(int(ey_) - 4, int(ey_) + 5):
                for cx in range(int(ex_) - 4, int(ex_) + 5):
                    if not (0 <= cx < W and 0 <= cy < H) or not foot[cy, cx]:
                        continue
                    if math.hypot(cx + .5 - ex_, cy + .5 - ey_) > max(2.5, m2t(12)) or crossed[cy, cx]:
                        continue
                    if (coll[cy, cx] & 3) == WALK and coll[cy, cx] & bit:
                        ramps[cy, cx] = True
                        found = True
            if found:
                continue
            # extremo dentro de lo que cruza (vía ensanchada): prolongar el paso en su dirección
            dx_, dy_ = ex_ - inner[0], ey_ - inner[1]
            norm = math.hypot(dx_, dy_) or 1
            dx_, dy_ = dx_ / norm, dy_ / norm
            t = 0.0
            while t <= T(60) and not found:
                px_, py_ = ex_ + dx_ * t, ey_ + dy_ * t
                cand = []
                for cy in range(int(py_) - 1, int(py_) + 2):
                    for cx in range(int(px_) - 1, int(px_) + 2):
                        if not (0 <= cx < W and 0 <= cy < H) or math.hypot(cx + .5 - px_, cy + .5 - py_) > 1.0:
                            continue
                        if (coll[cy, cx] & 3) == SOLID and not crossed[cy, cx]:
                            continue  # no atravesar edificios ni árboles
                        coll[cy, cx] |= bit
                        if not crossed[cy, cx] and (coll[cy, cx] & 3) == WALK:
                            cand.append((cx, cy))
                for cx, cy in cand:
                    ramps[cy, cx] = True
                    found = True
                t += 0.5
            if found:  # completar la zona de rampa de 2 tiles más allá del cruce
                for k in (0.5, 1.0, 1.5):
                    px_, py_ = ex_ + dx_ * (t + k), ey_ + dy_ * (t + k)
                    for cy in range(int(py_) - 1, int(py_) + 2):
                        for cx in range(int(px_) - 1, int(px_) + 2):
                            if 0 <= cx < W and 0 <= cy < H and math.hypot(cx + .5 - px_, cy + .5 - py_) <= 1.0 \
                                    and not crossed[cy, cx] and (coll[cy, cx] & 3) == WALK:
                                coll[cy, cx] |= bit
                                ramps[cy, cx] = True
            if not found:
                report['warnings'].append(f'paso {wid} (nivel {lv}): extremo sin rampa')
            else:
                report['warnings'].append(f'paso {wid} (nivel {lv}): prolongado {t:.1f} tiles hasta salir del cruce')
        # rampes més amples: una casella més cap al terra transitable del voltant (no sobre el que es creua). Amb
        # una rampa d'una sola casella en diagonal, la bici (que gira amb radi) no l'enfilava (Carrer de Santa Coloma)
        if cls not in (D['STEPS'],):
            mine = ramps & foot
            # al costat d'una via (sòlida) també: si no, a dalt de la rampa la bici sortia pel lateral a terra
            near = crossed_raw | dilate(crossed_raw & ((coll & 3) == WALK), 1)
            wide = dilate(mine, 1) & ~mine & ~near & ((coll & 3) == WALK) & ((coll & BIT_PENDING) == 0)
            if wide.any():
                coll[wide] |= bit
                ramps |= wide
                report['ramps_widened'] = report.get('ramps_widened', 0) + int(wide.sum())
        ramp_report.append({'way': wid, 'level': lv, 'ramp_cells': int(ramps.sum()) - n_before})
    # pasos sin salida: cada extremo de un carril a otro nivel (los dos puntos más alejados del componente)
    # debe tener rampa; si no, al bajar por un lado no se podía subir por el otro (Carrer de Cadaqués)
    report['dead_end_ramps'] = dead_end_ramps(coll, ramps)
    for c in overrides.get('ramps_add', []):
        ramps[c[1], c[0]] = True
    for c in overrides.get('ramps_remove', []):
        ramps[c[1], c[0]] = False
    coll[ramps] |= BIT_RAMP
    if rd is not None:
        keep = np.array([list(d) for d in poi_doors.values()], np.int64).reshape(-1, 2)
        start = poi_doors.get('sant_bartomeu', (poi_by_id['sant_bartomeu']['tile_x'], poi_by_id['sant_bartomeu']['tile_y']))
        opened, removed, isolated = realdata.repair_access(coll, L, tid, ledge, trees, keep, start, walkgraph, WALK)
        report['access_stairs'] = opened
        report['access_trees_removed'] = removed
        if isolated:
            report['warnings'].append(f'{len(isolated)} POI fuera de la zona principal tras el relieve')
    L['collision'] = coll

    # --- altura (desnivel) y superficie por casilla: capa 'height' (src/world/map.lua Map:height_at) ---
    # bits 0–9: altura del terreno en metros (MDT suavizado, el mismo que decide los bordes de roca: el
    # nivel es altura // 8); bits 10–11: superficie 0 natural, 1 pavimentada, 2 camino de tierra, 3 escaleras
    hl = np.zeros((H, W), np.uint32)
    if rd is not None:
        from scipy import ndimage as _nd
        hl[:] = np.clip(np.floor(_nd.uniform_filter(rd['elev'], 5)), 0, 1023).astype(np.uint32)
    paved = np.isin(d0, [D[k] for k in ('ROAD', 'ROAD_MAIN', 'MOTORWAY', 'PEDESTRIAN', 'FOOTWAY', 'PLATFORM',
                                         'PIER', 'LEVEL_CROSSING')]) | np.isin(ground, [G['URBAN'], G['PITCH'], G['RAILYARD']])
    paved |= (detail[1] > 0)   # tableros de puente
    dirt = np.isin(d0, [D['PATH'], D['TRACK']])
    stairs_t = {tid('st_stone_v'), tid('st_stone_h')}
    steps = (d0 == D['STEPS']) | np.isin(L['structures'], list(stairs_t))
    surf = np.where(steps, 3, np.where(paved, 1, np.where(dirt, 2, 0))).astype(np.uint32)
    L['height'] = hl | (surf << 10)
    report['height_m'] = [int(hl.min()), int(hl.max())]

    # --- objetos: aparición pública, anclas y casa (sin ubicación) -------------------
    # aparición pública: delante de Sant Bartomeu, en suelo transitable y lejos de las vías
    if 'sant_bartomeu' in poi_by_id:
        cx, cy = poi_doors.get('sant_bartomeu', (poi_by_id['sant_bartomeu']['tile_x'], poi_by_id['sant_bartomeu']['tile_y']))
    else:   # lugar nuevo: el centro del mapa (el punto GPS de tools/new_location.py)
        _w = json.load(open(os.path.join(ROOT, 'data/world.json')))
        cx, cy = to_tile(_w.get('center_lon', from_tile(W // 2, H // 2)[0]), _w.get('center_lat', from_tile(W // 2, H // 2)[1]))
    rails = dilate(np.isin(d0, [D['RAIL'], D['RAIL_HS'], D['LEVEL_CROSSING'], D['MOTORWAY']]), T(30))
    best = None
    for rad in range(1, T(300)):
        for y in range(cy - rad, cy + rad + 1):
            for x in range(cx - rad, cx + rad + 1):
                if coll[y, x] == WALK and not rails[y, x] and (x, y) != (cx, cy):
                    d = (x - cx) ** 2 + (y - cy - 1.5) ** 2
                    if best is None or d < best[0]:
                        best = (d, x, y)
        if best:
            break
    spawn = {'x': best[1], 'y': best[2]}
    objects.append({'type': 'spawn', 'name': 'spawn_public_centre', 'x': spawn['x'] * 16 + 8,
                    'y': spawn['y'] * 16 + 8, 'point': True,
                    'properties': {'public': True, 'note': 'Espacio público junto a Sant Bartomeu'}})
    for p in POIS:
        objects.append({'type': 'anchor', 'name': 'anchor_' + p['id'], 'x': p['tile_x'] * 16 + 8,
                        'y': p['tile_y'] * 16 + 8, 'point': True,
                        'properties': {'osm': p['osm'], 'lon': p['lon'], 'lat': p['lat'],
                                       'note': 'ancla cartográfica, no es punto de aparición'}})
    for nid, kind, x, y in r['crossings']:
        if 0 <= x < W and 0 <= y < H:
            objects.append({'type': 'level_crossing', 'name': f'lc_{nid}', 'x': x * 16, 'y': y * 16,
                            'point': True, 'properties': {'osm': f'node/{nid}'}})
    for nid, tags in osm.node_tags.items():
        if tags.get('railway') in ('halt', 'station'):
            x, y = to_tile_f(*osm.nodes[nid])
            objects.append({'type': 'station', 'name': tags.get('name', nid), 'x': x * 16, 'y': y * 16,
                            'point': True, 'properties': {'osm': f'node/{nid}'}})
    # objetos de contenido (NPC, carteles, enemigos) definidos a mano junto a un POI
    taken = set()
    for o in objects:
        if o.get('point'):
            taken.add((int(o['x'] // 16), int(o['y'] // 16)))
    for o in load_json('maps/source/content-objects.json', []):
        door = poi_doors.get(o['near'])
        if not door:
            report['warnings'].append(f"contenido {o['name']}: POI {o['near']} sin colocar")
            continue
        tx, ty = door[0] + o['offset'][0], door[1] + o['offset'][1]
        best = None
        for rad in range(0, T(120)):
            for yy_ in range(ty - rad, ty + rad + 1):
                for xx_ in range(tx - rad, tx + rad + 1):
                    if max(abs(xx_ - tx), abs(yy_ - ty)) != rad or not (0 <= xx_ < W and 0 <= yy_ < H):
                        continue
                    if coll[yy_, xx_] == WALK and (xx_, yy_) not in taken:
                        best = (xx_, yy_)
                        break
                if best: break
            if best: break
        if not best:
            report['warnings'].append(f"contenido {o['name']}: sin celda libre")
            continue
        taken.add(best)
        if o['type'] == 'sign':
            # los carteles bloquean su celda
            coll[best[1], best[0]] = SOLID
        objects.append({'type': o['type'], 'name': o['name'], 'x': best[0] * 16 + 8, 'y': best[1] * 16 + 8,
                        'point': True, 'properties': o.get('props', {})})

    # --- rutas de fase 2 (polilíneas dirigidas) -----------------------------------
    routes = build_routes(osm, r, report)
    for rt in routes:  # misma suavización que el dibujo, para que coches y trenes sigan la curva
        rt['points'], rt['levels'] = smooth_with_levels(rt['points'], rt['levels'])
    lines = build_lines(r)
    report['vector_lines'] = len(lines)
    # --- servicios del pueblo (data/services.json): personaje delante del edificio real de OSM -------
    report['services'] = place_services(osm, routes, poi_doors, coll, taken, objects, report)

    # cruces entre rutas de coche (zonas de reserva), precalculados aquí para no hacerlo en Lua
    def dense(pts, step=8):
        out = []
        for (ax, ay), (bx, by) in zip(pts, pts[1:]):
            n = max(1, int(math.dist((ax, ay), (bx, by)) // step))
            out += [(ax + (bx - ax) * k / n, ay + (by - ay) * k / n) for k in range(n)]
        return np.array(out)
    cars = [rt for rt in routes if rt['type'] == 'car' and rt['name'] != 'road_ap7']
    zones = []
    for i in range(len(cars)):
        A = dense(cars[i]['points'])
        for j in range(i + 1, len(cars)):
            B = dense(cars[j]['points'])
            if not len(A) or not len(B):
                continue
            for k in range(0, len(A), 512):
                a = A[k:k + 512]
                d2 = ((a[:, None, :] - B[None, :, :]) ** 2).sum(-1).min(1)
                for (x, y), dd in zip(a, d2):
                    if dd < 100 and all((x - zx) ** 2 + (y - zy) ** 2 > 40 ** 2 for zx, zy in zones):
                        zones.append((float(x), float(y)))
    for n_, (x, y) in enumerate(zones):
        objects.append({'type': 'junction', 'name': f'junction_{n_}', 'x': round(x, 1), 'y': round(y, 1),
                        'point': True, 'properties': {'r': 22}})
    report['junctions'] = len(zones)

    # --- escribir TMJ -------------------------------------------------------------
    write_tmj(L, objects, routes, tiles, report, lines)
    report['ramps'] = int(ramps.sum())
    report['ramp_ways'] = ramp_report
    report['buildings'] = len(binfo) - 1
    report['spawn_public_centre'] = spawn
    with open(os.path.join(ROOT, 'maps/source/import-report.json'), 'w') as f:
        json.dump(report, f, indent=1, ensure_ascii=False)
    # semántica compacta para validación/herramientas
    np.savez_compressed(os.path.join(ROOT, 'maps/source/semantic.npz'), ground=ground, d0=d0,
                        d1=detail[1], dm1=detail[-1], bld=bld, coll=coll, limit=r['limit'])
    print('ok', {k: v for k, v in report.items() if k not in ('ramp_ways', 'warnings')},
          len(report['warnings']), 'avisos')


def dead_end_ramps(coll, ramps):
    """Rampas en los extremos de los carriles a nivel 1 / -1 que no tienen ninguna a 3 casillas."""
    from collections import deque
    from scipy import ndimage
    added = 0
    for bit in (BIT_L1, BIT_LM1):
        lane = (coll & bit) > 0
        lab, n = ndimage.label(lane)
        for k, sl in enumerate(ndimage.find_objects(lab), 1):
            if sl is None:
                continue
            comp = lab[sl] == k
            if comp.sum() < 4:
                continue
            def far(start):
                dist = {start: 0}
                q = deque([start])
                last = start
                while q:
                    c = q.popleft(); last = c
                    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        y, x = c[0] + dy, c[1] + dx
                        if 0 <= y < comp.shape[0] and 0 <= x < comp.shape[1] and comp[y, x] and (y, x) not in dist:
                            dist[(y, x)] = dist[c] + 1
                            q.append((y, x))
                return last
            ys, xs = np.nonzero(comp)
            a = far((int(ys[0]), int(xs[0])))
            b = far(a)
            for ey, ex in (a, b):
                gy, gx = ey + sl[0].start, ex + sl[1].start
                y0, y1, x0, x1 = max(0, gy - 3), gy + 4, max(0, gx - 3), gx + 4
                if ramps[y0:y1, x0:x1].any():
                    continue
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        y, x = gy + dy, gx + dx
                        if 0 <= y < coll.shape[0] and 0 <= x < coll.shape[1] and (coll[y, x] & bit) and (coll[y, x] & 3) == WALK:
                            ramps[y, x] = True
                            added += 1
    return added


def place_services(osm, routes, poi_doors, coll, taken, objects, report):
    """Coloca cada servicio en la celda transitable libre más cercana a su elemento OSM (centro del edificio),
    a un lugar del plan (near + offset) o, en los baixadors inventados, junto a la vía (rail)."""
    spec = load_json('data/services.json', {'services': []})['services']
    placed = 0
    for sv in spec:
        if sv.get('runtime'):       # personatges que col·loca el joc (p. ex. la mestra a l'escola)
            continue
        anchor = None
        ref = sv.get('osm', '')
        if ref.startswith('node/') and ref[5:] in osm.nodes:
            anchor = to_tile_f(*osm.nodes[ref[5:]])
        elif ref.startswith('way/') and ref[4:] in osm.ways:
            pts = osm.way_tiles(ref[4:])
            if pts:
                anchor = (sum(p[0] for p in pts) / len(pts), sum(p[1] for p in pts) / len(pts))
        elif sv.get('tile'):            # adreça real sense element a l'OSM (Correus): la casella
            anchor = (sv['tile'][0] + 0.5, sv['tile'][1] + 0.5)
        elif sv.get('near') in poi_doors:
            anchor = poi_doors[sv['near']]
            if sv.get('rail'):
                rt = next((r_ for r_ in routes if r_['name'] == sv['rail']), None)
                if rt:
                    ax, ay = anchor[0] * 16 + 8, anchor[1] * 16 + 8
                    bx, by = min(rt['points'], key=lambda q: (q[0] - ax) ** 2 + (q[1] - ay) ** 2)
                    anchor = (bx / 16, by / 16)
        if anchor is None:
            report['warnings'].append(f"servicio {sv['id']}: sin ubicación ({ref or sv.get('near')})")
            continue
        off = sv.get('offset', [0, 0])
        tx, ty = int(anchor[0]) + off[0], int(anchor[1]) + off[1]
        best = None
        for rad in range(0, T(160)):
            for yy_ in range(ty - rad, ty + rad + 1):
                for xx_ in range(tx - rad, tx + rad + 1):
                    if max(abs(xx_ - tx), abs(yy_ - ty)) != rad or not (1 <= xx_ < W - 1 and 1 <= yy_ < H - 1):
                        continue
                    # libre y con paso alrededor (que el personaje no tape un pasillo)
                    if coll[yy_, xx_] == WALK and (xx_, yy_) not in taken and \
                            sum(coll[yy_ + dy, xx_ + dx] == WALK for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))) >= 3:
                        best = (xx_, yy_)
                        break
                if best: break
            if best: break
        if not best:
            report['warnings'].append(f"servicio {sv['id']}: sin celda libre")
            continue
        taken.add(best)
        props = {'service': sv['kind'], 'service_id': sv['id'], 'label': sv['label'], 'sprite': sv.get('sprite', 'npc_elder'),
                 'say_name': sv.get('name', sv['label']), 'facing': 'down'}
        if sv.get('fictitious'):
            props['fictitious'] = True
        objects.append({'type': 'service', 'name': 'service_' + sv['id'], 'x': best[0] * 16 + 8, 'y': best[1] * 16 + 8,
                        'point': True, 'properties': props})
        placed += 1
    return placed


def build_routes(osm, r, report):
    """Rutas de tren por corredor (cadena más larga por nombre) y de coche (N-340, TV-2041)."""
    routes = []

    def chain_for(pred):
        segs = [refs for wid, (t, refs) in osm.ways.items() if pred(t)]
        from osmlib import join_segments
        chains = join_segments(segs)

        def length(c):
            return sum(math.dist(to_tile_f(*osm.nodes[a]), to_tile_f(*osm.nodes[b])) for a, b in zip(c, c[1:]))
        return max(chains, key=length) if chains else None

    node_level = {}
    edge_level = {}   # nivell per tram: un pont d'un sol segment no té nodes interiors
    for wid, (t, refs) in osm.ways.items():
        if t.get('railway') == 'rail' or t.get('highway') in ('primary', 'tertiary'):
            lv = sem.way_level(t, wid, sum(math.dist(to_tile_f(*osm.nodes[a]), to_tile_f(*osm.nodes[b]))
                                           for a, b in zip(refs, refs[1:]) if a in osm.nodes and b in osm.nodes))
            for ref in refs[1:-1]:
                node_level[ref] = lv
            if lv:
                for a, b in zip(refs, refs[1:]):
                    edge_level[(a, b)] = edge_level[(b, a)] = lv
    local_chain_of = {}
    corridors = [
        ('train', 'rail_hs', lambda t: t.get('railway') == 'rail' and t.get('highspeed') == 'yes'
         and t.get('service') is None, 'Alta velocitat (decorativa)'),
        ('train', 'rail_interior', lambda t: t.get('railway') == 'rail'
         and (t.get('name') or '').startswith('FFCC Sant Vicenç de Calders - Lleida'), 'Línia interior (Roda de Mar)'),
        ('train', 'rail_litoral', lambda t: t.get('railway') == 'rail'
         and (t.get('name') or '').startswith('FFCC València'), 'Línia litoral'),
        ('car', 'road_n340', lambda t: t.get('highway') in ('primary', 'trunk') and t.get('ref') == 'N-340', 'N-340'),
        ('car', 'road_tv2041', lambda t: t.get('highway') == 'tertiary' and t.get('ref') == 'TV-2041', 'TV-2041'),
        ('car', 'road_ap7', lambda t: t.get('highway') == 'motorway' and t.get('ref') == 'AP-7',
         'AP-7 (decorativa, inaccesible)'),
    ]
    # calles locales largas (urbanizaciones) para que haya tráfico por todo el pueblo
    from osmlib import join_segments as _js
    loc_segs = [refs for wid, (t, refs) in osm.ways.items()
                if t.get('highway') in ('residential', 'unclassified', 'tertiary', 'secondary')
                and t.get('ref') not in ('TV-2041',) and not t.get('bridge') and not t.get('tunnel')]
    loc_chains = sorted(_js(loc_segs), key=lambda c: -sum(
        math.dist(to_tile_f(*osm.nodes[a]), to_tile_f(*osm.nodes[b])) for a, b in zip(c, c[1:])))
    for i, ch_ in enumerate(loc_chains[:14]):
        corridors.append(('car', f'road_local_{i}', (lambda chain: (lambda t: None))(ch_), 'Carrer local'))
        local_chain_of[f'road_local_{i}'] = ch_
    stations = []
    for nid, tags in osm.node_tags.items():
        if tags.get('railway') in ('halt', 'station'):
            stations.append(nid)
    from osmlib import join_segments as _join

    def chain_len(c):
        return sum(math.dist(to_tile_f(*osm.nodes[p]), to_tile_f(*osm.nodes[q])) for p, q in zip(c, c[1:]))

    for kind, rid, pred, label in corridors:
        if kind == 'train':
            segs = [refs for wid, (t, refs) in osm.ways.items() if pred(t) and t.get('service') is None]
            chains = sorted(_join(segs), key=chain_len, reverse=True)
            # vía doble: dos cadenas largas → una ruta por vía y sentido; vía única: ambos sentidos
            if len(chains) >= 2 and chain_len(chains[1]) > 0.5 * chain_len(chains[0]):
                picks = [(chains[0], rid + '_a', 'fwd'), (chains[1], rid + '_b', 'bwd')]
            else:
                picks = [(chains[0], rid, 'both')] if chains else []
        else:
            ch = local_chain_of.get(rid) or chain_for(pred)
            picks = [(ch, rid, 'both')] if ch else []
        if not picks:
            report['warnings'].append(f'ruta {rid}: sin geometría')
            continue
        for ch, name, dirs in picks:
            pts, levels, stops = [], [], []
            prev = None
            for ref in ch:
                el = edge_level.get((prev, ref), 0) if prev is not None else 0
                if el and (node_level.get(prev, 0) != el or node_level.get(ref, 0) != el):
                    # punt mig amb el nivell del pont/túnel (si no, el tren el creuaria a nivell del terra)
                    (ax, ay), (bx, by) = to_tile_f(*osm.nodes[prev]), to_tile_f(*osm.nodes[ref])
                    pts.append((round((ax + bx) * 8, 1), round((ay + by) * 8, 1)))
                    levels.append(el)
                    report['route_level_midpoints'] = report.get('route_level_midpoints', 0) + 1
                prev = ref
                x, y = to_tile_f(*osm.nodes[ref])
                pts.append((round(x * 16, 1), round(y * 16, 1)))
                levels.append(node_level.get(ref, 0))
                if ref in stations:
                    stops.append(len(pts) - 1)
            if pts[0][0] > pts[-1][0]:  # sentido de referencia: oeste → este
                pts, levels = pts[::-1], levels[::-1]
                stops = [len(pts) - 1 - s for s in stops]
            if kind == 'train' and not stops:
                for nid in stations:
                    sx, sy = to_tile_f(*osm.nodes[nid])
                    best = min(range(len(pts)), key=lambda i: (pts[i][0] - sx * 16) ** 2 + (pts[i][1] - sy * 16) ** 2)
                    if math.hypot(pts[best][0] - sx * 16, pts[best][1] - sy * 16) < 160:
                        stops.append(best)
            routes.append({'name': name, 'type': kind, 'label': label, 'points': pts, 'levels': levels,
                           'stops': stops, 'corridor': rid, 'dirs': dirs})
    return routes


VECTOR_CLASSES = {'TORRENT', 'STREAM', 'PATH', 'TRACK', 'STEPS', 'FOOTWAY', 'PEDESTRIAN', 'ROAD', 'ROAD_MAIN', 'MOTORWAY',
                  'RAIL', 'RAIL_HS', 'PLATFORM'}


def chaikin(pts, closed, iters=2, min_turn=12):
    """Suaviza esquinas (Chaikin) solo donde la polilínea gira más de `min_turn` grados."""
    for _ in range(iters):
        if len(pts) < 3:
            return pts
        out = [] if closed else [pts[0]]
        n = len(pts)
        rng = range(n) if closed else range(1, n - 1)
        for i in rng:
            a, b, c = pts[i - 1], pts[i], pts[(i + 1) % n]
            v1 = (b[0] - a[0], b[1] - a[1])
            v2 = (c[0] - b[0], c[1] - b[1])
            l1, l2 = math.hypot(*v1), math.hypot(*v2)
            turn = 0 if l1 == 0 or l2 == 0 else math.degrees(math.acos(max(-1, min(1, (v1[0] * v2[0] + v1[1] * v2[1]) / (l1 * l2)))))
            if turn < min_turn:
                out.append(b)
                continue
            out.append((b[0] - v1[0] * 0.25, b[1] - v1[1] * 0.25))
            out.append((b[0] + v2[0] * 0.25, b[1] + v2[1] * 0.25))
        if not closed:
            out.append(pts[-1])
        pts = out
    return pts


def smooth_with_levels(pts, levels):
    """Suaviza una ruta conservando el nivel de cada tramo (vértice nuevo → nivel del original cercano)."""
    sm = chaikin(list(pts), False)
    out_lv = []
    j = 0
    for p in sm:
        while j + 1 < len(pts) and math.dist(p, pts[j + 1]) < math.dist(p, pts[j]):
            j += 1
        out_lv.append(levels[j] if j < len(levels) else 0)
    return [(round(x, 1), round(y, 1)) for x, y in sm], out_lv


def build_lines(r):
    """Polilíneas en píxeles para el dibujo vectorial de vías (carreteras, caminos, ferrocarril)."""
    name = {v: k for k, v in D.items()}
    out = []
    for wid, (lv, loc, cls, pts) in r['way_mask'].items():
        cname = name[cls]
        if cname not in VECTOR_CLASSES or len(pts) < 2:
            continue
        refs = r['osm'].ways[wid][1]
        closed = refs[0] == refs[-1]
        sm = chaikin([(x * 16, y * 16) for x, y in pts], closed)
        width_px = max(6, round(m2t(r['way_width'].get(wid, 4)) * 16))
        if cname in ('RAIL', 'RAIL_HS'):
            width_px = 16
        out.append({'cls': cname, 'level': lv, 'w': width_px, 'closed': closed, 'osm': wid,
                    'pts': [(round(x, 1), round(y, 1)) for x, y in sm]})
    return out


def write_tmj(L, objects, routes, tiles, report, lines=()):
    count = len(tiles)
    src = os.path.join(ROOT, 'maps/source')
    os.makedirs(src, exist_ok=True)
    anim_tiles = []
    for name, t in tiles.items():
        if t.get('anim') and name.endswith('_0'):
            base = name[:-2]
            anim_tiles.append({'id': t['id'], 'animation': [
                {'tileid': tiles[f'{base}_{f}']['id'], 'duration': 250} for f in range(t['anim'])]})
    props = []
    for name, t in tiles.items():
        p = [{'name': 'name', 'type': 'string', 'value': name}]
        if t.get('solid'):
            p.append({'name': 'solid', 'type': 'bool', 'value': True})
        if t.get('overhead'):
            p.append({'name': 'overhead', 'type': 'bool', 'value': True})
        props.append({'id': t['id'], 'properties': p})
    by_id = {a['id']: a for a in anim_tiles}
    for p in props:
        if p['id'] in by_id:
            p['animation'] = by_id[p['id']]['animation']
    tsj = {'type': 'tileset', 'version': '1.10', 'tiledversion': '1.10.2', 'name': 'tiles',
           'image': '../../assets/runtime/tiles.png', 'imagewidth': 512, 'imageheight': 16 * ((count + 31) // 32),
           'tilewidth': 16, 'tileheight': 16, 'tilecount': count, 'columns': 32, 'margin': 0, 'spacing': 0,
           'tiles': props}
    with open(os.path.join(src, 'tiles.tsj'), 'w') as f:
        json.dump(tsj, f, separators=(',', ':'), ensure_ascii=False)
    ctsj = {'type': 'tileset', 'version': '1.10', 'tiledversion': '1.10.2', 'name': 'collision',
            'image': '../../assets/runtime/collision.png', 'imagewidth': 128, 'imageheight': 128,
            'tilewidth': 16, 'tileheight': 16, 'tilecount': 64, 'columns': 8, 'margin': 0, 'spacing': 0,
            'tiles': [{'id': c, 'properties': [{'name': 'code', 'type': 'int', 'value': c}]} for c in range(64)]}
    with open(os.path.join(src, 'collision.tsj'), 'w') as f:
        json.dump(ctsj, f, separators=(',', ':'))
    coll_first = COLL_FIRSTGID  # fijo: añadir tiles al atlas no desplaza la colisión
    assert count < COLL_FIRSTGID, 'demasiados tiles para COLL_FIRSTGID'
    layers = []
    lid = 1
    for name in ('ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead', 'collision', 'height'):
        if name not in L:
            continue
        arr = L[name].astype(np.int64)
        if name == 'collision':
            arr = arr + coll_first
        layer = {'id': lid, 'name': name, 'type': 'tilelayer', 'width': W, 'height': H, 'x': 0, 'y': 0,
                 'opacity': 0.6 if name == 'collision' else 1, 'visible': name not in ('collision', 'height'),
                 'data': arr.flatten().tolist()}
        if name == 'height':   # valores crudos (metros + superficie), no tiles: Tiled la muestra oculta
            layer['properties'] = [{'name': 'raw', 'type': 'bool', 'value': True}]
        layers.append(layer)
        lid += 1
    oid = 1
    objs = []
    for o in objects:
        e = {'id': oid, 'name': o['name'], 'type': o['type'], 'x': o['x'], 'y': o['y'],
             'width': o.get('width', 0), 'height': o.get('height', 0), 'rotation': 0, 'visible': True,
             'properties': [{'name': k, 'type': 'bool' if isinstance(v, bool) else 'int' if isinstance(v, int)
                             else 'float' if isinstance(v, float) else 'string', 'value': v}
                            for k, v in o.get('properties', {}).items()]}
        if o.get('point'):
            e['point'] = True
        objs.append(e)
        oid += 1
    layers.append({'id': lid, 'name': 'objects', 'type': 'objectgroup', 'draworder': 'topdown', 'objects': objs,
                   'x': 0, 'y': 0, 'opacity': 1, 'visible': True}); lid += 1
    robjs = []
    for rt in routes:
        x0, y0 = rt['points'][0]
        robjs.append({'id': oid, 'name': rt['name'], 'type': 'route_' + rt['type'], 'x': x0, 'y': y0,
                      'width': 0, 'height': 0, 'rotation': 0, 'visible': True,
                      'polyline': [{'x': round(px - x0, 1), 'y': round(py - y0, 1)} for px, py in rt['points']],
                      'properties': [
                          {'name': 'label', 'type': 'string', 'value': rt['label']},
                          {'name': 'levels', 'type': 'string', 'value': ','.join(map(str, rt['levels']))},
                          {'name': 'stops', 'type': 'string', 'value': ','.join(map(str, rt['stops']))},
                          {'name': 'corridor', 'type': 'string', 'value': rt.get('corridor', rt['name'])},
                          {'name': 'dirs', 'type': 'string', 'value': rt.get('dirs', 'both')}]})
        oid += 1
    lobjs = []
    for ln in lines:
        x0, y0 = ln['pts'][0]
        lobjs.append({'id': oid, 'name': '', 'type': 'line', 'x': x0, 'y': y0, 'width': 0, 'height': 0,
                      'rotation': 0, 'visible': True,
                      'polyline': [{'x': round(px - x0, 1), 'y': round(py - y0, 1)} for px, py in ln['pts']],
                      'properties': [{'name': 'cls', 'type': 'string', 'value': ln['cls']},
                                     {'name': 'level', 'type': 'int', 'value': ln['level']},
                                     {'name': 'w', 'type': 'int', 'value': ln['w']},
                                     {'name': 'closed', 'type': 'bool', 'value': ln['closed']},
                                     {'name': 'osm', 'type': 'string', 'value': 'way/' + ln['osm']}]})
        oid += 1
    layers.append({'id': lid, 'name': 'lines', 'type': 'objectgroup', 'draworder': 'topdown', 'objects': lobjs,
                   'x': 0, 'y': 0, 'opacity': 1, 'visible': True}); lid += 1
    layers.append({'id': lid, 'name': 'routes', 'type': 'objectgroup', 'draworder': 'topdown', 'objects': robjs,
                   'x': 0, 'y': 0, 'opacity': 1, 'visible': True}); lid += 1
    tmj = {'type': 'map', 'version': '1.10', 'tiledversion': '1.10.2', 'orientation': 'orthogonal',
           'renderorder': 'right-down', 'infinite': False, 'width': W, 'height': H, 'tilewidth': 16,
           'tileheight': 16, 'nextlayerid': lid, 'nextobjectid': oid, 'compressionlevel': -1,
           'properties': [
               {'name': 'scene', 'type': 'string', 'value': 'overworld'},
               {'name': 'origin_lon', 'type': 'float', 'value': ORIGIN_LON},
               {'name': 'origin_lat', 'type': 'float', 'value': ORIGIN_LAT},
               {'name': 'meters_per_tile', 'type': 'float', 'value': M_PER_TILE},
               {'name': 'attribution', 'type': 'string', 'value': '© OpenStreetMap contributors (ODbL)'}],
           'tilesets': [{'firstgid': 1, 'source': 'tiles.tsj'}, {'firstgid': coll_first, 'source': 'collision.tsj'}],
           'layers': layers}
    with open(os.path.join(src, 'overworld.tmj'), 'w') as f:
        json.dump(tmj, f, separators=(',', ':'), ensure_ascii=False)


if __name__ == '__main__':
    main()
