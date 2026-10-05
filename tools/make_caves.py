#!/usr/bin/env python3
"""Genera la escena ficticia «Cova de la Pedrera» como mapa Tiled (maps/source/cova_pedrera.tmj).

Tres salas: aprendizaje (cartel + palanca), combate (enemigos; la reja se abre al vencerlos)
y recompensa (cofre). No representa ninguna cavidad real.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
W, H = 40, 32
tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
tid = lambda n: tiles[n]['id'] + 1
COLL_FIRST = 4097  # mismo firstgid fijo que import_osm.py

grid = [['#'] * W for _ in range(H)]


def carve(x0, y0, x1, y1):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            grid[y][x] = '.'


carve(3, 18, 12, 27)    # sala 1: aprendizaje
carve(7, 28, 8, 30)     # salida
carve(13, 22, 16, 23)   # pasillo 1 → 2 (reja)
carve(17, 14, 36, 27)   # sala 2: combate
carve(25, 9, 26, 13)    # pasillo 2 → 3 (reja)
carve(18, 2, 33, 8)     # sala 3: recompensa
for x, y in ((20, 18), (21, 18), (30, 20), (31, 21), (24, 25)):  # columnas de roca
    grid[y][x] = '#'

ground, structures, coll = [], [], []
for y in range(H):
    for x in range(W):
        c = grid[y][x]
        if c == '.':
            ground.append(tid(f'g_cavefloor_{(x * 7 + y * 3) % 3}'))
            structures.append(0)
            coll.append(COLL_FIRST + 0)
        else:
            ground.append(tid(f'g_cave_{(x + y) % 3}'))
            m = 0
            for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0))):
                xx, yy = x + dx, y + dy
                if not (0 <= xx < W and 0 <= yy < H) or grid[yy][xx] == '#':
                    m |= bit
            # solo dibujar pared donde toca suelo (el resto es oscuridad)
            near_floor = any(0 <= x + dx < W and 0 <= y + dy < H and grid[y + dy][x + dx] == '.'
                             for dx in (-1, 0, 1) for dy in (-1, 0, 1))
            structures.append(tid(f'w_cliff_{m}') if near_floor else 0)
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


objects = [
    obj('spawn_entrance', 'spawn', 7, 26, point=True, public=True),
    obj('door_exit', 'door', 7, 29, 2, 1, target_scene='overworld', target_spawn='spawn_pedrera_door',
        return_spawn='spawn_entrance'),
    obj('sign_cave', 'sign', 5, 19, 1, 1, text='cave_sign'),
    obj('lever_gate1', 'lever', 10, 19, 1, 1, flag='cova_lever'),
    obj('gate1', 'gate', 14, 22, 1, 2, open_flag='cova_lever'),
    obj('boar_1', 'enemy', 28, 17, point=True, kind='boar', patrol='h', range=5, room='combat'),
    obj('boar_2', 'enemy', 22, 24, point=True, kind='boar', patrol='v', range=3, room='combat'),
    obj('bat_1', 'enemy', 33, 24, point=True, kind='bat', patrol='h', range=3, room='combat'),
    obj('gate2', 'gate', 25, 11, 2, 1, open_room_clear='combat'),
    obj('chest_sword', 'chest', 25, 4, 1, 1, item='sword_bera', flag='cova_chest'),
    obj('room_combat', 'room', 17, 14, 20, 14, room='combat'),
    # cofres per categoria (data/loot.json) i torxes (llum dinàmica)
    obj('cofre_cova_ferro', 'chest', 35, 26, 1, 1, tier='iron', flag='cofre_cova_ferro'),
    obj('cofre_cova_plata', 'chest', 31, 3, 1, 1, tier='silver', flag='cofre_cova_plata'),
] + [obj(f'torxa_{i}', 'torch', x, y, point=True) for i, (x, y) in
     enumerate(((4, 18), (11, 18), (18, 14), (35, 14), (19, 2), (32, 2), (26, 14)))]
tmj = {'type': 'map', 'version': '1.10', 'tiledversion': '1.10.2', 'orientation': 'orthogonal',
       'renderorder': 'right-down', 'infinite': False, 'width': W, 'height': H, 'tilewidth': 16, 'tileheight': 16,
       'nextlayerid': 6, 'nextobjectid': oid[0] + 1, 'compressionlevel': -1,
       'properties': [{'name': 'scene', 'type': 'string', 'value': 'cova_pedrera'},
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
with open(os.path.join(ROOT, 'maps/source/cova_pedrera.tmj'), 'w') as f:
    json.dump(tmj, f, separators=(',', ':'))
print('cova_pedrera.tmj ok')


# ------------------------------------------------------------------------------------------------------------
# Fase 6: Cova de Roda (boca a les coordenades reals 41.1843924, 1.4402913; l'interior és inventat): tres
# nivells que baixen per escales de corda, cada cop més foscos (menys torxes), i al fons el Bastó màgic i el
# Cristall del Drac. I el Cau del Drac, l'arena del cim. Galeries sinuoses amb llavor fixa (sempre iguals).
# ------------------------------------------------------------------------------------------------------------
import random  # noqa: E402
from collections import deque  # noqa: E402


def cave_grid(seed, W, H, waypoints, chambers, width=1):
    rng = random.Random(seed)
    g = [['#'] * W for _ in range(H)]

    def disc(cx, cy, r):
        for y in range(cy - r, cy + r + 1):
            for x in range(cx - r, cx + r + 1):
                if 2 <= x < W - 2 and 2 <= y < H - 2 and (x - cx) ** 2 + (y - cy) ** 2 <= r * r + 1:
                    g[y][x] = '.'

    for (ax, ay), (bx, by) in zip(waypoints, waypoints[1:]):   # camí sinuós entre punts de pas
        x, y = ax, ay
        guard = 0
        while (x, y) != (bx, by) and guard < 4000:
            guard += 1
            if rng.random() < 0.68:
                if abs(bx - x) > abs(by - y) or (abs(bx - x) == abs(by - y) and rng.random() < .5):
                    x += (bx > x) - (bx < x)
                else:
                    y += (by > y) - (by < y)
            else:
                dx, dy = rng.choice(((1, 0), (-1, 0), (0, 1), (0, -1)))
                x, y = min(W - 4, max(3, x + dx)), min(H - 4, max(3, y + dy))
            disc(x, y, width + (1 if rng.random() < .25 else 0))
    for cx, cy, rx, ry in chambers:                       # sales
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                n = ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2
                if n <= 1 + rng.random() * 0.25 and 2 <= x < W - 2 and 2 <= y < H - 2:
                    g[y][x] = '.'
    for _ in range(2):                                    # suavitzar: només s'obre roca (no desconnecta)
        add = []
        for y in range(2, H - 2):
            for x in range(2, W - 2):
                if g[y][x] == '#':
                    n = sum(g[y + dy][x + dx] == '.' for dy in (-1, 0, 1) for dx in (-1, 0, 1))
                    if n >= 6:
                        add.append((x, y))
        for x, y in add:
            g[y][x] = '.'
    return g, rng


def connected(g, start):
    H, W = len(g), len(g[0])
    seen = {start}
    q = deque([start])
    while q:
        x, y = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if 0 <= p[0] < W and 0 <= p[1] < H and p not in seen and g[p[1]][p[0]] == '.':
                seen.add(p); q.append(p)
    return seen


def cave_layers(g, seed):
    H, W = len(g), len(g[0])
    ground, structures, coll = [], [], []
    for y in range(H):
        for x in range(W):
            if g[y][x] == '.':
                ground.append(tid(f'g_cavefloor_{(x * 7 + y * 3 + seed) % 3}'))
                structures.append(0)
                coll.append(COLL_FIRST + 0)
            else:
                ground.append(tid(f'g_cave_{(x + y) % 3}'))
                m = 0
                for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0))):
                    xx, yy = x + dx, y + dy
                    if not (0 <= xx < W and 0 <= yy < H) or g[yy][xx] == '#':
                        m |= bit
                near_floor = any(0 <= x + dx < W and 0 <= y + dy < H and g[y + dy][x + dx] == '.'
                                 for dx in (-1, 0, 1) for dy in (-1, 0, 1))
                structures.append(tid(f'w_cliff_{m}') if near_floor else 0)
                coll.append(COLL_FIRST + 1)
    return ground, structures, coll


def write_scene(scene, g, seed, objects, extra_structs=(), props=()):
    H, W = len(g), len(g[0])
    ground, structures, coll = cave_layers(g, seed)
    for x, y, name in extra_structs:
        structures[y * W + x] = tid(name)
        coll[y * W + x] = COLL_FIRST + 0
    tmj = {'type': 'map', 'version': '1.10', 'tiledversion': '1.10.2', 'orientation': 'orthogonal',
           'renderorder': 'right-down', 'infinite': False, 'width': W, 'height': H, 'tilewidth': 16, 'tileheight': 16,
           'nextlayerid': 6, 'nextobjectid': max(o['id'] for o in objects) + 1, 'compressionlevel': -1,
           'properties': [{'name': 'scene', 'type': 'string', 'value': scene},
                          {'name': 'dark', 'type': 'bool', 'value': True},
                          {'name': 'fictional', 'type': 'bool', 'value': True}] + list(props),
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
    with open(os.path.join(ROOT, f'maps/source/{scene}.tmj'), 'w') as f:
        json.dump(tmj, f, separators=(',', ':'))


def torch_spots(g, path_cells, n, rng, avoid):
    """torxes a terra al costat d'una paret, repartides pel recorregut"""
    cand = [(x, y) for x, y in path_cells if any(g[y + dy][x + dx] == '#' for dx, dy in ((1, 0), (-1, 0), (0, -1)))]
    cand = [c for c in cand if all((c[0] - a[0]) ** 2 + (c[1] - a[1]) ** 2 > 9 for a in avoid)]
    cand.sort(key=lambda c: (c[0] * 31 + c[1] * 17) % 97)
    out = []
    for c in cand:
        if len(out) >= n:
            break
        if all((c[0] - o[0]) ** 2 + (c[1] - o[1]) ** 2 > 64 for o in out):
            out.append(c)
    return out


LEVELS = [
    # escena, llavor, mida, punts de pas, sales, torxes, enemics (tipus, quantitat), cofres
    dict(scene='cova_roda_1', seed=101, W=48, H=36, way=[(5, 31), (14, 22), (26, 26), (33, 14), (42, 5)],
         rooms=[(14, 22, 5, 4), (33, 14, 5, 4)], torches=7, enemies=[('bat', 3), ('boar', 1)],
         chests=[dict(tier='iron', flag='cofre_cova_roda_1')], sign='cova_roda_sign'),
    dict(scene='cova_roda_2', seed=202, W=52, H=40, way=[(42, 5), (30, 12), (14, 10), (10, 26), (26, 30), (45, 34)],
         rooms=[(30, 12, 5, 4), (10, 26, 4, 5), (26, 30, 6, 4)], torches=5, enemies=[('bat_dark', 3), ('boar_dark', 2)],
         chests=[dict(tier='silver', flag='cofre_cova_roda_2')]),
    dict(scene='cova_roda_3', seed=303, W=44, H=36, way=[(22, 31), (12, 24), (20, 16), (30, 18), (22, 8)],
         rooms=[(12, 24, 4, 3), (22, 8, 9, 5)], torches=4, enemies=[('bat_dark', 3), ('boar_dark', 2)],
         chests=[dict(tier='legend', item='baston_magic', flag='cova_roda_baston'),
                 dict(tier='legend', item='cristall_drac', flag='cova_roda_cristall')]),
]


def make_level(i, L):
    oid[0] = 0
    g, rng = cave_grid(L['seed'], L['W'], L['H'], L['way'], L['rooms'])
    (sx, sy), (ex, ey) = L['way'][0], L['way'][-1]
    reach = connected(g, (sx, sy))
    assert (ex, ey) in reach, L['scene']
    up_target = ('overworld', 'spawn_cova_roda_door') if i == 0 else (LEVELS[i - 1]['scene'], 'spawn_from_down')
    # escala amunt a (sx, sy): s'arriba una casella per sota (o al costat si és roca)
    # (de costat, el cos del jugador toca la porta en arribar i el torna a enviar a l'altre nivell: millor a sota o
    # a dues caselles)
    arrive = next(p for p in ((sx, sy + 1), (sx + 2, sy), (sx - 2, sy), (sx + 1, sy + 1), (sx - 1, sy + 1),
                              (sx + 1, sy), (sx - 1, sy), (sx, sy - 1)) if p in reach)
    objs = [obj('spawn_entrance', 'spawn', arrive[0], arrive[1], point=True, public=True),
            obj('spawn_from_up', 'spawn', arrive[0], arrive[1], point=True),     # (qui baixa del nivell de dalt)
            obj('door_up', 'door', sx, sy, 1, 1, target_scene=up_target[0], target_spawn=up_target[1])]
    structs = [(sx, sy, 'o_cave_ladder_up')]
    final = i == len(LEVELS) - 1
    if not final:
        down_arrive = next(p for p in ((ex, ey + 1), (ex - 2, ey), (ex + 2, ey), (ex - 1, ey + 1), (ex + 1, ey + 1),
                                       (ex - 1, ey), (ex + 1, ey), (ex, ey - 1)) if p in reach)
        objs += [obj('door_down', 'door', ex, ey, 1, 1, target_scene=LEVELS[i + 1]['scene'], target_spawn='spawn_from_up'),
                 obj('spawn_from_down', 'spawn', down_arrive[0], down_arrive[1], point=True)]   # (qui torna de baix)
        structs.append((ex, ey, 'o_cave_ladder_down'))
    # cofres a la sala del final (o la darrera sala), enemics a les sales i pel camí, torxes
    taken = {(sx, sy), (ex, ey), arrive}
    cx, cy = L['rooms'][-1][0], L['rooms'][-1][1]
    for k, ch in enumerate(L['chests']):
        p = min((c for c in reach if c not in taken and abs(c[1] - cy) <= 2 and g[c[1] - 1][c[0]] == '.'),
                key=lambda c: abs(c[0] - (cx + (k * 4 - 2 if len(L['chests']) > 1 else 0))) + abs(c[1] - (cy - 1)))
        taken.add(p)
        objs.append(obj(ch['flag'], 'chest', p[0], p[1], 1, 1, **{k2: v for k2, v in ch.items()}))
    cells = sorted(reach)
    n_en = 0
    for kind, n in L['enemies']:
        for _ in range(n):
            for _try in range(200):
                p = cells[rng.randrange(len(cells))]
                if p not in taken and (p[0] - arrive[0]) ** 2 + (p[1] - arrive[1]) ** 2 > 64:
                    break
            taken.add(p)
            n_en += 1
            objs.append(obj(f'{kind}_{n_en}', 'enemy', p[0], p[1], point=True, kind=kind,
                            patrol=rng.choice('hv'), range=rng.randint(2, 4)))
    for k, (x, y) in enumerate(torch_spots(g, cells, L['torches'], rng, list(taken))):
        objs.append(obj(f'torxa_{k}', 'torch', x, y, point=True))
    if L.get('sign'):
        p = next(c for c in ((arrive[0] + 2, arrive[1]), (arrive[0] - 2, arrive[1]), (arrive[0] + 1, arrive[1] - 1))
                 if c in reach and c not in taken)
        objs.append(obj('sign_cova_roda', 'sign', p[0], p[1], 1, 1, text=L['sign']))
    write_scene(L['scene'], g, L['seed'], objs, structs)
    print(f"{L['scene']}.tmj ok ({len(reach)} cel·les, {n_en} enemics)")


for _i, _L in enumerate(LEVELS):
    make_level(_i, _L)


# Cau del Drac: arena gran a l'interior del cim, amb torxes al voltant i el drac al mig
def make_lair():
    oid[0] = 0
    W, H = 40, 32
    g, rng = cave_grid(404, W, H, [(20, 28), (20, 22)], [(20, 14, 15, 10)])
    reach = connected(g, (20, 28))
    objs = [obj('spawn_entrance', 'spawn', 20, 27, point=True, public=True),
            obj('door_exit', 'door', 20, 28, 1, 1, target_scene='overworld', target_spawn='spawn_cau_drac_door'),
            obj('drac', 'boss', 20, 11, point=True, kind='dragon', flag='drac_vencut'),
            obj('room_drac', 'room', 6, 4, 29, 21, room='drac')]
    ring = [(round(20 + 13 * math.cos(a)), round(14 + 8.5 * math.sin(a))) for a in
            [i * math.pi / 5 for i in range(10)]]
    k = 0
    for x, y in ring:
        if (x, y) in reach:
            objs.append(obj(f'brasa_{k}', 'torch', x, y, point=True)); k += 1
    write_scene('cau_drac', g, 404, objs, [(20, 28, 'o_cave_ladder_up')])
    print(f'cau_drac.tmj ok ({len(reach)} cel·les, {k} torxes)')


import math  # noqa: E402
make_lair()
