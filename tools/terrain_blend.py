"""Transiciones suaves de terreno (Wang por esquinas) y sombras suaves, sobre el mapa decorado.

  · blend(m): cada vértice de la rejilla toma el terreno mayoritario de sus 4 celdas; cada celda se
    dibuja según sus 4 esquinas con los tiles tw_<A>_<B>_<c> de make_tiles.py (mezcla con dithering).
    Solo terrenos naturales/urbanos con tiles de transición; el mar, las piscinas, los suelos especiales
    (aparcamientos, adoquines, parterres…) y los bordes con ellos se quedan como estaban.
  · shadows(m): sombras en la capa ground_detail (se ven también sobre el asfalto vectorial): al este
    de los edificios, bajo la fachada desplazada a la derecha y elipse bajo cada árbol.
  · wangsets(tiles): los mismos conjuntos como Wang sets de Tiled (tipo «corner») para tiles.tsj.
Lo llama tools/decorate_map.py; tools/sat_pipeline.py lo reutiliza para exportar .tmx.
"""
import re

import numpy as np

PRIORITY = ['urban', 'park', 'grass', 'forest', 'scrub', 'farm', 'vineyard', 'dry', 'rock', 'beach', 'railyard']


def pairs(tiles):
    out = set()
    for n in tiles:
        mm = re.match(r'tw_([a-z]+)_([a-z]+)_\d+$', n)
        if mm:
            out.add((mm.group(1), mm.group(2)))
    return out


def terrains(tiles):
    ps = pairs(tiles)
    fams = sorted({f for p in ps for f in p}, key=lambda f: PRIORITY.index(f) if f in PRIORITY else 99)
    return fams, ps


def classify(ground, name_of, fams):
    """gid del suelo → índice de terreno (o -1)."""
    lut = {}
    for gid in np.unique(ground):
        n = name_of.get(int(gid) & 0x1FFFFFFF, '')
        mm = re.match(r'g_([a-z]+)_\d+$', n)
        lut[int(gid)] = fams.index(mm.group(1)) if mm and mm.group(1) in fams else -1
    keys = np.array(list(lut.keys()), np.int64)
    vals = np.array([lut[k] for k in keys], np.int16)
    order = np.argsort(keys)
    return vals[order][np.searchsorted(keys[order], ground)]


def vertices(T, nfam):
    """(H+1)×(W+1) terreno por vértice: mayoría de las 4 celdas; -1 si alguna no es mezclable."""
    H, W = T.shape
    P = np.full((H + 2, W + 2), -2, np.int16)
    P[1:-1, 1:-1] = T
    quad = [P[:-1, :-1], P[:-1, 1:], P[1:, :-1], P[1:, 1:]]
    best = np.full((H + 1, W + 1), -1, np.int16)
    bestc = np.zeros((H + 1, W + 1), np.int8)
    for k in range(nfam - 1, -1, -1):  # empate → gana el de más prioridad (índice menor, va al final)
        cnt = sum((q == k).astype(np.int8) for q in quad)
        upd = cnt >= bestc
        best[upd & (cnt > 0)] = k
        bestc = np.maximum(bestc, cnt)
    bad = sum((q == -1).astype(np.int8) for q in quad) > 0
    best[bad] = -1
    return best


def blend(m, rng_seed=11):
    fams, ps = terrains(m.tiles)
    if not fams:
        return {'blended': 0}
    G = m.L['ground']
    T = classify(G, m.name_of, fams)
    V = vertices(T, len(fams))
    H, W = T.shape
    nw, ne, se, sw = V[:-1, :-1], V[:-1, 1:], V[1:, 1:], V[1:, :-1]
    rng = np.random.default_rng(rng_seed)
    var = rng.integers(0, 3, size=(H, W))
    out = G.copy()
    changed = 0
    corners = np.stack([nw, ne, se, sw])
    valid = (corners >= 0).all(0) & (T >= 0) & ~((corners == T[None]).all(0))
    ys, xs = np.nonzero(valid)
    cache = {}
    for y, x in zip(ys, xs):
        cs = corners[:, y, x]
        u = set(int(v) for v in cs)
        if len(u) == 1:
            k = cs[0]
            if k == T[y, x]:
                continue  # sin cambios: conserva su variante
            name = f'g_{fams[k]}_{var[y, x]}'
        elif len(u) == 2:
            a, b = sorted(u)
            A, B = fams[a], fams[b]
            if (A, B) in ps:
                c = sum(1 << i for i in range(4) if cs[i] == b)
                name = f'tw_{A}_{B}_{c}'
            elif (B, A) in ps:
                c = sum(1 << i for i in range(4) if cs[i] == a)
                name = f'tw_{B}_{A}_{c}'
            else:
                continue
        else:
            continue
        gid = cache.get(name)
        if gid is None:
            gid = cache[name] = m.gid(name)
        out[y, x] = gid
        changed += 1
    m.L['ground'] = out
    return {'blended': changed}


def shadows(m):
    S, GD, OV = m.L['structures'], m.L['ground_detail'], m.L['ground']
    H, W = S.shape
    names = {int(g): m.name_of.get(int(g) & 0x1FFFFFFF, '') for g in np.unique(S)}
    bld = np.vectorize(lambda g: names[int(g)].startswith(('r_', 'f_')), otypes=[bool])(S)
    tree = np.vectorize(lambda g: names[int(g)].startswith('tree_') and names[int(g)].endswith('_bot'),
                        otypes=[bool])(S)
    gnames = {int(g): m.name_of.get(int(g) & 0x1FFFFFFF, '') for g in np.unique(OV)}
    water = np.vectorize(lambda g: gnames[int(g)].startswith(('sea_', 'pool_')), otypes=[bool])(OV)
    free = (GD == 0) & ~bld & ~water
    n = {'sh_e': 0, 'sh_s': 0, 'sh_se': 0, 'sh_tree': 0}
    g = {k: m.gid(k) for k in ('sh_e', 'sh_e_top', 'sh_s', 'sh_se', 'sh_tree')}
    # este del edificio
    e = np.zeros((H, W), bool)
    e[:, 1:] = bld[:, :-1]
    top = np.zeros((H, W), bool)
    top[1:, 1:] = ~bld[:-1, :-1]
    top[0, :] = True
    m_e = e & free
    GD[m_e & top] = g['sh_e_top']
    GD[m_e & ~top] = g['sh_e']
    n['sh_e'] = int(m_e.sum())
    # bajo la fachada (desplazada a la derecha): celdas al sur de una fachada, y la esquina sureste
    s = np.zeros((H, W), bool)
    s[1:, :] = bld[:-1, :]
    m_s = s & (GD == 0) & ~bld & ~water
    GD[m_s] = g['sh_s']
    n['sh_s'] = int(m_s.sum())
    se_ = np.zeros((H, W), bool)
    se_[1:, 1:] = bld[:-1, :-1]
    m_se = se_ & (GD == 0) & ~bld & ~water
    GD[m_se] = g['sh_se']
    n['sh_se'] = int(m_se.sum())
    m_t = tree & (GD == 0) & ~water
    GD[m_t] = g['sh_tree']
    n['sh_tree'] = int(m_t.sum())
    return n


def wangsets(tiles):
    """Wang sets de Tiled (corner) con los tiles g_* y tw_*: un conjunto por terreno."""
    fams, ps = terrains(tiles)
    colors = ['#d9c690', '#88a457', '#5f7d40', '#bfa970', '#9a8555', '#c4914a', '#a38f74', '#7a6853',
              '#f1e0aa', '#58565d', '#3e5a34', '#e6bd6b']
    wcolors = [{'name': f, 'color': colors[i % len(colors)], 'probability': 1, 'tile': tiles[f'g_{f}_0']['id']}
               for i, f in enumerate(fams)]
    wt = []
    for f in fams:
        for v in range(3):
            n = f'g_{f}_{v}'
            if n in tiles:
                k = fams.index(f) + 1
                wt.append({'tileid': tiles[n]['id'], 'wangid': [0, k, 0, k, 0, k, 0, k]})
    for A, B in ps:
        a, b = fams.index(A) + 1, fams.index(B) + 1
        for c in range(1, 15):
            n = f'tw_{A}_{B}_{c}'
            if n not in tiles:
                continue
            nw, ne, se, sw = [(b if (c >> i) & 1 else a) for i in range(4)]
            # orden de Tiled: top, top-right, right, bottom-right, bottom, bottom-left, left, top-left
            wt.append({'tileid': tiles[n]['id'], 'wangid': [0, ne, 0, se, 0, sw, 0, nw]})
    return [{'name': 'Terreny', 'type': 'corner', 'tile': -1, 'colors': wcolors, 'wangtiles': wt}]
