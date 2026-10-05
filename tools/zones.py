"""Zonas especiales rediseñadas a mano (editor web) e interiores.

Formato de maps/source/zones/<id>.json (lo escribe el editor):
{
  "id": "escola", "name": "Escola", "scene": "overworld", "x": 600, "y": 790, "w": 24, "h": 18,
  "ground": [nombre de tile por celda], "detail": [...], "structures": [...], "overhead": [...],
  "height": [0..3 por celda],
  "objects": [ {"type": "door", "x": 5, "y": 7, "interior": "escola_int"},
               {"type": "npc", "x": 3, "y": 9, "sprite": "npc_elder", "name": "Mestra", "say": ["Hola!"]},
               {"type": "sign", "x": 1, "y": 1, "say": ["Escola"]} ],
  "interiors": { "escola_int": { "name": "...", "w": 20, "h": 15, ...mismas capas..., "objects": [
               {"type": "exit", "x": 9, "y": 14}, ... ] } }
}
Opciones: "poly" (forma), "keep_ground" (celdas de ground vacías conservan el suelo del mapa),
"clear_decor" (además borra rótulos, servicios, props y coches aparcados de la zona); objeto {"type": "object",
"otype": "signboard"|"service"|…, "props": {…}, "dx"/"dy": px dentro de la celda} para objetos de juego sueltos.
Reglas de desnivel: una celda que linda con otra más baja es borde de roca (sólida, w_ledge_*) salvo que sea
escalera; así solo se sube y se baja por escaleras. Fuera de la zona se considera altura 0.
"""
import glob
import json
import os

import numpy as np

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
WALK, SOLID, WATER = 0, 1, 2
LAYER_KEYS = (('ground', 'ground'), ('detail', 'ground_detail'), ('structures', 'structures'),
              ('overhead', 'overhead'))


def load_zones():
    out = []
    for p in sorted(glob.glob(os.path.join(ROOT, 'maps/source/zones/*.json'))):
        with open(p) as f:
            z = json.load(f)
        z['_file'] = p
        out.append(z)
    return out


def _tiles():
    return json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']


def build_area(spec, tiles, outside_height=0, default_ground='g_grass_0'):
    """Capas (índice de atlas + 1), colisión y lista de errores para un área w × h."""
    w, h = spec['w'], spec['h']
    n = w * h
    errors = []
    layers = {}
    for key, lname in LAYER_KEYS:
        arr = np.zeros((h, w), np.int32)
        names = spec.get(key) or []
        for i in range(min(n, len(names))):
            nm = names[i]
            if not nm:
                continue
            t = tiles.get(nm)
            if t is None:
                errors.append(f"tile desconocido '{nm}' en {key}[{i}]")
                continue
            arr[i // w, i % w] = t['id'] + 1
        if key == 'ground' and not spec.get('keep_ground'):
            empty = arr == 0
            arr[empty] = tiles[default_ground]['id'] + 1
        layers[lname] = arr
    by_id = {t['id'] + 1: (nm, t) for nm, t in tiles.items()}
    height = np.array((spec.get('height') or [0] * n)[:n] + [0] * max(0, n - len(spec.get('height') or [])),
                      np.int32).reshape(h, w)
    coll = np.zeros((h, w), np.uint8)
    stairs = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            code = WALK
            for lname in ('ground', 'ground_detail', 'structures'):
                tid = layers[lname][y, x]
                if not tid:
                    continue
                nm, t = by_id[tid]
                if t.get('solid'):
                    code = SOLID
                elif t.get('water') and code == WALK:
                    code = WATER
                if t.get('stairs'):
                    stairs[y, x] = True
            coll[y, x] = code
    # taludes: celda junto a otra más baja (o al exterior más bajo) → roca sólida, salvo escaleras
    cliff = np.zeros((h, w), bool)
    for y in range(h):
        for x in range(w):
            hv = height[y, x]
            lower = False
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                xx, yy = x + dx, y + dy
                nh = height[yy, xx] if 0 <= xx < w and 0 <= yy < h else outside_height
                if nh < hv:
                    lower = True
            if lower and not stairs[y, x]:
                cliff[y, x] = True
    cliff_ids = {}
    for y, x in zip(*np.nonzero(cliff)):
        coll[y, x] = SOLID
        if not layers['structures'][y, x]:
            # borde de roca hacia los vecinos más bajos (mismo arte que el relieve del mapa)
            m = 0
            for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0))):
                xx, yy = x + dx, y + dy
                nh = height[yy, xx] if 0 <= xx < w and 0 <= yy < h else outside_height
                if nh < height[y, x]:
                    m |= bit
            layers['structures'][y, x] = tiles[f'w_ledge_{m}']['id'] + 1
    return layers, coll, height, stairs, errors


def npc_props(o):
    """Propiedades de juego de un personaje del editor (en zona o suelto por el mapa)."""
    p = {'sprite': o.get('sprite', 'npc_elder'), 'facing': o.get('facing', 'down'),
         'say': '|'.join(o.get('say') or ['...']), 'say_name': o.get('name', ''), 'wander': int(o.get('wander', 0))}
    if o.get('ai'):
        p['ai'] = True
        p['persona'] = str(o.get('persona', ''))[:600]
    return p


def apply_npcs(m, scene):
    """Personajes sueltos (maps/source/npcs.json, los crea el editor) → objetos 'npc' de la escena."""
    path = os.path.join(ROOT, 'maps/source/npcs.json')
    if not os.path.exists(path):
        return []
    warns = []
    for o in json.load(open(path)):
        if o.get('scene', 'overworld') != scene:
            continue
        x, y = o['x'], o['y']
        if m['coll'][y, x] & 3 or m['coll'][y, x] & 32:   # no transitable: celda libre más cercana
            best = None
            for r in range(1, 6):
                for dy in range(-r, r + 1):
                    for dx in range(-r, r + 1):
                        xx, yy = x + dx, y + dy
                        if best is None and 0 <= xx < m['width'] and 0 <= yy < m['height'] and not m['coll'][yy, xx] & 35:
                            best = (xx, yy)
            if best is None:
                warns.append(f"personaje {o['id']}: sin celda libre cerca de ({x},{y})")
                continue
            warns.append(f"personaje {o['id']}: movido de ({x},{y}) a {best} (celda bloqueada)")
            x, y = best
        m['objects'].append({'type': 'npc', 'name': 'npc_' + o['id'], 'x': x * 16 + 8, 'y': y * 16 + 8, 'w': 0, 'h': 0,
                             'props': npc_props(o)})
    return warns


def objects_for(spec, ox, oy, scene_id, zone_id, coll):
    """Objetos de juego (coordenadas en píxeles del mapa destino)."""
    objs, extra_scenes = [], []
    for k, o in enumerate(spec.get('objects', [])):
        x, y = o['x'], o['y']
        px, py = (ox + x) * 16, (oy + y) * 16
        t = o['type']
        nm = f"{zone_id}_{t}_{k}"
        if t == 'door':
            interior = o.get('interior')
            if not interior:
                continue
            coll[y, x] = WALK  # la puerta se puede pisar para entrar
            back = f'spawn_{interior}_door'
            objs.append({'type': 'door', 'name': nm, 'x': px, 'y': py, 'w': 16, 'h': 16,
                         'props': {'target_scene': interior, 'target_spawn': 'spawn_in', 'return_spawn': back}})
            objs.append({'type': 'spawn', 'name': back, 'x': px + 8, 'y': py + 24, 'w': 0, 'h': 0,
                         'props': {'public': True}})
        elif t == 'exit':
            objs.append({'type': 'door', 'name': nm, 'x': px, 'y': py, 'w': 16, 'h': 16,
                         'props': {'target_scene': o['target_scene'], 'target_spawn': o['target_spawn']}})
        elif t == 'spawn':
            objs.append({'type': 'spawn', 'name': o.get('name', nm), 'x': px + 8, 'y': py + 8, 'w': 0, 'h': 0,
                         'props': {'public': True}})
        elif t == 'npc':
            objs.append({'type': 'npc', 'name': nm, 'x': px + 8, 'y': py + 8, 'w': 0, 'h': 0,
                         'props': npc_props(o)})
        elif t == 'sign':
            coll[y, x] = SOLID
            objs.append({'type': 'sign', 'name': nm, 'x': px + 8, 'y': py + 8, 'w': 0, 'h': 0,
                         'props': {'say': '|'.join(o.get('say') or ['...'])}})
        elif t == 'object':   # objeto de juego genérico: otype (signboard, service, school…) + props; dx/dy en px
            objs.append({'type': o['otype'], 'name': o.get('name', nm), 'x': px + o.get('dx', 8), 'y': py + o.get('dy', 8),
                         'w': 0, 'h': 0, 'props': dict(o.get('props') or {})})
    return objs


def poly_mask(z):
    """Celdas de la zona dentro de su forma poligonal (z['poly']: vértices en coordenadas de la zona,
    en esquinas de celda). Sin forma → todo el rectángulo."""
    w, h = z['w'], z['h']
    poly = z.get('poly')
    if not poly or len(poly) < 3:
        return np.ones((h, w), bool)
    yy, xx = np.mgrid[0:h, 0:w]
    px, py = xx + 0.5, yy + 0.5
    inside = np.zeros((h, w), bool)
    n = len(poly)
    for i in range(n):  # par-impar (ray casting)
        x1, y1 = poly[i]
        x2, y2 = poly[(i + 1) % n]
        cross = (y1 > py) != (y2 > py)
        xint = x1 + (py - y1) * (x2 - x1) / ((y2 - y1) or 1e-9)
        inside ^= cross & (px < xint)
    return inside


MAP_EDITS = os.path.join(ROOT, 'maps/source/map-edits.json')
EDIT_LAYERS = {'ground': 'ground', 'detail': 'ground_detail', 'structures': 'structures', 'overhead': 'overhead'}


def apply_map_edits(m, tiles=None):
    """Retoques sueltos del mapa (editor «🖌️ Editar mapa»): {"x,y": {capa: tile o ""}}. Solo cambian
    esas celdas; su colisión de nivel 0 se recalcula con los tiles resultantes (se conservan puentes y túneles)."""
    if m['scene'] != 'overworld' or not os.path.exists(MAP_EDITS):
        return 0, []
    tiles = tiles or _tiles()
    by_id = {t['id'] + 1: t for t in tiles.values()}
    edits = json.load(open(MAP_EDITS)).get('cells', {})
    errors, n = [], 0
    for key, layers in edits.items():
        x, y = map(int, key.split(','))
        if not (0 <= x < m['width'] and 0 <= y < m['height']):
            errors.append(f'retoque fuera del mapa: {key}')
            continue
        for k, name in layers.items():
            ln = EDIT_LAYERS.get(k)
            if not ln:
                continue
            if name and name not in tiles:
                errors.append(f"retoque {key}: tile desconocido '{name}'")
                continue
            if ln not in m['layers']:
                m['layers'][ln] = np.zeros((m['height'], m['width']), np.int32)
            m['layers'][ln][y, x] = tiles[name]['id'] + 1 if name else 0
            if ln in m['flips']:
                m['flips'][ln][y, x] = 0
        code = WALK
        for ln in ('ground', 'ground_detail', 'structures'):
            t = by_id.get(int(m['layers'][ln][y, x])) if ln in m['layers'] else None
            if t and t.get('solid'):
                code = SOLID
            elif t and t.get('water') and code == WALK:
                code = WATER
        c = int(m['coll'][y, x])
        m['coll'][y, x] = (c & ~3 & ~32) | code
        n += 1
    return n, errors


def apply(m, tiles=None):
    """Aplica las zonas de la escena m (dict de compile_maps) y devuelve los interiores a compilar."""
    tiles = tiles or _tiles()
    interiors, errors, rects = [], [], []
    for z in load_zones():
        if z.get('scene', 'overworld') != m['scene']:
            continue
        zid = z['id']
        x0, y0, w, h = z['x'], z['y'], z['w'], z['h']
        if x0 < 0 or y0 < 0 or x0 + w > m['width'] or y0 + h > m['height']:
            errors.append(f'zona {zid}: fuera del mapa')
            continue
        for ln in m.get('lines', []):  # aviso: calle con coches dentro de la zona
            lp = ln.get('props', {})
            if lp.get('cls') in ('ROAD', 'ROAD_MAIN', 'MOTORWAY') and int(lp.get('level', 0)) == 0 and any(
                    x0 + 0.5 < px / 16 < x0 + w - 0.5 and y0 + 0.5 < py / 16 < y0 + h - 0.5 for px, py in ln['points']):
                print(f'  AVISO zona {zid}: una calle con coches ({ln.get("name")}) la atraviesa y quedará tapada')
                break
        layers, coll, height, stairs, errs = build_area(z, tiles)
        errors += [f'zona {zid}: {e}' for e in errs]
        sl = (slice(y0, y0 + h), slice(x0, x0 + w))
        pm = poly_mask(z)   # forma poligonal: fuera de ella se conserva el mapa
        for lname in ('ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead'):
            if lname not in m['layers']:
                m['layers'][lname] = np.zeros((m['height'], m['width']), np.int32)
            src = layers.get(lname, 0)
            src = src if isinstance(src, np.ndarray) else np.full((h, w), src, np.int32)
            keep = z.get('keep_ground') and lname == 'ground'   # celdas sin suelo propio: se conserva el del mapa
            m['layers'][lname][sl] = np.where(pm & ((src != 0) if keep else True), src, m['layers'][lname][sl])
            if lname in m['flips']:
                m['flips'][lname][sl][pm] = 0
        objs = objects_for(z, x0, y0, m['scene'], zid, coll)
        m['coll'][sl] = np.where(pm, coll, m['coll'][sl])

        def in_zone(o):
            tx, ty = int(o['x'] // 16) - x0, int(o['y'] // 16) - y0
            return 0 <= tx < w and 0 <= ty < h and pm[ty, tx]
        gone = ('npc', 'sign', 'enemy', 'chest', 'landmark')
        if z.get('clear_decor'):   # rótulos, servicios, props y coches aparcados que puso decorate/import
            gone += ('signboard', 'school', 'service', 'prop', 'parked_car')
        m['objects'] = [o for o in m['objects'] if not (in_zone(o) and o['type'] in gone)] + objs
        rect = {'id': zid, 'x': x0 * 16, 'y': y0 * 16, 'w': w * 16, 'h': h * 16}
        if z.get('poly') and len(z['poly']) >= 3:
            rect['poly'] = [v for px, py in z['poly'] for v in ((x0 + px) * 16, (y0 + py) * 16)]
        rects.append(rect)
        for door in [o for o in z.get('objects', []) if o['type'] == 'door' and o.get('interior')]:
            spec = (z.get('interiors') or {}).get(door['interior'])
            if not spec:
                errors.append(f"zona {zid}: puerta sin interior '{door['interior']}'")
                continue
            interiors.append((door['interior'], spec, m['scene'], f"spawn_{door['interior']}_door"))
    m['zones'] = rects
    return interiors, errors


def build_interior(iid, spec, back_scene, back_spawn, tileset_image, tiles=None):
    """Mapa de interior completo (mismo formato que compile_map)."""
    tiles = tiles or _tiles()
    w, h = spec['w'], spec['h']
    layers, coll, height, stairs, errors = build_area(spec, tiles, outside_height=0,
                                                    default_ground='i_floor_wood_0')
    objs = []
    spec_objs = list(spec.get('objects', []))
    if not any(o['type'] == 'exit' for o in spec_objs):
        spec_objs.append({'type': 'exit', 'x': w // 2, 'y': h - 1})
    for o in spec_objs:
        if o['type'] == 'exit':
            o.setdefault('target_scene', back_scene)
            o.setdefault('target_spawn', back_spawn)
    exit_o = next(o for o in spec_objs if o['type'] == 'exit')
    sx, sy = spec.get('spawn') or [exit_o['x'], exit_o['y'] - 1]
    objs = objects_for({'objects': spec_objs}, 0, 0, iid, iid, coll)
    coll[exit_o['y'], exit_o['x']] = WALK
    if coll[sy, sx] != WALK:
        errors.append(f'interior {iid}: el punto de entrada ({sx},{sy}) está bloqueado')
        coll[sy, sx] = WALK
    objs.append({'type': 'spawn', 'name': 'spawn_in', 'x': sx * 16 + 8, 'y': sy * 16 + 8, 'w': 0, 'h': 0,
                 'props': {'public': True}})
    return {'scene': iid, 'width': w, 'height': h, 'layers': layers, 'flips': {}, 'coll': coll,
            'objects': objs, 'routes': [], 'lines': [], 'anim': {}, 'zones': [],
            'props': {'scene': iid, 'interior': True, 'name': spec.get('name', iid)},
            'tileset_image': tileset_image}, errors
