"""Edificios del mapa: enderezado de huellas y vestido (tejado, cumbrera, fachadas por tipo de edificio).

Enderezar: las huellas del Catastro/OSM vienen giradas respecto a la rejilla (calles en diagonal) y al
rasterizarlas salen en escalera, con un trozo de fachada en cada peldaño. Para cada edificio se busca el
giro (−45°…45°) que mejor lo encaja en un rectángulo; se gira la huella ese ángulo alrededor de su centro
(conserva posición y superficie) y, si ya es casi un rectángulo, se sustituye por uno de la misma área.
Así las casas quedan rectas, con una sola fachada continua, como en los RPG clásicos.

Vestir: según el uso (Catastro) y las plantas:
  casa (tejado del color real de la ortofoto, cumbrera, puerta, garaje, balconeras)
  bloque de pisos (azotea con depósitos/placas, plantas altas con balcones, bajos con tiendas)
  comercio (toldos de colores), nave industrial (cubierta metálica, persianas), equipamiento público
  (ventanas de arco), masía (piedra y teja) e invernadero (cubierta de vidrio).
"""
import math

import numpy as np
from scipy import ndimage

from pixel import rng_for

N, E, S, Wb = 1, 2, 4, 8
PITCHED = ('terra', 'brown', 'slate', 'stone')
ANGLES = np.radians(np.arange(-45, 46, 3))
RECT_FILL = 0.74      # encaje mínimo para sustituir la huella por un rectángulo


def best_angle(xs, ys):
    """Ángulo (rad) que minimiza el rectángulo envolvente de los centros de celda."""
    px, py = xs + .5 - xs.mean() - .5, ys + .5 - ys.mean() - .5
    best, ba = -1.0, 0.0
    for a in ANGLES:
        ca, sa = math.cos(a), math.sin(a)
        qx, qy = px * ca + py * sa, -px * sa + py * ca
        fill = len(xs) / ((np.ptp(qx) + 1) * (np.ptp(qy) + 1)) - abs(a) * 0.01   # empate → sin girar
        if fill > best:
            best, ba = fill, a
    return ba


def straight_cells(xs, ys, a):
    """Celdas del edificio enderezado: rectángulo de igual área o huella girada (formas en L, patios)."""
    n = len(xs)
    cx, cy = xs.mean() + .5, ys.mean() + .5
    ca, sa = math.cos(a), math.sin(a)
    px, py = xs + .5 - cx, ys + .5 - cy
    qx, qy = px * ca + py * sa, -px * sa + py * ca
    w, h = np.ptp(qx) + 1, np.ptp(qy) + 1
    if n / (w * h) >= RECT_FILL:
        k = math.sqrt(n / (w * h))
        rw, rh = max(2, int(round(w * k))), max(2, int(round(h * k)))
        x0, y0 = int(round(cx - rw / 2)), int(round(cy - rh / 2))
        yy, xx = np.mgrid[y0:y0 + rh, x0:x0 + rw]
        return xx.ravel(), yy.ravel(), True
    # forma compleja: giro por vecino más próximo (muestreo inverso) y limpieza
    src = set(zip(xs.tolist(), ys.tolist()))
    r = int(math.ceil(max(w, h))) + 2
    out = []
    for ty in range(int(cy) - r, int(cy) + r + 1):
        for tx in range(int(cx) - r, int(cx) + r + 1):
            dx, dy = tx + .5 - cx, ty + .5 - cy
            sx, sy = dx * ca - dy * sa + cx, dx * sa + dy * ca + cy
            if (int(math.floor(sx)), int(math.floor(sy))) in src:
                out.append((tx, ty))
    if not out:
        return xs, ys, False
    ox, oy = np.array(out).T
    x0, y0 = ox.min(), oy.min()
    m = np.zeros((oy.max() - y0 + 1, ox.max() - x0 + 1), bool)
    m[oy - y0, ox - x0] = True
    m = ndimage.binary_fill_holes(m)
    m = ndimage.binary_opening(m, np.ones((2, 2))) | (m & ndimage.binary_erosion(m))
    yy, xx = np.nonzero(m)
    return xx + x0, yy + y0, False


def largest_rect(m):
    """Mayor rectángulo de True en una máscara 2D (histograma por filas). Devuelve (y0, x0, h, w)."""
    H, W = m.shape
    hist = np.zeros(W, int)
    best = (0, 0, 0, 0, 0)
    for y in range(H):
        hist = np.where(m[y], hist + 1, 0)
        stack = []
        for x in range(W + 1):
            hgt = hist[x] if x < W else 0
            start = x
            while stack and stack[-1][1] >= hgt:
                s0, sh = stack.pop()
                area = sh * (x - s0)
                if area > best[0] and sh >= 2 and x - s0 >= 2:
                    best = (area, y - sh + 1, s0, sh, x - s0)
                start = s0
            stack.append((start, hgt))
    return best[1:] if best[0] else None


def straighten(bld, blocked, min_cells=3):
    """Endereza todos los edificios de `bld` (índices > 0). blocked: celdas donde no puede haber
    edificio (vías, puentes, mar). Devuelve el nuevo array y estadísticas."""
    H, W = bld.shape
    out = np.zeros_like(bld)
    objs = ndimage.find_objects(bld)
    sizes = [(0 if sl is None else int((bld[sl] == i + 1).sum()), i + 1) for i, sl in enumerate(objs)]
    stats = {'rect': 0, 'rotated': 0, 'kept': 0, 'dropped': 0, 'turned': 0}
    for n, b in sorted(sizes, reverse=True):
        if n == 0:
            continue
        sl = objs[b - 1]
        ys, xs = np.nonzero(bld[sl] == b)
        ys, xs = ys + sl[0].start, xs + sl[1].start
        if n < min_cells:
            stats['dropped'] += 1
            continue
        a = best_angle(xs, ys)
        if abs(a) > 1e-6:
            stats['turned'] += 1
        nx, ny, is_rect = straight_cells(xs, ys, a)
        ok = (nx >= 0) & (ny >= 0) & (nx < W) & (ny < H)
        nx, ny = nx[ok], ny[ok]
        free = ~blocked[ny, nx] & (out[ny, nx] == 0)
        if free.all() and len(nx) >= min_cells:
            out[ny, nx] = b
            stats['rect' if is_rect else 'rotated'] += 1
            continue
        if is_rect and len(nx):
            # recortado por una calle o un vecino: el mayor rectángulo libre dentro del objetivo
            x0, y0 = nx.min(), ny.min()
            m = np.zeros((ny.max() - y0 + 1, nx.max() - x0 + 1), bool)
            m[ny[free] - y0, nx[free] - x0] = True
            r = largest_rect(m)
            if r and r[2] * r[3] >= max(min_cells, int(.45 * n)):
                ry, rx, rh, rw = r
                out[y0 + ry:y0 + ry + rh, x0 + rx:x0 + rx + rw] = b
                stats['rect'] += 1
                continue
        # sin hueco para la forma recta: se conserva la huella original donde está libre
        keep = ~blocked[ys, xs] & (out[ys, xs] == 0)
        if keep.sum() >= min_cells:
            out[ys[keep], xs[keep]] = b
            stats['kept'] += 1
        else:
            stats['dropped'] += 1
    clean_thin(out, stats, min_cells)
    return out, stats


def clean_thin(out, stats=None, min_cells=3):
    """Sin tiras de 1 casilla de ancho (no caben tejado y fachada legibles) ni restos diminutos.
    Modifica `out` en su sitio; se usa al enderezar y otra vez tras colocar hitos y accesos."""
    stats = stats if stats is not None else {}
    for _ in range(2):
        same_l = np.zeros_like(out, bool); same_r = np.zeros_like(out, bool)
        same_l[:, 1:] = out[:, 1:] == out[:, :-1]
        same_r[:, :-1] = out[:, :-1] == out[:, 1:]
        thin = (out > 0) & ~same_l & ~same_r
        stats['thin_cells'] = stats.get('thin_cells', 0) + int(thin.sum())
        out[thin] = 0
    ids, counts = np.unique(out[out > 0], return_counts=True)
    tiny = ids[counts < min_cells]
    if len(tiny):
        out[np.isin(out, tiny)] = 0
        stats['dropped'] = stats.get('dropped', 0) + len(tiny)
    return stats


# ------------------------------------------------------------------ estilo por tipo
def roof_from_rgb(rgb):
    r, g, b = rgb
    lum = (r + g + b) / 3
    if r > g + 8 and r > b + 30 and r > 110:
        return 'terra'
    if r > b + 15 and lum < 125:
        return 'brown'
    if lum < 100 and max(r, g, b) - min(r, g, b) < 18:
        return 'slate'
    return 'flat'


HOUSE_WALLS = ['white', 'white', 'white', 'ochre', 'ochre', 'stone', 'sand', 'sand', 'salmon', 'sky']
FLAT_WALLS = ['white', 'white', 'sand', 'ochre', 'salmon', 'sky']


def style(info, idx, cells):
    """Decide clase, tejado y pared del edificio (se guarda en info)."""
    rng = rng_for('b', idx)
    kind = info.get('kind') or 'yes'
    floors = info.get('floors') or 0
    rgb = info.get('rgb')
    sat_roof = roof_from_rgb(rgb) if rgb else None
    if kind in ('church', 'chapel', 'castle', 'ruins') or info.get('amenity') == 'place_of_worship':
        cls, rk, wc = 'civic', 'stone', 'stone'
    elif info.get('nucli') and kind not in ('industrial', 'warehouse', 'school', 'townhall', 'public', 'civic',
                                            'government', 'hotel', 'kindergarten', 'train_station', 'sports_hall'):
        # casco antiguo (tools/nuclis.py): casas en hilera con teja y la paleta de las fotos de calle;
        # el color por tramo de fachada lo pone dress()
        cls = 'house'
        rk = sat_roof if sat_roof in ('terra', 'brown') else info.get('nucli_roof', 'terra')
        wc = rng.choice(info['walls'])
    elif kind in ('industrial', 'warehouse', 'manufacture', 'factory', 'garages'):
        cls, rk, wc = 'industrial', 'metal', rng.choice(['metal', 'metal', 'brick', 'white'])
    elif kind == 'sports_hall':      # pavelló: coberta metàl·lica clara
        cls, rk, wc = 'civic', 'metal', 'white'
    elif kind in ('retail', 'commercial', 'supermarket', 'kiosk') or (kind == 'yes' and info.get('shop')):
        cls, rk, wc = 'retail', 'flat', rng.choice(['white', 'sand', 'ochre', 'white'])
    elif kind in ('school', 'public', 'hospital', 'civic', 'government', 'townhall', 'hotel', 'university',
                  'kindergarten', 'train_station', 'sports_hall'):
        cls = 'civic'
        rk = 'terra' if sat_roof == 'terra' else 'flat'
        wc = rng.choice(['ochre', 'stone', 'sand', 'white'])
    elif kind in ('farm', 'barn', 'farm_auxiliary', 'greenhouse', 'stable'):
        if kind == 'greenhouse' or (sat_roof == 'flat' and cells >= 40):
            cls, rk, wc = 'greenhouse', 'glass', 'glass'
        else:
            cls, rk, wc = 'farm', sat_roof if sat_roof in ('terra', 'brown') else 'terra', rng.choice(['stone', 'ochre', 'stone'])
    elif kind == 'apartments' or floors >= 3:
        cls = 'apartments'
        rk = 'flat' if sat_roof in (None, 'flat') or rng.random() < .7 else sat_roof
        wc = rng.choice(FLAT_WALLS)
    else:
        cls = 'house'
        rk = sat_roof or ('terra' if rng.random() < .72 else 'flat')
        wc = rng.choice(HOUSE_WALLS)
    info.update(cls=cls, roof=rk, wall=wc, floors=floors or (3 if cls == 'apartments' else 1))
    return info


def nmask(same, y, x, H, W):
    m = 0
    for dx, dy, bit in ((0, -1, N), (1, 0, E), (0, 1, S), (-1, 0, Wb)):
        yy, xx = y + dy, x + dx
        if not (0 <= yy < H and 0 <= xx < W) or same(yy, xx):
            m |= bit
    return m


def dress(bld, binfo, tid, front_walk_fn, pedestrian_fn):
    """Tiles de estructura para todos los edificios. front_walk_fn(y, x): ¿se puede pisar (y, x)?;
    pedestrian_fn(y, x): ¿es calle peatonal/acera? Devuelve {(y, x): gid} y estadísticas."""
    H, W = bld.shape
    out = {}
    stats = {}
    objs = ndimage.find_objects(bld)
    for b, sl in enumerate(objs, 1):
        if sl is None:
            continue
        sub = bld[sl] == b
        if not sub.any():
            continue
        info = binfo[b]
        style(info, b, int(sub.sum()))
        cls = info['cls']
        stats[cls] = stats.get(cls, 0) + 1
        y0, x0 = sl[0].start, sl[1].start
        rng = rng_for('dress', b)
        shops = rng.choice(['shop', 'shop2', 'shop3'])
        ys, xs = np.nonzero(sub)
        cols = {}
        for y, x in zip(ys + y0, xs + x0):
            cols.setdefault(x, []).append(y)
        bh = sl[0].stop - sl[0].start
        upper = 0
        if cls in ('apartments', 'retail', 'civic') and bh >= 4:
            upper = max(0, min(info['floors'] - 1, bh - 3, 2))
        elif cls == 'house' and info['floors'] >= 2 and bh >= 5:
            upper = 1
        # casco antiguo: tramos de 2-3 casillas = casas distintas, cada una con su color y su puerta
        seg_of = None
        if info.get('walls') and cls == 'house':
            xs_all = sorted(cols)
            seg_of, k, x = {}, 0, xs_all[0]
            srng = rng_for('seg', b)
            while x <= xs_all[-1]:
                wdt = 2 if srng.random() < .5 else 3
                for xx in range(x, x + wdt):
                    seg_of[xx] = k
                x += wdt
                k += 1
            seg_wall = {i: rng_for('segw', b, i).choice(info['walls']) for i in range(k)}
        facade = {}   # (y, x) -> fila (0 = planta baja, 1.. = altas)
        for x, yl in cols.items():
            yl = sorted(yl)
            bottom = [y for y in yl if y + 1 >= H or bld[y + 1, x] != b]
            for yb in bottom:
                facade[(yb, x)] = 0
                for u in range(1, upper + 1):
                    if yb - u - 1 >= 0 and bld[yb - u, x] == b and bld[yb - u - 1, x] == b:
                        facade[(yb - u, x)] = u
        # planta baja: puerta (y garaje, tiendas…) según la clase
        ground_cells = sorted([k for k, u in facade.items() if u == 0], key=lambda k: (k[1], k[0]))
        walk = [k for k in ground_cells if front_walk_fn(k[0] + 1, k[1])]
        door_cell = None
        doors = set()
        if walk:
            door_cell = walk[len(walk) // 2] if cls in ('apartments', 'civic', 'retail') else walk[int(rng.random() * len(walk))]
        if seg_of is not None:   # una puerta por casa de la hilera
            by_seg = {}
            for k_ in walk:
                by_seg.setdefault(seg_of[k_[1]], []).append(k_)
            doors = {v[len(v) // 2] for v in by_seg.values()}
            door_cell = None
        garage_cell = None
        if cls == 'house' and seg_of is None and len(walk) >= 3 and rng.random() < .35:
            cand = [walk[0], walk[-1]]
            garage_cell = cand[int(rng.random() * 2)]
            if garage_cell == door_cell:
                garage_cell = None
        for (y, x), u in facade.items():
            same_row = lambda yy, xx: facade.get((yy, xx)) == u and bld[yy, xx] == b and \
                (seg_of is None or seg_of.get(xx) == seg_of.get(x))
            lft, rgt = same_row(y, x - 1), same_row(y, x + 1)
            pos = 'm' if lft and rgt else 'r' if lft else 'l' if rgt else 's'
            if u > 0:
                kind = 'arch' if cls == 'civic' else ('bal' if cls == 'house' else 'up')
            elif (y, x) == door_cell or (y, x) in doors:
                kind = 'door'
            elif (y, x) == garage_cell:
                kind = 'garage'
            else:
                front = front_walk_fn(y + 1, x)
                r = rng_for('fac', b, x).random()
                if cls == 'retail' and front:
                    kind = shops
                elif cls == 'industrial':
                    kind = 'roll' if (x - x0) % 3 == 1 and front else 'win'
                elif cls == 'civic':
                    kind = 'arch'
                elif cls == 'apartments' and front and pedestrian_fn(y + 1, x) and r < .45:
                    kind = shops
                elif cls == 'farm':
                    kind = 'arch' if r < .3 else 'win'
                elif cls == 'house' and r < .25:
                    kind = 'bal'
                else:
                    kind = 'win'
            wall = seg_wall[seg_of[x]] if seg_of is not None else info['wall']
            out[(y, x)] = tid(f"f_{wall}_{pos}_{kind}")
        # tejado: cumbrera en la fila central de cada columna en los de pendiente; objetos en azoteas
        rk = info['roof']
        for x, yl in cols.items():
            roof_rows = [y for y in sorted(yl) if (y, x) not in facade]
            if not roof_rows:
                continue
            top, bot = roof_rows[0], roof_rows[-1]
            ridge = top + (bot - top) // 2
            for y in roof_rows:
                m = nmask(lambda yy, xx: bld[yy, xx] == b and (yy, xx) not in facade or
                          (yy == y + 1 and xx == x and (yy, xx) in facade), y, x, H, W)
                if rk in PITCHED and bot - top >= 1:
                    part = 'n' if y < ridge else 'k' if y == ridge else 's'
                    out[(y, x)] = tid(f'r_{rk}_{part}_{m}')
                elif rk == 'flat' and m == 15 and rng.random() < (.10 if cls != 'house' else .06):
                    out[(y, x)] = tid(f'r_flat_x{1 + int(rng.random() * 4)}')
                else:
                    out[(y, x)] = tid(f'r_{rk}_{m}')
    return out, stats
