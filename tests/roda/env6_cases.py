#!/usr/bin/env python3
"""Fase 6, mapa de col·lisions (python3 tests/env6_cases.py): escoles i Parc de la Silena reconstruïts per
satèl·lit, tanques de les parcel·les i entrades de la cova i del cau. Les tanques són sòlides; les pistes, el
pati i els mini-carrers són transitables i connectats amb el carrer; les portes de les tanques es poden passar."""
import json
import os

import numpy as np
from scipy import ndimage as nd

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
m = json.load(open(os.path.join(ROOT, 'maps/source/overworld.tmj')))
W, H = m['width'], m['height']
tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
name_of = {t['id'] + 1: n for n, t in tiles.items()}
L = {l['name']: l for l in m['layers']}
cf = next(ts['firstgid'] for ts in m['tilesets'] if 'collision' in ts['source'])
coll = np.array(L['collision']['data'], np.int64).reshape(H, W)
coll = np.where(coll > 0, coll - cf, 0) & 3
walk = coll == 0
lab, _ = nd.label(walk)
sizes = np.bincount(lab.ravel()); sizes[0] = 0
main = lab == sizes.argmax()
# abans de decorar (overworld.raw.json): el que ja era accessible ho ha de continuar sent
raw = json.load(open(os.path.join(ROOT, 'maps/source/overworld.raw.json')))
rl = {l['name']: l for l in raw['layers']}
c0 = np.array(rl['collision']['data'], np.int64).reshape(H, W)
c0 = np.where(c0 > 0, c0 - cf, 0) & 3
lab0, _ = nd.label(c0 == 0)
s0 = np.bincount(lab0.ravel()); s0[0] = 0
main0 = lab0 == s0.argmax()
names = {}
for layer in ('ground', 'ground_detail', 'structures'):
    a = np.array(L[layer]['data'], np.int64).reshape(H, W) & 0x1FFFFFFF
    names[layer] = a
objs = [o for l in m['layers'] if l['type'] == 'objectgroup' for o in l['objects']]

fails = 0


def check(c, msg):
    global fails
    print(('OK   ' if c else 'FAIL ') + msg)
    if not c:
        fails += 1


def cells_named(layer, prefixes):
    ids = [gid for gid, n in name_of.items() if n.startswith(prefixes)]
    return np.isin(names[layer], ids)


fence = cells_named('structures', ('o_mesh_', 'o_wall_', 'o_wood_'))
check(fence.sum() > 1000, f'tanques i murs al mapa ({int(fence.sum())} cel·les)')
check(bool((coll[fence] != 0).all()), 'totes les tanques i murs són sòlids al mapa de col·lisions')
for prefix, label in ((('g_court_red', 'g_court_green'), 'pistes vermelles i verdes'), (('g_yard_',), 'pati'),
                      (('g_miniroad', 'g_minizebra'), 'mini-carrers del Parc de la Silena')):
    c = cells_named('ground', prefix) & ~cells_named('structures', ('o_', 'f_', 'w_'))
    n = int(c.sum())
    was = c & main0      # (els patis interiors tancats per edificis ja ho eren a l'OSM)
    reach = int((was & main).sum())
    check(n > 0 and (c & walk).sum() == n, f'{label}: {n} cel·les transitables')
    check(reach == int(was.sum()), f'{label}: {reach}/{int(was.sum())} accessibles abans continuen connectades amb el carrer')
schools = [o for o in objs if o['type'] == 'school']
check(len(schools) >= 3, f'escoles reconstruïdes ({len(schools)})')
# portes de les tanques de les escoles: hi ha pas entre dins i fora
mesh = cells_named('structures', ('o_mesh_',))
lab_m, _ = nd.label(mesh)
check(int(lab_m.max()) >= len(schools), 'cada escola té el seu tancat')
# entrades de la cova i del cau: roca sòlida, boca transitable, davant connectat
for sid in ('cova_roda', 'cau_drac'):
    d = next((o for o in objs if o['type'] == 'door' and o['name'] == 'door_' + sid), None)
    check(d is not None, f'porta {sid}')
    if d:
        x, y = int(d['x'] // 16), int(d['y'] // 16)
        rocks = [(x - 1, y), (x + 1, y), (x - 1, y - 1), (x, y - 1), (x + 1, y - 1)]
        check(all(coll[ry, rx] != 0 for rx, ry in rocks) and coll[y, x] == 0, f'{sid}: roca sòlida i boca transitable')
        check(bool(main[y + 1, x]), f'{sid}: davant de la boca, connectat amb el poble')
print('TOTES LES PROVES DEL MAPA (FASE 6) OK' if fails == 0 else f'{fails} FALLADES')
raise SystemExit(1 if fails else 0)
