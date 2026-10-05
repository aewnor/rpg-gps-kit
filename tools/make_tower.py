#!/usr/bin/env python3
"""Les profunditats del Cucurull (maps/source/torre_cucurull.tmj): masmorra secreta sota la Torre del Cucurull
(2026-10-05). S'hi entra per la paret de l'estrella al peu de la torre (tools/decorate_map.py cave_entrances).
Inventada i dissenyada a mà, amb puzles (src/systems/puzzles.lua):

  A  entrada: empeny el bloc fins a la placa → s'obre la reixa
  B  dues plaques i dos blocs entre columnes → reixa
  C  runes romanes I, II, III, IV en ordre → reixa cap a dalt; a l'est, la sala D
  D  ratpenats i un senglar fosc guarden el cofre amb la Clau de la torre
  E  sala de dalt: porta amb pany (la clau) cap al tresor T; dos brasers que s'encenen amb la Bola de foc obren
     l'alcova de l'oest amb un cofre llegendari (opcional)
  T  el cor de la torre: l'Amulet del Cucurull
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
W, H = 40, 41
COLL_FIRST = 4097


def main():
    tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
    tid = lambda n: tiles[n]['id'] + 1
    grid = [['#'] * W for _ in range(H)]

    def carve(x0, y0, x1, y1):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                grid[y][x] = '.'

    carve(14, 31, 25, 38)            # A
    carve(19, 39, 20, 39)            # sortida
    carve(19, 27, 20, 30)            # A → B
    carve(9, 18, 30, 26)             # B
    for x, y in ((17, 20), (22, 20), (17, 24), (22, 24), (19, 22), (20, 22)):
        grid[y][x] = '#'             # columnes
    carve(19, 14, 20, 17)            # B → C
    carve(11, 8, 28, 13)             # C
    carve(29, 10, 31, 11)            # C → D
    carve(32, 6, 38, 15)             # D
    carve(19, 7, 20, 7)              # C → E
    carve(13, 1, 26, 6)              # E
    carve(10, 3, 12, 4)              # E → alcova
    carve(2, 1, 9, 6)                # alcova dels brasers
    carve(27, 2, 30, 3)              # E → T
    carve(31, 1, 38, 4)              # T

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

    objects = [
        obj('spawn_entrance', 'spawn', 19, 37, point=True, public=True),
        obj('door_exit', 'door', 19, 39, 2, 1, target_scene='overworld', target_spawn='spawn_cucurull_door',
            return_spawn='spawn_entrance'),
        obj('sign_torre', 'sign', 15, 31, 1, 1,
            say="Les profunditats del Cucurull|Sota la torre hi ha sales antigues tancades amb reixes."
                "|Empeny el bloc de pedra fins a la placa: caminant cap al bloc, s'arrossega."),
        # A: un bloc, una placa
        obj('bloc_a', 'block', 17, 34, 1, 1),
        obj('placa_a', 'plate', 22, 32, 1, 1, flag='cucurull_p1'),
        obj('reixa_a', 'gate', 19, 30, 2, 1, open_flag='cucurull_p1'),
        # B: dues plaques, dos blocs
        obj('bloc_b1', 'block', 15, 23, 1, 1),
        obj('bloc_b2', 'block', 24, 23, 1, 1),
        obj('placa_b1', 'plate', 11, 19, 1, 1, flag='cucurull_p2a'),
        obj('placa_b2', 'plate', 28, 19, 1, 1, flag='cucurull_p2b'),
        obj('reixa_b', 'gate', 19, 17, 2, 1, open_flag='cucurull_p2a,cucurull_p2b'),
        obj('sign_b', 'sign', 10, 25, 1, 1, say="Dues plaques, dos blocs.|Si un bloc queda enganxat a la paret, "
                                                 "surt i torna a entrar: la torre els torna al seu lloc."),
        # C: runes en ordre
        obj('runa_3', 'rune', 12, 9, 1, 1, group='cucurull_runes', order=3, n=3),
        obj('runa_1', 'rune', 27, 9, 1, 1, group='cucurull_runes', order=1, n=1),
        obj('runa_4', 'rune', 12, 12, 1, 1, group='cucurull_runes', order=4, n=4),
        obj('runa_2', 'rune', 27, 12, 1, 1, group='cucurull_runes', order=2, n=2),
        obj('sign_c', 'sign', 18, 13, 1, 1, say="Els romans comptaven així: I, II, III, IV.|Toca les pedres en ordre."),
        obj('reixa_c', 'gate', 19, 7, 2, 1, open_flag='cucurull_runes'),
        # D: la clau
        obj('cofre_clau', 'chest', 37, 7, 1, 1, item='clau_torre', flag='cucurull_clau'),
        obj('enemic_d1', 'enemy', 34, 9, point=True, kind='bat_dark', patrol='h', range=2, room='torre_d'),
        obj('enemic_d2', 'enemy', 36, 13, point=True, kind='bat_dark', patrol='v', range=2, room='torre_d'),
        obj('enemic_d3', 'enemy', 33, 12, point=True, kind='boar_dark', patrol='h', range=2, room='torre_d'),
        # E: porta amb pany, brasers i alcova
        obj('porta_tresor', 'gate', 29, 2, 1, 2, open_key='clau_torre', key_flag='cucurull_porta'),
        obj('braser_a', 'brazier', 14, 2, 1, 1, flag='cucurull_braser_a'),
        obj('braser_b', 'brazier', 25, 2, 1, 1, flag='cucurull_braser_b'),
        obj('reixa_alcova', 'gate', 11, 3, 1, 2, open_flag='cucurull_braser_a,cucurull_braser_b'),
        obj('sign_e', 'sign', 16, 6, 1, 1, say="Dos brasers apagats miren l'alcova de l'oest.|Diuen que només "
                                                "la màgia del foc els pot encendre."),
        obj('enemic_e1', 'enemy', 18, 4, point=True, kind='boar_dark', patrol='h', range=3, room='torre_e'),
        obj('enemic_e2', 'enemy', 22, 2, point=True, kind='boar_dark', patrol='h', range=2, room='torre_e'),
        obj('cofre_brasers', 'chest', 4, 3, 1, 1, tier='legend', flag='cofre_cucurull_brasers'),
        # T: el tresor
        obj('cofre_amulet', 'chest', 36, 2, 1, 1, item='amulet_cucurull', flag='cucurull_amulet'),
        obj('cofre_torre_plata', 'chest', 33, 3, 1, 1, tier='silver', flag='cofre_cucurull_plata'),
    ]
    for i, (x, y) in enumerate(((14, 31), (25, 31), (9, 18), (30, 18), (11, 8), (28, 8), (32, 6), (38, 6),
                                (13, 1), (26, 1), (2, 1), (9, 1), (31, 1), (38, 1))):
        objects.append(obj(f'torxa_{i}', 'torch', x, y, point=True))

    tmj = {'type': 'map', 'version': '1.10', 'tiledversion': '1.10.2', 'orientation': 'orthogonal',
           'renderorder': 'right-down', 'infinite': False, 'width': W, 'height': H, 'tilewidth': 16, 'tileheight': 16,
           'nextlayerid': 6, 'nextobjectid': oid[0] + 1, 'compressionlevel': -1,
           'properties': [{'name': 'scene', 'type': 'string', 'value': 'torre_cucurull'},
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
    with open(os.path.join(ROOT, 'maps/source/torre_cucurull.tmj'), 'w') as f:
        json.dump(tmj, f, separators=(',', ':'))
    n_floor = sum(r.count('.') for r in grid)
    print(f'torre_cucurull.tmj ok: {n_floor} cel·les, {len(objects)} objectes')


if __name__ == '__main__':
    main()
