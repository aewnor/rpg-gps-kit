"""Etapa 1 del importador: rasteriza OSM a una rejilla semántica MAP_TILES × MAP_TILES.

No decide tiles concretos; produce clases (suelo, detalle por nivel, edificios,
árboles, colisión) que luego `import_osm.py` traduce a capas de Tiled.
"""
import math
import numpy as np
from PIL import Image, ImageDraw

from osmlib import OSM, to_tile_f, to_tile, join_segments, m2t, MAP_TILES

W = H = MAP_TILES
S = 4  # supermuestreo para rasterizar

# --- clases de suelo ---------------------------------------------------------
G = dict(VOID=0, DRY=1, GRASS=2, FOREST=3, SCRUB=4, FARM=5, VINEYARD=6, URBAN=7,
         PARK=8, QUARRY=9, BEACH=10, ROCK=11, SEA=12, WATER=13, RAILYARD=14,
         CEMETERY=15, WETLAND=16, PITCH=17)
# --- clases de detalle (por nivel) -------------------------------------------
D = dict(NONE=0, STREAM=1, PATH=2, TRACK=3, STEPS=4, FOOTWAY=5, PEDESTRIAN=6,
         ROAD=7, ROAD_MAIN=8, MOTORWAY=9, RAIL=10, PLATFORM=11, PIER=12,
         LEVEL_CROSSING=13, PENDING=14, RAIL_HS=15, TORRENT=16)
WALKABLE_DETAIL = {D[k] for k in ('STREAM', 'PATH', 'TRACK', 'STEPS', 'FOOTWAY', 'PEDESTRIAN',
                                  'ROAD', 'ROAD_MAIN', 'PLATFORM', 'PIER', 'LEVEL_CROSSING')}
WALKABLE_GROUND = {G[k] for k in ('DRY', 'GRASS', 'FOREST', 'SCRUB', 'FARM', 'VINEYARD', 'URBAN',
                                  'PARK', 'QUARRY', 'BEACH', 'ROCK', 'RAILYARD', 'CEMETERY',
                                  'PITCH')}

# anchura REAL aproximada en metros (calzada + aceras); se convierte a tiles con m2t()
HIGHWAY = {
    'motorway': ('MOTORWAY', 12), 'motorway_link': ('MOTORWAY', 6),
    'trunk': ('ROAD_MAIN', 12), 'primary': ('ROAD_MAIN', 11), 'primary_link': ('ROAD', 6),
    'secondary': ('ROAD_MAIN', 10), 'secondary_link': ('ROAD', 6),
    'tertiary': ('ROAD_MAIN', 9), 'tertiary_link': ('ROAD', 6),
    'residential': ('ROAD', 8), 'unclassified': ('ROAD', 7), 'living_street': ('PEDESTRIAN', 6),
    'service': ('ROAD', 5), 'road': ('ROAD', 6),
    'pedestrian': ('PEDESTRIAN', 6), 'footway': ('FOOTWAY', 3), 'cycleway': ('FOOTWAY', 3),
    'steps': ('STEPS', 3), 'path': ('PATH', 3), 'track': ('TRACK', 4), 'bridleway': ('PATH', 3),
    # sin clasificar: bloqueadas y marcadas para revisión
    'construction': ('PENDING', 6), 'proposed': None, 'raceway': ('PENDING', 6),
}
M_RAIL = 4  # metros de una vía
DETAIL_PRIORITY = [D[k] for k in ('TORRENT', 'STREAM', 'PATH', 'TRACK', 'FOOTWAY', 'STEPS', 'PEDESTRIAN',
                                  'ROAD', 'ROAD_MAIN', 'PLATFORM', 'PIER', 'PENDING', 'RAIL',
                                  'RAIL_HS', 'MOTORWAY')]


def _level_overrides():
    """Niveles forzados por vía (map-overrides.json → level_overrides {way_id: nivel}): errores de etiquetado OSM."""
    import json, os
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'maps/source/map-overrides.json')
    try:
        return {str(k): int(v) for k, v in json.load(open(path)).get('level_overrides', {}).items()}
    except (OSError, ValueError):
        return {}


LEVEL_OVERRIDES = _level_overrides()


CUTTING_MIN = 30   # casillas: layer<0 sense tunnel tan llarg és una trinxera (la via va a nivell del terra)


def way_level(tags, wid=None, length=None):
    """Nivell de joc d'una via OSM: 1 pont, -1 túnel/coberta, 0 terra. `length` (casillas) distingueix un pas
    inferior curt (layer=-1, -1) d'una trinxera llarga sense tunnel (TV-2041 al nord, Camí de Roda-Vendrell: 0),
    que si no desapareixia sencera sota terra."""
    if wid is not None and str(wid) in LEVEL_OVERRIDES:
        return LEVEL_OVERRIDES[str(wid)]
    try:
        layer = int(tags.get('layer', '0'))
    except ValueError:
        layer = 0
    if tags.get('bridge') and tags.get('bridge') != 'no':
        return 1
    if (tags.get('tunnel') and tags.get('tunnel') != 'no') or tags.get('covered') == 'yes':
        return -1
    if layer > 0:
        return 1
    if layer < 0:
        return 0 if (length is not None and length >= CUTTING_MIN) else -1
    return 0


def local_cells(pts_list, kind, width_tiles=1, min_frac=0.5, holes=()):
    """Rasteriza en una ventana local (rápido). Devuelve (y0, x0, mask) o None."""
    allp = [p for pts in pts_list for p in pts]
    if not allp:
        return None
    pad = width_tiles + 1
    x0 = max(0, int(math.floor(min(p[0] for p in allp) - pad)))
    y0 = max(0, int(math.floor(min(p[1] for p in allp) - pad)))
    x1 = min(W, int(math.ceil(max(p[0] for p in allp) + pad)))
    y1 = min(H, int(math.ceil(max(p[1] for p in allp) + pad)))
    if x1 <= x0 or y1 <= y0:
        return None
    img = Image.new('L', ((x1 - x0) * S, (y1 - y0) * S), 0)
    d = ImageDraw.Draw(img)
    for pts in pts_list:
        sp = [((x - x0) * S, (y - y0) * S) for x, y in pts]
        if kind == 'poly':
            if len(sp) >= 3:
                d.polygon(sp, fill=255)
        else:
            if len(sp) < 2:
                continue
            w = max(1, int(round(width_tiles * S)))
            d.line(sp, fill=255, width=w)
            r = w / 2
            for x, y in sp:
                d.ellipse([x - r, y - r, x + r, y + r], fill=255)
    for pts in holes:
        sp = [((x - x0) * S, (y - y0) * S) for x, y in pts]
        if len(sp) >= 3:
            d.polygon(sp, fill=0)
    a = np.asarray(img, dtype=np.uint8).reshape(y1 - y0, S, x1 - x0, S) > 0
    return y0, x0, (a.sum(axis=(1, 3)) / (S * S)) >= min_frac


def four_connect(loc):
    """Cierra conexiones solo diagonales: el colisionador continuo no pasa por esquinas."""
    if loc is None:
        return None
    y0, x0, m = loc
    m = m.copy()
    h, w = m.shape
    for y in range(h - 1):
        for x in range(w - 1):
            a, b, c, d = m[y, x], m[y, x + 1], m[y + 1, x], m[y + 1, x + 1]
            if a and d and not b and not c:
                m[y, x + 1] = True
            elif b and c and not a and not d:
                m[y, x] = True
    return y0, x0, m


def paint(arr, loc, val, where=None):
    if loc is None:
        return
    y0, x0, m = loc
    sub = arr[y0:y0 + m.shape[0], x0:x0 + m.shape[1]]
    if where is not None:
        m = m & where(sub)
    sub[m] = val


def polygon_features(osm):
    """(tags, outer_rings_tiles, inner_rings_tiles, source_id) de vías cerradas y multipolígonos."""
    for wid, (tags, refs) in osm.ways.items():
        if len(refs) >= 4 and refs[0] == refs[-1]:
            yield tags, [osm.way_tiles(wid)], [], 'way/' + wid
    for rid, (tags, members) in osm.relations.items():
        if tags.get('type') != 'multipolygon':
            continue
        outer, inner = osm.multipolygon_rings(rid)
        tr = lambda ring: [to_tile_f(*c) for c in ring]
        yield tags, [tr(r) for r in outer], [tr(r) for r in inner], 'relation/' + rid


def ground_class(tags):
    lu, nat, lei = tags.get('landuse'), tags.get('natural'), tags.get('leisure')
    am = tags.get('amenity')
    if nat in ('water',) or lei == 'swimming_pool' or lu in ('reservoir', 'basin'):
        return 'WATER'
    if nat == 'beach' or nat == 'sand':
        return 'BEACH'
    if nat in ('bare_rock', 'cliff', 'scree'):
        return 'ROCK'
    if lu == 'quarry':
        return 'QUARRY'
    if lu in ('forest',) or nat == 'wood':
        return 'FOREST'
    if nat in ('scrub', 'heath'):
        return 'SCRUB'
    if nat == 'wetland':
        return 'WETLAND'
    if lu in ('vineyard',):
        return 'VINEYARD'
    if lu in ('farmland', 'orchard', 'meadow', 'plant_nursery', 'greenfield', 'farmyard'):
        return 'FARM'
    if lu in ('residential', 'commercial', 'retail', 'industrial', 'construction') or am in ('school', 'parking'):
        return 'URBAN'
    if lu == 'railway':
        return 'RAILYARD'
    if lu == 'cemetery' or am == 'grave_yard':
        return 'CEMETERY'
    if lei in ('pitch', 'sports_centre', 'track'):
        return 'PITCH'
    if lei in ('park', 'garden', 'playground', 'recreation_ground') or lu in ('grass', 'recreation_ground', 'village_green'):
        return 'PARK'
    return None


GROUND_ORDER = ['FARM', 'VINEYARD', 'SCRUB', 'FOREST', 'WETLAND', 'URBAN', 'RAILYARD', 'PARK',
                'PITCH', 'CEMETERY', 'QUARRY', 'ROCK', 'BEACH', 'WATER']


def rasterize_polys(polys):
    """polys: [(outer_rings, inner_rings)] → máscara bool."""
    out = np.zeros((H, W), bool)
    for outer, inner in polys:
        paint(out, local_cells(outer, 'poly', holes=inner), True)
    return out


def sea_polygon(osm):
    """Cierra la línea de costa contra el borde sur/este del rectángulo (tierra a la izquierda)."""
    segs = [refs for tags, refs in osm.ways.values() if tags.get('natural') == 'coastline']
    chains = [c for c in join_segments(segs) if len(c) > 10]
    chain = max(chains, key=len)
    pts = [to_tile_f(*osm.nodes[r]) for r in chain]
    # la cadena va de oeste a este con el mar a la derecha (sur): cerrar por el SE y SO
    big = 10_000
    pts = pts + [(big, pts[-1][1]), (big, big), (-big, big), (-big, pts[0][1])]
    return [pts]


def build(osm_path, limit_path=None):
    osm = OSM(osm_path)
    ground = np.full((H, W), G['DRY'], np.uint8)
    feats = {}
    buildings = []
    special = []
    for tags, outer, inner, src in polygon_features(osm):
        if tags.get('building') == 'roof':   # marquesines (gasolineres): les dibuixa decorate_map.canopies
            continue
        if tags.get('building') and tags.get('building') != 'no':
            buildings.append((tags, outer, inner, src))
            continue
        gc = ground_class(tags)
        if gc:
            feats.setdefault(gc, []).append((outer, inner))
        if tags.get('man_made') == 'pier':
            special.append(('PIER', outer, inner))
        elif tags.get('leisure') == 'marina':  # muelles y agua: se separan con la ortofoto (realdata.marina)
            special.append(('MARINA', outer, inner))
    masks = {}
    for gc in GROUND_ORDER:
        if gc in feats:
            masks[gc] = rasterize_polys(feats[gc])
    for gc in GROUND_ORDER:
        if gc in masks and gc not in ('BEACH', 'WATER'):
            ground[masks[gc]] = G[gc]
    sea = rasterize_polys([(sea_polygon(osm), [])])
    if 'BEACH' in masks:
        ground[masks['BEACH']] = G['BEACH']
    ground[sea] = G['SEA']
    # playas que OSM dibuja hasta el agua: conservar arena solo en tierra
    if 'WATER' in masks:
        ground[masks['WATER'] & ~sea] = G['WATER']
    # costa no arenosa → roca
    land = ground != G['SEA']
    near_sea = np.zeros_like(land)
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            near_sea |= np.roll(np.roll(sea, dy, 0), dx, 1)
    rocky = land & near_sea & (ground != G['BEACH'])
    ground[rocky] = G['ROCK']

    # --- vías por nivel ------------------------------------------------------
    detail = {lv: np.zeros((H, W), np.uint8) for lv in (-1, 0, 1)}
    way_mask = {}   # wid -> (level, mask) para la comprobación de cruces
    way_width = {}  # wid -> anchura en metros
    lines = {lv: {} for lv in (-1, 0, 1)}  # clase -> [(pts, width, wid)]
    for wid, (tags, refs) in osm.ways.items():
        cls = width = None
        hw, rw, ww = tags.get('highway'), tags.get('railway'), tags.get('waterway')
        if hw in HIGHWAY:
            spec = HIGHWAY[hw]
            if spec is None:
                continue
            cls, width = spec
            if hw == 'footway' and tags.get('footway') in ('sidewalk', 'crossing'):
                continue  # aceras ya van con la calzada
        elif rw in ('rail', 'light_rail', 'narrow_gauge'):
            # cada vía OSM es UNA vía (dos carriles): 1 tile de 4 m
            cls, width = ('RAIL_HS' if tags.get('highspeed') == 'yes' else 'RAIL'), M_RAIL
        elif rw == 'platform' or tags.get('public_transport') == 'platform':
            cls, width = 'PLATFORM', 4
        elif tags.get('man_made') == 'pier':
            cls, width = 'PIER', 4
        elif ww in ('stream', 'river', 'ditch', 'canal') and not tags.get('tunnel'):
            # torrentes con nombre (Torrent, Barranc, Fondo…): lecho ancho que no se puede cruzar
            # a pie; solo por puentes, pasarelas o donde una calle/camino pasa por encima
            if tags.get('name') and ww in ('stream', 'river'):
                cls, width = 'TORRENT', 8
            else:
                cls, width = 'STREAM', 3
        if cls is None:
            continue
        pts = osm.way_tiles(wid)
        if refs and refs[0] == refs[-1] and tags.get('area') == 'yes':
            continue
        lv = way_level(tags, wid, sum(math.dist(a, b) for a, b in zip(pts, pts[1:])) if pts else None)
        lines[lv].setdefault(D[cls], []).append((pts, width, wid))
    # cascos antiguos (maps/source/nuclis.json, tools/nuclis.py): calles residenciales como pavimento
    # peatonal y, en general, con la anchura real del casco (3-5 m) para que quepan las casas en hilera
    import nuclis as Nuclis
    _cx, _cy = to_tile(1.454242, 41.186165)  # Sant Bartomeu (urbano alrededor del casco, más abajo)
    core = (_cx, _cy, m2t(220))
    core_names, narrow = {}, {}
    for lv_ in (-1, 0, 1):
        for cls_, items in lines[lv_].items():
            for pts, width, wid in items:
                t = osm.ways[wid][0]
                n = Nuclis.way_nucli(pts)
                if n is None:
                    continue
                if cls_ == D['ROAD'] and t.get('highway') in ('residential', 'living_street', 'service', 'unclassified') and \
                        all(Nuclis.which(x, y) is n for x, y in pts):
                    core_names[wid] = True
                if t.get('highway') in Nuclis.NARROW:
                    narrow[wid] = min(width, n.get('street_m', 4))
    for lv in (-1, 0, 1):
        for cls in DETAIL_PRIORITY:
            for pts, width, wid in lines[lv].get(cls, []):
                width = narrow.get(wid, width)
                wt = max(1.0, m2t(width))
                loc = four_connect(local_cells([pts], 'line', wt, 0.3 if wt > 1.5 else 0.2))
                if cls == D['ROAD'] and core_names.get(wid):
                    cls_eff = D['PEDESTRIAN']
                else:
                    cls_eff = cls
                paint(detail[lv], loc, cls_eff)
                if loc is not None:
                    way_mask[wid] = (lv, loc, cls_eff, pts)
                    way_width[wid] = width
    marina = np.zeros((H, W), bool)
    for kind, outer, inner in special:
        m = rasterize_polys([(outer, inner)])
        if kind == 'MARINA':
            marina |= m
        else:
            detail[0][m & (detail[0] == 0)] = D['PIER']

    # suelo seco rodeado de calles → urbano (OSM no siempre cierra el landuse residencial)
    roads = np.isin(detail[0], [D['ROAD'], D['PEDESTRIAN'], D['FOOTWAY'], D['ROAD_MAIN']]).astype(np.int32)
    k = max(2, round(m2t(40)))
    cs = np.pad(roads, k).cumsum(0).cumsum(1)
    cs = np.pad(cs, ((1, 0), (1, 0)))
    win = cs[2 * k + 1:, 2 * k + 1:] - cs[:-2 * k - 1, 2 * k + 1:] - cs[2 * k + 1:, :-2 * k - 1] + cs[:-2 * k - 1, :-2 * k - 1]
    win = win[:H, :W]
    yy_, xx_ = np.mgrid[0:H, 0:W]
    area = (2 * k + 1) ** 2
    ground[(ground == G['DRY']) & (win >= 0.12 * area)] = G['URBAN']
    ground[(ground == G['DRY']) & (win >= 0.05 * area) & ((xx_ - core[0]) ** 2 + (yy_ - core[1]) ** 2 < core[2] ** 2)] = G['URBAN']

    # pasos a nivel identificados en OSM
    crossings = []
    for nid, tags in osm.node_tags.items():
        if tags.get('railway') == 'level_crossing' or tags.get('railway') == 'crossing':
            x, y = to_tile_f(*osm.nodes[nid])
            crossings.append((nid, tags.get('railway'), x, y))
            cx, cy = int(x), int(y)
            rr = max(2, round(m2t(16)))
            for yy in range(cy - rr, cy + rr + 1):
                for xx in range(cx - rr, cx + rr + 1):
                    if 0 <= xx < W and 0 <= yy < H and detail[0][yy, xx] in (D['RAIL'], D['RAIL_HS']):
                        if math.hypot(xx + .5 - x, yy + .5 - y) <= m2t(16):
                            detail[0][yy, xx] = D['LEVEL_CROSSING']

    # --- edificios ------------------------------------------------------------
    bld = np.zeros((H, W), np.int32)  # 0 = nada; >0 índice de edificio
    binfo = [None]
    for i, (tags, outer, inner, src) in enumerate(buildings, start=1):
        loc = local_cells(outer, 'poly', holes=inner)
        if loc is None:
            continue
        y0, x0, m = loc
        if not m.any():  # edificio menor que media celda: ocupar la celda del centroide
            pts = outer[0]
            cx = sum(p[0] for p in pts) / len(pts)
            cy = sum(p[1] for p in pts) / len(pts)
            if 0 <= int(cy) - y0 < m.shape[0] and 0 <= int(cx) - x0 < m.shape[1]:
                m[int(cy) - y0, int(cx) - x0] = True
        paint(bld, (y0, x0, m), len(binfo), where=lambda sub: sub == 0)
        binfo.append({'src': src, 'kind': tags.get('building'), 'name': tags.get('name'),
                      'amenity': tags.get('amenity'), 'shop': tags.get('shop'), 'generated': False})

    # límite municipal
    limit = None
    if limit_path:
        lo = OSM(limit_path)
        for rid, (tags, members) in lo.relations.items():
            if tags.get('boundary') == 'administrative' and tags.get('admin_level') == '8':
                outer, inner = lo.multipolygon_rings(rid)
                limit = rasterize_polys([([[to_tile_f(*c) for c in r] for r in outer],
                                          [[to_tile_f(*c) for c in r] for r in inner])])
    return dict(osm=osm, ground=ground, detail=detail, way_mask=way_mask, way_width=way_width, bld=bld, binfo=binfo,
                crossings=crossings, limit=limit, sea=sea, marina=marina)
