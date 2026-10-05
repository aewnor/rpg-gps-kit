"""Datos reales que complementan OSM en el importador (ver tools/fetch_sources.py).

  · edificios del Catastro (huella real en lugar de casas de relleno) y sus piscinas
  · suelo y árboles según la ortofoto PNOA (verdor y copas por tile)
  · niveles de terreno a partir del MDT: bordes de roca (w_ledge_*) entre niveles en terreno natural;
    calles, caminos y zonas urbanas siguen la pendiente sin bordes
  · reparación de accesos: si un borde o un árbol deja aislada una zona, se abre una escalera

Todo es opcional: sin cartography/derived/* el importador se comporta como antes.
"""
import gzip
import json
import os

import numpy as np
from scipy import ndimage

import semantic as sem
from semantic import G, D

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
DER = os.path.join(ROOT, 'cartography/derived')
LEVEL_STEP_M = 8.0   # metros por nivel de terreno
NATURAL = [G[k] for k in ('DRY', 'GRASS', 'SCRUB', 'FOREST')]
LEDGE_GROUND = NATURAL + [G[k] for k in ('FARM', 'VINEYARD', 'ROCK', 'QUARRY', 'WETLAND')]


def load():
    t = os.path.join(DER, 'terrain.npz')
    c = os.path.join(DER, 'catastro.json.gz')
    if not (os.path.exists(t) and os.path.exists(c)):
        return None
    z = np.load(t)
    with gzip.open(c, 'rt') as f:
        cat = json.load(f)
    return {'elev': z['elev'].astype(np.float32), 'rgb': z['rgb'], 'canopy': z['canopy'] / 255.0,
            'green': z['green'] / 255.0, 'cat': cat}


def neutral(h, w):
    """Sense ortofoto ni relleu (un lloc fora d'Espanya, o sense descarregar): valors neutres perquè la
    decoració (escoles, pistes, parcs, arbres) segueixi funcionant amb el que diu l'OSM."""
    rgb = np.empty((h, w, 3), np.uint8)
    rgb[:] = (118, 124, 96)
    return {'elev': np.zeros((h, w), np.float32), 'rgb': rgb, 'canopy': np.full((h, w), 0.15, np.float32),
            'green': np.full((h, w), 0.35, np.float32), 'cat': {'buildings': [], 'pools': []}, 'neutral': True}


# ------------------------------------------------------------------ suelo
def ground_from_satellite(rd, ground):
    """Terreno natural y jardines según el verdor real (suavizado para evitar ruido)."""
    can = ndimage.uniform_filter(rd['canopy'], 7)
    grn = ndimage.uniform_filter(rd['green'], 7)
    nat = np.isin(ground, NATURAL)
    new = np.full(ground.shape, G['DRY'], ground.dtype)
    new[grn > 0.35] = G['GRASS']
    new[(can > 0.18) & (grn > 0.3)] = G['SCRUB']
    new[can > 0.42] = G['FOREST']
    changed = nat & (new != ground)
    ground[nat] = new[nat]
    gardens = (ground == G['URBAN']) & (grn > 0.5)
    ground[gardens] = G['PARK']   # jardines: césped urbano (sin bordes de roca)
    return int(changed.sum()), int(gardens.sum())


# ------------------------------------------------------------------ puerto
def marina(rd, ground, d0, mask, sea_code, pier_code):
    """Puerto deportivo con la ortofoto: dársena (agua, también donde hay barcos amarrados), muelles
    anchos de hormigón (paviment), pantalanes de madera de una casilla (esqueleto de las franjas
    finas, unidos al muelle) y escollera de rocas en la cara del dique que da al mar abierto.
    Sin ortofoto, todo el polígono sería muelle y el puerto quedaría seco."""
    from skimage.morphology import skeletonize
    rgb = rd['rgb'].astype(np.float32)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    lum = rgb.mean(-1)
    water = mask & (b > r + 8) & (lum < 150)
    # barcos (blancos) amarrados: agua si buena parte del entorno es agua
    near = ndimage.uniform_filter(water.astype(np.float32), 5)
    water |= mask & (lum > 165) & (near > 0.35)
    water = ndimage.binary_opening(water, iterations=1) | (water & (near > 0.6))
    land = mask & ~water
    # muelles: tierra a 3+ casillas del agua, recrecida 2 (los pantalanes son franjas de 1-2)
    dist = ndimage.distance_transform_edt(land | ~mask)
    quay = ndimage.binary_dilation(land & (dist >= 3), iterations=2) & land
    lab, n = ndimage.label(quay)
    sizes = ndimage.sum(quay, lab, range(1, n + 1))
    quay &= np.isin(lab, 1 + np.nonzero(sizes >= 12)[0])    # islotes sueltos: agua
    thin = land & ~quay
    piers = skeletonize(thin)
    # 4-conexo para poder caminar: rellenar los pasos en diagonal
    ys, xs = np.nonzero(piers)
    for y, x in zip(ys, xs):
        for dy, dx in ((1, 1), (1, -1)):
            yy, xx = y + dy, x + dx
            if 0 <= yy < piers.shape[0] and 0 <= xx < piers.shape[1] and piers[yy, xx] \
                    and not piers[y, xx] and not piers[yy, x]:
                piers[y, xx] = True
    # cada pantalán, unido al muelle por el camino más corto dentro del puerto (si está a <= 8)
    lab, n = ndimage.label(piers)
    dq = ndimage.distance_transform_edt(~quay)
    keep = np.zeros_like(piers)
    for i in range(1, n + 1):
        comp = lab == i
        if comp.sum() < 3 or dq[comp].max() < 4:   # flecos pegados al muelle: no son pantalanes
            continue
        sl = ndimage.find_objects(comp.astype(np.int32))[0]
        y0, y1 = max(0, sl[0].start - 10), sl[0].stop + 10
        x0, x1 = max(0, sl[1].start - 10), sl[1].stop + 10
        cm, qm, mm = comp[y0:y1, x0:x1], quay[y0:y1, x0:x1], mask[y0:y1, x0:x1]
        prev = {(y, x): None for y, x in zip(*np.nonzero(cm))}
        frontier, hit = list(prev), None
        for _ in range(9):
            nxt = []
            for y, x in frontier:
                if qm[y, x]:
                    hit = (y, x); break
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    p = (y + dy, x + dx)
                    if 0 <= p[0] < cm.shape[0] and 0 <= p[1] < cm.shape[1] and mm[p] and p not in prev:
                        prev[p] = (y, x); nxt.append(p)
            if hit:
                break
            frontier = nxt
        if hit is None:
            continue
        keep[y0:y1, x0:x1] |= cm
        p = prev[hit]
        while p is not None and not cm[p]:
            keep[y0 + p[0], x0 + p[1]] = True
            p = prev[p]
    piers = keep & mask & ~quay
    quay |= thin & ~piers & (dq <= 2)   # borde del muelle que la ortofoto ve fino
    water = mask & ~quay & ~piers
    # agua o pantalán encerrados por el muelle (sin salida al mar abierto): muelle
    wet = water | piers | ((ground == sea_code) & ~mask)
    lab, _ = ndimage.label(wet)
    open_ids = set(np.unique(lab[(ground == sea_code) & ~mask])) - {0}
    pocket = (water | piers) & ~np.isin(lab, list(open_ids))
    quay |= pocket
    water &= ~pocket
    piers &= ~pocket
    # escollera: muelle a <= 2 casillas del mar abierto (fuera del puerto)
    open_sea = (ground == sea_code) & ~mask
    rocks = quay & (ndimage.distance_transform_edt(~open_sea) <= 2.5) & (d0 == 0)
    ground[water | piers] = sea_code
    d0[water] = 0
    d0[piers & (d0 == 0)] = pier_code
    ground[quay] = G['URBAN']
    ground[rocks] = G['ROCK']
    d0[quay & ~rocks & (d0 == 0)] = D['PEDESTRIAN']
    return int(water.sum()), int(quay.sum()), int(piers.sum()), int(rocks.sum())


# ------------------------------------------------------------------ edificios
USE_KIND = {'3_industrial': 'industrial', '4_1_office': 'commercial', '4_2_retail': 'retail',
            '4_3_publicServices': 'public', '2_agriculture': 'farm'}


def catastro_buildings(rd, bld, binfo, ground, d0, d1, dm1):
    # ni sobre vías ni sobre las bocas de pasos inferiores (con margen de 4 celdas)
    blocked = (d0 > 0) | (d1 > 0) | np.isin(ground, [G['SEA'], G['VOID']]) | ndimage.binary_dilation(dm1 > 0, iterations=4)
    n_add = n_dup = 0
    for b in rd['cat']['buildings']:
        if len(b['outer']) < 3:
            continue
        loc = sem.local_cells([[tuple(p) for p in b['outer']]], 'poly', 1, 0.45,
                              holes=[[tuple(p) for p in h] for h in b.get('holes', [])])
        if loc is None:
            continue
        y0, x0, m = loc
        if m.sum() < 2:
            continue
        sub_b = bld[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
        if (sub_b[m] > 0).mean() > 0.5:
            n_dup += 1
            continue
        free = m & (sub_b == 0) & ~blocked[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
        if free.sum() < 2:
            continue
        rgb = rd['rgb'][y0:y0 + m.shape[0], x0:x0 + m.shape[1]][free].mean(axis=0)
        floors = b.get('floors') or 1
        kind = USE_KIND.get(b.get('use'), 'apartments' if floors >= 3 else 'house')
        idx = len(binfo)
        binfo.append({'src': 'catastro', 'kind': kind, 'name': None, 'amenity': None, 'generated': False,
                      'floors': floors, 'rgb': [float(v) for v in rgb]})
        sub_b[free] = idx
        n_add += 1
    return n_add, n_dup


def merge_rows(bld, binfo, skip=None, max_cells=12, max_block=60):
    """Casas adosadas del catastro (parcelas pequeñas que se tocan): una sola hilera con una puerta y un
    color por casa (buildings.dress con info['walls']). Sueltas, al enderezarlas se perdían casi todas.
    skip: máscara donde no se une (cascos antiguos, que ya lo hacen con nuclis.merge_blocks)."""
    small = np.zeros(len(binfo), bool)
    for i, info in enumerate(binfo):
        if info and info.get('src') == 'catastro' and info.get('kind') in ('house', 'apartments') \
                and (info.get('floors') or 1) <= 3:
            small[i] = True
    ids, counts = np.unique(bld[bld > 0], return_counts=True)
    small[ids[counts > max_cells]] = False
    cand = small[bld] & (bld > 0)
    if skip is not None:
        cand &= ~skip
    lab, n = ndimage.label(cand)
    merged = 0
    for k, sl in enumerate(ndimage.find_objects(lab), 1):
        if sl is None:
            continue
        cells = lab[sl] == k
        members = np.unique(bld[sl][cells])
        if len(members) < 2 or cells.sum() > max_block:
            continue
        main = int(members[0])
        info = binfo[main]
        info['kind'] = 'house'
        info['floors'] = max(int(binfo[i].get('floors') or 1) for i in members)
        info['walls'] = ['white', 'white', 'ochre', 'sand', 'stone', 'salmon', 'sky']
        info['row_houses'] = int(len(members))
        bld[sl][cells] = main
        merged += len(members) - 1
    return merged


def pools(rd, ground, bld, d0):
    n = 0
    for p in rd['cat']['pools']:
        loc = sem.local_cells([[tuple(q) for q in p['outer']]], 'poly', 1, 0.3)
        if loc is None:
            continue
        y0, x0, m = loc
        sl = (slice(y0, y0 + m.shape[0]), slice(x0, x0 + m.shape[1]))
        ok = m & (bld[sl] == 0) & (d0[sl] == 0) & ~np.isin(ground[sl], [G['SEA'], G['VOID']])
        if ok.any():
            ground[sl][ok] = G['WATER']
            n += 1
    return n


# ------------------------------------------------------------------ árboles
def trees_from_satellite(rd, ground, occupied, near_occ, rng):
    """1/2 pino, 3 palmera, 4 olivo, 5/6 arbusto, donde la ortofoto muestra copas."""
    H, W = ground.shape
    can = rd['canopy']
    trees = np.zeros((H, W), np.uint8)
    taken = np.zeros((H, W), bool)
    ok = ~occupied & ~near_occ & ~np.isin(ground, [G['SEA'], G['WATER'], G['BEACH'], G['VOID'], G['PITCH'],
                                                     G['RAILYARD']])
    ok[0, :] = False
    ys, xs = np.nonzero(ok & (can >= 0.3))
    order = np.argsort(-can[ys, xs], kind='stable')
    urban = {G['URBAN'], G['PARK'], G['CEMETERY'], G['GRASS']}
    for k in order:
        y, x = int(ys[k]), int(xs[k])
        if taken[max(0, y - 1):y + 2, max(0, x - 1):x + 2].any():
            continue
        c, g = can[y, x], ground[y, x]
        if c < 0.5:
            if g in (G['SCRUB'], G['DRY'], G['FOREST']) and rng.random() < 0.3:
                trees[y, x] = 5 + (rng.random() < .5)
                taken[y, x] = True
            continue
        if occupied[y - 1, x]:
            continue
        p = 0.8 if g in urban else 0.55
        if rng.random() >= p:
            continue
        if g in (G['FARM'], G['VINEYARD']):
            trees[y, x] = 4
        elif g in (G['URBAN'], G['PARK']) and rng.random() < .35:
            trees[y, x] = 3
        else:
            trees[y, x] = 1 + (rng.random() < .35)
        taken[y, x] = True
    return trees


# ------------------------------------------------------------------ relieve
def terrain_levels(rd):
    e = ndimage.uniform_filter(rd['elev'], 5)
    return np.floor(e / LEVEL_STEP_M).astype(np.int16)


def ledges(level, ground, free):
    """Máscara (bits N=1 E=2 S=4 W=8 del vecino más bajo) de las celdas con borde de roca.
    `free`: celdas donde puede ir un borde (terreno natural sin vías, edificios ni objetos)."""
    H, W = level.shape
    mask = np.zeros((H, W), np.uint8)
    pad = np.pad(level, 1, mode='edge')
    for bit, (dy, dx) in ((1, (-1, 0)), (2, (0, 1)), (4, (1, 0)), (8, (0, -1))):
        nb = pad[1 + dy:1 + dy + H, 1 + dx:1 + dx + W]
        mask[nb < level] |= bit
    mask[~(free & np.isin(ground, LEDGE_GROUND))] = 0
    return mask


def near_town(bld, ground, r=3):
    """Cerca de casas o en suelo urbano no hay bordes de roca (las parcelas ya están niveladas)."""
    town = (bld > 0) | np.isin(ground, [G['URBAN'], G['PARK'], G['PITCH'], G['CEMETERY'], G['RAILYARD']])
    return ndimage.binary_dilation(town, iterations=r)


# ------------------------------------------------------------------ accesos
def repair_access(coll, L, tid, ledge, trees, keep_cells, start, walkgraph, WALK, max_iter=60):
    """Abre escaleras en bordes (o quita árboles) hasta que toda zona transitable grande o con
    contenido conecte con la principal. Devuelve (escaleras abiertas, árboles quitados, zonas aisladas)."""
    H, W = coll.shape
    opened = removed = 0
    stairs_v, stairs_h = tid('st_stone_v'), tid('st_stone_h')
    for _ in range(max_iter):
        lab = walkgraph.components_fast(coll)[0]
        main = lab[start[1], start[0]]
        sizes = np.bincount(lab.ravel())
        important = np.zeros(sizes.shape, bool)
        important[np.unique(lab[keep_cells[:, 1], keep_cells[:, 0]])] = True
        important |= sizes >= 40
        important[0] = False
        important[main] = False
        if not important.any():
            break
        cand = (ledge > 0) | (trees > 0)
        pad = np.pad(lab, 1)
        nbs = [pad[0:H, 1:W + 1], pad[2:H + 2, 1:W + 1], pad[1:H + 1, 0:W], pad[1:H + 1, 2:W + 2]]
        changed = 0
        done = set()
        imp_nb = np.zeros((H, W), bool)
        multi = np.zeros((H, W), bool)
        for i, a in enumerate(nbs):
            imp_nb |= important[a]
            for b in nbs[i + 1:]:
                multi |= (a != b) & (a > 0) & (b > 0)
        ys, xs = np.nonzero(cand & imp_nb & multi)
        # primero los que unen con la principal
        for prefer_main in (True, False):
            for y, x in zip(ys, xs):
                ls = {int(n[y, x]) for n in nbs} - {0}
                bad = [l_ for l_ in ls if important[l_] and l_ not in done]
                if not bad or len(ls) < 2:
                    continue
                if prefer_main and main not in ls:
                    continue
                if ledge[y, x]:
                    m = ledge[y, x]
                    L['structures'][y, x] = stairs_h if (m & 10) and not (m & 5) else stairs_v
                    ledge[y, x] = 0
                    opened += 1
                else:
                    L['structures'][y, x] = 0
                    if y > 0:
                        L['overhead'][y - 1, x] = 0
                    trees[y, x] = 0
                    removed += 1
                coll[y, x] = (int(coll[y, x]) & 0xFC) | WALK
                done.update(bad)
                changed += 1
        if not changed:
            break
    lab = walkgraph.components_fast(coll)[0]
    main = lab[start[1], start[0]]
    isolated = [int(l_) for l_ in np.unique(lab[keep_cells[:, 1], keep_cells[:, 0]]) if l_ and l_ != main]
    return opened, removed, isolated
