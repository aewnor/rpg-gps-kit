#!/usr/bin/env python3
"""Valida mapas y contenido. Sale con código 1 si algo falla.

Comprobaciones:
  - cada .tmj compila (GID/tileset ausente, IDs duplicados, spawn bloqueado, características no soportadas)
  - rutas peatonales por niveles entre el spawn público y los POI del recorrido inicial
  - ningún cruce a distinto nivel crea una conexión: no hay rampas donde se solapan vías que se cruzan
    sin compartir nodo, y autopista/vías férreas no son transitables en el nivel 0 salvo pasos a nivel
  - costa cerrada: el mar es una sola región conexa que toca el borde sur
  - las tres redes ferroviarias son rutas distintas sin vértices compartidos
  - diálogos/textos referenciados por objetos existen en data/dialogue.json
  - campañas de misiones (data/missions.json): pasos, objetivos, objetos y escenas existen (tools/campaigns.py)
"""
import json
import os
import sys
from collections import deque

import numpy as np

import compile_maps
import walkgraph

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
ROUTE_INITIAL = ['arc_de_bera', 'roc_sant_gaieta', 'ermita_bera']
ROUTE_BRANCH = ['pedrera_elies', 'cucurull']
# interiors que el joc genera per a les portes dels monuments (src/world/procgen.lua POI_SIZE)
POI_KINDS = {'church', 'chapel', 'library', 'townhall', 'clinic', 'police', 'post', 'station'}
# lloc nou (tools/new_location.py): les comprovacions pròpies de Roda de Berà (monuments, les tres línies de tren,
# la Cova de la Pedrera, el mar al sud) no hi apliquen
_WORLD = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'data', 'world.json')))
RODA = _WORLD.get('name') in (None, 'Roda de Berà')
OTHERS = ['sant_bartomeu', 'roda_de_mar', 'mirador_morella', 'ajuntament', 'biblioteca', 'castell_creixell']


def main():
    errors, info = [], {}
    maps = {}
    src = os.path.join(ROOT, 'maps/source')
    for p in sorted(os.listdir(src)):
        if p.endswith('.tmj'):
            try:
                maps[p] = compile_maps.compile_map(os.path.join(src, p))
            except compile_maps.CompileError as e:
                errors.append(str(e))
    ow = maps.get('overworld.tmj')
    if ow is None:
        errors.append('overworld.tmj no compila')
        return finish(errors, info)

    coll = ow['coll']
    objs = {(o['type'], o['name']): o for o in ow['objects']}
    spawn = objs[('spawn', 'spawn_public_centre')]
    start = (int(spawn['x'] // 16), int(spawn['y'] // 16), 0)

    # --- rutas peatonales entre POI (misma componente del grafo celda×nivel) ---------
    comps = walkgraph.components_fast(coll)
    c0 = comps[0][start[1], start[0]]

    def reach(x, y):
        return any(comps[lv][y, x] == c0 and c0 for lv in comps)
    routes = {}
    for pid in (ROUTE_INITIAL + ROUTE_BRANCH + OTHERS if RODA else list(_WORLD.get('pois', []))):
        o = objs.get(('poi', pid))
        if not o:
            errors.append(f'POI {pid} sin colocar')
            continue
        gx, gy = int(o['x'] // 16), int(o['y'] // 16)
        ok = reach(gx, gy)
        routes[pid] = {'reachable': bool(ok)}
        if not ok:
            errors.append(f'sin ruta peatonal: spawn_public_centre → {pid}')
    info['pedestrian_routes'] = routes
    info['components_l0'] = int(len(np.unique(comps[0])) - 1)

    # --- cruces a distinto nivel ------------------------------------------------------
    sem = np.load(os.path.join(ROOT, 'maps/source/semantic.npz'))
    d0, d1, dm1 = sem['d0'], sem['d1'], sem['dm1']
    import semantic as S
    blocked0 = np.isin(d0, [S.D['MOTORWAY'], S.D['RAIL'], S.D['RAIL_HS']])
    leak = blocked0 & ((coll & 3) == 0) & ((coll & 32) == 0)
    if leak.any():
        ys, xs = np.nonzero(leak)
        errors.append(f'{leak.sum()} celdas de autopista/vía transitables a nivel 0, p. ej. ({xs[0]},{ys[0]})')
    ramps = (coll & 16) > 0
    # una rampa no puede estar donde el tablero/túnel se superpone con otra vía del nivel 0
    overlap_up = (d1 > 0) & (d0 > 0) & ~np.isin(d0, list(S.WALKABLE_DETAIL))
    overlap_dn = (dm1 > 0) & (d0 > 0) & ~np.isin(d0, list(S.WALKABLE_DETAIL))
    bad = ramps & (overlap_up | overlap_dn)
    if bad.any():
        ys, xs = np.nonzero(bad)
        errors.append(f'{bad.sum()} rampas sobre cruces a distinto nivel, p. ej. ({xs[0]},{ys[0]})')
    # pasar de un tablero a lo que cruza por debajo solo es posible por rampas
    false_links = 0
    H, W = coll.shape
    for y, x in zip(*np.nonzero((coll & 4) > 0)):
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < W and 0 <= ny < H:
                nl = walkgraph.step(coll, x, y, 1, nx, ny)
                if nl == 0 and not (coll[y, x] & 16 or coll[ny, nx] & 16):
                    false_links += 1
    if false_links:
        errors.append(f'{false_links} transiciones nivel 1 → 0 fuera de rampas')
    info['ramps'] = int(ramps.sum())
    info['grade_separated_cells'] = int(((d1 > 0) & (d0 > 0)).sum() + ((dm1 > 0) & (d0 > 0)).sum())
    info['pending_review_cells'] = int(((coll & 32) > 0).sum())

    # --- costa ------------------------------------------------------------------------
    sea = sem['ground'] == S.G['SEA']
    seen = np.zeros_like(sea)
    ys, xs = np.nonzero(sea[-1:])
    q = deque((H - 1, x) for x in xs)
    for c in q:
        seen[c] = True
    while q:
        y, x = q.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            ny, nx = y + dy, x + dx
            if 0 <= ny < H and 0 <= nx < W and sea[ny, nx] and not seen[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    stray = sea & ~seen
    if stray.sum() > 0:
        errors.append(f'{stray.sum()} celdas de mar aisladas: la costa no cierra bien')
    if RODA and sea[:int(H * 0.3)].any():
        errors.append('hay mar en el tercio norte: polígono marino invertido')
    info['sea_cells'] = int(sea.sum())

    # --- redes ferroviarias -------------------------------------------------------------
    rails = {r['name']: r for r in ow['routes'] if r['type'] == 'route_train'}
    corr = {}
    for n, r in rails.items():
        corr.setdefault(r['props'].get('corridor', n), []).append(r)
    for need in (('rail_hs', 'rail_interior', 'rail_litoral') if RODA else ()):
        if need not in corr:
            errors.append(f'falta el corredor ferroviario {need}')
    cn = list(corr)
    for i in range(len(cn)):
        for j in range(i + 1, len(cn)):
            a = {tuple(p) for r in corr[cn[i]] for p in r['points']}
            b = {tuple(p) for r in corr[cn[j]] for p in r['points']}
            if a & b:
                errors.append(f'los corredores {cn[i]} y {cn[j]} comparten vértices')
    info['rail_tracks'] = {c: [r['name'] + ':' + r['props'].get('dirs', '') for r in rs] for c, rs in corr.items()}

    # --- contenido referenciado -----------------------------------------------------------
    dlg = json.load(open(os.path.join(ROOT, 'data/dialogue.json')))
    for m in maps.values():
        for o in m['objects']:
            for key in ('dialogue', 'text'):
                k = o['props'].get(key)
                if k and k not in dlg:
                    errors.append(f"{m['scene']}: objeto {o['name']} referencia el texto inexistente '{k}'")
    # destinos de puertas (incluye interiores generados desde las zonas)
    import zones as Z
    for m in list(maps.values()):
        for iid, spec, back_scene, back_spawn in m.get('interiors', []):
            im, errs = Z.build_interior(iid, spec, back_scene, back_spawn, m['tileset_image'])
            errors.extend(errs)
            maps[iid] = im
    scenes = {m['scene']: m for m in maps.values()}
    for m in maps.values():
        for o in m['objects']:
            if o['type'] == 'door' and o['props'].get('poi'):   # interior generat al joc (procgen.poi)
                if o['props']['poi'] not in POI_KINDS:
                    errors.append(f"{m['scene']}: puerta {o['name']} → interior desconegut {o['props']['poi']}")
            elif o['type'] == 'door':
                ts, sp = o['props'].get('target_scene'), o['props'].get('target_spawn')
                tgt = scenes.get(ts)
                if not tgt:
                    errors.append(f"{m['scene']}: puerta {o['name']} → escena inexistente {ts}")
                elif not any(x['type'] == 'spawn' and x['name'] == sp for x in tgt['objects']):
                    if RODA or m['scene'] != 'cova_pedrera':   # (lloc nou: la Pedrera no s'hi enllaça)
                        errors.append(f"{m['scene']}: puerta {o['name']} → spawn inexistente {ts}/{sp}")
    # campañas de misiones (las edita /editor/missions.html; mismo validador)
    import campaigns
    for cid, (errs, warns) in campaigns.validate_all(campaigns.load()).items():
        errors.extend(f'misiones {cid}: {e}' for e in errs)
        info.setdefault('mission_warnings', 0)
        info['mission_warnings'] += len(warns)
    return finish(errors, info)


def finish(errors, info):
    out = {'ok': not errors, 'errors': errors, 'info': info}
    with open(os.path.join(ROOT, 'maps/source/validation-report.json'), 'w') as f:
        json.dump(out, f, indent=1, ensure_ascii=False)
    print(json.dumps(info, ensure_ascii=False, indent=1))
    for e in errors:
        print('ERROR', e)
    print('VALIDACIÓN', 'OK' if not errors else 'FALLIDA')
    return 0 if not errors else 1


if __name__ == '__main__':
    sys.exit(main())
