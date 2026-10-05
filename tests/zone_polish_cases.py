"""Zones revisades del mapa (python3 tests/zone_polish_cases.py): cofres amagats i objectes de racó on es pot arribar,
la platja i les places decorades i res enganxat als punts d'inici. Llegeix maps/source/overworld.tmj."""
import json, os, sys
import numpy as np
ROOT = os.path.join(os.path.dirname(__file__), '..')
sys.path.insert(0, os.path.join(ROOT, 'tools'))
import walkgraph

RODA = json.load(open(os.path.join(ROOT, 'data/world.json'))).get('name') in (None, 'Roda de Berà')   # (cofres i platja de Roda)
m = json.load(open(os.path.join(ROOT, 'maps/source/overworld.tmj')))
W, H = m['width'], m['height']
L = {l['name']: l for l in m['layers']}
cf = m['tilesets'][1]['firstgid']
coll = np.array(L['collision']['data'], np.int64).reshape(H, W)
coll = np.where(coll > 0, coll - cf, 0)
st = np.array(L['structures']['data'], np.int64).reshape(H, W) & 0x1FFFFFFF
tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
gid = {n: t['id'] + 1 for n, t in tiles.items()}
objs = [o for l in m['layers'] if l['type'] == 'objectgroup' for o in l['objects']]
comp = walkgraph.components_fast(coll.astype(np.uint8))[0]
sp = next(o for o in objs if o['name'] == 'spawn_public_centre')
main_c = comp[int(sp['y'] // 16), int(sp['x'] // 16)]


def reachable(x, y):
    """La casella o una veïna és de la zona principal (els cofres són sòlids: s'obren des del costat)."""
    return any(0 <= x + dx < W and 0 <= y + dy < H and comp[y + dy, x + dx] == main_c
               for dx, dy in ((0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)))


chests = [o for o in objs if o['type'] == 'chest' and o['name'].startswith('cofre_') and not o['name'].startswith('cofre_fusta')]
names = {o['name'] for o in chests}
for flag in () if not RODA else ('cofre_arc', 'cofre_port', 'cofre_roc', 'cofre_bosc', 'cofre_silena', 'cofre_sant_bartomeu'):
    assert flag in names, f'falta {flag}'
for o in chests:
    assert reachable(int(o['x'] // 16), int(o['y'] // 16)), f'{o["name"]} no és accessible'
print(f'OK   {len(chests)} cofres amagats, tots accessibles')

hidden = [o for o in objs if o['type'] == 'pickup' and o['name'].startswith('amagat_')]
assert len(hidden) >= (15 if RODA else 3), len(hidden)
for o in hidden:
    assert o['name'].isascii(), o['name']
    assert reachable(int(o['x'] // 16), int(o['y'] // 16)), f'{o["name"]} no és accessible'
print(f'OK   {len(hidden)} objectes amagats a places i monuments, accessibles i amb nom ASCII')

count = lambda *ns: int(sum((st == gid[n]).sum() for n in ns))
assert not RODA or count('o_lifeguard') >= 5 and count('o_shower') >= 5 and count('o_umbrella_0', 'o_umbrella_1', 'o_umbrella_2') >= 60
print('OK   platja amb socorristes, dutxes i para-sols')
assert not RODA or count('o_statue') >= 3 and count('o_info') >= 8 and count('o_planter') >= 5
print('OK   places i monuments amb estàtua, panell i jardineres')

polish = {gid[n] for n in tiles if n.startswith(('o_umbrella', 'o_lounger', 'o_lifeguard', 'o_shower', 'o_icecream',
                                                  'o_sandcastle', 'o_statue', 'o_info', 'o_planter', 'o_terrace',
                                                  'o_bike_rack'))}
for o in objs:
    if o['type'] != 'spawn':
        continue
    x, y = int(o['x'] // 16), int(o['y'] // 16)
    near = st[max(0, y - 2):y + 3, max(0, x - 2):x + 3]
    assert not np.isin(near, list(polish)).any(), f'objecte de zona enganxat a {o["name"]}'
print('OK   res de les zones a 2 caselles dels punts d\'inici')
# obres: estructures de formigó, grues i obrers; cap «casa solar» damunt d'un edifici en construcció
assert not RODA or count('r_skel_0', 'r_skel_1') >= 100 and count('o_crane_base') >= 3, 'obres sense estructura o sense grua'
builders = [o for o in objs if o['type'] == 'npc' and any(p['name'] == 'sprite' and p['value'].startswith('npc_builder')
                                                        for p in o.get('properties', []))]
assert not RODA or len(builders) >= 4, len(builders)
skel = np.isin(st, [gid['r_skel_0'], gid['r_skel_1']])
for o in objs:
    if o['type'] == 'solar_house':
        x, y = int(o['x'] // 16), int(o['y'] // 16)
        assert not skel[max(0, y - 3):y + 1, max(0, x - 2):x + 3].any(), f'casa solar en obres a {x},{y}'
for o in objs:
    if o['type'] == 'chest' and o['name'].startswith('cofre_obra_'):
        assert reachable(int(o['x'] // 16), int(o['y'] // 16)), o['name']
print(f'OK   obres: estructures, grues i {len(builders)} obrers; cofres d\'obra accessibles')
print('TOTES LES PROVES DE ZONES OK')
