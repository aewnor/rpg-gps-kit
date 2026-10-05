#!/usr/bin/env python3
"""Compila mapas Tiled (.tmj + .tsj externos) a chunks binarios (zlib) de 32 × 32 + índice Lua.

Uso: python3 tools/compile_maps.py [maps/source/overworld.tmj ...]
Sin argumentos compila todos los .tmj de maps/source/. Salida: maps/runtime/<escena>/.

Soportado: mapas ortogonales finitos, capas de tiles con datos JSON sin comprimir, tilesets
externos con imagen única, objetos punto/rectángulo/polilínea con propiedades tipadas, flags de
volteo. Todo lo demás se rechaza indicando archivo y objeto.
"""
import json
import os
import sys

import numpy as np

import walkgraph
import zones as zones_mod

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
CHUNK = 32
FLIP_H, FLIP_V, FLIP_D, ROT_HEX = 0x80000000, 0x40000000, 0x20000000, 0x10000000
GID_MASK = 0x0FFFFFFF
TILE_LAYERS = ('ground', 'ground_detail', 'structures', 'cover_low', 'bridge', 'overhead', 'height')
RAW_LAYERS = ('height',)   # valores crudos (no gids): altura en metros + superficie (tools/import_osm.py)
REQUIRED = ('ground', 'collision')


class CompileError(Exception):
    def __init__(self, file, where, msg):
        super().__init__(f'{os.path.relpath(file, ROOT)}: {where}: {msg}')


def load_tilesets(path, tmj):
    sets = []
    for ts in tmj.get('tilesets', []):
        if 'source' not in ts:
            raise CompileError(path, 'tilesets', 'tileset embebido no soportado (usar .tsj externo)')
        tpath = os.path.normpath(os.path.join(os.path.dirname(path), ts['source']))
        if not os.path.exists(tpath):
            raise CompileError(path, f"tileset {ts['source']}", 'archivo ausente')
        tsj = json.load(open(tpath))
        if 'image' not in tsj:
            raise CompileError(tpath, 'tileset', 'colección de imágenes no soportada')
        sets.append({'firstgid': ts['firstgid'], 'name': tsj['name'], 'count': tsj['tilecount'],
                     'tsj': tsj, 'path': tpath})
    sets.sort(key=lambda s: s['firstgid'])
    names = [s['name'] for s in sets]
    if 'tiles' not in names or 'collision' not in names:
        raise CompileError(path, 'tilesets', "se requieren los tilesets 'tiles' y 'collision'")
    return sets


def resolve(sets, gid, path, where):
    """gid limpio → (nombre_tileset, id_local)."""
    for s in reversed(sets):
        if gid >= s['firstgid']:
            local = gid - s['firstgid']
            if local >= s['count']:
                raise CompileError(path, where, f'GID {gid} fuera del tileset {s["name"]}')
            return s['name'], local
    raise CompileError(path, where, f'GID {gid} sin tileset')


def props(obj, path, where):
    out = {}
    for p in obj.get('properties', []) or []:
        t = p.get('type', 'string')
        if t not in ('string', 'int', 'float', 'bool'):
            raise CompileError(path, where, f"propiedad '{p['name']}' de tipo {t} no soportada")
        out[p['name']] = p['value']
    return out


def compile_map(path):
    tmj = json.load(open(path))
    if tmj.get('orientation') != 'orthogonal':
        raise CompileError(path, 'map', f"orientación {tmj.get('orientation')} no soportada")
    if tmj.get('infinite'):
        raise CompileError(path, 'map', 'mapas infinitos no soportados')
    if tmj.get('tilewidth') != 16 or tmj.get('tileheight') != 16:
        raise CompileError(path, 'map', 'el tamaño de tile debe ser 16 × 16')
    W, H = tmj['width'], tmj['height']
    sets = load_tilesets(path, tmj)
    mprops = props(tmj, path, 'map')
    scene = mprops.get('scene') or os.path.splitext(os.path.basename(path))[0]
    tiles_first = next(s['firstgid'] for s in sets if s['name'] == 'tiles')

    layers, flips = {}, {}
    coll = None
    objects, routes, lines = [], [], []
    seen_names = {}
    for layer in tmj['layers']:
        lname = layer.get('name')
        ltype = layer.get('type')
        where = f'capa {lname}'
        if ltype == 'tilelayer':
            if 'chunks' in layer:
                raise CompileError(path, where, 'chunks de mapa infinito no soportados')
            if layer.get('encoding') not in (None, 'csv') or layer.get('compression'):
                raise CompileError(path, where, 'datos codificados/comprimidos no soportados: usar arrays JSON')
            if lname not in TILE_LAYERS and lname != 'collision':
                raise CompileError(path, where, 'nombre de capa desconocido')
            if lname in RAW_LAYERS:
                layers[lname] = np.array(layer['data'], dtype=np.int64).reshape(H, W).clip(0, 65535).astype(np.int32)
                continue
            data = np.array(layer['data'], dtype=np.uint64).reshape(H, W)
            raw = (data & GID_MASK).astype(np.int64)
            fl = (data >> 29).astype(np.uint8)  # bits H, V, D
            if (data & ROT_HEX).any():
                raise CompileError(path, where, 'rotación hexagonal no soportada')
            out = np.zeros((H, W), np.int32)
            uniq = np.unique(raw)
            lut = {}
            for g in uniq:
                g = int(g)
                if g == 0:
                    lut[0] = 0
                    continue
                ys, xs = np.nonzero(raw == g)
                tsname, local = resolve(sets, g, path, f'{where} celda ({xs[0]},{ys[0]})')
                if lname == 'collision':
                    if tsname != 'collision':
                        raise CompileError(path, f'{where} celda ({xs[0]},{ys[0]})', 'la capa de colisión solo admite el tileset collision')
                    lut[g] = local
                else:
                    if tsname != 'tiles':
                        raise CompileError(path, f'{where} celda ({xs[0]},{ys[0]})', f'tileset {tsname} no válido en capa visual')
                    lut[g] = local + 1  # índice en el atlas, base 1; 0 = celda vacía
            for g, v in lut.items():
                out[raw == g] = v
            if lname == 'collision':
                if (fl != 0).any():
                    raise CompileError(path, where, 'la colisión no admite volteos')
                coll = out.astype(np.uint8)
            else:
                layers[lname] = out
                if (fl != 0).any():
                    flips[lname] = fl
        elif ltype == 'objectgroup':
            for o in layer.get('objects', []):
                where = f"objeto id={o.get('id')} '{o.get('name')}'"
                if 'gid' in o:
                    raise CompileError(path, where, 'objetos-tile no soportados')
                if o.get('ellipse') or o.get('polygon') or o.get('text'):
                    raise CompileError(path, where, 'elipses, polígonos y textos no soportados')
                p = props(o, path, where)
                entry = {'id': o['id'], 'name': o.get('name', ''), 'type': o.get('type') or o.get('class', ''),
                         'x': o['x'], 'y': o['y'], 'w': o.get('width', 0), 'h': o.get('height', 0),
                         'props': p}
                if o.get('name'):
                    key = (entry['type'], o['name'])
                    if key in seen_names:
                        raise CompileError(path, where, f"ID duplicado '{o['name']}' (ya en objeto {seen_names[key]})")
                    seen_names[key] = o['id']
                if 'polyline' in o:
                    entry['points'] = [[o['x'] + q['x'], o['y'] + q['y']] for q in o['polyline']]
                    if entry['type'] == 'line':
                        lines.append(entry)
                    else:
                        routes.append(entry)
                else:
                    objects.append(entry)
        else:
            raise CompileError(path, f'capa {lname}', f'tipo de capa {ltype} no soportado')
    for req in REQUIRED:
        if req != 'collision' and req not in layers:
            raise CompileError(path, 'map', f"falta la capa '{req}'")
    if coll is None:
        raise CompileError(path, 'map', "falta la capa 'collision'")

    # animaciones del tileset principal
    anim = {}
    tiles_tsj = next(s for s in sets if s['name'] == 'tiles')['tsj']
    for t in tiles_tsj.get('tiles', []):
        if t.get('animation'):
            anim[t['id'] + 1] = {'frames': [f['tileid'] + 1 for f in t['animation']],
                                 'duration': t['animation'][0]['duration'] / 1000}
    m = {'scene': scene, 'width': W, 'height': H, 'layers': layers, 'flips': flips, 'coll': coll,
         'objects': objects, 'lines': lines}
    interiors, zerr = zones_mod.apply(m)
    zerr += zones_mod.apply_npcs(m, scene)
    n_ed, ed_err = zones_mod.apply_map_edits(m)
    zerr += ed_err
    if n_ed:
        print(f'  {n_ed} retoques del mapa (maps/source/map-edits.json)')
    for e in zerr:
        print('AVISO', e)
    coll, objects = m['coll'], m['objects']
    # spawns (después de aplicar zonas): deben caer en celda transitable
    for o in objects:
        if o['type'] in ('spawn', 'door_target'):
            tx, ty = int(o['x'] // 16), int(o['y'] // 16)
            lv = int(o['props'].get('level', 0))
            if not (0 <= tx < W and 0 <= ty < H) or not walkgraph.walk_at(int(coll[ty, tx]), lv):
                raise CompileError(path, f"spawn '{o['name']}'", f'bloqueado o fuera del mapa en ({tx},{ty})')

    # personajes y servicios que han quedado dentro de un edificio o un muro (al rehacer manzanas, zonas o
    # retoques): a la casilla transitable más cercana, mejor con espacio alrededor para hablarles
    moved = 0
    for o in objects:
        if o['type'] not in ('npc', 'service') or o['props'].get('level'):
            continue
        tx, ty = int(o['x'] // 16), int(o['y'] // 16)
        def room(x, y):
            return sum(1 for dy in (-1, 0, 1) for dx in (-1, 0, 1)
                       if 0 <= x + dx < W and 0 <= y + dy < H and walkgraph.walk_at(int(coll[y + dy, x + dx]), 0))
        if 0 <= tx < W and 0 <= ty < H and walkgraph.walk_at(int(coll[ty, tx]), 0) and room(tx, ty) >= 4:
            continue
        best = None
        for r in range(1, 7):
            for dy in range(-r, r + 1):
                for dx in range(-r, r + 1):
                    x, y = tx + dx, ty + dy
                    if max(abs(dx), abs(dy)) != r or not (0 <= x < W and 0 <= y < H):
                        continue
                    if walkgraph.walk_at(int(coll[y, x]), 0) and room(x, y) >= 4:
                        k = (dx * dx + dy * dy, -dy)       # más cerca; a igualdad, delante (abajo)
                        if best is None or k < best[0]:
                            best = (k, x, y)
            if best:
                break
        if best:
            o['x'], o['y'] = best[1] * 16 + 8, best[2] * 16 + 8
            moved += 1
    if moved:
        print(f'  {moved} personajes/servicios movidos fuera de edificios')

    comp = walkgraph.components_fast(coll)[0]
    return {'scene': scene, 'width': W, 'height': H, 'layers': layers, 'lines': lines,
            'interiors': interiors, 'zones': m.get('zones', []), 'flips': flips, 'coll': coll,
            'comp': comp, 'objects': objects, 'routes': routes, 'anim': anim, 'props': mprops,
            'tileset_image': os.path.relpath(os.path.normpath(os.path.join(
                os.path.dirname(next(s['path'] for s in sets if s['name'] == 'tiles')), tiles_tsj['image'])), ROOT)}


def lua(v, indent=''):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, np.integer)):
        return str(int(v))
    if isinstance(v, (float, np.floating)):
        f = float(v)
        return str(int(f)) if f.is_integer() else repr(round(f, 3))
    if isinstance(v, str):
        return '"' + v.replace('\\', '\\\\').replace('"', '\\"').replace('\n', '\\n') + '"'
    if v is None:
        return 'nil'
    if isinstance(v, (list, tuple)):
        return '{' + ','.join(lua(x) for x in v) + '}'
    if isinstance(v, dict):
        parts = []
        for k, x in v.items():
            key = k if isinstance(k, str) and k.isidentifier() else f'[{lua(k)}]'
            parts.append(f'{key}={lua(x)}')
        return '{' + ','.join(parts) + '}'
    raise TypeError(type(v))


def write_runtime(m):
    out = os.path.join(ROOT, 'maps/runtime', m['scene'])
    os.makedirs(out, exist_ok=True)
    for f in os.listdir(out):
        os.remove(os.path.join(out, f))
    W, H = m['width'], m['height']
    cw, ch = (W + CHUNK - 1) // CHUNK, (H + CHUNK - 1) // CHUNK
    import struct
    import zlib
    for cy in range(ch):
        for cx in range(cw):
            sl = (slice(cy * CHUNK, min(H, cy * CHUNK + CHUNK)), slice(cx * CHUNK, min(W, cx * CHUNK + CHUNK)))
            hh, ww = m['coll'][sl].shape
            mask, parts = 0, []
            for li, name in enumerate(TILE_LAYERS):
                arr = m['layers'].get(name)
                if arr is not None and arr[sl].any():
                    mask |= 1 << li
                    parts.append(arr[sl].astype('<u2').tobytes())
            parts.append(m['coll'][sl].astype('u1').tobytes())
            parts.append(m['comp'][sl].astype('<u4').tobytes())
            fl = []
            for li, name in enumerate(TILE_LAYERS):
                arr = m['flips'].get(name)
                if arr is not None:
                    a2 = arr[sl].flatten()
                    for i in np.nonzero(a2)[0]:
                        fl.append(struct.pack('<BHB', li, int(i), int(a2[i])))
            payload = b'RC1' + struct.pack('<BBHH', ww, hh, mask, len(fl)) + b''.join(parts) + b''.join(fl)
            with open(os.path.join(out, f'c_{cx}_{cy}.bin'), 'wb') as f:
                f.write(zlib.compress(payload, 9))
    # vías vectoriales: arrays planos + índice por chunk
    if m['lines']:
        order = {'SHADOW': -1, 'TORRENT': 0, 'STREAM': 1, 'PATH': 2, 'TRACK': 3, 'STEPS': 4, 'FOOTWAY': 5,
                 'PEDESTRIAN': 6, 'PLATFORM': 7, 'ROAD': 8, 'ROAD_MAIN': 9, 'MOTORWAY': 10, 'RAIL': 11, 'RAIL_HS': 12,
                 'ZEBRA': 13, 'SHADE': 14, 'PARAPET': 15}
        ls = sorted(m['lines'], key=lambda e: (e['props'].get('level', 0), order.get(e['props'].get('cls'), 0)))
        items, by_chunk = [], {}
        size = CHUNK * 16
        for i, e in enumerate(ls, start=1):
            p = e['props']
            flat = [round(v, 1) for pt in e['points'] for v in pt]
            items.append({'c': p['cls'], 'l': p.get('level', 0), 'w': p['w'], 'k': bool(p.get('closed')), 'p': flat})
            xs, ys = flat[0::2], flat[1::2]
            pad = p['w']
            for cy in range(max(0, int((min(ys) - pad) // size)), min(ch - 1, int((max(ys) + pad) // size)) + 1):
                for cx in range(max(0, int((min(xs) - pad) // size)), min(cw - 1, int((max(xs) + pad) // size)) + 1):
                    by_chunk.setdefault(cy * 1024 + cx, []).append(i)
        with open(os.path.join(out, 'lines.lua'), 'w') as f:
            f.write('return ' + lua({'items': items, 'chunks': by_chunk}) + '\n')
        with open(os.path.join(out, 'lines.json'), 'w') as f:
            json.dump(items, f, separators=(',', ':'))
    index = {'scene': m['scene'], 'width': W, 'height': H, 'chunk': CHUNK, 'tile': 16,
             'zones': m.get('zones', []),
             'chunks_x': cw, 'chunks_y': ch, 'objects': m['objects'], 'routes': m['routes'],
             'anim': m['anim'], 'props': m['props'], 'tileset_image': m['tileset_image']}
    with open(os.path.join(out, 'index.lua'), 'w') as f:
        f.write('return ' + lua(index) + '\n')
    return out, cw * ch


def main(paths):
    if not paths:
        src = os.path.join(ROOT, 'maps/source')
        paths = sorted(os.path.join(src, p) for p in os.listdir(src) if p.endswith('.tmj'))
    ok = True
    extra = {}
    for p in paths:
        try:
            m = compile_map(p)
            out, n = write_runtime(m)
            print(f'{os.path.relpath(p, ROOT)} → {os.path.relpath(out, ROOT)} ({n} chunks, '
                  f'{len(m["objects"])} objetos, {len(m["routes"])} rutas, {len(m["zones"])} zonas)')
            for iid, spec, back_scene, back_spawn in m['interiors']:
                im, errs = zones_mod.build_interior(iid, spec, back_scene, back_spawn, m['tileset_image'])
                for e in errs:
                    print('AVISO', e)
                im['comp'] = walkgraph.components_fast(im['coll'])[0]
                im['anim'] = m['anim']
                write_runtime(im)
                extra[iid] = {'map': 'maps/runtime/' + iid, 'music': 'overworld', 'outdoor': False,
                              'interior': True, 'name': spec.get('name', iid)}
                print(f'  interior {iid} ({im["width"]}×{im["height"]})')
        except CompileError as e:
            print('ERROR', e)
            ok = False
    if not sys.argv[1:]:
        # escenas generadas (interiores): las lee el juego además de data/scenes.json
        for d in os.listdir(os.path.join(ROOT, 'maps/runtime')):
            if d.endswith('_int') and d not in extra:
                import shutil
                shutil.rmtree(os.path.join(ROOT, 'maps/runtime', d))
        with open(os.path.join(ROOT, 'maps/runtime/scenes_extra.json'), 'w') as f:
            json.dump(extra, f, indent=1, ensure_ascii=False)
    return ok


if __name__ == '__main__':
    sys.exit(0 if main(sys.argv[1:]) else 1)
