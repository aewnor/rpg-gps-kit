#!/usr/bin/env python3
"""Masmorra del Castell de Creixell (maps/source/masmorra_castell.tmj): escena inventada sota el castell.

Sales generades amb llavor fixa (mateixa masmorra a cada build) i unides per passadissos:
  · vestíbul amb l'entrada (porta cap al castell) i un cartell
  · sales amb enemics més forts (senglar i ratpenat foscos) i cofres de ferro i de plata
  · la sala més llunyana de l'entrada (per camí) té el cofre llegendari
Torxes a les parets (llum dinàmica: src/scenes/world_scene.lua draw_darkness). No representa cap lloc real.
"""
import json
import os
import random
from collections import deque

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
W, H = 60, 46
tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
tid = lambda n: tiles[n]['id'] + 1
COLL_FIRST = 4097
rng = random.Random(20261003)

grid = [['#'] * W for _ in range(H)]
rooms = []


def carve(x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            grid[y][x] = '.'


def overlaps(r, o, pad=2):
    return not (r[2] + pad < o[0] or o[2] + pad < r[0] or r[3] + pad < o[1] or o[3] + pad < r[1])


entry = (25, 2, 34, 8)          # vestíbul (a dalt al centre)
rooms.append(entry)
carve(*entry)
tries = 0
while len(rooms) < 8 and tries < 800:
    tries += 1
    w, h = rng.randint(7, 12), rng.randint(6, 9)
    x0, y0 = rng.randint(2, W - w - 3), rng.randint(11, H - h - 3)
    r = (x0, y0, x0 + w - 1, y0 + h - 1)
    if any(overlaps(r, o) for o in rooms):
        continue
    rooms.append(r)
    carve(*r)


def center(r):
    return ((r[0] + r[2]) // 2, (r[1] + r[3]) // 2)


# passadissos en L de 2 de gruix: cada sala amb la més propera ja connectada (arbre) + un parell de dreceres
connected = [0]
for i in sorted(range(1, len(rooms)), key=lambda k: center(rooms[k])[1]):
    j = min(connected, key=lambda k: abs(center(rooms[k])[0] - center(rooms[i])[0]) + abs(center(rooms[k])[1] - center(rooms[i])[1]))
    (ax, ay), (bx, by) = center(rooms[j]), center(rooms[i])
    carve(min(ax, bx), ay, max(ax, bx), ay + 1)
    carve(bx, min(ay, by), bx + 1, max(ay, by))
    connected.append(i)
for i, j in ((1, 3), (4, 6)):
    if j < len(rooms):
        (ax, ay), (bx, by) = center(rooms[i]), center(rooms[j])
        carve(min(ax, bx), by, max(ax, bx), by + 1)
        carve(ax, min(ay, by), ax + 1, max(ay, by))

# columnes a les sales grans
for r in rooms[1:]:
    if r[2] - r[0] >= 9 and r[3] - r[1] >= 7:
        for x, y in ((r[0] + 2, r[1] + 2), (r[2] - 2, r[1] + 2), (r[0] + 2, r[3] - 2), (r[2] - 2, r[3] - 2)):
            grid[y][x] = '#'

# distància per camí des de l'entrada → sala del tresor = la més llunyana
ex, ey = 29, 3
dist = {(ex, ey): 0}
q = deque([(ex, ey)])
while q:
    x, y = q.popleft()
    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
        n = (x + dx, y + dy)
        if 0 <= n[0] < W and 0 <= n[1] < H and grid[n[1]][n[0]] == '.' and n not in dist:
            dist[n] = dist[(x, y)] + 1
            q.append(n)
order = sorted(range(1, len(rooms)), key=lambda k: dist.get(center(rooms[k]), 0))
treasure = order[-1]

# puzle (2026-10-05): el cofre llegendari queda en un nínxol tancat per una reixa al mur de dalt de la sala del
# tresor; s'obre empenyent el bloc fins a la placa. Una altra sala amaga un nínxol darrere una paret secreta.
def niche(r, need=3):
    """Columna x del mur de dalt de `r` on cap un nínxol d'1 × 2 envoltat de roca (o None)."""
    cx = (r[0] + r[2]) // 2
    for x in sorted(range(r[0] + 1, r[2]), key=lambda v: abs(v - cx)):
        if r[1] - need < 0:
            return None
        if all(grid[y][xx] == '#' for y in range(r[1] - need, r[1]) for xx in (x - 1, x, x + 1)):
            return x
    return None


puzzle_objs, reserved = [], set()
tr = rooms[treasure]
nx = niche(tr)
if nx is not None:
    carve(nx, tr[1] - 2, nx, tr[1] - 1)
    ty = (tr[1] + tr[3]) // 2
    if grid[ty][tr[0] + 2] == '#':
        ty += 1
    bx, px = tr[0] + 2, tr[2] - 2
    puzzle_objs += [('bloc_tresor', 'block', bx, ty, {}), ('placa_tresor', 'plate', px, ty, {'flag': 'masmorra_placa'}),
                    ('reixa_tresor', 'gate', nx, tr[1] - 1, {'open_flag': 'masmorra_placa'}),
                    ('sign_tresor', 'sign', tr[0] + 1, tr[1], {'say': "El tresor del castell dorm darrere la reixa."
                                                                      "|Una placa al terra espera el pes d'una pedra."})]
    reserved |= {(bx, ty), (px, ty), (bx - 1, ty), (bx + 1, ty), (nx, tr[1])}
secret_room = next((ri for ri in order[1:-1] if niche(rooms[ri]) is not None), None)
if secret_room is not None:
    sr = rooms[secret_room]
    sx = niche(sr)
    carve(sx, sr[1] - 2, sx, sr[1] - 1)
    puzzle_objs += [('paret_masmorra', 'secret', sx, sr[1] - 1,
                     {'flag': 'masmorra_secret', 'say': "Aquesta pedra sona buida... S'enfonsa i hi ha un amagatall!"}),
                    ('cofre_amagat', 'chest', sx, sr[1] - 2, {'tier': 'silver', 'flag': 'cofre_masmorra_amagat'})]
    reserved |= {(sx, sr[1])}

ground, structures, coll = [], [], []
for y in range(H):
    for x in range(W):
        if grid[y][x] == '.':
            ground.append(tid(f'g_cobble_{(x * 5 + y * 3) % 3}'))
            structures.append(0)
            coll.append(COLL_FIRST + 0)
        else:
            ground.append(tid(f'g_cave_{(x + y) % 3}'))
            m = 0
            for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0))):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < W and 0 <= yy < H) or grid[yy][xx] == '#':
                    m |= bit
            near_floor = any(0 <= x + dx < W and 0 <= y + dy < H and grid[y + dy][x + dx] == '.'
                             for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            structures.append(tid(f'w_stone_{m}') if near_floor else 0)
            coll.append(COLL_FIRST + 1)

oid = [0]


def obj(name, typ, x, y, w=0, h=0, point=False, **p):
    oid[0] += 1
    o = {'id': oid[0], 'name': name, 'type': typ, 'x': x * 16 + (8 if point else 0),
         'y': y * 16 + (8 if point else 0), 'width': w * 16, 'height': h * 16, 'rotation': 0, 'visible': True,
         'properties': [{'name': k, 'type': 'bool' if isinstance(v, bool) else 'int' if isinstance(v, int)
                         else 'string', 'value': v} for k, v in p.items()]}
    if point:
        o['point'] = True
    return o


carve(29, 1, 30, 1)
objects = [
    obj('spawn_entrance', 'spawn', 29, 4, point=True, public=True),
    obj('door_exit', 'door', 29, 1, 2, 1, target_scene='overworld', target_spawn='spawn_castell_door',
        return_spawn='spawn_entrance'),
    obj('sign_masmorra', 'sign', 26, 3, 1, 1, text='dungeon_sign'),
]
free = lambda x, y: grid[y][x] == '.'
n_enemy = 0
for k, ri in enumerate(order):
    r = rooms[ri]
    cx, cy = center(r)
    deep = k >= len(order) // 2
    for e in range(2 if ri != treasure else 3):
        x, y = rng.randint(r[0] + 1, r[2] - 1), rng.randint(r[1] + 1, r[3] - 1)
        if free(x, y) and (x, y) not in reserved:
            n_enemy += 1
            kind = 'boar_dark' if (e + k) % 2 == 0 or ri == treasure else 'bat_dark'
            objects.append(obj(f'enemic_{n_enemy}', 'enemy', x, y, point=True, kind=kind,
                               patrol='h' if e % 2 == 0 else 'v', range=2, room=f'sala_{ri}'))
    tier = 'legend' if ri == treasure else ('silver' if k == len(order) - 2 else ('iron' if k in (1, 3) else None))
    if tier:
        chx, chy = (nx, r[1] - 2) if ri == treasure and nx is not None else (cx, r[1] + 1)
        objects.append(obj(f'cofre_masmorra_{ri}', 'chest', chx, chy, 1, 1, tier=tier, flag=f'cofre_masmorra_{ri}'))
    for tx, ty in ((r[0], r[1]), (r[2], r[1])):   # torxes als racons de dalt
        objects.append(obj(f'torxa_{ri}_{tx}', 'torch', tx, ty, point=True))
for name, typ, x, y, props in puzzle_objs:
    objects.append(obj(name, typ, x, y, 1, 1, **props))
for x, y in ((26, 2), (33, 2)):
    objects.append(obj(f'torxa_v_{x}', 'torch', x, y, point=True))

tmj = {'type': 'map', 'version': '1.10', 'tiledversion': '1.10.2', 'orientation': 'orthogonal',
       'renderorder': 'right-down', 'infinite': False, 'width': W, 'height': H, 'tilewidth': 16, 'tileheight': 16,
       'nextlayerid': 6, 'nextobjectid': oid[0] + 1, 'compressionlevel': -1,
       'properties': [{'name': 'scene', 'type': 'string', 'value': 'masmorra_castell'},
                      {'name': 'dark', 'type': 'bool', 'value': True},
                      {'name': 'fictional', 'type': 'bool', 'value': True}],
       'tilesets': [{'firstgid': 1, 'source': 'tiles.tsj'}, {'firstgid': COLL_FIRST, 'source': 'collision.tsj'}],
       'layers': [
           {'id': 1, 'name': 'ground', 'type': 'tilelayer', 'width': W, 'height': H, 'x': 0, 'y': 0, 'opacity': 1,
            'visible': True, 'data': ground},
           {'id': 2, 'name': 'structures', 'type': 'tilelayer', 'width': W, 'height': H, 'x': 0, 'y': 0,
            'opacity': 1, 'visible': True, 'data': structures},
           {'id': 3, 'name': 'collision', 'type': 'tilelayer', 'width': W, 'height': H, 'x': 0, 'y': 0,
            'opacity': .6, 'visible': False, 'data': coll},
           {'id': 4, 'name': 'objects', 'type': 'objectgroup', 'draworder': 'topdown', 'x': 0, 'y': 0,
            'opacity': 1, 'visible': True, 'objects': objects},
       ]}
with open(os.path.join(ROOT, 'maps/source/masmorra_castell.tmj'), 'w') as f:
    json.dump(tmj, f, separators=(',', ':'))
unreached = sum(1 for r in rooms if center(r) not in dist)
print(f'masmorra_castell.tmj ok: {len(rooms)} sales, {n_enemy} enemics, tresor a la sala {treasure}, '
      f'{unreached} sales sense camí, puzle {"sí" if nx is not None else "NO"}, '
      f'secret {"sí" if secret_room is not None else "NO"}')

# Les profunditats del Cucurull (tools/make_tower.py): també aquí, perquè `make maps` la generi
import runpy  # noqa: E402
runpy.run_path(os.path.join(os.path.dirname(os.path.abspath(__file__)), 'make_tower.py'), run_name='__main__')
