#!/usr/bin/env python3
"""Pruebas del compilador/validador con mapas sintéticos (ejecutar desde tools/)."""
import copy
import json
import os
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'tools'))
import compile_maps  # noqa: E402

ROOT = compile_maps.ROOT
fails = 0


def check(cond, msg):
    global fails
    print(('OK   ' if cond else 'FAIL ') + msg)
    if not cond:
        fails += 1


tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))
COUNT = tiles['count']
G = tiles['tiles']['g_dry_0']['id'] + 1
CF = COUNT + 1  # firstgid de collision


def base():
    W = H = 4
    return {'type': 'map', 'orientation': 'orthogonal', 'infinite': False, 'width': W, 'height': H,
            'tilewidth': 16, 'tileheight': 16,
            'properties': [{'name': 'scene', 'type': 'string', 'value': 'prueba'}],
            'tilesets': [{'firstgid': 1, 'source': 'tiles.tsj'}, {'firstgid': CF, 'source': 'collision.tsj'}],
            'layers': [
                {'name': 'ground', 'type': 'tilelayer', 'width': W, 'height': H, 'data': [G] * 16},
                {'name': 'collision', 'type': 'tilelayer', 'width': W, 'height': H, 'data': [CF] * 16},
                {'name': 'objects', 'type': 'objectgroup', 'objects': [
                    {'id': 1, 'name': 'spawn_a', 'type': 'spawn', 'x': 24, 'y': 24, 'point': True,
                     'properties': [{'name': 'public', 'type': 'bool', 'value': True}]}]}]}


def compile_variant(mut, name):
    m = base()
    mut(m)
    d = os.path.join(ROOT, 'maps/source')
    fd, path = tempfile.mkstemp(suffix='.tmj', dir=d)
    os.close(fd)
    try:
        json.dump(m, open(path, 'w'))
        return compile_maps.compile_map(path), None
    except compile_maps.CompileError as e:
        return None, str(e)
    finally:
        os.remove(path)


r, err = compile_variant(lambda m: None, 'ok')
check(r is not None, 'mapa mínimo válido compila')


def flips(m):
    d = m['layers'][0]['data']
    d[0] = 0                               # celda vacía
    d[1] = G | 0x80000000                  # volteo horizontal
    d[2] = G | 0x40000000 | 0x20000000     # vertical + diagonal
r, err = compile_variant(flips, 'flips')
check(r is not None and r['layers']['ground'][0, 0] == 0, 'celda vacía (GID 0) se conserva como 0')
check(r is not None and r['layers']['ground'][0, 1] == G and r['flips']['ground'][0, 1] == 4,
      'flag de volteo H separado del GID')
check(r is not None and r['flips']['ground'][0, 2] == 3, 'flags V+D separados del GID')

cases = [
    ('GID fuera de rango', lambda m: m['layers'][0]['data'].__setitem__(5, CF + 200), 'fuera'),
    ('tileset ausente', lambda m: m['tilesets'].__setitem__(0, {'firstgid': 1, 'source': 'no_existe.tsj'}), 'ausente'),
    ('tileset embebido', lambda m: m['tilesets'].__setitem__(0, {'firstgid': 1, 'name': 'x'}), 'embebido'),
    ('IDs duplicados', lambda m: m['layers'][2]['objects'].append(
        {'id': 2, 'name': 'spawn_a', 'type': 'spawn', 'x': 8, 'y': 8, 'point': True}), 'duplicado'),
    ('spawn bloqueado', lambda m: m['layers'][1]['data'].__setitem__(5, CF + 1), 'bloqueado'),
    ('mapa isométrico', lambda m: m.__setitem__('orientation', 'isometric'), 'orientación'),
    ('mapa infinito', lambda m: m.__setitem__('infinite', True), 'infinitos'),
    ('datos comprimidos', lambda m: m['layers'][0].update({'encoding': 'base64', 'compression': 'zlib'}), 'comprimidos'),
    ('objeto-tile', lambda m: m['layers'][2]['objects'].append({'id': 3, 'name': 't', 'gid': G, 'x': 0, 'y': 0}), 'objetos-tile'),
    ('elipse', lambda m: m['layers'][2]['objects'].append({'id': 4, 'name': 'e', 'ellipse': True, 'x': 0, 'y': 0}), 'elipses'),
    ('capa de imagen', lambda m: m['layers'].append({'name': 'img', 'type': 'imagelayer'}), 'imagelayer'),
    ('capa desconocida', lambda m: m['layers'].append({'name': 'rara', 'type': 'tilelayer', 'width': 4, 'height': 4, 'data': [0] * 16}), 'desconocido'),
    ('colisión con tileset visual', lambda m: m['layers'][1]['data'].__setitem__(0, G), 'solo admite'),
    ('sin capa de colisión', lambda m: m['layers'].pop(1), 'collision'),
    ('propiedad de tipo no soportado', lambda m: m['layers'][2]['objects'][0]['properties'].append(
        {'name': 'c', 'type': 'color', 'value': '#fff'}), 'no soportada'),
]
for label, mut, needle in cases:
    r, err = compile_variant(mut, label)
    check(r is None and err and needle in err, f'rechaza {label}: {err}')
    if err and os.path.basename(ROOT) in err:
        pass
# el mensaje identifica archivo y objeto
r, err = compile_variant(cases[3][1], 'dup')
check(err and '.tmj' in err and "objeto id=2" in err, 'el error identifica archivo y objeto')

print('TODAS LAS PRUEBAS DE MAPA OK' if fails == 0 else f'{fails} FALLOS')
sys.exit(1 if fails else 0)
