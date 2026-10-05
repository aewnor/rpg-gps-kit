"""El paperdoll de Lua (src/paperdoll/) dibuja exactamente los mismos píxeles que tools/chars.py y
tools/make_sprites.py: personajes del pueblo, el protagonista con sus aspectos y sus hojas de acción, bici
y vehículos (python3 tests/paperdoll_cases.py, desde la raíz del repositorio)."""
import json
import os
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, 'tools'))
os.chdir(os.path.join(ROOT, 'tools'))
import make_sprites as ms  # noqa: E402  (genera también los PNG: es idempotente)
os.chdir(ROOT)


def jsonable(spec):
    out = {}
    for k, v in spec.items():
        if isinstance(v, tuple):
            v = '#%02x%02x%02x' % v[:3]
        out[k] = v
    return out


cases = [{'id': 'player', 'spec': jsonable(ms.PLAYER), 'full': True}]
for name, spec in ms.NPCS.items():
    cases.append({'id': name, 'spec': jsonable(spec), 'full': name in ('npc_postie', 'npc_elder')})
for sk in json.load(open(os.path.join(ROOT, 'data/skins.json')))['skins']:
    if sk['id'] == 'default':
        continue
    cols = ms.spec_of(sk['colors'], sk.get('hat'), sk.get('hair'), sk.get('outfit'), sk.get('extra'))
    cases.append({'id': 'skin_' + sk['id'], 'spec': jsonable(cols), 'full': sk['id'] in ('nena', 'pirate')})

with tempfile.NamedTemporaryFile('w', suffix='.json', delete=False) as f:
    json.dump(cases, f)
    path = f.name
res = subprocess.run(['luajit', 'tools/paperdoll_dump.lua', path], capture_output=True, text=True, cwd=ROOT)
os.unlink(path)
if res.returncode:
    print(res.stderr)
    sys.exit(1)
lua = {}
for line in res.stdout.split('\n'):
    if line.strip():
        i, kind, w, h, hx = line.split('\t')
        lua[(i, kind)] = (int(w), int(h), bytes.fromhex(hx))

fails = 0
checked = 0
for c in cases:
    src = ms.PLAYER if c['id'] == 'player' else ms.NPCS.get(c['id'], c['spec'])
    want = {'walk': ms.character(src)}
    if c['full']:
        want['action'] = ms.action_sheet(src)
        want['bike'] = ms.bike_sheet(src)
        for v in ('patinete', 'scooter', 'motocross'):
            want[v] = ms.vehicle_sheet(src, v)
    for kind, spr in want.items():
        got = lua.get((c['id'], kind))
        ok = got is not None and got[0] == spr.w and got[1] == spr.h and got[2] == spr.a.tobytes()
        checked += 1
        if not ok:
            fails += 1
            diff = '?'
            if got and got[0] == spr.w and got[1] == spr.h:
                import numpy as np
                g = np.frombuffer(got[2], np.uint8).reshape(spr.h, spr.w, 4)
                d = np.argwhere((g != spr.a).any(axis=2))
                diff = f'{len(d)} píxeles distintos, p. ej. (x={d[0][1]}, y={d[0][0]}) lua={tuple(g[d[0][0], d[0][1]])} py={tuple(spr.a[d[0][0], d[0][1]])}'
            print(f'FAIL {c["id"]} {kind}: {diff}')
print(f'{checked} hojas comparadas')
print('TODAS LAS PRUEBAS DEL PAPERDOLL OK' if fails == 0 else f'{fails} FALLOS')
sys.exit(1 if fails else 0)
