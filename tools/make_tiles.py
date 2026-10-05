"""Genera el atlas de tiles 16 × 16 (assets/runtime/tiles.png) y su manifiesto (data/tiles.json).

El arte es original y procedural: cada tile se dibuja con la paleta de pixel.py y una semilla
derivada de su nombre, así que regenerar produce exactamente los mismos píxeles.

Máscaras de vecindad: N=1, E=2, S=4, W=8; bit activo = el vecino es de la misma familia.
"""
import math
import json
import os
import sys
import numpy as np

from pixel import Sprite, mix, rgba, rng_for, sheet

T = 16
N, E, S_, W_ = 1, 2, 4, 8
ROOT = os.path.join(os.path.dirname(__file__), '..')

tiles = []      # (name, Sprite, props)
index = {}


def add(name, spr, **props):
    assert name not in index, name
    index[name] = len(tiles)
    tiles.append((name, spr, props))


def jitter_edges(s, mask, rng, depth=2, prob=0.55):
    """Bordes irregulares (transparentes) en los lados no conectados: caminos de tierra."""
    for y in range(T):
        for x in range(T):
            d = []
            if not mask & N: d.append(y)
            if not mask & S_: d.append(T - 1 - y)
            if not mask & W_: d.append(x)
            if not mask & E: d.append(T - 1 - x)
            if d and min(d) < depth and rng.random() < prob * (1 - min(d) / depth):
                s.a[y, x, 3] = 0


def edge_lines(s, mask, col, width=1, col_inner=None):
    for i in range(width):
        c = col if i == 0 or not col_inner else col_inner
        if not mask & N: s.hline(0, T - 1, i, c)
        if not mask & S_: s.hline(0, T - 1, T - 1 - i, c)
        if not mask & W_: s.vline(i, 0, T - 1, c)
        if not mask & E: s.vline(T - 1 - i, 0, T - 1, c)


# --- suelos -------------------------------------------------------------------
# Tres variantes por terreno, de más oscura (0) a más clara (2): el importador elige la variante según
# la luminosidad real de la ortofoto en esa casilla, así las manchas del mapa siguen las del satélite.
VARIANT_LIGHT = (-0.045, 0.0, 0.045)


def tone(c, v):
    k = VARIANT_LIGHT[v]
    return mix(c, 'white' if k > 0 else 'ink', abs(k)) if k else rgba(c)


def ground(name, base, specks, density, extra=None, variants=3):
    for v in range(variants):
        rng = rng_for('g', name, v)
        s = Sprite(T, T, None)
        s.a[:, :] = tone(base, v)
        for yy in range(T):
            for xx in range(T):
                if rng.random() < density:
                    s.px(xx, yy, tone(rng.choice(specks), v))
        if extra:
            extra(s, rng, v)
        add(f'g_{name}_{v}', s)


def tufts(colors, n):
    def f(s, rng, v):
        for _ in range(n):
            x, y = rng.randrange(1, 15), rng.randrange(2, 15)
            c = tone(rng.choice(colors), v)
            s.px(x, y, c); s.px(x - 1, y - 1, c); s.px(x + 1, y - 1, c)
    return f


def grass_blades(light, dark, n):
    """Briznas en «v» con la punta iluminada (luz arriba a la izquierda)."""
    def f(s, rng, v):
        for _ in range(n):
            x, y = rng.randrange(1, 15), rng.randrange(3, 15)
            s.px(x, y, tone(dark, v)); s.px(x - 1, y - 1, tone(dark, v)); s.px(x + 1, y - 1, tone(light, v))
            s.px(x - 1, y - 2, tone(light, v))
    return f


def flowers(s, rng, v):
    grass_blades('sun', 'pine2', 2)(s, rng, v)
    for _ in range(2):
        x, y = rng.randrange(2, 14), rng.randrange(2, 14)
        c = rng.choice(['white', 'ochre', 'red'])
        s.px(x, y, c); s.px(x, y + 1, 'pine3')


def pebbles(s, rng, v):
    for _ in range(3):
        x, y = rng.randrange(1, 14), rng.randrange(1, 14)
        s.px(x, y, tone('stone', v)); s.px(x + 1, y, tone('stone2', v)); s.px(x, y + 1, tone('dry3', v))
    tufts(['pine2', 'dry3'], 1)(s, rng, v)


def yard(s, rng, v):
    """Patios y jardines secos de las parcelas urbanas: grava clara, alguna losa y alguna mata."""
    if rng.random() < .5:
        x, y = rng.randrange(1, 11), rng.randrange(1, 12)
        s.rect(x, y, 4, 3, tone('stone', v)); s.hline(x + 1, x + 3, y + 3, tone('dry2', v))
    grass_blades('pine', 'pine2', 1 + int(rng.random() < .5))(s, rng, v)


def needles(s, rng, v):
    for _ in range(10):
        x, y = rng.randrange(0, 15), rng.randrange(0, 16)
        s.px(x, y, tone('dry3', v)); s.px(x + 1, y, tone('dry2', v))
    grass_blades('pine2', 'pine4', 2)(s, rng, v)


def furrows(s, rng, v):
    for y in range(1, T, 4):
        s.hline(0, T - 1, y, tone('dry3', v))
        s.hline(0, T - 1, y + 1, tone('dry', v))
        for x in range(0, T):
            if rng.random() < .25: s.px(x, y - 1, tone('pine2', v))


def vines(s, rng, v):
    for y in range(2, T, 6):
        s.hline(0, T - 1, y + 2, tone('dry3', v))
        for x in range(0, T, 2):
            s.px(x + (y // 6) % 2, y, tone('pine2', v)); s.px(x, y + 1, tone('pine3', v))
            if rng.random() < .3: s.px(x, y - 1, tone('sun', v))


def crosses(s, rng, v):
    x, y = 4 + v * 3, 5
    s.vline(x, y, y + 5, 'white3'); s.hline(x - 1, x + 1, y + 1, 'white3')
    s.hline(x - 1, x + 1, y + 6, 'pine3')


def puddles(s, rng, v):
    for _ in range(2):
        x, y = rng.randrange(2, 12), rng.randrange(2, 13)
        s.rect(x, y, 3, 2, 'sea2'); s.px(x, y, 'sea')


def void_trees(s, rng, v):
    for _ in range(5):
        x, y = rng.randrange(0, 14), rng.randrange(0, 14)
        s.rect(x, y, 3, 2, 'pine3'); s.px(x + 1, y - 1, 'pine2')


def strata(s, rng, v):
    for y in range(2, T, 5):
        for x in range(T):
            if rng.random() < .7: s.px(x, y, tone('stone2', v))


ground('dry', 'dry', ['dry2', 'dry3'], 0.10, pebbles)
ground('grass', 'pine', ['pine2', 'sun'], 0.06, grass_blades('sun', 'pine2', 3))
ground('forest', 'pine3', ['pine4', 'pine2'], 0.16, needles)
ground('scrub', 'dry2', ['dry3', 'dry'], 0.10, tufts(['pine2', 'pine3', 'pine'], 6))
ground('farm', 'dry', ['dry2'], 0.05, furrows)
ground('vineyard', 'dry', ['dry2'], 0.05, vines)
ground('urban', 'dry', ['stone', 'dry2'], 0.08, yard)
ground('park', 'pine', ['pine2', 'sun'], 0.06, flowers)
ground('quarry', 'stone', ['stone2', 'white2'], 0.18, strata)
ground('beach', 'sand', ['sand2', 'white'], 0.10)
ground('rock', 'stone2', ['stone3', 'stone'], 0.25, tufts(['stone3'], 2))
ground('railyard', 'stone2', ['stone3', 'asph2'], 0.3)
ground('cemetery', 'pine', ['pine2'], 0.08, crosses)
ground('wetland', 'pine2', ['pine3', 'pine'], 0.15, puddles)
ground('pitch', 'pine', ['pine2'], 0.05)
ground('void', 'pine4', ['pine3'], 0.2, void_trees)
ground('cave', 'stone3', ['stone2', 'ink'], 0.12)
ground('cavefloor', 'dry3', ['dry2', 'stone3'], 0.12)


# --- agua con espuma (autotile 16 × frames) -----------------------------------
def sea_tile(mask, f, kind):
    rng = rng_for('sea', kind, mask, f)
    if kind == 'sea':
        deep, mid, light = 'sea2', 'sea3', 'sea'
    elif kind == 'seadeep':
        deep, mid, light = 'deep', 'sea3', 'sea2'
    else:
        deep, mid, light = 'pool', 'sea', 'foam'
    s = Sprite(T, T, deep)
    for i in range(6 if kind != 'seadeep' else 4):  # destellos que se desplazan con el frame
        x = (rng.randrange(T) + f * 3) % T
        y = rng.randrange(T)
        s.hline(x, min(T - 1, x + 2), y, light)
    s.speckle(rng, [mid], 0.06)
    # orilla: franja clara + espuma ondulante
    for y in range(T):
        for x in range(T):
            d = []
            if not mask & N: d.append(y)
            if not mask & S_: d.append(T - 1 - y)
            if not mask & W_: d.append(x)
            if not mask & E: d.append(T - 1 - x)
            if not d:
                continue
            m = min(d)
            wave = (x + y + f * 2) % 6 < 3
            if kind == 'pool':
                if m == 0:
                    s.px(x, y, 'white2')
                elif m == 1:
                    s.px(x, y, 'white3')
                elif m == 2:
                    s.px(x, y, 'sea')
            elif m == 0 or (m == 1 and wave):
                s.px(x, y, 'foam')
            elif m <= 2:
                s.px(x, y, 'pool')
            elif m <= 4:
                s.px(x, y, 'sea')
    return s


for kind, frames in (('sea', 4), ('pool', 2)):
    for mask in range(16):
        for f in range(frames):
            add(f'{kind}_{mask}_{f}', sea_tile(mask, f, kind), anim=frames)


# --- vías: detalle con máscara -------------------------------------------------
def road(mask, rng, base, specks, curb):
    s = Sprite(T, T, base)
    s.speckle(rng, specks, 0.05)
    if curb:
        # acera de 3 px en los lados exteriores
        for i in range(3):
            c = 'white3' if i == 2 else 'white2'
            if not mask & N: s.hline(0, T - 1, i, c)
            if not mask & S_: s.hline(0, T - 1, T - 1 - i, c)
            if not mask & W_: s.vline(i, 0, T - 1, c)
            if not mask & E: s.vline(T - 1 - i, 0, T - 1, c)
        for i in range(0, T, 4):  # juntas de baldosa
            if not mask & N: s.px(i, 0, 'white3')
            if not mask & S_: s.px(i, T - 3, 'white3')
    return s


def paving(mask, rng):
    s = Sprite(T, T, 'white')
    for i in range(0, T, 4):
        s.hline(0, T - 1, i, 'white2')
    for j in range(T // 4):
        off = 2 if j % 2 else 0
        for i in range(off, T, 4):
            s.vline(i, j * 4, j * 4 + 3, 'white2')
    s.speckle(rng, ['white3'], 0.03)
    edge_lines(s, mask, 'stone2')
    return s


def dirt(mask, rng, base='dry2', specks=('dry3', 'dry')):
    s = Sprite(T, T, base)
    s.speckle(rng, list(specks), 0.18)
    jitter_edges(s, mask, rng)
    return s


def stream(mask, rng):
    s = Sprite(T, T, 'stone')
    s.speckle(rng, ['stone2', 'stone3', 'white2'], 0.3)
    for y in range(T):
        x = 7 + (1 if (y // 4) % 2 else -1)
        if rng.random() < .7:
            s.px(x, y, 'sea2')
    jitter_edges(s, mask, rng, 2, 0.6)
    return s


def steps(mask, rng):
    s = Sprite(T, T, 'stone')
    for y in range(0, T, 4):
        s.hline(0, T - 1, y + 3, 'stone3'); s.hline(0, T - 1, y, 'white2')
    edge_lines(s, mask, 'stone3')
    return s


def motorway(mask, rng):
    s = Sprite(T, T, 'asph3')
    s.speckle(rng, ['asph2'], 0.06)
    for i, c in ((0, 'white3'), (1, 'asph2'), (3, 'white')):
        if not mask & N: s.hline(0, T - 1, i, c)
        if not mask & S_: s.hline(0, T - 1, T - 1 - i, c)
        if not mask & W_: s.vline(i, 0, T - 1, c)
        if not mask & E: s.vline(T - 1 - i, 0, T - 1, c)
    return s


def platform(mask, rng):
    s = Sprite(T, T, 'white2')
    s.speckle(rng, ['white3'], 0.05)
    edge_lines(s, mask, 'ochre', 1)
    return s


def pier(mask, rng):
    s = Sprite(T, T, 'ochre2')
    for y in range(0, T, 3):
        s.hline(0, T - 1, y, 'ochre3')
    edge_lines(s, mask, 'ink')
    return s


def bridge_deck(mask, rng, base):
    s = road(mask, rng, base, ['asph2'], False)
    for i, c in ((0, 'ink'), (1, 'stone'), (2, 'stone2')):
        if not mask & N: s.hline(0, T - 1, i, c)
        if not mask & S_: s.hline(0, T - 1, T - 1 - i, c)
        if not mask & W_: s.vline(i, 0, T - 1, c)
        if not mask & E: s.vline(T - 1 - i, 0, T - 1, c)
    return s


FAMILIES = {
    'road': lambda m, r: road(m, r, 'asph', ['asph2'], True),
    'main': lambda m, r: road(m, r, 'asph2', ['asph3'], True),
    'moto': motorway,
    'paving': paving,
    'path': lambda m, r: dirt(m, r),
    'track': lambda m, r: dirt(m, r, 'dry3', ('dry2', 'stone3')),
    'stream': stream,
    'steps': steps,
    'platform': platform,
    'pier': pier,
    'bridge': lambda m, r: bridge_deck(m, r, 'asph'),
    'bridgemoto': lambda m, r: bridge_deck(m, r, 'asph3'),
}
for fam, fn in FAMILIES.items():
    for mask in range(16):
        add(f'd_{fam}_{mask}', fn(mask, rng_for('d', fam, mask)))


# --- ferrocarril orientado ----------------------------------------------------
def rail(orient, hs, bridge=False):
    s = Sprite(T, T, 'stone2')
    rng = rng_for('rail', orient, hs, bridge)
    s.speckle(rng, ['stone3', 'stone'], 0.3)
    rail_c = 'white3' if hs else 'asph3'
    if orient == 'h':
        for x in range(1, T, 4):
            s.vline(x, 3, 12, 'ochre3'); s.vline(x + 1, 3, 12, 'ochre3')
        s.hline(0, T - 1, 5, rail_c); s.hline(0, T - 1, 10, rail_c)
    elif orient == 'v':
        for y in range(1, T, 4):
            s.hline(3, 12, y, 'ochre3'); s.hline(3, 12, y + 1, 'ochre3')
        s.vline(5, 0, T - 1, rail_c); s.vline(10, 0, T - 1, rail_c)
    else:  # diagonales: d1 = «\\», d2 = «/»
        for t in range(1, T, 3):
            for u in range(-4, 5):
                if orient == 'd1':
                    s.px(t + u, t - u, 'ochre3')
                else:
                    s.px(t + u, T - 1 - t + u, 'ochre3')
        for i in range(T):
            for off in (-3, 3):
                s.px(i + off, i if orient == 'd1' else T - 1 - i, rail_c)
    return s


for hs in (False, True):
    for o in ('h', 'v', 'd1', 'd2'):
        add(f'd_{"railhs" if hs else "rail"}_{o}', rail(o, hs))

lc = road(15, rng_for('lc'), 'asph', ['asph2'], False)
for x in range(0, T, 4):
    lc.rect(x, 0, 2, 2, 'red'); lc.rect(x + 2, 0, 2, 2, 'white')
    lc.rect(x, 14, 2, 2, 'red'); lc.rect(x + 2, 14, 2, 2, 'white')
lc.hline(0, T - 1, 5, 'white3'); lc.hline(0, T - 1, 10, 'white3')
add('d_crossing', lc)
pend = Sprite(T, T, 'white')
for y in range(T):
    for x in range(T):
        if ((x + y) // 4) % 2:
            pend.px(x, y, 'red')
add('d_pending', pend)
tun = Sprite(T, T, 'asph3')
tun.speckle(rng_for('tun'), ['ink'], 0.3)
add('d_tunnel', tun)


# --- edificios -----------------------------------------------------------------
# Tejados: r_<tipo>_<máscara> (genérico) y, en los de pendiente, vertiente norte (n, al sol), cumbrera (k)
# y vertiente sur (s, en sombra): r_<tipo>_<n|k|s>_<máscara>. El importador pone la cumbrera en la fila
# central de cada edificio, así las casas se leen con volumen. Planos (azotea): pretil, grava y, en el
# interior, depósitos, aire acondicionado, placas solares o claraboyas (r_flat_x<1..4>).
ROOFS = {
    'terra': ('terra', 'terra2', 'terra3'),
    'brown': ('ochre2', 'ochre3', 'terra3'),
    'slate': ('asph', 'asph2', 'asph3'),
    'stone': ('stone', 'stone2', 'stone3'),
    'flat': ('white2', 'white3', 'stone3'),
    'metal': (mix('white2', 'sea3', .18), mix('white3', 'sea3', .2), 'asph2'),
    'glass': (mix('white', 'pool', .35), mix('white2', 'pool', .25), 'white3'),
}
PITCHED = ('terra', 'brown', 'slate', 'stone')


def roof(kind, mask, part=None):
    c1, c2, c3 = ROOFS[kind]
    rng = rng_for('roof', kind, mask, part)
    hi = mix(c1, 'white', .22)
    s = Sprite(T, T, None)
    if kind in PITCHED:
        base, shade, deep = (c1, c2, c3) if part != 's' else (c2, c3, mix(c3, 'ink', .3))
        s.a[:, :] = rgba(base) if isinstance(base, str) else base
        if kind in ('terra', 'brown'):
            for y in range(0, T, 4):          # hiladas de teja árabe
                s.hline(0, T - 1, y, hi if part != 's' else c1)
                s.hline(0, T - 1, y + 3, shade)
                off = (y // 4) % 2 * 2
                for x in range(off, T, 4):
                    s.px(x, y + 1, shade); s.px(x, y + 2, deep)
        elif kind == 'slate':
            for y in range(0, T, 3):
                s.hline(0, T - 1, y, shade)
                for x in range((y // 3) % 2 * 3, T, 6): s.px(x, y + 1, deep)
        else:
            for y in range(0, T, 5):
                s.hline(0, T - 1, y, shade)
            s.speckle(rng, [deep], 0.04)
        if part == 'k':                       # cumbrera: caballete claro con sombra debajo
            s.hline(0, T - 1, 6, hi); s.hline(0, T - 1, 7, mix(c1, 'white', .35)); s.hline(0, T - 1, 8, c3)
            s.a[9:, :] = rgba(c2) if isinstance(c2, str) else c2
            for y in range(10, T, 4):
                s.hline(0, T - 1, y + 2, c3)
    elif kind == 'flat':
        s.a[:, :] = rgba(c1)
        s.speckle(rng, [c2, mix(c1, 'white', .3)], 0.08)
    elif kind == 'metal':
        s.a[:, :] = c1
        for x in range(0, T, 3):
            s.vline(x, 0, T - 1, c2); s.vline(x + 1, 0, T - 1, mix(c1, 'white', .25))
    else:  # invernadero
        s.a[:, :] = c1
        for x in range(0, T, 4):
            s.vline(x, 0, T - 1, 'white3')
        s.hline(0, T - 1, 7, 'white3')
        for y in range(1, T, 5): s.px((y * 3) % T, y, 'white')
    # bordes: alero/pretil claro arriba e izquierda, sombra abajo a la derecha
    if kind in ('flat', 'metal', 'glass'):
        if not mask & N: s.hline(0, T - 1, 0, 'white'); s.hline(0, T - 1, 1, c2 if kind == 'flat' else c1)
        if not mask & W_: s.vline(0, 0, T - 1, 'white'); s.vline(1, 0, T - 1, c2 if kind == 'flat' else c1)
        if not mask & E: s.vline(T - 1, 0, T - 1, c3); s.vline(T - 2, 0, T - 1, c2)
    else:
        if not mask & N: s.hline(0, T - 1, 0, 'white'); s.hline(0, T - 1, 1, hi)
        if not mask & W_: s.vline(0, 0, T - 1, hi)
        if not mask & E: s.vline(T - 1, 0, T - 1, c3); s.vline(T - 2, 0, T - 1, mix(c2, c3, .5))
    if not mask & S_: s.hline(0, T - 1, T - 1, 'ink'); s.hline(0, T - 1, T - 2, c3)
    return s


def roof_prop(i):
    """Elementos de azotea (tile interior, máscara 15)."""
    s = roof('flat', 15)
    s.a[:, :] = roof('flat', 15).a
    if i == 1:    # depósito de agua
        s.rect(4, 3, 8, 9, 'white'); s.rect(4, 3, 8, 2, 'white2'); s.vline(11, 3, 11, 'white3')
        s.rect(5, 12, 8, 2, (31, 26, 36, 90))
    elif i == 2:  # aire acondicionado
        s.rect(3, 5, 10, 6, 'stone'); s.rect(3, 5, 10, 1, 'white2')
        for y in range(6, 10): s.hline(4, 7, y, 'stone3' if y % 2 else 'stone2')
        s.rect(9, 6, 3, 3, 'asph2'); s.px(10, 7, 'asph3'); s.rect(4, 11, 10, 1, (31, 26, 36, 90))
    elif i == 3:  # placas solares
        for y0 in (2, 9):
            s.rect(1, y0, 14, 5, 'sea3')
            for x in range(1, 15, 3): s.vline(x, y0, y0 + 4, 'deep')
            s.hline(1, 14, y0 + 2, 'deep'); s.px(2, y0, 'sea'); s.px(3, y0, 'sea')
    else:         # claraboya
        s.rect(4, 4, 8, 8, 'white3'); s.rect(5, 5, 6, 6, 'sea2'); s.px(5, 5, 'pool'); s.px(6, 5, 'pool')
    return s


for kind in ROOFS:
    for mask in range(16):
        add(f'r_{kind}_{mask}', roof(kind, mask), solid=True)
    if kind in PITCHED:
        for part in ('n', 'k', 's'):
            for mask in range(16):
                add(f'r_{kind}_{part}_{mask}', roof(kind, mask, part), solid=True)
for i in range(1, 5):
    add(f'r_flat_x{i}', roof_prop(i), solid=True)

# Fachadas f_<pared>_<posición l|m|r|s>_<tipo>: una fila bajo el tejado (dos en bloques de pisos:
# la de arriba es «up»). Tipos: win (ventana con persianas), bal (balconera), door, shop/shop2/shop3
# (toldo rojo, azul, verde), garage, roll (persiana metálica de nave), arch (ventana de arco, edificios
# públicos y masías) y up (planta alta de pisos, con balcón).
WALLS = {'white': ('white', 'white2', 'white3'), 'ochre': ('ochre', 'ochre2', 'ochre3'),
         'stone': ('stone', 'stone2', 'stone3'), 'sand': ('sand', 'sand2', 'ochre2'),
         'salmon': (mix('terra', 'white', .35), mix('terra', 'white', .1), 'terra2'),
         'sky': (mix('sea', 'white', .62), mix('sea', 'white', .4), mix('sea2', 'ink', .1)),
         'brick': ('terra2', 'terra3', mix('terra3', 'ink', .3)),
         'metal': (mix('white2', 'sea3', .15), mix('white3', 'sea3', .2), 'asph2'),
         'glass': (mix('white', 'pool', .3), mix('white2', 'pool', .25), 'white3')}
FACADE_KINDS = ('win', 'door', 'shop', 'shop2', 'shop3', 'bal', 'garage', 'roll', 'arch', 'up')
SHUTTERS = {'white': ('pine2', 'pine3'), 'ochre': ('ochre3', 'terra3'), 'stone': ('ochre3', 'terra3'),
            'sand': ('sea2', 'sea3'), 'salmon': ('pine2', 'pine3'), 'sky': ('white', 'white2'),
            'brick': ('asph2', 'asph3'), 'metal': ('asph2', 'asph3'), 'glass': ('white3', 'stone2')}
AWNING = {'shop': ('red', 'white'), 'shop2': ('blue', 'white'), 'shop3': ('pine2', 'white')}


def window(s, c3, sh, x0=4, w=8, y0=4, h=7, shutters=True):
    if shutters:
        s.rect(x0 - 2, y0, 2, h, sh[0]); s.rect(x0 + w, y0, 2, h, sh[0])
        for y in range(y0 + 1, y0 + h, 2):
            s.hline(x0 - 2, x0 - 1, y, sh[1]); s.hline(x0 + w, x0 + w + 1, y, sh[1])
    s.rect(x0, y0, w, h, 'white2')                       # marco
    s.rect(x0 + 1, y0 + 1, w - 2, h - 2, 'sea3')         # vidrio
    s.vline(x0 + w // 2, y0 + 1, y0 + h - 2, 'white2')
    s.px(x0 + 1, y0 + 1, 'sea'); s.px(x0 + 2, y0 + 1, 'sea'); s.px(x0 + 1, y0 + 2, 'sea')
    s.hline(x0 - 1, x0 + w, y0 + h, 'white')             # alféizar
    s.hline(x0, x0 + w, y0 + h + 1, c3)


def facade(col, pos, kind):
    c1, c2, c3 = WALLS[col]
    sh = SHUTTERS[col]
    s = Sprite(T, T, None)
    s.a[:, :] = rgba(c1) if isinstance(c1, str) else c1
    rng = rng_for('fac', col, pos, kind)
    if col == 'stone':
        s.speckle(rng, [c2, c3], 0.15, (0, 2, T, 12))
    elif col == 'brick':
        for y in range(2, 14, 3):
            s.hline(0, T - 1, y, c2)
            for x in range((y // 3) % 2 * 3, T, 6): s.vline(x, y, y + 2, c2)
    elif col == 'metal':
        for x in range(0, T, 3): s.vline(x, 2, 13, c2)
    elif col not in ('glass',):
        s.speckle(rng, [c2], 0.03, (0, 2, T, 12))
    upper = kind == 'up'
    if not upper:
        s.hline(0, T - 1, 0, c3)          # sombra del alero
        s.hline(0, T - 1, 1, c2)
        s.hline(0, T - 1, T - 2, 'stone2' if col not in ('brick', 'metal') else c3)   # zócalo
        s.hline(0, T - 1, T - 3, mix('stone2', c1, .5) if col not in ('brick', 'metal') else c2)
        s.hline(0, T - 1, T - 1, 'ink')
    else:
        s.hline(0, T - 1, 0, c2)          # forjado entre plantas
    if pos in ('l', 's'): s.vline(0, 0, T - 1, mix(c1, 'white', .3))
    if pos in ('r', 's'): s.vline(T - 1, 0, T - 1, c3); s.vline(T - 2, 1, T - 2, c2)
    if kind == 'win':
        window(s, c3, sh)
    elif kind == 'arch':
        s.rect(5, 5, 6, 7, 'white2'); s.rect(6, 6, 4, 6, 'sea3')
        for x, y in ((5, 4), (10, 4), (6, 3), (7, 3), (8, 3), (9, 3)): s.px(x, y, 'white2')
        s.px(6, 5, 'white2'); s.px(9, 5, 'white2'); s.px(7, 4, 'sea3'); s.px(8, 4, 'sea3'); s.px(6, 6, 'sea')
        s.hline(4, 11, 12, 'white'); s.hline(5, 11, 13, c3)
    elif kind in ('bal', 'up'):
        y0 = 3 if upper else 3
        s.rect(5, y0, 6, 9, 'white2'); s.rect(6, y0 + 1, 4, 8, 'sea3'); s.vline(8, y0 + 1, y0 + 8, 'white2')
        s.px(6, y0 + 1, 'sea'); s.px(6, y0 + 2, 'sea')
        s.rect(3, y0, 2, 9, sh[0]); s.rect(11, y0, 2, 9, sh[0])
        for y in range(y0 + 1, y0 + 9, 2): s.hline(3, 4, y, sh[1]); s.hline(11, 12, y, sh[1])
        s.hline(2, 13, y0 + 6, 'ink')                     # barandilla de hierro
        for x in range(2, 14, 2): s.vline(x, y0 + 6, y0 + 9, 'ink')
        s.hline(1, 14, y0 + 10, 'white'); s.hline(1, 14, y0 + 11, c3)   # losa del balcón y su sombra
        if upper:
            s.hline(1, 14, y0 + 12, mix(c3, c1, .5))
    elif kind == 'door':
        s.rect(4, 3, 8, 11, 'white2')                     # marco de piedra
        s.rect(5, 4, 6, 10, 'ochre3'); s.rect(6, 5, 4, 9, 'ochre2')
        s.vline(8, 5, 13, 'ochre3'); s.px(9, 9, 'ochre'); s.px(6, 5, 'ochre')
        s.rect(3, 14, 10, 1, 'stone')                     # escalón
    elif kind in AWNING:
        a, b = AWNING[kind]
        for x in range(0, T):
            c = a if (x // 2) % 2 == 0 else b
            s.vline(x, 2, 4, c)
        for x in range(0, T, 2): s.px(x, 5, a)
        s.hline(0, T - 1, 6, (31, 26, 36, 90))
        s.rect(2, 7, 12, 6, 'white2'); s.rect(3, 8, 10, 5, 'sea3')
        for x in range(4, 12, 2): s.px(x, 11, rng.choice(['red', 'ochre', 'white', 'pine', 'blue']))
        s.px(3, 8, 'sea'); s.px(4, 8, 'sea'); s.px(3, 9, 'sea')
    elif kind == 'garage':
        s.rect(2, 3, 12, 11, c3); s.rect(3, 4, 10, 10, 'white3')
        for y in range(5, 14, 2): s.hline(3, 12, y, 'stone2')
        s.px(8, 12, 'asph3')
    elif kind == 'roll':
        s.rect(1, 3, 14, 11, 'asph3'); s.rect(2, 4, 12, 10, 'stone2')
        for y in range(4, 14, 2): s.hline(2, 13, y, 'stone3')
        s.hline(1, 14, 3, 'ochre2')
    return s


for col in WALLS:
    for pos in ('l', 'm', 'r', 's'):
        for kind in FACADE_KINDS:
            add(f'f_{col}_{pos}_{kind}', facade(col, pos, kind), solid=True)


# --- vegetación y muros ---------------------------------------------------------
def canopy(top, bot, cx, cy, rx, ry, cols, rng, holes=0.0, lumpy=0.0):
    """Copa elíptica repartida entre el tile de arriba (overhead) y el de abajo (y >= 16).
    cols: (luz, base, sombra, contorno). Luz desde arriba a la izquierda."""
    light, base, dark, edge = cols
    for y in range(0, 32):
        for x in range(T):
            dx, dy = (x + .5 - cx) / rx, (y + .5 - cy) / ry
            r = dx * dx + dy * dy + (rng.random() - .5) * lumpy
            if r > 1:
                continue
            if holes and r < .8 and rng.random() < holes:
                continue
            c = base
            if dx + dy < -0.55: c = light
            elif dx * 0.6 + dy > 0.45: c = dark
            if r > .78: c = edge if dy > -0.2 else dark
            if rng.random() < .1: c = dark if c == base else c
            (top if y < T else bot).px(x, y - (0 if y < T else T), c)


def pine(v):
    """Pino piñonero: copa ancha y plana en el tile superior (overhead) y tronco inclinado abajo."""
    top, bot = Sprite(T, T), Sprite(T, T)
    rng = rng_for('pine', v)
    cols = ('pine2', 'pine3', 'pine4', mix('pine4', 'ink', .3)) if v == 0 else \
           (mix('pine2', 'sun', .3), 'pine2', 'pine3', 'pine4')
    for y in range(2, T):                        # tronco rojizo, algo torcido
        x = 7 + (1 if y > 9 else 0) - (1 if v and y < 6 else 0)
        bot.px(x, y, 'terra3'); bot.px(x + 1, y, 'ochre3')
    bot.px(6, 4, 'terra3'); bot.px(10, 2, 'ochre3')
    bot.hline(5, 11, 14, (31, 26, 36, 70)); bot.hline(6, 10, 15, (31, 26, 36, 50))
    canopy(top, bot, 8, 12 if v == 0 else 11, 8.6, 6.8, cols, rng, lumpy=.25)
    for _ in range(6):                           # mechones de luz
        x, y = rng.randrange(2, 10), rng.randrange(6, 11)
        top.px(x, y, cols[0]); top.px(x + 1, y, cols[0])
    return top, bot


def palm():
    """Palmera: penacho de hojas arqueadas y tronco anillado."""
    top, bot = Sprite(T, T), Sprite(T, T)
    import math
    for y in range(0, 15):
        x = 7 + (1 if y < 5 else 0)
        c = 'ochre2' if y % 3 else 'ochre3'
        bot.px(x, y, c); bot.px(x + 1, y, 'ochre3' if y % 3 else 'terra3')
    bot.hline(6, 10, 15, (31, 26, 36, 70))
    for ang, ln, droop in ((200, 7, .5), (160, 7, .5), (240, 6, .3), (300, 6, .3), (20, 7, .5), (-20, 7, .5),
                           (95, 5, .2), (130, 6, .6), (50, 6, .6)):
        a = math.radians(ang)
        for i in range(1, ln + 1):
            x = 8 + math.cos(a) * i
            y = 10 - math.sin(a) * i * .7 + droop * i * i / ln
            c = 'pine' if i < 3 else ('pine2' if i < ln - 1 else 'pine3')
            top.px(int(round(x)), int(round(y)), c)
            top.px(int(round(x)), int(round(y)) + 1, 'pine3' if i > 1 else 'pine2')
    top.rect(7, 9, 3, 3, 'pine2'); top.px(7, 9, 'sun')
    top.px(7, 12, 'ochre3'); top.px(9, 12, 'terra3'); top.px(8, 13, 'ochre3')   # dátiles
    return top, bot


def olive():
    """Olivo: copa gris plateada y abierta, tronco retorcido."""
    top, bot = Sprite(T, T), Sprite(T, T)
    rng = rng_for('olive')
    silver = (mix('pine', 'stone', .45), mix('pine2', 'stone2', .35), mix('pine3', 'stone3', .3), 'pine4')
    for y in range(0, 13):
        x = 7 + (1 if (y // 3) % 2 else 0)
        bot.px(x, y, 'stone3'); bot.px(x + 1, y, 'ochre3' if y % 4 else 'stone3')
    bot.px(6, 10, 'stone3'); bot.px(10, 11, 'stone3')
    bot.hline(4, 12, 13, (31, 26, 36, 70))
    canopy(top, bot, 8, 12, 7.6, 6.0, silver, rng, holes=.08, lumpy=.5)
    return top, bot


def cypress():
    """Ciprés: columna estrecha y oscura (cementerios, jardines)."""
    top, bot = Sprite(T, T), Sprite(T, T)
    rng = rng_for('cypress')
    for y in range(0, 30):
        half = min(3.5, 0.6 + y * 0.35) if y < 10 else (3.5 if y < 24 else 3.5 - (y - 24) * 0.5)
        for x in range(T):
            d = x + .5 - 8
            if abs(d) > half:
                continue
            c = 'pine3' if d < -1 else 'pine4' if d > 1 else ('pine3' if rng.random() < .6 else 'pine2')
            if d < -half + 1.2 and y % 3 == 0: c = 'pine2'
            (top if y < T else bot).px(x, y - (0 if y < T else T), c)
    bot.hline(5, 11, 15, (31, 26, 36, 70))
    return top, bot


for v in range(2):
    t, b = pine(v)
    add(f'tree_pine{v}_top', t, overhead=True)
    add(f'tree_pine{v}_bot', b, solid=True)
t, b = palm(); add('tree_palm_top', t, overhead=True); add('tree_palm_bot', b, solid=True)
t, b = olive(); add('tree_olive_top', t, overhead=True); add('tree_olive_bot', b, solid=True)
for v in range(2):
    s = Sprite(T, T)
    rng = rng_for('bush', v)
    cols = ('pine', 'pine2', 'pine3', 'pine4') if v == 0 else ('sun', 'pine', 'pine2', 'pine3')
    tmp = Sprite(T, T)
    canopy(tmp, s, 8, 26, 6.5, 5.0, cols, rng, lumpy=.4)
    if v == 1:
        for _ in range(4):
            x, y = rng.randrange(4, 12), rng.randrange(6, 12)
            if s.a[y, x, 3]: s.px(x, y, rng.choice(['white', 'red', 'ochre']))
    s.hline(4, 12, 15, (31, 26, 36, 60))
    add(f'bush_{v}', s, solid=True)


def wall(mask, kind):
    s = Sprite(T, T)
    if kind == 'stone':
        c1, c2, c3 = 'stone', 'stone2', 'stone3'
    elif kind == 'hedge':
        c1, c2, c3 = 'pine2', 'pine3', 'pine4'
    else:  # acantilado de cantera
        c1, c2, c3 = 'stone2', 'stone3', 'ink'
    rng = rng_for('wall', mask, kind)
    x0 = 0 if mask & W_ else 3
    x1 = T - 1 if mask & E else 12
    y0 = 0 if mask & N else 3
    y1 = T - 1 if mask & S_ else 12
    if kind == 'cliff':
        x0, x1, y0, y1 = 0, T - 1, 0, T - 1
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            c = c1
            if y >= y1 - 2: c = c3
            elif rng.random() < .25: c = c2
            if kind == 'stone' and (y % 4 == 0 or (x + (y // 4) * 3) % 6 == 0): c = c2
            s.px(x, y, c)
    if kind == 'cliff':
        for y in range(2, T, 5):
            s.hline(0, T - 1, y, c3)
    return s


for kind in ('stone', 'hedge', 'cliff'):
    for mask in range(16):
        add(f'w_{kind}_{mask}', wall(mask, kind), solid=True)

# --- interiores, escaleras y desniveles (añadidos al final: no cambian IDs anteriores) ---
def interior_tiles():
    def floor_wood(v):
        s = Sprite(T, T, 'ochre2')
        for y in range(0, T, 4):
            s.hline(0, T - 1, y + 3, 'ochre3')
            off = (y // 4 * 5 + v * 3) % T
            s.vline(off, y, y + 3, 'ochre3')
        s.speckle(rng_for('fw', v), ['ochre'], 0.04)
        return s
    for v in range(2):
        add(f'i_floor_wood_{v}', floor_wood(v))
    for v in range(2):
        s = Sprite(T, T, 'white')
        for y in range(0, T, 8):
            for x in range(0, T, 8):
                if ((x + y) // 8 + v) % 2:
                    s.rect(x, y, 8, 8, 'white2')
        add(f'i_floor_tile_{v}', s)
    s = Sprite(T, T, 'terra2'); s.speckle(rng_for('rug'), ['terra'], 0.2); edge_lines(s, 0, 'ochre')
    add('i_rug', s)
    s = Sprite(T, T, 'terra'); s.speckle(rng_for('rugc'), ['terra2'], 0.2)
    add('i_rug_c', s)
    # paredes: cara (sólida) y remate superior oscuro
    s = Sprite(T, T, 'white2'); s.rect(0, 12, T, 4, 'stone2'); s.hline(0, T - 1, 12, 'stone3'); s.hline(0, T - 1, 0, 'white3')
    add('i_wall', s, solid=True)
    s = Sprite(T, T, 'asph3'); s.hline(0, T - 1, T - 1, 'ink'); s.speckle(rng_for('wt'), ['asph2'], 0.1)
    add('i_wall_top', s, solid=True)
    s = Sprite(T, T, 'white2'); s.rect(0, 12, T, 4, 'stone2'); s.rect(3, 2, 10, 8, 'sea'); s.rect(3, 2, 10, 8, 'sea')
    s.vline(8, 2, 9, 'white'); s.hline(3, 12, 6, 'white'); edge_lines(s, 0b1111 ^ 0, 'white2')
    add('i_wall_window', s, solid=True)
    for side in ('l', 'r'):
        s = Sprite(T, T, 'white2'); s.rect(0, 12, T, 4, 'stone2')
        s.rect(0 if side == 'r' else 1, 2, 15, 9, 'pine3'); s.rect(0 if side == 'r' else 2, 3, 14 if side == 'l' else 14, 7, 'pine2')
        if side == 'l':
            s.hline(4, 10, 5, 'white'); s.hline(4, 8, 7, 'white')
        else:
            s.hline(1, 6, 5, 'white'); s.rect(9, 10, 3, 1, 'white')
        add(f'i_board_{side}', s, solid=True)
    # muebles (sólidos)
    s = Sprite(T, T); s.rect(1, 4, 14, 7, 'ochre2'); s.hline(1, 14, 4, 'ochre'); s.rect(2, 11, 2, 4, 'ochre3'); s.rect(12, 11, 2, 4, 'ochre3')
    s.rect(4, 6, 5, 3, 'white')
    add('i_desk', s, solid=True)
    s = Sprite(T, T); s.rect(4, 6, 8, 6, 'red'); s.rect(4, 2, 8, 4, 'terra2'); s.rect(4, 12, 1, 3, 'ink'); s.rect(11, 12, 1, 3, 'ink')
    add('i_chair', s)
    s = Sprite(T, T, 'ochre3'); 
    for y in (1, 6, 11):
        s.hline(1, 14, y + 4, 'ochre2')
        for x in range(2, 14, 2):
            s.vline(x, y, y + 3, rng_for('book', x, y).choice(['red', 'blue', 'pine2', 'ochre', 'white']))
    add('i_shelf', s, solid=True)
    s = Sprite(T, T); s.rect(1, 3, 14, 9, 'ochre2'); s.hline(1, 14, 3, 'ochre'); s.rect(2, 12, 2, 3, 'ochre3'); s.rect(12, 12, 2, 3, 'ochre3')
    add('i_table', s, solid=True)
    s = Sprite(T, T); s.rect(5, 9, 6, 6, 'terra2'); s.rect(3, 2, 10, 8, 'pine2'); s.speckle(rng_for('pl'), ['pine'], 0.3, (3, 2, 10, 8))
    add('i_plant', s, solid=True)
    s = Sprite(T, T); s.rect(1, 1, 14, 14, 'white'); s.rect(1, 1, 14, 4, 'blue'); s.rect(1, 5, 14, 10, 'white2'); s.rect(2, 6, 12, 8, 'white')
    add('i_bed', s, solid=True)
    s = Sprite(T, T, 'stone'); s.rect(2, 6, 12, 8, 'terra'); s.hline(2, 13, 6, 'terra2')
    for x in range(3, 13, 3): s.vline(x, 8, 12, 'terra2')
    add('i_exit', s)            # felpudo de salida (transitable)
    s = Sprite(T, T); s.rect(2, 2, 12, 12, 'white3'); s.rect(3, 3, 10, 10, 'white'); s.px(8, 8, 'ink'); s.vline(8, 4, 8, 'ink')
    add('i_clock', s, solid=True)
    # escaleras (transitables: unen alturas distintas) y bordillo de desnivel
    for o in ('v', 'h'):
        s = Sprite(T, T, 'stone')
        for i in range(0, T, 4):
            if o == 'v':
                s.hline(0, T - 1, i, 'white2'); s.hline(0, T - 1, i + 3, 'stone3')
            else:
                s.vline(i, 0, T - 1, 'white2'); s.vline(i + 3, 0, T - 1, 'stone3')
        add(f'st_stone_{o}', s, stairs=True)
    s = Sprite(T, T, 'ochre2')
    for i in range(0, T, 4):
        s.hline(0, T - 1, i, 'ochre'); s.hline(0, T - 1, i + 3, 'ochre3')
    add('st_wood_v', s, stairs=True)
    # patio: pavimento de colores y líneas de pista
    s = Sprite(T, T, 'terra'); s.speckle(rng_for('pista'), ['terra2'], 0.06)
    add('g_court_0', s)
    s = Sprite(T, T, 'terra'); s.hline(0, T - 1, 7, 'white'); s.speckle(rng_for('pista2'), ['terra2'], 0.06)
    add('g_court_line_h', s)
    s = Sprite(T, T, 'terra'); s.vline(7, 0, T - 1, 'white'); s.speckle(rng_for('pista3'), ['terra2'], 0.06)
    add('g_court_line_v', s)
    s = Sprite(T, T); s.rect(6, 2, 4, 10, 'white'); s.rect(5, 1, 6, 1, 'red'); s.vline(7, 12, 15, 'asph3')
    add('o_basket', s, solid=True)
    s = Sprite(T, T); s.rect(1, 6, 14, 3, 'ochre2'); s.rect(2, 9, 2, 5, 'ochre3'); s.rect(12, 9, 2, 5, 'ochre3')
    add('o_bench', s, solid=True)
    s = Sprite(T, T); s.vline(7, 3, 15, 'asph3'); s.rect(5, 0, 6, 4, 'white'); s.px(7, 1, 'ochre')
    add('o_lamp', s, solid=True)
    s = Sprite(T, T)
    for x in range(0, T, 3): s.vline(x, 4, 15, 'asph2')
    s.hline(0, T - 1, 4, 'asph3'); s.hline(0, T - 1, 9, 'asph3')
    add('o_fence', s, solid=True)


interior_tiles()


def ledge(mask):
    """Borde de nivel de terreno: franja de roca que ocupa la casilla (es sólida). Los bits N/E/S/W
    marcan el lado del vecino más bajo: ahí se ve la cara de la roca (más alta hacia el sur, que es
    lo que mira la cámara); en los lados altos asoma la hierba del nivel superior."""
    s = Sprite(T, T)
    rng = rng_for('ledge', mask)
    for y in range(T):
        for x in range(T):
            s.px(x, y, 'stone' if rng.random() < .6 else rng.choice(['stone2', 'white2', 'stone']))
    # grietas suaves
    for _ in range(3):
        x, y = rng.randrange(2, T - 2), rng.randrange(2, T - 6)
        for k in range(rng.randrange(2, 5)):
            s.px(x + k // 2, y + k, 'stone2')
    if mask & S_:   # cara visible hacia el sur: estratos y pie oscuro
        for y in range(7, T):
            for x in range(T):
                c = 'stone2' if (y - 7) % 4 else 'stone3'
                if y >= T - 2:
                    c = 'stone3'
                s.px(x, y, c if rng.random() > .08 else 'stone3')
        s.hline(0, T - 1, 6, 'white2')
    else:           # el borde no mira a cámara: se ve el canto de la roca
        s.hline(0, T - 1, T - 1, 'stone3')
    if mask & N:
        s.hline(0, T - 1, 0, 'stone3'); s.hline(0, T - 1, 1, 'stone2')
    else:           # arriba sigue el terreno alto: matas de hierba en el canto
        for x in range(T):
            if rng.random() < .45:
                s.px(x, 0, 'pine2')
            if rng.random() < .2:
                s.px(x, 1, 'pine3')
    if mask & W_:
        s.vline(0, 0, T - 1, 'stone3'); s.vline(1, 0, T - 1, 'stone2')
    if mask & E:
        s.vline(T - 1, 0, T - 1, 'stone3'); s.vline(T - 2, 0, T - 1, 'stone2')
    return s


for mask in range(16):
    add(f'w_ledge_{mask}', ledge(mask), solid=True)


# --- texturas añadidas (al final del atlas: no cambian los id existentes) ---------------
def bays(s, rng, v):              # plazas de aparcamiento
    for x in (0, 8):
        s.vline(x, 2, 13, 'white2')
    if v == 2:
        s.hline(0, T - 1, 2, 'white2')


def cobbles(s, rng, v):           # adoquines del casco antiguo
    for y in range(0, T, 4):
        off = (y // 4) % 2 * 2
        s.hline(0, T - 1, y, 'stone2')
        for x in range(off, T, 4):
            s.vline(x, y, y + 3, 'stone2')
            if rng.random() < .3:
                s.px(x + 1, y + 1, 'white2')


def flowerbed(s, rng, v):         # parterre con flores
    for _ in range(14):
        x, y = rng.randrange(1, 15), rng.randrange(1, 15)
        c = rng.choice(['red', 'ochre', 'white', 'terra', 'blue'])
        s.px(x, y, c); s.px(x, y + 1, 'pine3')


ground('asphalt', 'asph', ['asph2', 'asph3'], 0.10)
ground('parking', 'asph', ['asph2'], 0.08, bays)
ground('cobble', 'stone', ['white2'], 0.04, cobbles)
ground('flowers', 'pine', ['pine2'], 0.10, flowerbed)
ground('sandpit', 'sand', ['sand2', 'dry'], 0.15)


def obj(name, draw, **props):
    sp = Sprite(T, T)
    draw(sp)
    add(name, sp, **props)


def _fountain(s):
    for y in range(T):
        for x in range(T):
            d = (x - 7.5) ** 2 + (y - 8.5) ** 2
            if d < 52: s.px(x, y, 'stone2')
            if d < 36: s.px(x, y, 'sea2')
            if d < 20: s.px(x, y, 'sea')
    s.rect(7, 3, 2, 6, 'stone'); s.px(7, 2, 'foam'); s.px(8, 2, 'foam'); s.px(6, 4, 'foam'); s.px(9, 4, 'foam')


def _swing(s):
    s.hline(1, 14, 2, 'asph3'); s.vline(1, 2, 15, 'asph3'); s.vline(14, 2, 15, 'asph3')
    for x in (4, 10):
        s.vline(x, 3, 10, 'stone3'); s.vline(x + 2, 3, 10, 'stone3'); s.rect(x, 11, 3, 1, 'red')


def _slide(s):
    s.rect(2, 2, 4, 12, 'ochre2'); [s.hline(2, 5, y, 'ochre3') for y in range(3, 14, 3)]
    for k in range(10):
        s.rect(6 + k, 3 + k, 2, 2, 'blue')


def _bin(s):
    s.rect(5, 5, 6, 9, 'pine3'); s.rect(4, 4, 8, 2, 'pine4'); s.vline(7, 7, 12, 'pine2')


def _bus_l(s):
    s.rect(0, 2, T, 2, 'asph3'); s.rect(0, 4, T, 9, 'sea'); s.rect(1, 5, T - 1, 7, 'sea3')
    s.rect(2, 13, 12, 2, 'stone2'); s.vline(0, 2, 15, 'asph3'); s.px(4, 7, 'foam')


def _bus_r(s):
    s.rect(0, 2, T, 2, 'asph3'); s.rect(0, 4, 13, 9, 'sea'); s.rect(0, 5, 12, 7, 'sea3')
    s.vline(13, 2, 15, 'asph3'); s.rect(12, 0, 4, 5, 'blue'); s.rect(13, 1, 2, 3, 'white')


def _hydrant(s):
    s.rect(6, 6, 4, 8, 'red'); s.rect(5, 8, 6, 2, 'terra2'); s.rect(6, 5, 4, 1, 'terra3')


obj('o_fountain', _fountain, solid=True)
obj('o_swing', _swing, solid=True)
obj('o_slide', _slide, solid=True)
obj('o_bin', _bin, solid=True)
obj('o_busstop_l', _bus_l, solid=True)
obj('o_busstop_r', _bus_r, solid=True)
obj('o_hydrant', _hydrant, solid=True)

t, b = cypress(); add('tree_cypress_top', t, overhead=True); add('tree_cypress_bot', b, solid=True)
for f in range(4):
    add(f'seadeep_15_{f}', sea_tile(15, f, 'seadeep'), anim=4)


# --- barraca de pedra seca (2 × 2: cúpula en overhead, muro con portal sólido) y parada de mercado ---------
def barraca():
    tl, tr, bl, br = (Sprite(T, T) for _ in range(4))
    rng = rng_for('barraca')
    W2, H2 = 32, 32
    img = Sprite(W2, H2)
    for y in range(4, 31):
        for x in range(2, 30):
            dx, dy = (x + .5 - 16) / 13.5, (y + .5 - 20) / 15
            if dy < 0 and dx * dx + dy * dy > 1:      # cúpula falsa por aproximación de hiladas
                continue
            if dy >= 0 and abs(dx) > 1:
                continue
            c = 'stone'
            row = (y - 4) // 3
            if (x + row * 2) % 5 == 0 or (y - 4) % 3 == 0: c = 'stone2'
            if dx > .45: c = 'stone2' if c == 'stone' else 'stone3'
            if dx < -.5 and dy < .2 and c == 'stone': c = 'white2'
            if rng.random() < .06: c = 'stone3'
            img.px(x, y, c)
    for y in range(4, 9):                              # matas en la cúpula
        for x in range(10, 20):
            if rng.random() < .25 and img.a[y, x, 3]: img.px(x, y, rng.choice(['pine2', 'dry3']))
    for y in range(19, 31):                            # portal con dintel
        for x in range(13, 19):
            img.px(x, y, 'ink' if y > 19 else 'stone3')
    img.hline(11, 20, 18, 'stone3'); img.hline(11, 20, 17, 'white2')
    img.hline(3, 28, 31, (31, 26, 36, 90))
    tl.a = img.a[0:16, 0:16].copy(); tr.a = img.a[0:16, 16:32].copy()
    bl.a = img.a[16:32, 0:16].copy(); br.a = img.a[16:32, 16:32].copy()
    return tl, tr, bl, br


tl, tr, bl, br = barraca()
add('o_barraca_tl', tl, overhead=True); add('o_barraca_tr', tr, overhead=True)
add('o_barraca_bl', bl, solid=True); add('o_barraca_br', br, solid=True)


def stall(v):
    """Parada del mercado setmanal: toldo de rayas, mostrador con fruta, verdura o ropa."""
    s = Sprite(T, T)
    a, b = (('red', 'white'), ('pine2', 'white'), ('blue', 'white'))[v]
    for x in range(T):
        s.vline(x, 1, 4, a if (x // 2) % 2 == 0 else b)
    for x in range(0, T, 2): s.px(x, 5, a)
    s.vline(1, 5, 14, 'asph3'); s.vline(14, 5, 14, 'asph3')
    s.rect(1, 9, 14, 5, 'ochre2'); s.hline(1, 14, 9, 'ochre'); s.hline(1, 14, 13, 'ochre3')
    goods = (['red', 'ochre', 'pine', 'terra'], ['pine', 'pine2', 'sun', 'ochre'], ['blue', 'white', 'red', 'sea'])[v]
    rng = rng_for('stall', v)
    for x in range(2, 14):
        s.px(x, 8, rng.choice(goods))
        if rng.random() < .5: s.px(x, 7, rng.choice(goods))
    s.hline(1, 14, 15, (31, 26, 36, 70))
    return s


for v in range(3):
    add(f'o_stall_{v}', stall(v), solid=True)


# --- adornos de temporada (data/themes.json): se dibujan sobre el mapa, no bloquean ----------
def _pumpkin(s):
    for y in range(T):
        for x in range(T):
            if ((x - 7.5) / 6.5) ** 2 + ((y - 10.5) / 4.8) ** 2 < 1:
                s.px(x, y, 'ochre2' if x in (4, 7, 8, 11) else 'ochre')
    s.rect(7, 4, 2, 3, 'pine3')
    s.px(5, 9, 'ink'); s.px(6, 9, 'ink'); s.px(9, 9, 'ink'); s.px(10, 9, 'ink')
    for x in range(5, 11): s.px(x, 12 + x % 2, 'ink')


def _ghost(s):
    for y in range(2, 15):
        for x in range(3, 13):
            if (y < 7 and (x - 7.5) ** 2 + (y - 7) ** 2 < 22) or (7 <= y < 13) or (y >= 13 and x % 3 != 0):
                s.px(x, y, 'white')
    s.px(5, 7, 'ink'); s.px(10, 7, 'ink'); s.rect(7, 9, 2, 2, 'ink'); s.vline(12, 6, 13, 'white2')


def _cobweb(s):
    for k in range(0, 9):
        s.px(k, 0, 'white2'); s.px(0, k, 'white2'); s.px(k // 1, k, 'white2')
    for r in (3, 6):
        for k in range(r + 1):
            s.px(k, r - k, 'white2')


def _xmas(s):
    for y in range(2, 14):
        w = (y - 1) // 2
        for x in range(8 - w, 8 + w):
            s.px(x, y, 'pine2' if (x + y) % 3 else 'pine3')
    s.rect(7, 14, 2, 2, 'ochre3'); s.px(7, 1, 'ochre'); s.px(8, 1, 'ochre')
    for (x, y, c) in ((6, 6, 'red'), (9, 8, 'blue'), (5, 11, 'ochre'), (10, 12, 'red'), (8, 4, 'white')):
        s.px(x, y, c)


def _gift(s):
    s.rect(4, 8, 8, 7, 'red'); s.vline(7, 8, 14, 'ochre'); s.vline(8, 8, 14, 'ochre')
    s.hline(4, 11, 10, 'ochre'); s.px(6, 7, 'ochre'); s.px(9, 7, 'ochre')


def _garland(s):
    for x in range(T):
        y = 1 + int(2 * abs(((x / 15.0) * 2) - 1))
        s.px(x, y, 'pine2')
        if x % 4 == 1: s.px(x, y + 1, ('red', 'ochre', 'blue', 'white')[(x // 4) % 4])


for name, fn in (('th_pumpkin', _pumpkin), ('th_ghost', _ghost), ('th_cobweb', _cobweb),
                 ('th_xmas_tree', _xmas), ('th_gift', _gift), ('th_garland', _garland)):
    obj(name, fn)


# --- muebles de casa (interiores procedurales y casa de Nena) --------------------------
def _sofa(sp):
    sp.rect(0, 3, 16, 11, 'blue'); sp.rect(0, 3, 16, 4, 'sea3'); sp.rect(1, 7, 14, 6, 'blue')
    sp.vline(7, 7, 12, 'sea3'); sp.hline(0, 15, 14, 'ink')


def _armchair(sp):
    sp.rect(2, 3, 12, 11, 'terra2'); sp.rect(2, 3, 12, 4, 'terra3'); sp.rect(4, 7, 8, 6, 'terra'); sp.hline(2, 13, 14, 'ink')


def _tv(sp):
    sp.rect(1, 2, 14, 9, 'ink'); sp.rect(2, 3, 12, 7, 'sea3'); sp.px(3, 4, 'sea'); sp.rect(6, 11, 4, 1, 'asph3')
    sp.rect(0, 12, 16, 3, 'ochre3')


def _counter(sp):
    sp.rect(0, 2, 16, 13, 'white2'); sp.rect(0, 2, 16, 4, 'white'); sp.hline(0, 15, 6, 'white3'); sp.vline(8, 7, 14, 'white3')
    sp.px(6, 10, 'stone3'); sp.px(10, 10, 'stone3')


def _stove(sp):
    _counter(sp); sp.rect(2, 2, 12, 4, 'asph3')
    for x in (4, 10): sp.rect(x, 3, 2, 2, 'red')


def _sink(sp):
    _counter(sp); sp.rect(4, 2, 8, 4, 'stone'); sp.rect(5, 3, 6, 2, 'sea2'); sp.px(8, 1, 'stone3')


def _fridge(sp):
    sp.rect(2, 0, 12, 16, 'white'); sp.hline(2, 13, 6, 'white3'); sp.vline(12, 2, 4, 'stone3'); sp.vline(12, 8, 12, 'stone3')
    sp.vline(2, 0, 15, 'white2')


def _toilet(sp):
    sp.rect(5, 1, 6, 4, 'white2'); sp.rect(4, 5, 8, 8, 'white'); sp.rect(6, 7, 4, 4, 'sea'); sp.hline(4, 11, 13, 'white3')


def _shower(sp):
    for y in range(0, 16, 4):
        for x in range(0, 16, 4):
            sp.rect(x, y, 4, 4, 'sea' if (x + y) % 8 else 'white')
    sp.rect(7, 7, 2, 2, 'asph3'); sp.vline(0, 0, 15, 'white3')


def _bath(sp):
    sp.rect(0, 2, 16, 13, 'white'); sp.rect(2, 4, 12, 9, 'sea'); sp.rect(3, 5, 4, 2, 'foam')


def _wardrobe(sp):
    sp.rect(0, 0, 16, 15, 'ochre2'); sp.vline(8, 1, 14, 'ochre3'); sp.px(6, 7, 'ochre'); sp.px(9, 7, 'ochre')
    sp.hline(0, 15, 0, 'ochre'); sp.hline(0, 15, 15, 'ink')


def _washer(sp):
    sp.rect(1, 1, 14, 14, 'white'); sp.rect(1, 1, 14, 3, 'white2')
    for y in range(6, 14):
        for x in range(3, 13):
            if (x - 7.5) ** 2 + (y - 9.5) ** 2 < 14: sp.px(x, y, 'sea3' if (x - 7.5) ** 2 + (y - 9.5) ** 2 < 6 else 'stone2')


def _nightstand(sp):
    sp.rect(3, 5, 10, 9, 'ochre2'); sp.hline(3, 12, 9, 'ochre3'); sp.rect(6, 1, 4, 4, 'ochre'); sp.px(7, 0, 'white')


def _fireplace(sp):
    sp.rect(0, 1, 16, 14, 'stone'); sp.rect(3, 5, 10, 9, 'ink'); sp.rect(5, 9, 6, 4, 'red'); sp.rect(6, 8, 4, 3, 'ochre')
    sp.hline(0, 15, 1, 'stone2')


def _radiator(sp):
    for x in range(1, 15, 2): sp.vline(x, 4, 13, 'white')
    sp.hline(1, 14, 4, 'white2'); sp.hline(1, 14, 13, 'white3')


def _pc(sp):
    sp.rect(1, 6, 14, 8, 'ochre2'); sp.hline(1, 14, 6, 'ochre'); sp.rect(4, 0, 8, 6, 'ink'); sp.rect(5, 1, 6, 4, 'sea2')
    sp.rect(5, 9, 6, 2, 'asph2')


def _bed_t(sp):
    sp.rect(1, 2, 14, 14, 'white'); sp.rect(1, 2, 14, 2, 'ochre3'); sp.rect(3, 5, 10, 5, 'white2'); sp.rect(1, 11, 14, 5, 'blue')


def _bed_b(sp):
    sp.rect(1, 0, 14, 14, 'blue'); sp.hline(1, 14, 3, 'sea3'); sp.rect(1, 13, 14, 2, 'ochre3')


def _box(sp):
    sp.rect(2, 4, 12, 10, 'ochre'); sp.hline(2, 13, 7, 'ochre2'); sp.vline(8, 4, 7, 'ochre3'); sp.hline(2, 13, 13, 'ochre3')


def _toys(sp):
    sp.rect(1, 6, 14, 8, 'red'); sp.rect(3, 3, 3, 3, 'blue'); sp.rect(8, 2, 3, 4, 'ochre'); sp.rect(11, 4, 2, 2, 'pine')


def _mailbox(sp):
    for y in (2, 7):
        for x in (1, 6, 11):
            sp.rect(x, y, 4, 4, 'stone2'); sp.hline(x, x + 3, y + 1, 'ink')


def _bike(sp):
    for cx in (4, 12):
        for a in range(0, 360, 30):
            import math as _m
            sp.px(round(cx + 3 * _m.cos(_m.radians(a))), round(10 + 3 * _m.sin(_m.radians(a))), 'ink')
    sp.hline(4, 12, 8, 'red'); sp.vline(8, 6, 10, 'red'); sp.hline(10, 13, 5, 'ink')


def _lamp(sp):
    sp.rect(5, 1, 6, 4, 'ochre'); sp.vline(8, 5, 13, 'asph3'); sp.rect(6, 13, 4, 2, 'asph3')


def _stairs_up(sp):
    for y in range(0, 16, 4):
        sp.rect(0, y, 16, 4, 'ochre2'); sp.hline(0, 15, y, 'ochre'); sp.hline(0, 15, y + 3, 'ochre3')
    sp.rect(6, 5, 4, 6, 'white'); sp.px(7, 4, 'white'); sp.px(8, 4, 'white')


def _stairs_down(sp):
    for y in range(0, 16, 4):
        sp.rect(0, y, 16, 4, 'stone2'); sp.hline(0, 15, y, 'stone'); sp.hline(0, 15, y + 3, 'stone3')
    sp.rect(6, 5, 4, 6, 'white'); sp.px(7, 11, 'white'); sp.px(8, 11, 'white')


def _cashier(sp):
    _counter(sp); sp.rect(9, 1, 6, 4, 'asph3'); sp.rect(10, 2, 4, 2, 'pine')


def _fridge_shop(sp):
    sp.rect(0, 0, 16, 15, 'sea'); sp.rect(1, 1, 14, 13, 'sea3')
    for y in (3, 7, 11):
        sp.hline(1, 14, y, 'white2')
        for x in range(2, 14, 3): sp.px(x, y - 1, rng_for('fs', x, y).choice(['red', 'ochre', 'white', 'pine']))


for name, fn, solid in (('i_sofa', _sofa, True), ('i_armchair', _armchair, True), ('i_tv', _tv, True),
                        ('i_counter', _counter, True), ('i_stove', _stove, True), ('i_sink', _sink, True),
                        ('i_fridge', _fridge, True), ('i_toilet', _toilet, True), ('i_shower', _shower, False),
                        ('i_bath', _bath, True), ('i_wardrobe', _wardrobe, True), ('i_washer', _washer, True),
                        ('i_nightstand', _nightstand, True), ('i_fireplace', _fireplace, True),
                        ('i_radiator', _radiator, True), ('i_pc', _pc, True), ('i_bed_t', _bed_t, True),
                        ('i_bed_b', _bed_b, True), ('i_box', _box, True), ('i_toys', _toys, True),
                        ('i_mailbox', _mailbox, True), ('i_bike', _bike, True), ('i_lamp', _lamp, True),
                        ('i_stairs_up', _stairs_up, False), ('i_stairs_down', _stairs_down, False),
                        ('i_cashier', _cashier, True), ('i_fridge_shop', _fridge_shop, True)):
    if solid:
        obj(name, fn, solid=True)
    else:
        obj(name, fn)

# --- transiciones de terreno (Wang por esquinas) y sombras ----------------------
# tw_<A>_<B>_<c>: tile de A con las esquinas del bit c en B (NW=1, NE=2, SE=4, SW=8; c = 1..14).
# Mezcla bilineal desde las esquinas + dithering ordenado (Bayer 4×4) + ruido: borde orgánico y
# continuo entre tiles vecinos (dos tiles que comparten esquina comparten su terreno).
# Los usa tools/terrain_blend.py; tools/sat_pipeline.py exporta los mismos conjuntos como Wang sets de Tiled.
WANG_PAIRS = [('forest', 'scrub'), ('grass', 'scrub'), ('dry', 'grass'), ('park', 'urban'), ('dry', 'scrub'),
              ('dry', 'urban'), ('park', 'scrub'), ('grass', 'park'), ('grass', 'urban'), ('scrub', 'urban'),
              ('forest', 'park'), ('farm', 'scrub'), ('dry', 'rock'), ('grass', 'rock'), ('rock', 'scrub'),
              ('forest', 'rock'), ('dry', 'farm'), ('forest', 'grass'), ('dry', 'forest'), ('dry', 'railyard'),
              ('grass', 'railyard'), ('dry', 'beach'), ('beach', 'urban'), ('farm', 'grass'), ('dry', 'vineyard')]
BAYER4 = [[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]


def wang_tile(a, b, c, v):
    sa, sb = tiles[index[f'g_{a}_{v}']][1], tiles[index[f'g_{b}_{v}']][1]
    rng = rng_for('wang', a, b, c, v)
    corners = [(c >> k) & 1 for k in range(4)]  # NW, NE, SE, SW
    s = Sprite(T, T)
    for y in range(T):
        for x in range(T):
            u, w = (x + 0.5) / T, (y + 0.5) / T
            wb = (corners[0] * (1 - u) * (1 - w) + corners[1] * u * (1 - w) +
                  corners[2] * u * w + corners[3] * (1 - u) * w)
            th = (BAYER4[y % 4][x % 4] + 0.5) / 16 * 0.6 + 0.2 + (rng.random() - 0.5) * 0.25
            s.a[y, x] = (sb if wb > th else sa).a[y, x]
    return s


for a, b in WANG_PAIRS:
    for c in range(1, 15):
        add(f'tw_{a}_{b}_{c}', wang_tile(a, b, c, c % 3))


def shadow(name, alpha_fn):
    s = Sprite(T, T)
    for y in range(T):
        for x in range(T):
            al = alpha_fn(x, y)
            if al > 0:
                s.a[y, x] = (22, 18, 36, int(min(125, al * 1.15)))
    add(name, s)


# sombras (luz desde arriba a la izquierda → caen a la derecha y abajo), capa ground_detail: también
# se ven sobre el asfalto vectorial. sh_e: junto al lado este de un edificio; sh_se/sh_s: bajo la
# fachada desplazadas a la derecha; sh_tree: elipse bajo la copa.
_fade = lambda d, n: max(0.0, 1 - d / n)
shadow('sh_e', lambda x, y: 95 * _fade(x, 7) * (1 if y >= 4 else _fade(4 - y, 4)) if x < 7 else 0)
shadow('sh_e_top', lambda x, y: 95 * _fade(x, 7) * _fade(max(0, 8 - y), 5) if x < 7 else 0)
shadow('sh_s', lambda x, y: 80 * _fade(y, 4) * _fade(max(0, 5 - x), 5) if y < 4 else 0)
shadow('sh_se', lambda x, y: 85 * _fade(y, 4) * _fade(x, 7) if (y < 4 and x < 7) else 0)
shadow('sh_tree', lambda x, y: 100 * max(0.0, 1 - (((x - 10.5) / 6.5) ** 2 + ((y - 12.5) / 3.2) ** 2)) ** 0.7)


# --- interiores de los POIs con minijuegos (fase 4) -----------------------------------------------------
# AL FINAL DEL ATLAS a propósito: los ids de los tiles anteriores no cambian y los mapas ya compilados
# siguen valiendo. Casino (moqueta, màquines de fira, ruleta, rètol), Gimnàs (pesos, bici estàtica, cinta,
# estora) i Poliesportiu (parquet de pista, porteria, cons, vitrina de trofeus).
def _carpet(v):
    s = Sprite(T, T)
    s.rect(0, 0, T, T, 'terra2')
    for y in range(T):
        for x in range(T):
            if (x + y + v * 3) % 8 == 0 or (x - y) % 8 == 4: s.px(x, y, 'terra')
    for x, y in ((3, 3), (11, 11)): s.px(x, y, 'ochre')
    return s


for _v in range(2):
    add(f'i_floor_carpet_{_v}', _carpet(_v))


def _court(v):
    s = Sprite(T, T)
    s.rect(0, 0, T, T, 'ochre2')
    for y in range(0, T, 4): s.hline(0, 15, y, 'ochre3' if (y // 4 + v) % 2 else 'ochre')
    for y in range(T):
        for x in range(T):
            if rng_for('court', x, y + v * 16).random() < 0.06: s.px(x, y, 'ochre3')
    return s


add('i_floor_court_0', _court(0))
add('i_floor_court_1', _court(1))
_cl = _court(0); _cl.hline(0, 15, 7, 'white'); _cl.hline(0, 15, 8, 'white')
add('i_court_line', _cl)
_mat = Sprite(T, T); _mat.rect(0, 0, T, T, 'sea3'); _mat.rect(1, 1, 14, 14, 'sea2')
for _y in range(3, 14, 4): _mat.hline(1, 14, _y, 'sea3')
add('i_mat', _mat)


def _slot(sp):    # màquina de fira: rètol de llums, pantalla de 3 rodets, palanca
    sp.rect(2, 0, 12, 15, 'terra3'); sp.rect(3, 1, 10, 13, 'red')
    for x in range(3, 13, 2): sp.px(x, 1, 'ochre' if x % 4 == 1 else 'white')
    sp.rect(4, 4, 8, 5, 'ink'); sp.rect(5, 5, 2, 3, 'white'); sp.rect(7, 5, 2, 3, 'white'); sp.rect(9, 5, 2, 3, 'white')
    sp.px(5, 6, 'red'); sp.px(7, 6, 'ochre'); sp.px(9, 6, 'pine2')
    sp.rect(5, 10, 6, 2, 'ochre2'); sp.vline(14, 3, 8, 'stone2'); sp.rect(14, 2, 2, 2, 'red')
    sp.rect(2, 14, 12, 2, 'asph3')


def _roulette_l(sp):
    sp.rect(0, 3, 16, 11, 'pine3'); sp.rect(1, 4, 15, 9, 'pine2'); sp.hline(0, 15, 14, 'ochre3')
    for a in range(0, 360, 30):
        import math as _mm
        x, y = 7 + 4 * _mm.cos(_mm.radians(a)), 8 + 4 * _mm.sin(_mm.radians(a))
        sp.px(round(x), round(y), 'red' if (a // 30) % 2 else 'ink')
    sp.rect(6, 7, 3, 3, 'ochre'); sp.px(7, 8, 'white')


def _roulette_r(sp):
    sp.rect(0, 3, 16, 11, 'pine3'); sp.rect(0, 4, 15, 9, 'pine2'); sp.hline(0, 15, 14, 'ochre3')
    for i in range(3):
        for j in range(4):
            sp.rect(2 + j * 3, 5 + i * 3, 2, 2, 'red' if (i + j) % 2 else 'ink')


def _weights(sp):  # banc amb barra i discos
    sp.rect(3, 8, 10, 3, 'asph3'); sp.vline(4, 11, 14, 'asph2'); sp.vline(11, 11, 14, 'asph2')
    sp.hline(0, 15, 5, 'stone2'); sp.rect(0, 2, 3, 7, 'ink'); sp.rect(13, 2, 3, 7, 'ink')
    sp.rect(1, 3, 1, 5, 'asph3'); sp.rect(14, 3, 1, 5, 'asph3')


def _gym_bike(sp):
    sp.rect(3, 12, 10, 2, 'asph3'); sp.vline(8, 5, 12, 'stone3'); sp.rect(6, 4, 5, 2, 'ink')
    sp.rect(10, 8, 4, 4, 'red'); sp.px(11, 9, 'white'); sp.hline(3, 7, 3, 'stone2'); sp.vline(3, 3, 7, 'stone2')
    sp.rect(2, 1, 3, 2, 'sea3')


def _treadmill(sp):
    sp.rect(1, 9, 14, 5, 'asph3'); sp.rect(2, 10, 12, 3, 'ink')
    for x in range(3, 14, 3): sp.px(x, 11, 'asph2')
    sp.vline(2, 2, 9, 'stone2'); sp.vline(13, 2, 9, 'stone2'); sp.rect(3, 1, 10, 3, 'asph2'); sp.rect(6, 2, 4, 1, 'sea')


def _goal(part):
    def f(sp):
        sp.rect(0, 2, 16, 12, 'white2')
        for y in range(3, 14, 2):
            for x in range(0, 16, 2): sp.px(x + (y // 2) % 2, y, 'white3')
        sp.hline(0, 15, 1, 'white'); sp.hline(0, 15, 2, 'white')
        if part == 'l': sp.vline(0, 1, 14, 'white'); sp.vline(1, 1, 14, 'white')
        if part == 'r': sp.vline(14, 1, 14, 'white'); sp.vline(15, 1, 14, 'white')
    return f


def _cones(sp):
    for cx, cy in ((4, 12), (11, 8)):
        sp.rect(cx - 3, cy + 2, 7, 1, 'terra3')
        for k in range(5): sp.hline(cx - k // 2, cx + k // 2, cy - 4 + k + 1, 'terra' if k != 2 else 'white')
    sp.rect(6, 13, 4, 2, 'ochre')


def _trophies(sp):
    sp.rect(1, 1, 14, 14, 'ochre3'); sp.rect(2, 2, 12, 12, 'sea3')
    for x, h in ((3, 4), (7, 6), (11, 3)):
        sp.rect(x, 9 - h, 3, 2, 'ochre'); sp.vline(x + 1, 11 - h, 10, 'ochre2'); sp.rect(x, 10, 3, 1, 'ochre2')
    sp.hline(2, 13, 11, 'white3')


def _wall_neon(sp):
    sp.rect(0, 0, T, T, 'white2'); sp.rect(0, 12, T, 4, 'white3')
    sp.rect(1, 3, 14, 7, 'ink')
    for x in range(2, 14, 2): sp.px(x, 4, 'ochre' if x % 4 else 'red'); sp.px(x + 1, 8, 'red' if x % 4 else 'ochre')
    sp.rect(4, 5, 8, 3, 'terra'); sp.rect(5, 6, 6, 1, 'ochre')


for name, fn in (('i_slot', _slot), ('i_roulette_l', _roulette_l), ('i_roulette_r', _roulette_r),
                 ('i_weights', _weights), ('i_gym_bike', _gym_bike), ('i_treadmill', _treadmill),
                 ('i_goal_l', _goal('l')), ('i_goal_m', _goal('m')), ('i_goal_r', _goal('r')),
                 ('i_cones', _cones), ('i_trophies', _trophies), ('i_wall_neon', _wall_neon)):
    obj(name, fn, solid=True)

# --- fase 6: tanques, murs i reixes de parcel·les i escoles; patis, pistes i parc viari ---------------------
# També AL FINAL de l'atles (ids estables). Peces h (horitzontal), v (vertical) i c (pal/cantonada): el mapa
# tria la peça segons els veïns (tools/decorate_map.py).
def _fence(kind, part):
    def f(sp):
        if kind == 'wood':
            post, rail, hi = 'ochre3', 'ochre2', 'ochre'
        elif kind == 'mesh':
            post, rail, hi = 'pine3', 'pine2', 'pine'
        else:  # mur arrebossat
            post, rail, hi = 'white3', 'white2', 'white'
        if kind == 'wall':
            if part in ('h', 'c'): sp.rect(0 if part == 'h' else 5, 6, 16 if part == 'h' else 6, 7, rail); sp.rect(0 if part == 'h' else 5, 5, 16 if part == 'h' else 6, 2, hi); sp.hline(0 if part == 'h' else 5, 15 if part == 'h' else 10, 12, post)
            if part in ('v', 'c'): sp.rect(5, 0 if part == 'v' else 5, 6, 16 if part == 'v' else 8, rail); sp.rect(5, 0 if part == 'v' else 5, 2, 16 if part == 'v' else 8, hi)
            return
        if part in ('h', 'c'):
            sp.hline(0, 15, 7, rail); sp.hline(0, 15, 11, rail)
            for x in range(1, 16, 5 if kind == 'wood' else 4):
                sp.vline(x, 4, 13, post); sp.px(x, 4, hi)
            if kind == 'mesh':
                for x in range(0, 16, 2):
                    for y in range(6, 12, 2): sp.px(x + (y // 2) % 2, y, rail)
        if part in ('v', 'c'):
            sp.vline(7, 0, 15, rail); sp.vline(9, 0, 15, rail)
            for y in range(1, 16, 5 if kind == 'wood' else 4):
                sp.rect(6, y, 5, 2, post); sp.px(6, y, hi)
    return f


for _k in ('wood', 'wall', 'mesh'):
    for _p in ('h', 'v', 'c'):
        obj(f'o_{_k}_{_p}', _fence(_k, _p), solid=True)


def _ground(base, c2, c3, pattern, v):
    s = Sprite(T, T)
    s.rect(0, 0, T, T, base)
    r = rng_for('g6', base, v)
    for y in range(T):
        for x in range(T):
            if pattern == 'yard' and (x % 8 == 0 or y % 8 == 0): s.px(x, y, c2)
            elif r.random() < 0.06: s.px(x, y, c2 if r.random() < .6 else c3)
    return s


for _v in range(2):
    add(f'g_yard_{_v}', _ground('stone', 'stone2', 'white2', 'yard', _v))
    add(f'g_court_red_{_v}', _ground('terra', 'terra2', 'ochre2', 'court', _v))
    add(f'g_court_green_{_v}', _ground('pine2', 'pine3', 'pine', 'court', _v))
    add(f'g_skate_{_v}', _ground('white3', 'stone2', 'white2', 'yard', _v))
for _c, _n in (('terra', 'red'), ('pine2', 'green')):
    _h = Sprite(T, T); _h.rect(0, 0, T, T, _c); _h.hline(0, 15, 7, 'white'); _h.hline(0, 15, 8, 'white')
    add(f'g_court_{_n}_line_h', _h)
    _vv = Sprite(T, T); _vv.rect(0, 0, T, T, _c); _vv.vline(7, 0, 15, 'white'); _vv.vline(8, 0, 15, 'white')
    add(f'g_court_{_n}_line_v', _vv)
# parc viari (Parc de la Silena): carrers petits d'asfalt amb línia, zebra i senyals
_mr = Sprite(T, T); _mr.rect(0, 0, T, T, 'asph')
for _x in range(0, 16, 6): _mr.hline(_x, _x + 2, 8, 'white')
add('g_miniroad_h', _mr)
_mv = Sprite(T, T); _mv.rect(0, 0, T, T, 'asph')
for _y in range(0, 16, 6): _mv.vline(8, _y, _y + 2, 'white')
add('g_miniroad_v', _mv)
_mz = Sprite(T, T); _mz.rect(0, 0, T, T, 'asph')
for _x in range(1, 16, 4): _mz.rect(_x, 1, 2, 14, 'white')
add('g_minizebra', _mz)
_ramp = Sprite(T, T); _ramp.rect(0, 0, T, T, 'white3')
for _y in range(16): _ramp.hline(0, 15, _y, 'white2' if _y < 8 else 'stone2')
_ramp.hline(0, 15, 0, 'asph3')
add('g_skate_ramp', _ramp)


def _stop_sign(sp):
    sp.vline(7, 6, 15, 'stone3'); sp.vline(8, 6, 15, 'asph2')
    sp.rect(4, 0, 8, 7, 'red'); sp.rect(5, 1, 6, 5, 'red'); sp.hline(5, 10, 3, 'white')


def _round_sign(sp):
    sp.vline(7, 6, 15, 'stone3'); sp.vline(8, 6, 15, 'asph2')
    sp.rect(4, 0, 8, 7, 'blue'); sp.px(6, 2, 'white'); sp.px(9, 2, 'white'); sp.px(6, 5, 'white'); sp.px(9, 5, 'white')


def _minilight(sp):
    sp.vline(7, 7, 15, 'asph3'); sp.rect(5, 0, 6, 8, 'ink')
    sp.rect(6, 1, 4, 2, 'red'); sp.rect(6, 5, 4, 2, 'pine')


for name, fn in (('o_sign_stop', _stop_sign), ('o_sign_round', _round_sign), ('o_minilight', _minilight)):
    obj(name, fn, solid=True)

# --- aula de l'escola (fase 6): pissarra a la paret i pupitres -------------------------------------------
def _blackboard(sp):
    sp.rect(0, 0, T, T, 'white2'); sp.rect(0, 12, T, 4, 'white3')
    sp.rect(1, 2, 14, 9, 'ochre3'); sp.rect(2, 3, 12, 7, 'pine4')
    sp.hline(3, 9, 5, 'white'); sp.hline(3, 7, 7, 'white2'); sp.px(11, 5, 'ochre'); sp.hline(4, 12, 11, 'ochre3')


def _desk(sp):
    sp.rect(2, 4, 12, 6, 'ochre2'); sp.rect(2, 4, 12, 1, 'ochre'); sp.vline(3, 10, 13, 'stone3'); sp.vline(12, 10, 13, 'stone3')
    sp.rect(5, 5, 4, 3, 'white'); sp.px(10, 6, 'blue')
    sp.rect(5, 12, 6, 3, 'blue')


obj('i_blackboard', _blackboard, solid=True)
obj('i_school_desk', _desk, solid=True)

# --- blocs de pisos (fase 6): ascensor i porta de pis a la paret del replà -----------------------------
def _lift(sp):
    sp.rect(0, 0, T, T, 'white2'); sp.rect(0, 12, T, 4, 'stone2'); sp.hline(0, T - 1, 12, 'stone3')
    sp.rect(2, 1, 11, 11, 'stone3'); sp.rect(3, 2, 4, 10, 'stone'); sp.rect(8, 2, 4, 10, 'stone')
    sp.vline(7, 2, 11, 'asph2'); sp.hline(3, 11, 2, 'white3')
    sp.rect(4, 0, 7, 1, 'ink'); sp.px(6, 0, 'red'); sp.px(7, 0, 'red')
    sp.rect(13, 5, 2, 4, 'asph3'); sp.px(13, 6, 'sun'); sp.px(14, 7, 'sun')


def _flat_door(sp):
    sp.rect(0, 0, T, T, 'white2'); sp.rect(0, 12, T, 4, 'stone2')
    sp.rect(3, 1, 10, 15, 'terra3'); sp.rect(4, 2, 8, 14, 'terra2'); sp.rect(5, 3, 6, 5, 'terra'); sp.rect(5, 9, 6, 5, 'terra')
    sp.px(10, 9, 'sun'); sp.rect(6, 4, 4, 2, 'sun'); sp.px(7, 4, 'ink'); sp.px(8, 5, 'ink')
    sp.rect(3, 15, 10, 1, 'terra3')


obj('i_lift', _lift, solid=True)
obj('i_flat_door', _flat_door, solid=False)

# --- Cova de Roda (fase 6): roca amb la boca de la cova (3 × 2) i escales de corda entre nivells ---------
def _rock(sp, top, side):
    sp.rect(0, 0, T, T, 'stone2')
    rng = rng_for('cave_rock', top, side)
    sp.speckle(rng, ['stone', 'stone3'], 0.25)
    for _ in range(3):
        x, y = rng.randrange(1, 13), rng.randrange(2, 13)
        sp.hline(x, x + 2, y, 'stone3'); sp.px(x, y - 1, 'white3')
    if top:
        for x in range(T):
            h = 3 + (x * 7 + (0 if side == 'm' else 3)) % 4 // 2
            for y in range(h):
                sp.px(x, y, (0, 0, 0, 0))
            sp.px(x, h, 'white3')
    if side == 'l':
        for y in range(T): sp.px(0, y, (0, 0, 0, 0)); sp.px(1, y, 'stone3') if y > 3 else None
    if side == 'r':
        for y in range(T): sp.px(15, y, (0, 0, 0, 0)); sp.px(14, y, 'stone3') if y > 3 else None


def _mouth(sp):
    sp.rect(0, 0, T, T, 'stone2'); sp.speckle(rng_for('mouth'), ['stone', 'stone3'], 0.2)
    for y in range(T):
        for x in range(T):
            if (x - 7.5) ** 2 / 42 + (y - 16) ** 2 / 200 < 1:
                sp.px(x, y, 'ink' if (x - 7.5) ** 2 / 26 + (y - 16) ** 2 / 150 < 1 else 'asph3')
    sp.hline(5, 10, 15, 'asph3')


def _ladder(sp, down):
    sp.rect(0, 0, T, T, 'asph3' if down else 'stone2')
    if down:
        for y in range(T):
            for x in range(T):
                if (x - 7.5) ** 2 + (y - 8) ** 2 < 42: sp.px(x, y, 'ink')
    sp.vline(4, 1 if down else 0, 15, 'terra2'); sp.vline(11, 1 if down else 0, 15, 'terra2')
    for y in range(2 if down else 1, 16, 4): sp.hline(5, 10, y, 'terra')
    if not down:
        sp.rect(3, 0, 10, 1, 'sun')


obj('o_cave_rock_tl', lambda s: _rock(s, True, 'l'), solid=True)
obj('o_cave_rock_tm', lambda s: _rock(s, True, 'm'), solid=True)
obj('o_cave_rock_tr', lambda s: _rock(s, True, 'r'), solid=True)
obj('o_cave_rock_l', lambda s: _rock(s, False, 'l'), solid=True)
obj('o_cave_rock_r', lambda s: _rock(s, False, 'r'), solid=True)
obj('o_cave_mouth', _mouth, solid=False)
obj('o_cave_ladder_down', lambda s: _ladder(s, True), solid=False)
obj('o_cave_ladder_up', lambda s: _ladder(s, False), solid=False)

# --- Port de Roda de Berà: barcos amarrats (2 caselles, vistos des de dalt), noray, salvavides i fars de la bocana.
# AL FINAL de l'atles (ids estables). o_boat_<tipus><color>_<dir>_<0|1>: dir = r/l (proa a la dreta/esquerra,
# 0 = casella esquerra) o d/u (proa avall/amunt, 0 = casella de dalt). La popa toca el pantalà.
def _boat_full(kind, color):
    s = Sprite(32, 16)
    prof = {}
    for x in range(1, 31):
        hw = 4.6 if x < 21 else 4.6 * (30.5 - x) / 9.5
        prof[x] = hw
        for y in range(16):
            d = abs(y + 0.5 - 8)
            if d <= hw:
                s.px(x, y, color if d > hw - 1.3 else 'white')
    for x in range(1, 31):       # contorn fosc
        for y in range(16):
            if s.a[y, x, 3] and any(not (0 <= x + dx < 32 and 0 <= y + dy < 16) or not s.a[y + dy, x + dx, 3]
                                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                s.px(x, y, 'ink')
    if kind == 's':              # velero: cabina, pal i botavara
        s.rect(7, 6, 9, 4, 'white2'); s.hline(8, 14, 6, 'white3'); s.px(9, 8, 'sea2'); s.px(12, 8, 'sea2')
        s.hline(4, 20, 8, 'stone3'); s.rect(19, 7, 2, 2, 'ink'); s.px(24, 8, 'stone3')
    else:                        # llanxa: cabina amb parabrisa i motor fora borda
        s.rect(11, 5, 9, 6, 'white2'); s.vline(20, 5, 10, 'sea2'); s.vline(21, 6, 9, 'sea2')
        s.hline(12, 18, 5, 'white3'); s.rect(0, 6, 2, 4, 'asph3'); s.rect(3, 6, 6, 4, 'stone')
    return s


def _cut(big, x, y):
    t = Sprite(T, T)
    t.a[:, :] = big.a[y:y + T, x:x + T]
    return t


for kind in ('s', 'm'):
    for color in ('blue', 'red', 'pine2'):
        big = _boat_full(kind, color)
        tag = kind + {'blue': 'b', 'red': 'r', 'pine2': 'g'}[color]
        rot = {'r': big.a, 'l': big.a[:, ::-1], 'd': np.rot90(big.a, -1), 'u': np.rot90(big.a, 1)}
        for d, arr in rot.items():
            full = Sprite(arr.shape[1], arr.shape[0]); full.a[:, :] = arr
            for i in range(2):
                add(f'o_boat_{tag}_{d}_{i}', _cut(full, i * T if d in 'rl' else 0, i * T if d in 'du' else 0), solid=True)


def _bollard(s):
    s.rect(5, 9, 6, 4, 'asph'); s.rect(6, 6, 4, 4, 'asph2'); s.rect(5, 5, 6, 2, 'asph3'); s.hline(6, 9, 5, 'stone2')


def _lifebuoy(s):
    s.vline(7, 3, 14, 'stone3'); s.vline(8, 3, 14, 'stone2')
    for y in range(T):
        for x in range(T):
            d = (x - 7.5) ** 2 + (y - 7.5) ** 2
            if 9 <= d < 25:
                s.px(x, y, 'red' if (x < 8) == (y < 8) else 'white')


def _beacon(color):
    def draw(s):
        s.rect(4, 12, 8, 3, 'stone2'); s.rect(5, 3, 6, 9, 'white')
        for y in (4, 7, 10):
            s.rect(5, y, 6, 2, color)
        s.rect(6, 1, 4, 2, 'sun'); s.px(7, 0, 'foam'); s.px(8, 0, 'foam'); s.vline(4, 3, 11, 'ink'); s.vline(11, 3, 11, 'ink')
    return draw


obj('o_bollard', _bollard, solid=True)
obj('o_lifebuoy', _lifebuoy, solid=True)
obj('o_beacon_g', _beacon('pine2'), solid=True)
obj('o_beacon_r', _beacon('red'), solid=True)

# --- parcs infantils més variats: balancí, molla, castell amb tobogan i taula de pícnic (AL FINAL: ids estables)
def _seesaw(s):
    for k in range(4):                      # peu triangular
        s.hline(7 - k // 2, 8 + k // 2, 9 + k, 'asph3')
    s.hline(5, 10, 13, 'asph2')
    for k in range(14):                     # taulell inclinat, amb gruix
        y = 9 - (k * 4) // 13
        s.px(1 + k, y, 'red'); s.px(1 + k, y + 1, 'terra2')
    s.rect(1, 8, 3, 2, 'sun'); s.rect(12, 4, 3, 2, 'sun')        # seients
    s.vline(4, 6, 8, 'asph3'); s.hline(3, 5, 6, 'asph3')         # agafadors
    s.vline(11, 2, 5, 'asph3'); s.hline(10, 12, 2, 'asph3')


def _springrider(s):
    for y in range(9, 14):
        s.px(7 + (y % 2), y, 'stone3')
    s.rect(4, 4, 8, 5, 'pine2'); s.rect(3, 3, 3, 3, 'pine2'); s.px(4, 3, 'ink'); s.rect(9, 4, 2, 1, 'sun')
    s.rect(6, 13, 4, 2, 'asph2')


def _climb(s):
    s.rect(2, 3, 10, 10, 'ochre2'); s.rect(3, 4, 8, 8, 'ochre')
    s.rect(1, 1, 12, 3, 'red'); s.hline(2, 11, 3, 'terra2')
    for y in (6, 9):
        s.hline(3, 10, y, 'ochre3')
    for k in range(5):
        s.rect(11 + k // 2, 8 + k, 3, 2, 'blue')


def _picnic(s):
    s.rect(2, 2, 12, 3, 'ochre2'); s.rect(2, 6, 12, 5, 'ochre'); s.hline(2, 13, 8, 'ochre3')
    s.rect(2, 12, 12, 3, 'ochre2'); s.vline(3, 11, 11, 'ochre3'); s.vline(12, 11, 11, 'ochre3')


obj('o_seesaw', _seesaw, solid=True)
obj('o_springrider', _springrider, solid=True)
obj('o_climb', _climb, solid=True)
obj('o_picnic', _picnic, solid=True)

# --- pista poliesportiva blava (Poliesportiu municipal i pistes a l'aire lliure): AL FINAL, ids estables
for _v in range(2):
    add(f'g_court_blue_{_v}', _ground('blue', 'sea3', 'sea2', 'court', _v))
_h = Sprite(T, T); _h.rect(0, 0, T, T, 'blue'); _h.hline(0, 15, 7, 'white'); _h.hline(0, 15, 8, 'white')
add('g_court_blue_line_h', _h)
_vv = Sprite(T, T); _vv.rect(0, 0, T, T, 'blue'); _vv.vline(7, 0, 15, 'white'); _vv.vline(8, 0, 15, 'white')
add('g_court_blue_line_v', _vv)

# --- gasolineres: marquesina (overhead, 16 peces segons els veïns) i sortidor; AL FINAL de l'atles ---------
def _canopy(mask):
    s = Sprite(T, T)
    s.rect(0, 0, T, T, 'white2')
    for y in (5, 11):
        s.hline(0, 15, y, 'white3')
    s.px(4, 8, 'sun'); s.px(12, 2, 'sun'); s.px(12, 14, 'sun')       # llums
    if not mask & N: s.rect(0, 0, T, 3, 'red'); s.hline(0, 15, 3, 'terra3')
    if not mask & S_: s.rect(0, 12, T, 4, 'red'); s.hline(0, 15, 12, 'white'); s.hline(0, 15, 15, 'terra3')
    if not mask & W_: s.rect(0, 0, 2, T, 'red')
    if not mask & E: s.rect(14, 0, 2, T, 'red')
    return s


for _m in range(16):
    add(f'o_canopy_{_m}', _canopy(_m), overhead=True)


def _pump(s):
    s.rect(4, 3, 8, 11, 'white'); s.rect(4, 3, 8, 3, 'red'); s.rect(5, 7, 6, 3, 'ink'); s.px(6, 8, 'sun'); s.px(8, 8, 'sun')
    s.vline(12, 6, 11, 'asph3'); s.px(13, 11, 'asph3'); s.rect(3, 14, 10, 2, 'stone2')
    s.vline(3, 3, 13, 'ink'); s.vline(12, 3, 5, 'ink')


def _pillar(s):
    s.rect(6, 0, 4, 14, 'white3'); s.vline(6, 0, 13, 'stone2'); s.rect(5, 13, 6, 3, 'stone2')


obj('o_fuel_pump', _pump, solid=True)
obj('o_canopy_pillar', _pillar, solid=True)

# --- placas solars, grades i camp de gespa artificial (camp de futbol, pavelló): AL FINAL, ids estables ----
def _solar(sp):
    sp.rect(0, 0, T, T, 'stone3')
    sp.rect(1, 1, 14, 14, mix('blue', 'ink', .55))
    for k in (5, 10):
        sp.vline(k, 1, 14, 'stone2'); sp.hline(1, 14, k, 'stone2')
    sp.px(3, 3, 'sea'); sp.px(8, 2, 'sea'); sp.px(12, 7, 'sea')


def _bleacher(sp, inside):
    base = 'stone2' if inside else 'white3'
    sp.rect(0, 0, T, T, base)
    for y in (0, 5, 10):
        sp.rect(0, y, T, 4, 'stone' if inside else 'white2'); sp.hline(0, 15, y + 4, 'asph3')
        for x in range(1, 16, 3):
            sp.rect(x, y + 1, 2, 2, ('blue', 'red', 'ochre')[(x // 3 + y) % 3])


def _turf(v):
    sp = Sprite(T, T)
    sp.rect(0, 0, T, T, mix('pine2', 'pine3', .45))
    for x in range(0, T, 8):
        sp.rect(x, 0, 4, T, mix('pine2', 'pine3', .25) if (x // 8 + v) % 2 == 0 else mix('pine2', 'pine3', .45))
    r = rng_for('turf', v)
    for _ in range(10):
        sp.px(int(r.random() * 16), int(r.random() * 16), 'pine2')
    return sp


def _turf_line(kind):
    sp = _turf(0)
    if kind == 'h': sp.hline(0, 15, 7, 'white'); sp.hline(0, 15, 8, 'white')
    elif kind == 'v': sp.vline(7, 0, 15, 'white'); sp.vline(8, 0, 15, 'white')
    else:   # punt central
        for y in range(T):
            for x in range(T):
                if 30 <= (x - 7.5) ** 2 + (y - 7.5) ** 2 <= 49: sp.px(x, y, 'white')
        sp.rect(7, 7, 2, 2, 'white')
    return sp


add('r_solar', (lambda: (lambda sp: (_solar(sp), sp)[1])(Sprite(T, T)))(), solid=True)
add('i_bleacher', (lambda: (lambda sp: (_bleacher(sp, True), sp)[1])(Sprite(T, T)))(), solid=True)
add('o_bleacher', (lambda: (lambda sp: (_bleacher(sp, False), sp)[1])(Sprite(T, T)))(), solid=True)
for _v in range(2):
    add(f'g_turf_{_v}', _turf(_v))
add('g_turf_line_h', _turf_line('h'))
add('g_turf_line_v', _turf_line('v'))
add('g_turf_spot', _turf_line('c'))
for _p in ('l', 'm', 'r'):
    obj(f'o_goal_{_p}', _goal(_p), solid=True)

# --- font d'aigua potable (amenity=drinking_water): AL FINAL, ids estables --------------------------------
def _drinking(sp):
    sp.rect(5, 12, 6, 3, 'stone2'); sp.rect(6, 3, 4, 10, 'stone'); sp.rect(6, 3, 4, 2, 'stone3')
    sp.rect(9, 5, 3, 2, 'asph3'); sp.px(11, 7, 'sea'); sp.px(11, 9, 'sea'); sp.px(11, 11, 'sea2')
    sp.rect(4, 13, 8, 1, 'sea2')


obj('o_drinking', _drinking, solid=True)

# --- botigues grans (súpers i Leroy Merlin, procgen.store): AL FINAL, ids estables --------------------------
def _store_floor(v):
    sp = Sprite(T, T, 'white2')
    sp.rect(0, 0, T, T, mix('white', 'white2', .5 if v else .25))
    sp.hline(0, 15, 15, mix('white2', 'stone2', .35)); sp.vline(15, 0, 15, mix('white2', 'stone2', .35))
    sp.px(3, 4, 'white'); sp.px(11, 9, 'white')
    return sp


PRODUCTS = (('red', 'ochre', 'white'), ('ochre', 'terra', 'ochre2'), ('blue', 'white', 'sea'),
            ('pine2', 'white', 'ochre'), ('red', 'white', 'blue'), ('terra2', 'sand', 'white'))


def _shelf_food(v):
    sp = Sprite(T, T)
    sp.rect(0, 0, T, T, 'stone2'); sp.rect(0, 0, T, 1, 'stone3'); sp.rect(0, 15, T, 1, 'asph3')
    cols = PRODUCTS[v % len(PRODUCTS)]
    r = rng_for('shelf', v)
    for y in (1, 6, 11):
        sp.hline(0, 15, y + 4, 'stone3')
        x = 1
        while x < 15:
            w = r.choice((2, 2, 3))
            c = r.choice(cols)
            sp.rect(x, y, min(w, 15 - x), 4, c)
            sp.px(x, y, mix(c, 'white', .4))
            x += w + (1 if r.random() < 0.3 else 0)
    return sp


def _fruit(v):
    sp = Sprite(T, T)
    sp.rect(1, 3, 14, 12, 'ochre3'); sp.rect(2, 4, 12, 10, 'ochre2')
    c1, c2 = (('red', 'terra2'), ('ochre', 'terra'), ('pine2', 'pine'), ('sand', 'ochre'))[v % 4]
    r = rng_for('fruit', v)
    for _ in range(14):
        x, y = 2 + int(r.random() * 11), 4 + int(r.random() * 9)
        sp.rect(x, y, 2, 2, c1); sp.px(x, y, mix(c1, 'white', .4)); sp.px(x + 1, y + 1, c2)
    sp.hline(1, 14, 9, 'ochre3')
    return sp


def _bread(sp):
    sp.rect(1, 4, 14, 10, 'ochre3'); sp.rect(2, 5, 12, 8, 'ochre2')
    for x, y in ((3, 6), (8, 6), (4, 9), (9, 10)):
        sp.rect(x, y, 4, 2, mix('ochre', 'terra', .35)); sp.hline(x, x + 3, y, 'sand')


def _freezer(sp):
    sp.rect(0, 2, 16, 13, 'white'); sp.rect(1, 3, 14, 11, mix('sea', 'white', .45))
    sp.vline(8, 3, 13, 'white2')
    for x, y in ((3, 6), (11, 5), (4, 10), (12, 10)):
        sp.rect(x, y, 2, 2, ('red', 'blue', 'ochre', 'pine2')[(x + y) % 4])


def _checkout(sp):
    sp.rect(0, 3, 16, 10, 'stone2'); sp.rect(0, 5, 16, 5, 'asph3')
    for x in range(1, 16, 4): sp.vline(x, 5, 9, 'asph2')
    sp.rect(3, 6, 3, 3, 'red'); sp.rect(10, 6, 2, 3, 'ochre')
    sp.hline(0, 15, 12, 'stone3')


def _till(sp):
    sp.rect(0, 3, 16, 10, 'stone2'); sp.rect(3, 1, 9, 6, 'asph3'); sp.rect(4, 2, 7, 3, 'sea')
    sp.rect(5, 8, 6, 3, 'ink'); sp.hline(5, 10, 8, 'asph2'); sp.px(13, 5, 'red')


def _cart(sp):
    sp.rect(2, 3, 12, 9, 'stone'); sp.rect(3, 4, 10, 7, 'white2')
    for x in range(4, 13, 2): sp.vline(x, 4, 10, 'stone')
    sp.hline(2, 13, 3, 'red'); sp.rect(12, 1, 3, 2, 'red')
    sp.px(3, 13, 'ink'); sp.px(12, 13, 'ink')


def _baskets(sp):
    for k in range(3):
        y = 9 - k * 3
        sp.rect(2, y, 12, 5, 'red'); sp.hline(2, 13, y, 'terra2')
        for x in range(3, 13, 3): sp.px(x, y + 2, 'terra2')


def _diy_wood(sp):
    for k, y in enumerate(range(2, 14, 3)):
        c = ('ochre2', 'sand', 'ochre', 'ochre3')[k % 4]
        sp.rect(0, y, 16, 3, c); sp.hline(0, 15, y, mix(c, 'white', .3)); sp.px(5 + k * 2, y + 1, 'ochre3')
    sp.vline(0, 2, 14, 'stone3'); sp.vline(15, 2, 14, 'stone3')


def _diy_paint(sp):
    sp.rect(0, 0, T, T, 'stone2')
    for y in (1, 8):
        sp.hline(0, 15, y + 6, 'stone3')
        for k, x in enumerate(range(1, 15, 5)):
            c = ('red', 'blue', 'ochre', 'pine2', 'white', 'terra')[(k + y) % 6]
            sp.rect(x, y + 1, 4, 5, 'white2'); sp.rect(x, y + 2, 4, 3, c); sp.hline(x, x + 3, y + 1, 'stone')


def _diy_tools(sp):
    sp.rect(0, 0, T, T, 'ochre2')
    for y in range(1, 16, 3):
        for x in range(1, 16, 3): sp.px(x, y, 'ochre3')
    sp.rect(2, 2, 2, 7, 'asph3'); sp.rect(1, 2, 4, 2, 'stone')          # martell
    sp.rect(7, 3, 1, 8, 'stone'); sp.rect(6, 10, 3, 3, 'red')            # tornavís
    sp.rect(11, 2, 2, 9, 'stone2'); sp.rect(10, 2, 4, 2, 'stone')        # clau anglesa
    sp.rect(2, 12, 5, 2, 'ochre'); sp.rect(9, 13, 5, 1, 'asph3')


def _diy_tiles(sp):
    sp.rect(0, 0, T, T, 'stone3')
    for y in range(1, 15, 5):
        for x in range(1, 15, 5):
            c = ('white', 'terra2', 'sea', 'sand', 'stone', 'ochre2')[(x * 3 + y) % 6]
            sp.rect(x, y, 4, 4, c); sp.px(x, y, mix(c, 'white', .4))


def _diy_garden(sp):
    sp.rect(0, 11, 16, 4, 'ochre3')
    for x, c in ((1, 'pine2'), (6, 'pine'), (11, 'pine2')):
        sp.rect(x + 1, 8, 3, 3, 'terra2'); sp.rect(x, 3, 5, 5, c); sp.px(x + 2, 2, ('red', 'ochre', 'white')[x % 3])
        sp.px(x + 1, 4, mix(c, 'white', .3))


def _diy_pipe(sp):
    sp.rect(0, 0, T, T, 'stone2')
    for y in range(2, 14, 3):
        c = ('white', 'stone', 'terra', 'ochre')[(y // 3) % 4]
        sp.rect(0, y, 16, 2, c); sp.hline(0, 15, y, mix(c, 'white', .4))


def _pallet(sp):
    sp.rect(0, 12, 16, 3, 'ochre3'); sp.hline(0, 15, 12, 'ochre2')
    sp.rect(1, 3, 14, 9, 'ochre'); sp.rect(1, 3, 14, 2, 'sand'); sp.vline(8, 3, 11, 'ochre3')
    sp.rect(3, 6, 3, 2, 'white'); sp.rect(10, 6, 3, 2, 'red')


for _v in range(2):
    add(f'i_floor_store_{_v}', _store_floor(_v))
for _v in range(6):
    add(f'i_shelf_food_{_v}', _shelf_food(_v), solid=True)
for _v in range(4):
    add(f'i_fruit_{_v}', _fruit(_v), solid=True)
for _n, _f in (('i_bread', _bread), ('i_freezer', _freezer), ('i_checkout', _checkout), ('i_till', _till),
               ('i_cart', _cart), ('i_baskets', _baskets), ('i_diy_wood', _diy_wood), ('i_diy_paint', _diy_paint),
               ('i_diy_tools', _diy_tools), ('i_diy_tiles', _diy_tiles), ('i_diy_garden', _diy_garden),
               ('i_diy_pipe', _diy_pipe), ('i_pallet', _pallet)):
    obj(_n, _f, solid=True)

# --- cases amb placas solars (procgen opts.solar): AL FINAL, ids estables --------------------------------------
def _inverter(sp):
    sp.rect(3, 2, 10, 12, 'white'); sp.rect(3, 2, 10, 1, 'white2'); sp.rect(5, 4, 6, 3, 'asph3')
    sp.hline(6, 9, 5, 'pine2'); sp.px(11, 9, 'pine2'); sp.px(11, 11, 'ochre'); sp.rect(5, 13, 6, 1, 'stone3')


def _battery(sp):
    for x in (1, 6, 11):
        sp.rect(x, 1, 4, 14, 'stone'); sp.rect(x, 1, 4, 1, 'white2'); sp.rect(x + 1, 4, 2, 6, 'asph3')
        for y in range(5, 10, 2): sp.hline(x + 1, x + 2, y, 'pine2')


def _smart_panel(sp):
    sp.rect(0, 0, T, T, 'white2'); sp.rect(0, 12, T, 4, 'stone2')
    sp.rect(3, 2, 10, 8, 'asph3'); sp.rect(4, 3, 8, 6, 'sea'); sp.rect(5, 4, 3, 2, 'ochre'); sp.rect(9, 6, 2, 2, 'pine2')


def _robot_vac(sp):
    for y in range(T):
        for x in range(T):
            if (x - 7.5) ** 2 + (y - 8.5) ** 2 <= 30: sp.px(x, y, 'asph3')
            elif (x - 7.5) ** 2 + (y - 8.5) ** 2 <= 36: sp.px(x, y, 'stone3')
    sp.rect(6, 6, 4, 2, 'stone'); sp.px(7, 10, 'pine2')


def _ev_charger(sp):
    sp.rect(5, 1, 6, 13, 'white'); sp.rect(6, 3, 4, 3, 'sea'); sp.rect(7, 8, 2, 2, 'pine2')
    sp.vline(11, 6, 13, 'asph3'); sp.hline(11, 14, 13, 'asph3'); sp.rect(5, 14, 6, 1, 'stone3')


for _n, _f, _solid in (('i_inverter', _inverter, True), ('i_battery', _battery, True), ('i_smart_panel', _smart_panel, True),
                       ('i_robot_vac', _robot_vac, False), ('i_ev_charger', _ev_charger, True)):
    obj(_n, _f, solid=_solid)

# --- zonas revisadas (decorate_map.zone_polish): playa, plazas y monumentos. AL FINAL, ids estables ----------
def _umbrella(col):
    def d(sp):
        sp.vline(8, 9, 15, 'stone3')
        for y in range(T):
            for x in range(T):
                r2 = (x - 7.5) ** 2 + (y - 6.5) ** 2
                if r2 <= 42:
                    ang = math.atan2(y - 6.5, x - 7.5)
                    sp.px(x, y, col if int((ang + math.pi) / (math.pi / 4)) % 2 else 'white')
                elif r2 <= 49: sp.px(x, y, 'ink')
        sp.rect(7, 6, 2, 2, 'stone3')
    return d


def _towel(col):
    def d(sp):
        sp.rect(3, 1, 10, 14, col); sp.rect(3, 1, 10, 1, 'white')
        for y in range(4, 14, 3): sp.hline(3, 12, y, 'white')
        sp.rect(3, 14, 10, 1, 'white')
    return d


def _lifeguard(sp):
    sp.vline(3, 6, 15, 'ochre3'); sp.vline(12, 6, 15, 'ochre3'); sp.hline(3, 12, 11, 'ochre3')
    for y in range(7, 15, 2): sp.hline(5, 10, y, 'ochre2')
    sp.rect(2, 3, 12, 4, 'red'); sp.rect(2, 3, 12, 1, 'white'); sp.rect(4, 0, 8, 3, 'sun'); sp.hline(4, 11, 2, 'ochre3')


def _shower(sp):
    sp.rect(5, 12, 6, 3, 'stone2'); sp.vline(8, 2, 12, 'stone3'); sp.hline(8, 12, 2, 'stone3')
    sp.rect(11, 3, 3, 2, 'stone'); [sp.px(x, y, 'sea2') for x, y in ((11, 6), (13, 7), (12, 9), (11, 10))]


def _terrace(sp):
    for x, y in ((1, 2), (12, 2), (1, 11), (12, 11)):
        sp.rect(x, y, 3, 3, 'terra2')
    sp.rect(4, 4, 8, 8, 'white'); sp.rect(4, 4, 8, 1, 'white2'); sp.rect(6, 6, 2, 2, 'sea'); sp.rect(9, 8, 2, 2, 'red')
    sp.rect(5, 11, 6, 1, 'stone3')


def _planter(sp):
    sp.rect(2, 7, 12, 8, 'terra'); sp.rect(2, 7, 12, 1, 'terra2'); sp.rect(2, 14, 12, 1, 'terra3')
    sp.rect(3, 3, 10, 5, 'pine2')
    for k, (x, y) in enumerate(((4, 3), (7, 2), (10, 3), (5, 5), (9, 5), (12, 4))):
        sp.px(x, y, ('red', 'sun', 'blush', 'white')[k % 4])


def _statue(sp):
    sp.rect(3, 11, 10, 4, 'stone2'); sp.rect(4, 10, 8, 1, 'stone'); sp.hline(3, 12, 14, 'stone3')
    sp.rect(6, 4, 4, 6, 'stone'); sp.rect(6, 1, 4, 3, 'stone'); sp.vline(10, 3, 6, 'stone'); sp.px(10, 2, 'stone')
    sp.vline(6, 5, 9, 'stone3'); sp.rect(6, 12, 4, 1, 'sun')


def _info(sp):
    sp.vline(4, 9, 15, 'asph3'); sp.vline(11, 9, 15, 'asph3')
    sp.rect(1, 1, 14, 9, 'pine3'); sp.rect(2, 2, 12, 7, 'white'); sp.rect(3, 3, 5, 4, 'pine2'); sp.rect(4, 4, 2, 2, 'sea')
    for y in (3, 5, 7): sp.hline(9, 12, y, 'asph3')


def _bike_rack(sp):
    for x in (2, 7, 12):
        sp.vline(x, 5, 13, 'stone3'); sp.vline(x + 2, 5, 13, 'stone3'); sp.hline(x, x + 2, 4, 'stone3')
    sp.hline(1, 15, 13, 'asph3')
    sp.rect(5, 7, 1, 6, 'blue'); sp.rect(10, 7, 1, 6, 'red')


def _icecream(sp):
    sp.rect(2, 6, 12, 7, 'white'); sp.rect(2, 6, 12, 1, 'white2'); sp.rect(3, 8, 10, 3, 'sea2')
    sp.rect(4, 8, 2, 2, 'blush'); sp.rect(7, 8, 2, 2, 'sun'); sp.rect(10, 8, 2, 2, 'pine2')
    for x in (4, 11): sp.rect(x, 13, 2, 2, 'asph3')
    sp.vline(7, 0, 5, 'stone3'); sp.rect(3, 0, 10, 2, 'red'); sp.hline(3, 12, 1, 'white')


def _sandcastle(sp):
    sp.rect(3, 8, 10, 6, 'sand2'); sp.rect(3, 13, 10, 1, 'ochre2')
    for x in (3, 7, 11): sp.rect(x, 5, 2, 3, 'sand2'); sp.px(x, 4, 'sand2')
    sp.rect(7, 10, 2, 3, 'ochre3'); sp.vline(8, 0, 4, 'asph3'); sp.rect(9, 0, 3, 2, 'red')


def _lounger(col):
    def d(sp):
        sp.rect(4, 1, 8, 4, col); sp.rect(4, 1, 8, 1, 'white')          # capçal aixecat
        sp.rect(4, 5, 8, 9, 'white'); [sp.hline(4, 11, y, col) for y in (7, 10, 13)]
        for x, y in ((4, 14), (11, 14), (4, 5), (11, 5)): sp.px(x, y, 'stone3')
    return d


for _n, _f, _solid in (('o_umbrella_0', _umbrella('red'), True), ('o_umbrella_1', _umbrella('blue'), True),
                       ('o_umbrella_2', _umbrella('sun'), True), ('o_towel_0', _towel('sea'), False),
                       ('o_towel_1', _towel('blush'), False), ('o_lifeguard', _lifeguard, True), ('o_shower', _shower, True),
                       ('o_terrace', _terrace, True), ('o_planter', _planter, True), ('o_statue', _statue, True),
                       ('o_info', _info, True), ('o_bike_rack', _bike_rack, True), ('o_icecream', _icecream, True),
                       ('o_sandcastle', _sandcastle, True), ('o_lounger_0', _lounger('sea'), True),
                       ('o_lounger_1', _lounger('sun'), True)):
    obj(_n, _f, solid=_solid)

# --- obres (decorate_map.construction_sites): solar, estructura de formigó, tanca, grua i maquinària. AL FINAL --
def _site_ground(v):
    def d(sp):
        r = rng_for('site', v)
        sp.rect(0, 0, T, T, 'dry2'); sp.speckle(r, ['dry3', 'ochre3', 'stone2'], 0.12)
        if v == 1:                                   # roderes de camió
            for y in range(T): sp.px(4 + (y // 6) % 2, y, 'ochre3'); sp.px(11 + (y // 6) % 2, y, 'ochre3')
        if v == 2:
            for k in range(3): sp.rect(2 + k * 5, 10 - k, 2, 1, 'stone3')
    return d


def _skel_roof(v):
    def d(sp):
        sp.rect(0, 0, T, T, 'stone'); sp.hline(0, T - 1, 0, 'white2'); sp.hline(0, T - 1, T - 1, 'stone3')
        for x in (1, 14):                            # pilars que sobresurten amb ferros
            sp.rect(x - 1, 1, 2, 2, 'stone3'); sp.px(x - 1, 0, 'terra3'); sp.px(x, 0, 'terra3')
        if v == 0:
            for x in range(3, 13, 3): sp.vline(x, 4, 12, 'terra3')     # ferralla de la llosa
            sp.hline(3, 12, 8, 'terra3')
        else:
            sp.rect(3, 4, 10, 8, 'ochre2'); [sp.vline(x, 4, 11, 'ochre3') for x in range(4, 13, 3)]   # encofrat
    return d


def _skel_face(pos):
    def d(sp):
        sp.rect(0, 0, T, T, 'asph'); sp.rect(0, 0, T, 3, 'stone'); sp.hline(0, T - 1, 3, 'stone3')
        sp.rect(0, 9, T, 2, 'stone'); sp.rect(0, 14, T, 2, 'stone2')
        if pos in ('l', 's'): sp.rect(0, 0, 3, T, 'stone2')
        if pos in ('r', 's'): sp.rect(13, 0, 3, T, 'stone2')
        if pos == 'm': sp.rect(7, 0, 2, T, 'stone2')
        sp.rect(3, 11, 4, 3, 'terra'); sp.hline(3, 6, 12, 'terra2')  # paret de maó a mig fer
    return d


def _sfence(kind):
    def d(sp):
        if kind == 'h':
            sp.rect(0, 5, T, 8, 'pine3'); sp.hline(0, T - 1, 4, 'stone3'); sp.hline(0, T - 1, 13, 'stone3')
            for x in (0, 15): sp.vline(x, 3, 14, 'stone3')
            sp.rect(4, 7, 8, 3, 'white'); sp.rect(5, 8, 2, 1, 'red'); sp.rect(9, 8, 2, 1, 'red')
        elif kind == 'v':
            sp.rect(5, 0, 6, T, 'pine3'); sp.vline(4, 0, T - 1, 'stone3'); sp.vline(11, 0, T - 1, 'stone3')
        else:
            sp.rect(4, 4, 8, 9, 'pine3'); sp.rect(4, 3, 8, 1, 'stone3'); sp.rect(6, 12, 4, 3, 'stone2')
    return d


def _crane(part):
    def d(sp):
        Y = 'sun'
        Yd = mix('sun', 'ochre3', .5)
        if part == 'base':
            sp.rect(1, 9, 14, 6, 'stone2'); sp.rect(1, 9, 14, 1, 'stone')
            sp.rect(5, 0, 6, 10, Y); [sp.hline(5, 10, y, Yd) for y in range(1, 10, 3)]
        elif part == 'mast':
            sp.rect(5, 0, 6, T, Y)
            for y in range(0, T, 4): sp.px(6 + (y // 4) % 2 * 3, y, Yd); sp.hline(5, 10, y + 2, Yd)
        elif part == 'jib':
            sp.rect(0, 5, T, 5, Y)
            for x in range(0, T, 4): sp.vline(x, 5, 9, Yd); sp.px(x + 2, 7, Yd)
        elif part == 'cab':
            sp.rect(0, 5, T, 5, Y); sp.rect(4, 2, 8, 9, 'white'); sp.rect(5, 3, 6, 4, 'sea'); sp.rect(5, 0, 6, 2, Y)
        elif part == 'counter':
            sp.rect(0, 5, T, 5, Y); sp.rect(1, 3, 9, 9, 'stone3'); sp.hline(1, 9, 7, 'stone2')
        elif part == 'cable':
            sp.vline(8, 0, T - 1, 'asph3')
        elif part == 'hook':
            sp.vline(8, 0, 6, 'asph3'); sp.rect(6, 6, 5, 3, 'red'); sp.px(8, 10, 'asph3'); sp.px(7, 11, 'asph3')
            sp.rect(3, 12, 10, 3, 'ochre2'); sp.hline(3, 12, 13, 'ochre3')     # palet de maons penjat
    return d


def _mixer(sp):
    sp.rect(2, 11, 12, 2, 'asph3'); sp.rect(3, 13, 2, 2, 'ink'); sp.rect(11, 13, 2, 2, 'ink')
    for y in range(T):
        for x in range(T):
            if (x - 8) ** 2 / 30 + (y - 6.5) ** 2 / 22 <= 1: sp.px(x, y, 'red')
    sp.rect(4, 3, 8, 1, 'terra2'); sp.rect(6, 5, 4, 3, 'terra2'); sp.rect(12, 1, 3, 3, 'stone3')


def _sandpile(sp):
    for y in range(T):
        for x in range(T):
            d = (x - 7.5) ** 2 / 50 + (y - 11) ** 2 / 30
            if y >= 3 and d <= 1: sp.px(x, y, 'sand2' if d > .5 else 'sand')
    sp.px(6, 6, 'ochre2'); sp.px(9, 9, 'ochre2'); sp.px(4, 11, 'ochre2')


def _bricks(sp):
    sp.rect(1, 12, 14, 3, 'ochre2'); sp.hline(1, 14, 13, 'ochre3')
    for y in range(3, 12, 3):
        for x in range(1 + (y // 3) % 2 * 2, 14, 4): sp.rect(x, y, 3, 2, 'terra')
    sp.vline(0, 2, 12, 'white2'); sp.vline(15, 2, 12, 'white2')


def _rebar(sp):
    sp.rect(1, 12, 14, 2, 'ochre2')
    for y in range(4, 12, 2): sp.hline(0, 15, y, 'terra3')
    sp.rect(3, 3, 1, 10, 'ochre3'); sp.rect(12, 3, 1, 10, 'ochre3')


def _cabin(side):
    def d(sp):
        sp.rect(0, 2, T, 12, 'white'); sp.rect(0, 1, T, 2, 'stone'); sp.rect(0, 13, T, 2, 'stone3')
        if side == 'l':
            sp.vline(0, 1, 14, 'stone3'); sp.rect(3, 5, 6, 4, 'sea'); sp.rect(4, 6, 2, 1, 'foam')
        else:
            sp.vline(15, 1, 14, 'stone3'); sp.rect(9, 5, 4, 8, 'blue'); sp.px(10, 9, 'sun'); sp.rect(2, 5, 5, 3, 'sea')
    return d


def _toilet(sp):
    sp.rect(4, 1, 8, 14, 'blue'); sp.rect(4, 1, 8, 2, mix('blue', 'white', .3)); sp.rect(6, 5, 4, 8, mix('blue', 'ink', .3))
    sp.px(9, 9, 'white'); sp.rect(6, 4, 4, 1, 'pine2')


def _digger(side):
    def d(sp):
        Y, Yd = 'sun', mix('sun', 'ochre3', .5)
        if side == 'l':                              # braç i cullera
            sp.rect(10, 3, 6, 3, Y); sp.rect(4, 3, 7, 2, Y); sp.rect(2, 5, 3, 6, Y)
            sp.rect(0, 10, 6, 4, 'stone3'); sp.hline(0, 5, 13, 'asph3'); [sp.px(x, 14, 'stone3') for x in (0, 2, 4)]
        else:                                        # cabina i erugues
            sp.rect(0, 11, 15, 4, 'asph3'); [sp.px(x, 12, 'stone3') for x in range(1, 15, 2)]
            sp.rect(0, 4, 13, 7, Y); sp.rect(5, 1, 7, 7, Y); sp.rect(6, 2, 5, 4, 'sea'); sp.hline(0, 12, 10, Yd)
    return d


def _cone(sp):
    sp.rect(3, 13, 10, 2, 'terra2')
    for y in range(3, 13):
        w = 1 + (y - 3) // 2
        sp.hline(8 - w, 7 + w, y, 'white' if y in (6, 7, 10) else 'terra')


def _barrow(sp):
    sp.rect(2, 4, 9, 6, 'pine2'); sp.rect(3, 5, 7, 3, 'stone2'); sp.rect(11, 6, 3, 3, 'ink'); sp.px(12, 7, 'stone3')
    sp.hline(0, 3, 10, 'asph3'); sp.hline(0, 3, 12, 'asph3'); sp.vline(4, 10, 13, 'asph3')


def _scaffold(top):
    def d(sp):
        for x in (1, 14): sp.vline(x, 0, T - 1, 'stone3')
        for y in ((2, 9) if not top else (4, 12)):
            sp.rect(0, y, T, 2, 'ochre2'); sp.hline(0, T - 1, y + 1, 'ochre3')
        for k in range(T): sp.px(k, (k if not top else T - 1 - k), 'stone2')
    return d


for _n, _f, _solid in (('g_site_0', _site_ground(0), False), ('g_site_1', _site_ground(1), False),
                       ('g_site_2', _site_ground(2), False),
                       ('r_skel_0', _skel_roof(0), True), ('r_skel_1', _skel_roof(1), True),
                       ('f_skel_l', _skel_face('l'), True), ('f_skel_m', _skel_face('m'), True),
                       ('f_skel_r', _skel_face('r'), True), ('f_skel_s', _skel_face('s'), True),
                       ('o_sfence_h', _sfence('h'), True), ('o_sfence_v', _sfence('v'), True),
                       ('o_sfence_c', _sfence('c'), True),
                       ('o_crane_base', _crane('base'), True), ('o_mixer', _mixer, True), ('o_sandpile', _sandpile, True),
                       ('o_bricks', _bricks, True), ('o_rebar', _rebar, True), ('o_cabin_l', _cabin('l'), True),
                       ('o_cabin_r', _cabin('r'), True), ('o_toilet', _toilet, True), ('o_digger_l', _digger('l'), True),
                       ('o_digger_r', _digger('r'), True), ('o_cone', _cone, True), ('o_barrow', _barrow, True),
                       ('o_scaffold', _scaffold(False), True)):
    obj(_n, _f, solid=_solid)
for _n, _f in (('o_crane_mast', _crane('mast')), ('o_crane_jib', _crane('jib')), ('o_crane_cab', _crane('cab')),
               ('o_crane_counter', _crane('counter')), ('o_crane_cable', _crane('cable')), ('o_crane_hook', _crane('hook')),
               ('o_scaffold_top', _scaffold(True))):
    obj(_n, _f, overhead=True)

# --- fonts amb el raig animat (4 fotogrames; decorate_map canvia les o_fountain per o_fountain_a_0). AL FINAL
def _fountain_anim(f):
    def d(s):
        for y in range(T):
            for x in range(T):
                dd = (x - 7.5) ** 2 + (y - 9.5) ** 2
                if dd < 46: s.px(x, y, 'stone2')
                if dd < 32: s.px(x, y, 'sea2')
                if dd < 16: s.px(x, y, 'sea')
        s.rect(5, 15, 6, 1, 'stone3')
        for k, (rx, ry) in enumerate(((7.5, 9.5),)):    # ona que s'eixampla al bassal
            r2 = 1.5 + f
            for a in range(0, 360, 30):
                px_, py_ = int(rx + r2 * math.cos(math.radians(a))), int(ry + r2 * 0.6 * math.sin(math.radians(a)))
                if (px_ - 7.5) ** 2 + (py_ - 9.5) ** 2 < 30: s.px(px_, py_, 'foam' if k == 0 else 'sea2')
        s.rect(7, 4, 2, 6, 'stone')
        top = 1 + (f % 2)
        s.rect(7, top, 2, 4 - top, 'foam')
        for dx, dy in [((-2, 2), (3, 3)), ((-3, 4), (4, 2)), ((-2, 5), (3, 5)), ((-4, 3), (4, 4))][f]:
            s.px(7 + dx, top + dy, 'foam')
    return d


for _f in range(4):
    obj(f'o_fountain_a_{_f}', _fountain_anim(_f), solid=True, anim=4)

# rejilla de colisión para Tiled (6 bits: tipo0(2) + paso1 + paso-1 + rampa + pendiente)
COLL_COLORS = ['#00000000', '#ff3b3b', '#3b8bff', '#ff9a3b']


from nature_art import register as register_nature
register_nature(add)

# banc de taller (2026-10-05, src/systems/crafting.lua): taulell de fusta amb serra, martell i un tauló
# (després de register_nature: els ids de nature_* no es mouen)
_s = Sprite(T, T); _s.rect(0, 5, 16, 6, 'ochre2'); _s.hline(0, 15, 5, 'ochre'); _s.hline(0, 15, 10, 'ochre3')
_s.rect(1, 11, 2, 5, 'ochre3'); _s.rect(13, 11, 2, 5, 'ochre3'); _s.hline(1, 14, 13, 'ochre3')
_s.rect(2, 2, 6, 3, 'stone2'); _s.hline(2, 7, 4, 'stone3'); _s.rect(8, 3, 2, 2, 'ochre3')      # serra
_s.rect(11, 1, 1, 5, 'ochre3'); _s.rect(10, 1, 3, 2, 'asph2')                                   # martell
_s.rect(3, 7, 9, 2, 'sand'); _s.px(5, 7, 'ochre3'); _s.px(9, 8, 'ochre3')                        # tauló
add('i_workbench', _s, solid=True)

# granges (2026-10-05, src/systems/farm.lua): abeurador de pedra amb aigua i bala de palla
_s = Sprite(T, T); _s.rect(1, 6, 14, 7, 'stone2'); _s.hline(1, 14, 6, 'stone'); _s.rect(2, 7, 12, 3, 'sea')
_s.hline(3, 8, 7, 'foam'); _s.hline(1, 14, 12, 'stone3'); _s.rect(2, 13, 2, 2, 'stone3'); _s.rect(12, 13, 2, 2, 'stone3')
add('o_trough', _s, solid=True)
_s = Sprite(T, T); _s.rect(1, 4, 14, 10, 'sun'); _s.hline(1, 14, 4, 'sand'); _s.hline(1, 14, 13, 'ochre')
for _y in (6, 9, 11): _s.hline(2, 13, _y, 'ochre')
_s.vline(5, 4, 13, 'ochre3'); _s.vline(10, 4, 13, 'ochre3')
add('o_hay', _s, solid=True)

# interiors exclusius dels edificis importants (2026-10-05, procgen.poi: church, chapel, library, townhall,
# clinic, police, post, station)
for _v in (0, 1):                                                  # terra de lloses de pedra
    _s = Sprite(T, T, 'stone'); _s.hline(0, 15, 7, 'stone2'); _s.hline(0, 15, 15, 'stone2')
    _s.vline(7 if _v else 3, 0, 7, 'stone2'); _s.vline(11 if _v else 13, 8, 15, 'stone2')
    _s.px(4, 3, 'white2'); _s.px(10, 11, 'white2')
    add(f'i_floor_stone_{_v}', _s)
_s = Sprite(T, T); _s.rect(0, 4, 16, 3, 'ochre3'); _s.rect(0, 9, 16, 4, 'ochre2'); _s.hline(0, 15, 9, 'ochre')
_s.rect(1, 13, 2, 3, 'ochre3'); _s.rect(13, 13, 2, 3, 'ochre3'); _s.hline(0, 15, 4, 'ochre2')
add('i_pew', _s, solid=True)                                       # banc d'església
_s = Sprite(T, T); _s.rect(1, 5, 14, 10, 'white'); _s.hline(1, 14, 5, 'white2'); _s.rect(1, 9, 14, 2, 'red')
_s.vline(8, 1, 6, 'ochre'); _s.hline(6, 10, 3, 'ochre'); _s.rect(2, 3, 1, 3, 'sun'); _s.rect(13, 3, 1, 3, 'sun')
add('i_altar', _s, solid=True)                                     # altar amb creu i ciris
_s = Sprite(T, T, 'white2'); _s.rect(0, 12, T, 4, 'stone2'); _s.rect(4, 1, 8, 11, 'asph3')
for _x, _y, _c in ((5, 2, 'red'), (8, 2, 'blue'), (5, 5, 'sun'), (8, 5, 'pine2'), (5, 8, 'blue'), (8, 8, 'red')):
    _s.rect(_x, _y, 3, 3, _c)
_s.vline(8, 2, 10, 'asph3'); _s.hline(5, 10, 5, 'asph3'); _s.hline(5, 10, 8, 'asph3')
add('i_wall_stained', _s, solid=True)                              # vitrall
_s = Sprite(T, T)
for _x, _h in ((3, 7), (6, 9), (9, 6), (12, 8)):
    _s.rect(_x, 15 - _h, 2, _h, 'white'); _s.px(_x, 14 - _h, 'sun'); _s.px(_x + 1, 13 - _h, 'ochre')
_s.hline(2, 14, 15, 'ochre3')
add('i_candles', _s, solid=True)                                   # ciris
_s = Sprite(T, T)
for _x in range(1, 16, 3): _s.vline(_x, 0, 15, 'asph2')
_s.hline(0, 15, 1, 'asph2'); _s.hline(0, 15, 14, 'asph2')
add('i_cell', _s, solid=True)                                      # reixa del calabós
_s = Sprite(T, T); _s.vline(3, 1, 15, 'stone3'); _s.rect(4, 1, 9, 6, 'sun'); _s.rect(4, 2, 9, 1, 'red'); _s.rect(4, 4, 9, 1, 'red')
_s.rect(4, 6, 9, 1, 'red'); _s.rect(1, 14, 5, 2, 'stone3')
add('i_flag', _s, solid=True)                                      # senyera
_s = Sprite(T, T); _s.rect(0, 7, 16, 4, 'blue'); _s.hline(0, 15, 7, 'sea'); _s.rect(1, 11, 2, 4, 'asph3'); _s.rect(13, 11, 2, 4, 'asph3')
add('i_bench', _s, solid=True)                                     # banc de sala d'espera
_s = Sprite(T, T); _s.rect(3, 1, 10, 14, 'red'); _s.rect(5, 3, 6, 4, 'sea'); _s.rect(5, 9, 6, 1, 'asph3'); _s.rect(9, 11, 2, 2, 'sun')
add('i_ticket', _s, solid=True)                                    # màquina de bitllets

def write_outputs():
    os.makedirs(os.path.join(ROOT, 'assets/runtime'), exist_ok=True)
    cols = 32
    atlas = sheet([t[1] for t in tiles], cols)
    atlas.image().save(os.path.join(ROOT, 'assets/runtime/tiles.png'))
    for name, _, props in tiles:      # agua: el compilador de zonas la necesita
        if name.startswith('sea_') or name.startswith('pool_'):
            props['water'] = True
    manifest = {'tile_size': T, 'columns': cols, 'count': len(tiles),
                'tiles': {name: dict(id=i, **props) for i, (name, _, props) in enumerate(tiles)}}
    with open(os.path.join(ROOT, 'data/tiles.json'), 'w') as f:
        json.dump(manifest, f, indent=0, ensure_ascii=False)
    # tileset de colisión: 64 códigos
    coll = []
    for code in range(64):
        s = Sprite(T, T)
        kind = code & 3
        if kind == 1: s.rect(0, 0, T, T, (255, 59, 59, 110))
        if kind == 2: s.rect(0, 0, T, T, (59, 139, 255, 110))
        if kind == 3: s.rect(0, 0, T, T, (255, 154, 59, 110))
        if code & 4: s.rect(2, 2, 4, 4, (255, 255, 0, 220))     # transitable en nivel 1
        if code & 8: s.rect(10, 2, 4, 4, (0, 255, 255, 220))    # transitable en nivel -1
        if code & 16: s.rect(6, 10, 4, 4, (255, 0, 255, 220))   # rampa
        if code & 32: s.rect(0, 0, T, 2, (255, 0, 255, 255))    # pendiente de revisión
        coll.append(s)
    sheet(coll, 8).image().save(os.path.join(ROOT, 'assets/runtime/collision.png'))
    # paleta común para el dibujo vectorial (src/world/vectors.lua) y el editor
    from pixel import PALETTE
    with open(os.path.join(ROOT, 'data/palette.json'), 'w') as f:
        json.dump(PALETTE, f, indent=0)
    print(f'{len(tiles)} tiles → assets/runtime/tiles.png')


if __name__ == '__main__':
    write_outputs()
