"""Personajes 16 × 24 dibujados por partes (cabeza, pelo, ropa, brazos, piernas) con contorno automático.

Hoja: 6 columnas × 4 filas (abajo, arriba, izquierda, derecha).
  columnas 0–3: ciclo de caminar (0 paso con el pie izquierdo, 1 cruce, 2 paso derecho, 3 cruce)
  columna 4: reposo · columna 5: parpadeo (el juego lo muestra un instante cada pocos segundos)
En los pasos el cuerpo baja 1 px (contacto con el suelo) y los brazos se balancean al revés que las
piernas. Luz desde arriba a la izquierda: sombra en el lado derecho del pelo, la ropa y la cara.

spec (dict): colores por letra — h/H pelo (claro/sombra), s/S piel, w/W ropa, b pantalón o falda,
o zapatos, r boca, e iris — y estilo: _hair (short, bob, long, pigtails, bun, bald, spiky),
_outfit (tshirt, shorts, pants, dress, sweater, uniform), _hat (cap, ranger, beanie, witch, pirate,
santa, pumpkin, chef, nena), _extra (lista: apron, bag, cane, beard, glasses, scarf, belt).
"""
from pixel import Sprite, mix, rgba

W, H = 16, 24
INK = 'ink'

DEFAULTS = {'h': 'ochre3', 'H': 'terra3', 's': 'skin', 'S': 'skin2', 'w': 'white', 'W': 'white2',
            'b': 'blue', 'o': 'terra3', 'r': 'terra2', 'e': 'asph3', 'p': 'blush'}


def _rgb(c):
    return rgba(c) if isinstance(c, str) else c


class Px:
    """Lienzo disperso: (x, y) → color. Se convierte en Sprite con contorno exterior."""

    def __init__(self):
        self.p = {}

    def put(self, x, y, c):
        if 0 <= x < W and 0 <= y < H:
            self.p[(x, y)] = c

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def has(self, x, y):
        return (x, y) in self.p

    def merge(self, other, dy=0):
        for (x, y), c in other.p.items():
            self.put(x, y + dy, c)

    def sprite(self, outline=True):
        s = Sprite(W, H)
        if outline:
            for (x, y) in list(self.p):
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    q = (x + dx, y + dy)
                    if q not in self.p and 0 <= q[0] < W and 0 <= q[1] < H:
                        s.px(q[0], q[1], INK)
        for (x, y), c in self.p.items():
            s.px(x, y, _rgb(c))
        return s


# ------------------------------------------------------------------ cabeza
HEAD_ROWS = {2: (4, 11), 11: (4, 11)}


def head_shape(px, c):
    for y in range(2, 12):
        x0, x1 = HEAD_ROWS.get(y, (3, 12))
        px.rect(x0, y, x1, y, c)


def face(px, d, cm, blink):
    s, S = cm['s'], cm['S']
    if d == 'down':
        head_shape(px, s)
        for y in range(3, 12):              # mejilla derecha en sombra suave
            if px.has(12, y): px.put(12, y, S)
        px.put(11, 11, S)
        if blink:
            for x in (5, 6, 9, 10): px.put(x, 8, INK)
        else:
            for ex in (5, 9):
                px.put(ex, 7, INK); px.put(ex + 1, 7, 'white')
                px.put(ex, 8, cm['e']); px.put(ex + 1, 8, INK)
        px.put(4, 9, cm['p']); px.put(11, 9, cm['p'])
        px.put(7, 10, cm['r']); px.put(8, 10, cm['r'])
    elif d == 'up':
        head_shape(px, s)
    else:  # mirando a la izquierda
        head_shape(px, s)
        px.put(2, 8, s)                     # nariz
        px.put(9, 8, S); px.put(9, 9, S)    # oreja
        if blink:
            px.put(4, 8, INK); px.put(5, 8, INK)
        else:
            px.put(4, 7, 'white'); px.put(5, 7, INK); px.put(4, 8, cm['e']); px.put(5, 8, INK)
        px.put(5, 9, cm['p'])
        px.put(3, 10, cm['r'])


def hair(px, d, cm, style):
    h, Hs = cm['h'], cm['H']
    L = cm.get('L') or mix(h, 'white', 0.28)

    def put(x, y, c=None):
        px.put(x, y, c or h)

    if style == 'bald':
        if d == 'up':
            for y in range(5, 11):
                for x in range(3, 13): put(x, y, Hs if y > 8 else h)
        elif d == 'down':
            for y in range(5, 9): put(3, y); put(12, y, Hs)
        else:
            for y in range(5, 10):
                for x in range(9, 13): put(x, y, Hs if x == 12 else h)
        return
    # casquete común
    for y in range(2, 6):
        x0, x1 = HEAD_ROWS.get(y, (3, 12))
        for x in range(x0, x1 + 1):
            if d == 'left' and y == 5 and x < 6:
                continue
            put(x, y, Hs if (x >= 11 and d != 'left') or (d == 'left' and x >= 11) else h)
    for x in range(5, 8): put(x, 3, L)      # brillo
    put(6, 2, L)
    if d == 'down':
        fringe = {'short': (3, 4, 6, 9, 11, 12), 'spiky': (3, 5, 7, 10, 12), 'bob': (3, 4, 5, 10, 11, 12),
                  'long': (3, 4, 5, 6, 11, 12), 'pigtails': (3, 4, 6, 7, 8, 11, 12), 'bun': (3, 12)}
        for x in fringe.get(style, (3, 12)):
            put(x, 6, Hs if x >= 11 else h)
        sides = {'short': 7, 'spiky': 7, 'bun': 7, 'pigtails': 8, 'bob': 11, 'long': 13}[style]
        for y in range(6, sides + 1):
            put(3, y, h); put(12, y, Hs)
        if style in ('bob', 'long'):
            for y in range(7, sides + 1):
                put(2, y, h); put(13, y, Hs)
            put(4, 10, h); put(11, 10, Hs)
        if style == 'pigtails':
            for y in range(7, 12):
                put(1, y, h); put(2, y, Hs if y > 9 else h); put(13, y, Hs); put(14, y, Hs)
        if style == 'spiky':
            put(4, 1, h); put(8, 1, h); put(11, 1, Hs)
    elif d == 'up':
        bottom = {'short': 10, 'spiky': 10, 'bun': 10, 'pigtails': 10, 'bob': 12, 'long': 14}[style]
        for y in range(5, bottom + 1):
            x0, x1 = HEAD_ROWS.get(y, (3, 12))
            if style in ('bob', 'long') and y >= 7:
                x0, x1 = 2, 13
            for x in range(x0, x1 + 1):
                put(x, y, Hs if y >= bottom - 1 or x >= 12 else h)
        if style == 'pigtails':
            for y in range(7, 12):
                put(1, y, h); put(2, y, h); put(13, y, Hs); put(14, y, Hs)
        if style == 'spiky':
            put(4, 1, h); put(8, 1, h); put(11, 1, Hs)
    else:
        back = {'short': 9, 'spiky': 9, 'bun': 9, 'pigtails': 9, 'bob': 11, 'long': 14}[style]
        put(3, 6, h); put(4, 6, h)
        for y in range(5, back + 1):
            for x in range(7 if y < 8 else 8, 13):
                if (x, y) in ((9, 8), (9, 9)) and style in ('short', 'spiky', 'bun', 'pigtails'):
                    continue  # oreja a la vista
                put(x, y, Hs if x == 12 or y == back else h)
        if style in ('bob', 'long'):
            for y in range(7, back + 1): put(13, y, Hs)
        if style == 'pigtails':
            for y in range(7, 12): put(13, y, h); put(14, y, Hs)
        if style == 'spiky':
            put(5, 1, h); put(9, 1, h); put(13, 3, Hs)
    if style == 'bun':
        for y in (0, 1):
            for x in range(6, 10): put(x, y, Hs if x == 9 else h)


def hat(px, d, cm, kind):
    if not kind or kind == 'nena':
        return
    if kind == 'cap':
        c, c2 = cm.get('c', cm['w']), cm.get('C', cm['W'])
        px.rect(4, 1, 11, 1, c)
        px.rect(3, 2, 12, 4, c)
        px.rect(5, 2, 7, 2, mix(c, 'white', .3))
        if d == 'down': px.rect(3, 5, 12, 5, c2)
        elif d == 'left': px.rect(1, 5, 5, 5, c2)
        else: px.rect(3, 5, 12, 5, c)
    elif kind == 'ranger':
        px.rect(5, 0, 10, 2, 'ochre2'); px.rect(5, 2, 10, 2, 'pine3')
        px.rect(1, 3, 14, 3, 'ochre3' if d != 'up' else 'ochre2')
        px.rect(6, 0, 7, 0, mix('ochre2', 'white', .3))
    elif kind == 'beanie':
        px.rect(4, 1, 11, 1, cm.get('c', 'red'))
        px.rect(3, 2, 12, 4, cm.get('c', 'red'))
        px.rect(3, 4, 12, 4, cm.get('C', 'terra2'))
        for x in range(4, 12, 2): px.put(x, 3, cm.get('C', 'terra2'))
    elif kind in ('helmet', 'helmet_ride'):   # casc de bici/moto (vermell) o d'hípica (negre), com a src/paperdoll/chars.lua
        c = 'red' if kind == 'helmet' else 'asph3'
        c2, c3 = mix(c, 'ink', .3), mix(c, 'white', .4)
        px.rect(4, 0, 11, 0, c); px.rect(3, 1, 12, 4, c); px.rect(3, 5, 12, 5, c2)
        if kind == 'helmet':
            for x in range(5, 11, 2): px.put(x, 1, 'ink'); px.put(x, 2, c2)
        px.put(5, 1, c3); px.put(6, 1, c3)
        if d == 'down': px.rect(3, 6, 3, 7, c2); px.rect(12, 6, 12, 7, c2)   # sense corretja davant dels ulls
        elif d == 'left': px.rect(9, 5, 12, 7, c2); px.rect(2, 5, 4, 5, c)
        else: px.rect(3, 5, 12, 6, c2)
    elif kind == 'hardhat':   # casc d'obra groc amb ala (obrers de les obres)
        c, c2, c3 = 'sun', mix('sun', 'ochre3', .45), mix('sun', 'white', .5)
        px.rect(5, 0, 10, 0, c); px.rect(4, 1, 11, 4, c); px.rect(7, 0, 8, 4, c2)
        px.rect(2, 5, 13, 5, c2); px.put(5, 1, c3); px.put(5, 2, c3)
    elif kind == 'chef':
        px.rect(4, 0, 11, 3, 'white'); px.rect(3, 4, 12, 4, 'white2'); px.put(10, 1, 'white2'); px.put(11, 2, 'white2')
    elif kind == 'witch':
        px.rect(1, 4, 14, 4, 'asph3'); px.rect(2, 4, 13, 4, mix('asph3', 'ink', .4))
        px.rect(4, 2, 11, 3, 'asph3'); px.rect(5, 1, 10, 1, 'asph3'); px.rect(7, 0, 10, 0, 'asph3')
        px.rect(4, 3, 11, 3, 'terra'); px.put(5, 2, mix('asph3', 'white', .25))
    elif kind == 'pirate':
        px.rect(3, 2, 12, 4, 'red'); px.rect(4, 1, 11, 1, 'red')
        for x in (4, 7, 10): px.put(x, 3, 'white')
        if d == 'left': px.rect(12, 5, 13, 7, 'red')
        elif d == 'up': px.rect(7, 5, 8, 7, 'red')
    elif kind == 'santa':
        px.rect(4, 1, 11, 3, 'red'); px.rect(9, 0, 12, 1, 'red')
        px.rect(3, 4, 12, 4, 'white'); px.rect(13, 1, 14, 2, 'white')
    elif kind == 'pumpkin':
        for y in range(2, 12):
            x0, x1 = HEAD_ROWS.get(y, (2, 13))
            for x in range(x0, x1 + 1):
                px.put(x, y, 'ochre2' if x in (5, 10) or x >= 12 else 'ochre')
        px.rect(7, 0, 8, 1, 'pine2')
        if d == 'down':
            for x, y in ((5, 6), (6, 6), (9, 6), (10, 6), (6, 5), (9, 5)):
                px.put(x, y, INK)
            for x in range(5, 11): px.put(x, 9 if x % 2 else 8, INK)
        elif d == 'left':
            for x, y in ((3, 6), (4, 6), (4, 5), (3, 9), (4, 8), (5, 9)): px.put(x, y, INK)


# ------------------------------------------------------------------ cuerpo
def torso(px, d, cm, outfit, extras, swing):
    """Tronco, caderas y brazos (sin desplazar). swing: −1/0/+1 balanceo (mano izquierda de pantalla)."""
    w, Wd, s, b = cm['w'], cm['W'], cm['s'], cm['b']
    sleeve_long = outfit in ('sweater', 'uniform', 'pants')
    dress = outfit == 'dress'
    hip = w if dress else b
    hip_shade = Wd if dress else mix(b, 'ink', .25)
    if d in ('down', 'up'):
        px.rect(4, 12, 11, 16, w)
        px.rect(11, 12, 11, 16, Wd)
        px.rect(4, 17, 11, 18, hip); px.rect(11, 17, 11, 18, hip_shade)
        if dress:
            px.rect(3, 17, 12, 18, w); px.rect(3, 18, 12, 18, Wd); px.put(12, 17, Wd)
        if d == 'down' and outfit not in ('sweater', 'uniform'):
            px.put(7, 12, s); px.put(8, 12, s)           # cuello
        if d == 'down' and outfit == 'uniform':
            px.put(7, 12, 'white'); px.put(8, 12, 'white'); px.put(6, 14, cm.get('c', 'ochre'))
        if 'belt' in extras or outfit in ('pants', 'shorts', 'uniform'):
            if not dress: px.rect(4, 16, 11, 16, mix(b, 'ink', .4))
        # brazos (los dos lados) con manga y mano
        for side, x in ((-1, 3), (1, 12)):
            sw = swing * side * -1 if d == 'down' else swing * side
            top, hand = 12, 16 + (1 if sw > 0 else 0) - (1 if sw < 0 else 0)
            for y in range(top, hand):
                sl = y <= 13 or sleeve_long
                c = (w if side < 0 else Wd) if sl else (s if side < 0 else cm['S'])
                px.put(x, y, c)
            px.put(x, hand, s if side < 0 else cm['S'])
    else:  # izquierda
        px.rect(5, 12, 10, 16, w)
        px.rect(10, 12, 10, 16, Wd)
        px.rect(5, 17, 10, 18, hip); px.rect(10, 17, 10, 18, hip_shade)
        if dress:
            px.rect(4, 17, 11, 18, w); px.rect(4, 18, 11, 18, Wd)
        if 'belt' in extras or outfit in ('pants', 'shorts', 'uniform'):
            if not dress: px.rect(5, 16, 10, 16, mix(b, 'ink', .4))
        # brazo visible: delante (swing>0), atrás (swing<0) o caído
        if swing > 0:
            pts = [(7, 12), (7, 13), (6, 14), (5, 15)]
        elif swing < 0:
            pts = [(8, 12), (8, 13), (9, 14), (10, 15)]
        else:
            pts = [(7, 12), (7, 13), (7, 14), (7, 15)]
        for i, (x, y) in enumerate(pts):
            sl = i < 2 or sleeve_long
            px.put(x, y, Wd if sl else cm['S'])
            px.put(x + 1, y, Wd if sl else cm['S'])
        hx, hy = pts[-1]
        px.put(hx, hy + 1, s); px.put(hx + 1, hy + 1, cm['S'])


def legs(px, d, cm, outfit, bob, lift):
    """Piernas y zapatos con el suelo fijo (los pies tocan la fila 22). lift: 'L', 'R' o None."""
    bare = outfit in ('shorts', 'dress', 'tshirt')
    lc = cm['s'] if bare else cm['b']
    lc2 = cm['S'] if bare else mix(cm['b'], 'ink', .25)
    o, o2 = cm['o'], mix(cm['o'], 'ink', .35)
    top = 19 + bob
    if d in ('down', 'up'):
        for name, xs, sx in (('L', (5, 6), (4, 6)), ('R', (9, 10), (9, 11))):
            foot = 20 if lift == name else 21
            for y in range(top, foot):
                px.put(xs[0], y, lc); px.put(xs[1], y, lc2)
            px.rect(sx[0], foot, sx[1], foot + 1, o)
            px.rect(sx[0], foot + 1, sx[1], foot + 1, o2)
    else:
        if lift is None:  # piernas juntas
            for y in range(top, 21):
                px.rect(6, y, 7, y, lc); px.rect(8, y, 9, y, lc2)
            px.rect(4, 21, 9, 22, o); px.rect(4, 22, 9, 22, o2)
        else:  # zancada: pierna delantera a la izquierda, trasera a la derecha (talón levantado)
            front_c, back_c = (lc, lc2)
            for i, y in enumerate(range(top, 21)):
                px.rect(5 - min(i, 1), y, 6 - min(i, 1), y, front_c)
                px.rect(9 + min(i, 1), y, 10 + min(i, 1), y, back_c)
            px.rect(2, 21, 5, 22, o); px.rect(2, 22, 5, 22, o2)
            px.rect(10, 20, 12, 21, o2)


def extras_draw(px, d, cm, extras):
    if 'apron' in extras:
        if d == 'down':
            px.rect(5, 13, 10, 18, 'white'); px.rect(10, 13, 10, 18, 'white2'); px.rect(6, 15, 9, 15, 'white2')
        elif d == 'left':
            px.rect(4, 13, 5, 18, 'white')
        else:
            px.put(7, 15, 'white'); px.put(8, 15, 'white')
    if 'scarf' in extras:
        c = cm.get('c', 'red')
        if d == 'left': px.rect(5, 12, 9, 12, c); px.rect(4, 13, 5, 14, c)
        else: px.rect(4, 12, 11, 12, c); px.put(9 if d == 'down' else 6, 13, c); px.put(9 if d == 'down' else 6, 14, c)
    if 'bag' in extras:
        if d == 'down':
            for i in range(5): px.put(4 + i, 12 + i, 'ochre3')
            px.rect(9, 15, 12, 17, 'ochre2'); px.rect(9, 15, 12, 15, 'ochre3')
        elif d == 'up':
            for i in range(5): px.put(11 - i, 12 + i, 'ochre3')
            px.rect(3, 15, 6, 17, 'ochre2')
        else:
            px.rect(8, 15, 11, 17, 'ochre2'); px.put(8, 15, 'ochre3'); px.put(7, 12, 'ochre3'); px.put(7, 13, 'ochre3')
    if 'beard' in extras:
        c, c2 = cm['h'], cm['H']
        if d == 'down':
            px.rect(4, 9, 11, 11, c); px.rect(5, 12, 10, 12, c2)
            px.put(7, 10, cm['r']); px.put(8, 10, cm['r']); px.put(11, 9, c2); px.put(11, 10, c2)
        elif d == 'left':
            px.rect(3, 9, 7, 11, c); px.rect(4, 12, 6, 12, c2); px.put(3, 10, cm['r'])
    if 'glasses' in extras:
        if d == 'down':
            for x in (4, 7, 8, 11): px.put(x, 7, INK)
        elif d == 'left':
            px.put(3, 7, INK); px.put(6, 7, INK)
    if 'ribs' in extras and d in ('down', 'up'):   # disfraz de esqueleto
        for y in (13, 15):
            px.rect(5, y, 10, y, 'white2')
        px.rect(7, 12, 8, 16, 'white')
    if 'cane' in extras:
        if d == 'down':
            for y in range(15, 23): px.put(13, y, 'ochre3')
            px.put(12, 15, 'ochre3')
        elif d == 'left':
            for y in range(16, 23): px.put(3, y, 'ochre3')
            px.put(4, 16, 'ochre3')


def frame(spec, d, col):
    cm = dict(DEFAULTS)
    cm.update({k: v for k, v in spec.items() if not k.startswith('_')})
    style = spec.get('_hair', 'short')
    outfit = spec.get('_outfit', 'shorts')
    hat_kind = spec.get('_hat')
    extras = spec.get('_extra', [])
    walking = col < 4
    bob = 1 if walking and col in (0, 2) else 0
    lift = ('L' if col == 0 else 'R' if col == 2 else None) if walking else None
    swing = (1 if col == 0 else -1 if col == 2 else 0) if walking else 0
    blink = col == 5
    up = Px()
    if d == 'up' and style in ('bob', 'long', 'pigtails'):
        hair(up, d, cm, style)   # el pelo largo cae por la espalda (se dibuja y luego el cuerpo encima)
        back_hair = dict(up.p)
    else:
        back_hair = {}
    torso(up, d, cm, outfit, extras, swing)
    for k, v in back_hair.items():
        if k[1] >= 12:
            up.p[k] = v
    face(up, d, cm, blink)
    if hat_kind != 'pumpkin':
        hair(up, d, cm, style)
    extras_draw(up, d, cm, extras)
    hat(up, d, cm, hat_kind)
    low = Px()
    legs(low, d, cm, outfit, bob, lift if d != 'left' else (lift and 'step'))
    out = Px()
    out.merge(low)
    out.merge(up, bob)
    return out.sprite()


def sheet_frames(spec):
    frames = []
    for d in ('down', 'up', 'left'):
        for col in range(6):
            frames.append(frame(spec, d, col))
    frames += [f.flip_h() for f in frames[12:18]]
    return frames
