#!/usr/bin/env python3
"""Para cada puente/paso inferior transitable que cruza algo, comprueba que se puede ir a pie de un
extremo al otro (BFS por niveles en una ventana local) y que el recorrido usa su nivel."""
import json
import math
import os
import sys

import numpy as np

import semantic as S
import walkgraph
from osmlib import m2t

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))


def main():
    r = S.build(os.path.join(ROOT, 'cartography/municipio.osm.gz'))
    coll = np.load(os.path.join(ROOT, 'maps/source/semantic.npz'))['coll']
    H, W = coll.shape
    osm = r['osm']
    res, bad = [], []
    for wid, (lv, loc, cls, pts) in r['way_mask'].items():
        if lv == 0 or cls not in S.WALKABLE_DETAIL or len(pts) < 2:
            continue
        # ¿cruza algo de otro nivel?
        y0, x0, m = loc
        crosses = False
        for owid, (olv, oloc, ocls, opts) in r['way_mask'].items():
            if olv == lv or owid == wid or set(osm.ways[wid][1]) & set(osm.ways[owid][1]):
                continue
            oy, ox, om = oloc
            ys0, ys1 = max(y0, oy), min(y0 + m.shape[0], oy + om.shape[0])
            xs0, xs1 = max(x0, ox), min(x0 + m.shape[1], ox + om.shape[1])
            if ys0 < ys1 and xs0 < xs1 and (m[ys0 - y0:ys1 - y0, xs0 - x0:xs1 - x0] &
                                           om[ys0 - oy:ys1 - oy, xs0 - ox:xs1 - ox]).any():
                crosses = True
                break
        if not crosses:
            continue
        # puntos de inicio/fin: celda transitable a nivel 0 más allá de cada extremo
        def outside(end, inner):
            dx, dy = end[0] - inner[0], end[1] - inner[1]
            n = math.hypot(dx, dy) or 1
            for t in np.arange(0, m2t(80), 0.5):
                x, y = int(end[0] + dx / n * t), int(end[1] + dy / n * t)
                if 0 <= x < W and 0 <= y < H and walkgraph.walk_at(int(coll[y, x]), 0) and not coll[y, x] & 12:
                    return x, y
            return None
        a = outside(pts[0], pts[1])
        b = outside(pts[-1], pts[-2])
        if not a or not b:
            res.append({'way': wid, 'level': lv, 'ok': None, 'why': 'extremo sin suelo cercano'})
            continue
        pad = 60
        wx0, wy0 = max(0, min(a[0], b[0]) - pad), max(0, min(a[1], b[1]) - pad)
        wx1, wy1 = min(W, max(a[0], b[0]) + pad), min(H, max(a[1], b[1]) + pad)
        sub = coll[wy0:wy1, wx0:wx1]
        on_deck = set()
        for yy, xx in zip(*np.nonzero(m)):
            on_deck.add((x0 + xx - wx0, y0 + yy - wy0))

        def bfs(start, goal):
            from collections import deque
            prev = {start: None}
            q = deque([start])
            while q and len(prev) < 400000:
                cur = q.popleft()
                if goal(cur):
                    return cur
                x, y, l = cur
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    nl = walkgraph.step(sub, x, y, l, x + dx, y + dy)
                    if nl is not None and (x + dx, y + dy, nl) not in prev:
                        prev[(x + dx, y + dy, nl)] = cur
                        q.append((x + dx, y + dy, nl))
            return None
        mid = bfs((a[0] - wx0, a[1] - wy0, 0), lambda c: c[2] == lv and (c[0], c[1]) in on_deck)
        end = mid and bfs(mid, lambda c: (c[0], c[1]) == (b[0] - wx0, b[1] - wy0))
        p = end
        ok = bool(mid and end)
        # celda «sobre lo cruzado»: solo transitable al nivel del paso (la prueba real obliga a pisarla)
        mx_, my_ = pts[len(pts) // 2]
        over = None
        for (cx, cy) in on_deck:
            code = int(sub[cy, cx])
            other = 8 if lv == 1 else 4   # sin el otro nivel (puente sobre un paso inferior)
            if walkgraph.walk_at(code, lv) and not walkgraph.walk_at(code, 0) and not code & 16 and not code & other:
                d = (cx + wx0 - mx_) ** 2 + (cy + wy0 - my_) ** 2
                if over is None or d < over[0]:
                    over = (d, cx + wx0, cy + wy0)
        item = {'way': wid, 'level': lv, 'name': osm.ways[wid][0].get('name') or osm.ways[wid][0].get('highway'),
                'from': [int(a[0]), int(a[1])], 'to': [int(b[0]), int(b[1])], 'ok': ok, 'over': [int(over[1]), int(over[2])] if over else None}
        res.append(item)
        if not ok:
            bad.append(item)
    out = {'checked': len(res), 'failed': bad}
    json.dump(res, open(os.path.join(ROOT, 'maps/source/crossings-report.json'), 'w'), indent=1, ensure_ascii=False)
    print(f"{len(res)} pasos comprobados, {len(bad)} fallan")
    for b_ in bad:
        print('  FALLA', b_)
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
