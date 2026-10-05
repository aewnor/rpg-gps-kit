"""Grafo de movimiento por niveles, compartido por el compilador y el validador.

Código de colisión por celda (6 bits):
  bits 0-1  tipo en el nivel 0: 0 transitable, 1 sólido, 2 agua, 3 peligro (autopista)
  bit 2 (4)  transitable en el nivel 1 (tablero de puente)
  bit 3 (8)  transitable en el nivel -1 (túnel/paso inferior)
  bit 4 (16) rampa: une los niveles transitables de esa celda con los vecinos
  bit 5 (32) geometría pendiente de revisión (bloqueada)
Misma regla que src/world/collision.lua.
"""
from collections import deque

import numpy as np

LEVELS = (-1, 0, 1)


def walk_at(code, level):
    if level == 0:
        return (code & 3) == 0 and not code & 32
    if level == 1:
        return bool(code & 4)
    return bool(code & 8)


def ramp_level(code):
    """Nivel no cero que une una rampa (1 puente, -1 túnel)."""
    return 1 if code & 4 else -1 if code & 8 else 0


def step(coll, x, y, level, nx, ny):
    """Nivel resultante al pasar de (x, y) a (nx, ny), o None si no se puede.

    - Fuera de rampas se conserva el nivel.
    - Al entrar en una rampa se conserva el nivel si es posible.
    - Al salir de una rampa se prefiere el nivel del puente/túnel si la celda destino lo admite;
      si no, el nivel 0.
    """
    H, W = coll.shape
    if not (0 <= nx < W and 0 <= ny < H):
        return None
    c, n = int(coll[y, x]), int(coll[ny, nx])
    if n & 16:
        if walk_at(n, level):
            return level
        for lv in (ramp_level(n), 0):
            if walk_at(n, lv):
                return lv
        return None
    if c & 16:
        rl = ramp_level(c)
        if rl and walk_at(n, rl):
            return rl
        if walk_at(n, 0):
            return 0
        return level if walk_at(n, level) else None
    return level if walk_at(n, level) else None


def components(coll):
    """Componentes conexas por (celda, nivel). Devuelve dict nivel -> array int32 (0 = no transitable)."""
    H, W = coll.shape
    comp = {lv: np.zeros((H, W), np.int32) for lv in LEVELS}
    cid = 0
    for lv0 in LEVELS:
        for y0 in range(H):
            for x0 in range(W):
                if comp[lv0][y0, x0] or not walk_at(int(coll[y0, x0]), lv0):
                    continue
                cid += 1
                comp[lv0][y0, x0] = cid
                q = deque([(x0, y0, lv0)])
                while q:
                    x, y, lv = q.popleft()
                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                        nx, ny = x + dx, y + dy
                        nl = step(coll, x, y, lv, nx, ny)
                        if nl is not None and not comp[nl][ny, nx]:
                            comp[nl][ny, nx] = cid
                            q.append((nx, ny, nl))
    return comp


def path(coll, start, goal, max_nodes=2_000_000):
    """BFS por niveles desde start=(x,y,nivel) hasta goal=(x,y) a cualquier nivel."""
    prev = {start: None}
    q = deque([start])
    while q:
        cur = q.popleft()
        x, y, lv = cur
        if (x, y) == goal:
            out = []
            while cur:
                out.append(cur)
                cur = prev[cur]
            return out[::-1]
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = x + dx, y + dy
            nl = step(coll, x, y, lv, nx, ny)
            if nl is not None and (nx, ny, nl) not in prev:
                prev[(nx, ny, nl)] = cur
                q.append((nx, ny, nl))
        if len(prev) > max_nodes:
            break
    return None


def _walk(code, level):
    if level == 0:
        return ((code & 3) == 0) & ((code & 32) == 0)
    if level == 1:
        return (code & 4) > 0
    return (code & 8) > 0


def _step_vec(c, n, level):
    """Versión vectorizada de step(): devuelve array de nivel destino (-9 = imposible)."""
    out = np.full(c.shape, -9, np.int8)
    rl_n = np.where(n & 4, 1, np.where(n & 8, -1, 0))
    rl_c = np.where(c & 4, 1, np.where(c & 8, -1, 0))
    nr, cr = (n & 16) > 0, (c & 16) > 0
    w_l = _walk(n, level)
    w_0 = _walk(n, 0)
    w_rln = np.where(rl_n == 1, _walk(n, 1), np.where(rl_n == -1, _walk(n, -1), False))
    w_rlc = np.where(rl_c == 1, _walk(n, 1), np.where(rl_c == -1, _walk(n, -1), False))
    # n es rampa
    m = nr
    out[m & w_l] = level
    sel = m & ~w_l & (rl_n != 0) & w_rln
    out[sel] = rl_n[sel]
    out[m & ~w_l & ~((rl_n != 0) & w_rln) & w_0] = 0
    # c es rampa (y n no)
    m = ~nr & cr
    sel = m & (rl_c != 0) & w_rlc
    out[sel] = rl_c[sel]
    rest = m & ~((rl_c != 0) & w_rlc)
    out[rest & w_0] = 0
    out[rest & ~w_0 & w_l] = level
    # ninguna rampa
    out[~nr & ~cr & w_l] = level
    return out


def components_fast(coll):
    """Componentes conexas (débiles) del grafo (celda, nivel) con scipy. Mismo formato que components()."""
    from scipy.sparse import coo_matrix
    from scipy.sparse.csgraph import connected_components
    H, W = coll.shape
    coll = coll.astype(np.int32)
    N = H * W
    idx = np.arange(N, dtype=np.int64).reshape(H, W)
    lv_index = {-1: 0, 0: 1, 1: 2}
    rows, cols = [], []
    for level in LEVELS:
        valid = _walk(coll, level)
        for dy, dx in ((0, 1), (1, 0), (0, -1), (-1, 0)):
            ys = slice(max(0, -dy), H - max(0, dy))
            xs = slice(max(0, -dx), W - max(0, dx))
            yn = slice(max(0, dy), H - max(0, -dy))
            xn = slice(max(0, dx), W - max(0, -dx))
            c, n = coll[ys, xs], coll[yn, xn]
            nl = _step_vec(c, n, level)
            ok = valid[ys, xs] & (nl != -9)
            src = idx[ys, xs][ok] + lv_index[level] * N
            dst_l = np.where(nl[ok] == -1, 0, np.where(nl[ok] == 0, 1, 2))
            dst = idx[yn, xn][ok] + dst_l * N
            rows.append(src)
            cols.append(dst)
    r = np.concatenate(rows)
    c = np.concatenate(cols)
    g = coo_matrix((np.ones(len(r), np.int8), (r, c)), shape=(3 * N, 3 * N))
    _, labels = connected_components(g, directed=True, connection='weak')
    out = {}
    for level in LEVELS:
        lab = labels[lv_index[level] * N:(lv_index[level] + 1) * N].reshape(H, W).astype(np.int32) + 1
        lab[~_walk(coll, level)] = 0
        out[level] = lab
    return out
