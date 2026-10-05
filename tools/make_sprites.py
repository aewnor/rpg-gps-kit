#!/usr/bin/env python3
"""Genera sprites originales: protagonista, NPC, enemigos, vehículos, hitos, objetos, UI y fuente.

Salida en assets/runtime/sprites/*.png, assets/runtime/font.png y data/landmarks.json.
"""
import json
import os

from PIL import Image, ImageDraw, ImageFont

from pixel import Sprite, mix, rgba, rng_for, sheet, PALETTE

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
OUT = os.path.join(ROOT, 'assets/runtime/sprites')
os.makedirs(OUT, exist_ok=True)


def save(spr, name):
    spr.image().save(os.path.join(OUT, name + '.png'))


# ------------------------------------------------------------------------------------
# Personajes 16 × 24 (tools/chars.py): filas = abajo, arriba, izquierda, derecha; columnas = 4 pasos,
# reposo y parpadeo. Cada personaje es un diseño (pelo, ropa, complementos) más sus colores.
# ------------------------------------------------------------------------------------
import chars  # noqa: E402

SKIN_STYLE = {   # aspectos de data/skins.json sin estilo explícito: estilo según el sombrero
    'nena': {'_hair': 'bob', '_outfit': 'dress', 'e': 'blue'},
    'cap': {'_hair': 'short', '_outfit': 'shorts', '_hat': 'cap'},
    'pirate': {'_hair': 'short', '_outfit': 'pants', '_hat': 'pirate', '_extra': ['belt']},
    'witch': {'_hair': 'long', '_outfit': 'dress', '_hat': 'witch'},
    'santa': {'_hair': 'short', '_outfit': 'uniform', '_hat': 'santa', '_extra': ['beard', 'belt']},
    'pumpkin': {'_hair': 'short', '_outfit': 'pants', '_hat': 'pumpkin'},
}


def spec_of(colors, hat=None, hair=None, outfit=None, extra=None):
    sp = dict(colors)
    sp.update(SKIN_STYLE.get(hat, {}))
    if hat and hat not in SKIN_STYLE:
        sp['_hat'] = hat
    if hair: sp['_hair'] = hair
    if outfit: sp['_outfit'] = outfit
    if extra is not None: sp['_extra'] = extra
    return sp


def character(spec, kind=None):
    if '_hat' in spec and '_hair' not in spec:   # compatibilidad: {'_hat': 'nena', ...}
        spec = spec_of({k: v for k, v in spec.items() if k != '_hat'}, spec['_hat'])
    return sheet(chars.sheet_frames(spec), 6)


PLAYER = {'h': 'ochre3', 'H': 'terra3', 'w': 'white', 'W': 'white2', 'b': 'blue', '_hair': 'short',
          '_outfit': 'shorts'}
NPCS = {
    # La Carme, forner: moño, gorro blanco y delantal
    'npc_baker': {'h': 'ochre3', 'H': 'terra3', 'w': 'white', 'W': 'white2', 'b': 'stone3', 'o': 'asph3',
                  '_hair': 'bun', '_outfit': 'pants', '_hat': 'chef', '_extra': ['apron']},
    # En Pere, pescador: barba blanca, gorro de lana y jersey marinero
    'npc_fisher': {'h': 'white2', 'H': 'white3', 'w': 'blue', 'W': 'sea3', 'b': 'asph2', 's': mix('skin', 'ochre2', .25),
                   'S': 'skin2', 'c': 'red', 'C': 'terra2', '_hair': 'short', '_outfit': 'sweater', '_hat': 'beanie',
                   '_extra': ['beard']},
    # L'avi Josep: calvo con canas, gafas, rebeca verde y bastón
    'npc_elder': {'h': 'white', 'H': 'white2', 'w': 'pine2', 'W': 'pine3', 'b': 'stone3', 'o': 'ochre3',
                  '_hair': 'bald', '_outfit': 'sweater', '_extra': ['glasses', 'cane']},
    # La Laia: coletas y vestido rojo
    'npc_girl': {'h': 'terra3', 'H': mix('terra3', 'ink', .3), 'w': 'red', 'W': 'terra2', 'o': 'blue',
                 '_hair': 'pigtails', '_outfit': 'dress'},
    # L'Anna, agent forestal: sombrero, uniforme verde y pelo largo
    'npc_ranger': {'h': 'ochre2', 'H': 'ochre3', 'w': mix('pine2', 'ochre2', .2), 'W': 'pine3', 'b': 'pine3',
                   'o': 'ochre3', '_hair': 'long', '_outfit': 'uniform', '_hat': 'ranger', '_extra': ['belt']},
    # La Marta, carter: gorra y camisa amarillas, pantalón azul y cartera
    'npc_postie': {'h': 'ink', 'H': 'asph3', 'w': 'ochre', 'W': 'ochre2', 'b': 'blue', 'c': 'ochre', 'C': 'ochre2',
                   '_hair': 'bob', '_outfit': 'uniform', '_hat': 'cap', '_extra': ['bag']},
    # nuevos para el editor: turista, niño y vecina
    'npc_tourist': {'h': 'sand2', 'H': 'ochre2', 'w': 'sea', 'W': 'sea2', 'b': 'sand2', 's': mix('skin', 'red', .12),
                    'c': 'white', 'C': 'white2', '_hair': 'short', '_outfit': 'shorts', '_hat': 'cap', '_extra': ['bag']},
    'npc_kid': {'h': 'ink', 'H': 'asph3', 'w': 'ochre', 'W': 'ochre2', 'b': 'blue', 'o': 'red',
                '_hair': 'spiky', '_outfit': 'shorts'},
    'npc_lady': {'h': 'asph3', 'H': 'ink', 'w': 'blue', 'W': mix('blue', 'ink', .3), 'o': 'terra2', 'e': 'pine2',
                 '_hair': 'long', '_outfit': 'dress', '_extra': ['scarf'], 'c': 'ochre'},
    # serveis del poble (data/services.json)
    'npc_police': {'h': 'asph3', 'H': 'ink', 'w': mix('blue', 'ink', .35), 'W': mix('blue', 'ink', .55), 'b': mix('blue', 'ink', .5),
                   'o': 'ink', 'c': mix('blue', 'ink', .35), 'C': 'white', '_hair': 'short', '_outfit': 'uniform',
                   '_hat': 'cap', '_extra': ['belt']},
    'npc_doctor': {'h': 'ochre2', 'H': 'ochre3', 'w': 'white', 'W': 'white2', 'b': 'sea2', 'o': 'white2',
                   '_hair': 'bun', '_outfit': 'sweater', '_extra': ['glasses']},
    'npc_clerk': {'h': 'terra3', 'H': mix('terra3', 'ink', .3), 'w': 'pine2', 'W': 'pine3', 'b': 'asph2', 'o': 'asph3',
                  '_hair': 'bob', '_outfit': 'pants', '_extra': ['apron']},
    # la mestra, mestra de l'Escola Salvador Espriu: cabells llargs, jersei verd i bossa de llibres
    'npc_teacher': {'h': 'terra3', 'H': mix('terra3', 'ink', .3), 'w': 'pine2', 'W': 'pine3', 'b': 'asph3', 'o': 'terra3',
                    'e': 'pine3', '_hair': 'long', '_outfit': 'sweater', '_extra': ['bag', 'glasses'], 'c': 'ochre'},
    # obrers de les obres (decorate_map.construction_sites): casc groc, armilla taronja i texans
    'npc_builder': {'h': 'asph3', 'H': 'ink', 'w': 'terra', 'W': 'terra2', 'b': 'blue', 'o': 'asph3',
                    'c': 'sun', 'C': 'ochre', '_hair': 'short', '_outfit': 'uniform', '_hat': 'hardhat', '_extra': ['belt']},
    'npc_builder2': {'h': 'terra3', 'H': mix('terra3', 'ink', .3), 'w': 'ochre', 'W': 'ochre2', 'b': 'asph2', 'o': 'asph3',
                     'c': 'sun', 'C': 'ochre', '_hair': 'bob', '_outfit': 'uniform', '_hat': 'hardhat', '_extra': ['belt']},
    'npc_coach': {'h': 'ink', 'H': 'asph3', 'w': 'red', 'W': 'terra2', 'b': 'red', 'o': 'white',
                  '_hair': 'spiky', '_outfit': 'sweater', '_extra': ['belt']},
}
save(character(PLAYER), 'player')


def cat_sheet(c1, c2, c3, belly):
    """Gato en el formato de personaje (16 × 24; filas abajo, arriba, izquierda, derecha; 4 pasos + 2 reposo)."""
    cm = {'k': 'ink', 'a': c1, 'b': c2, 'c': c3, 'w': belly, 'e': 'pine', 'p': 'terra'}
    SIDE = ["...........b....", "..k.k.......b...", "..kaak.......b..", ".kaeaak......b..",
            ".kaaaakkkkkkab..", "..kpakaabaabaak.", "...kkwaabaabaak.", "....kwwaaaaaak..",
            "....kakkkkkakk.."]
    FRONT = ["..k......k......", "..kak...kak.....", "..kaakkkaak.....", "..kaeaaaeak.....",
             "..kaaapaaak.....", "...kawwwak......", "...kawwwak......", "..kaawwwaak.....",
             "..kaabwbaak..b..", "..kwkaaakwk.bb..", "...kk...kkkb...."]
    BACK = ["..k......k......", "..kak...kak.....", "..kaakkkaak.....", "..kaaaaaaak.....",
            "..kabaaabak.....", "...kaaaaak......", "...kabbbak......", "..kaaaaaaak.....",
            "..kaabbbaak.....", "..kaaaaaaak.b...", "...kkkkkkk.b...."]
    frames = []
    for row, pat in (('down', FRONT), ('up', BACK), ('left', SIDE)):
        for f in range(6):
            sp = Sprite(16, 24)
            walking = f < 4
            bob = 1 if (walking and f in (1, 3)) or (not walking and f == 5) else 0
            top = 24 - len(pat) - 1
            sp.pattern(0 if row == 'left' else 2, top + bob, pat, cm)
            if row == 'left' and walking:   # patas alternas
                legs = ["....ka.k..ka.k..", "....k..ka.k..ka."][f % 2]
                sp.pattern(0, top + len(pat) - 1 + bob, [legs], cm)
            frames.append(sp)
    frames += [fr.flip_h() for fr in frames[12:18]]
    return sheet(frames, 6)


save(cat_sheet('ochre', 'ochre2', 'ochre3', 'white'), 'npc_cat_orange')
save(cat_sheet('white', 'stone2', 'asph2', 'white'), 'npc_cat_grey')
for name, cols in NPCS.items():
    save(character(cols), name)


# ------------------------------------------------------------------------------------
# Enemigos 16 × 16 (2 frames, mirando a la izquierda)
# ------------------------------------------------------------------------------------
# Senglar (jabalí): cuerpo rechoncho con cresta, hocico claro y colmillos; 2 frames de trote.
# Ratpenat: alas membranosas con dedos, orejas y ojos rojos; 2 frames de aleteo. Contorno automático.
BOAR = [
    [
        "................",
        "................",
        "................",
        "......HHHH......",
        "....HHBBBBHH....",
        "..HHBBBBBBBBBH..",
        ".EBBBBbBBBBBBBH.",
        "oSeBBBBBBBBBBBb.",
        "SSBBBBBBBBBBBBb.",
        "nSSbBBBBBBBBBb..",
        ".ttbbbbbbbbbb...",
        "...LL.....LL....",
        "...L......L.....",
        "..ll.....ll.....",
    ],
    [
        "................",
        "................",
        "......HHHH......",
        "....HHBBBBHH....",
        "..HHBBBBBBBBBH..",
        ".EBBBBbBBBBBBBH.",
        "oSeBBBBBBBBBBBb.",
        "SSBBBBBBBBBBBBb.",
        "nSSbBBBBBBBBBb..",
        ".ttbbbbbbbbbb...",
        "....L.....L.....",
        "....LL.....LL...",
        ".....ll.....ll..",
        "................",
    ],
]
BAT = [
    [
        "................",
        "W..............W",
        "WW....E..E....WW",
        "WmW...EEEE...WmW",
        "WmmW.BBBBBB.WmmW",
        ".WmmWBrBBrBWmmW.",
        "..WmmBBBBBBmmW..",
        "...WWBbttbBWW...",
        ".....BBBBBB.....",
        "......BBBB......",
    ],
    [
        "................",
        "................",
        "......E..E......",
        "......EEEE......",
        "....WBBBBBBW....",
        "..WWmBrBBrBmWW..",
        ".WmmmBBBBBBmmmW.",
        "WmmWWBbttbBWWmmW",
        "WmW..BBBBBB..WmW",
        "W.....BBBB.....W",
    ],
]


def creature(rows, cm, h=16):
    from chars import Px
    px = Px()
    top = h - len(rows) - 1
    for j, row in enumerate(rows):
        for i, ch in enumerate(row):
            if ch in cm:
                px.put(i, top + j, cm[ch])
    spr = px.sprite()
    out = Sprite(16, 16)
    out.a = spr.a[:16].copy()
    return out


BOAR_CM = {'B': 'ochre3', 'b': mix('ochre3', 'ink', .35), 'H': mix('ochre3', 'ink', .55), 'E': 'ink',
           'S': mix('ochre2', 'skin', .4), 'o': 'ink', 'e': 'red', 'n': 'terra3', 't': 'white', 'L': 'terra3',
           'l': 'ink'}
BAT_CM = {'B': 'asph2', 'b': 'asph3', 'W': 'asph3', 'm': mix('terra3', 'asph2', .5), 'E': 'asph2', 'r': 'red',
          't': 'white'}
for name, frames, cm in (('enemy_boar', BOAR, BOAR_CM), ('enemy_bat', BAT, BAT_CM)):
    sprs = [creature(fr, cm) for fr in frames]
    hurt = []
    for s in sprs:  # frame de daño en blanco
        h = Sprite(16, 16)
        h.a = s.a.copy()
        mask = h.a[:, :, 3] > 0
        h.a[mask, :3] = (255, 255, 255)
        hurt.append(h)
    save(sheet(sprs + hurt, 4), name)


# ------------------------------------------------------------------------------------
# Efectos y objetos
# ------------------------------------------------------------------------------------
def slash(direction):
    s = Sprite(16, 16)
    pts = []
    for i in range(10):
        import math
        a = math.radians(-60 + i * 12)
        pts.append((8 + 7 * math.cos(a), 8 + 7 * math.sin(a)))
    for i, (x, y) in enumerate(pts):
        s.px(int(x), int(y), 'white'); s.px(int(x) - 1, int(y), 'white2')
        if i % 2: s.px(int(x) - 2, int(y), 'sea')
    if direction == 'left':
        s = s.flip_h()
    elif direction in ('up', 'down'):
        s.a = s.a.transpose(1, 0, 2).copy()
        if direction == 'up':
            s.a = s.a[::-1].copy()
    return s


save(sheet([slash(d) for d in ('down', 'up', 'left', 'right')], 4), 'slash')

sword = Sprite(16, 16)
sword.pattern(0, 0, [
    "...........kk...",
    "..........kwk...",
    ".........kwWk...",
    "........kwWk....",
    ".......kwWk.....",
    "......kwWk......",
    "..k..kwWk.......",
    "..kkkwWk........",
    "...kowk.........",
    "...koook........",
    "..kok.kk........",
    ".kok............",
    ".kk.............",
], {'k': 'ink', 'w': 'white', 'W': 'white3', 'o': 'ochre2'})
shield = Sprite(16, 16)
shield.pattern(2, 1, [
    "kkkkkkkkkk",
    "kWWWrrWWWk",
    "kWWWrrWWWk",
    "krrrrrrrrk",
    "kWWWrrWWWk",
    ".kWWrrWWk.",
    ".kWWrrWWk.",
    "..kWrrWk..",
    "...kkkk...",
], {'k': 'ink', 'W': 'ochre', 'r': 'red'})
heart_full, heart_empty = Sprite(8, 8), Sprite(8, 8)
H8 = [".kk.kk..", "krrkrrk.", "krrrrrk.", ".krrrk..", "..krk...", "...k...."]
heart_full.pattern(0, 1, H8, {'k': 'ink', 'r': 'red'})
heart_empty.pattern(0, 1, H8, {'k': 'ink', 'r': 'white3'})
postcard = Sprite(16, 16)
postcard.rect(1, 3, 14, 10, 'white'); postcard.rect(2, 4, 7, 5, 'sea'); postcard.rect(2, 7, 7, 2, 'sand')
postcard.rect(11, 4, 3, 3, 'red'); postcard.hline(10, 13, 9, 'white3'); postcard.hline(10, 13, 11, 'white3')
for x in range(1, 15): postcard.px(x, 13, 'ink')
notebook = Sprite(16, 16)
notebook.rect(3, 1, 10, 14, 'terra2'); notebook.rect(4, 2, 8, 12, 'terra'); notebook.rect(5, 5, 6, 3, 'white')
notebook.vline(3, 1, 14, 'ink')
chest_c, chest_o = Sprite(16, 16), Sprite(16, 16)
CH = ["kkkkkkkkkkkkkk", "kooooooooooook", "kOOOOOOOOOOOOk", "kkkkkkyykkkkkk", "kooooooyyooook",
      "kooooooooooook", "kOOOOOOOOOOOOk", "kOOOOOOOOOOOOk", "kkkkkkkkkkkkkk"]
chest_c.pattern(1, 5, CH, {'k': 'ink', 'o': 'ochre2', 'O': 'ochre3', 'y': 'ochre'})
chest_o.pattern(1, 2, ["kkkkkkkkkkkkkk", "kOOOOOOOOOOOOk", "kkkkkkkkkkkkkk", "k............k"] + CH[3:],
                {'k': 'ink', 'o': 'ochre2', 'O': 'ochre3', 'y': 'ochre', '.': 'asph3'})
lever_a, lever_b = Sprite(16, 16), Sprite(16, 16)
for s, top in ((lever_a, 3), (lever_b, 11)):
    s.rect(4, 11, 8, 4, 'stone3'); s.hline(4, 11, 11, 'stone')
    x = top
    for i in range(7):
        s.px(int(x + (8 - x) * i / 7), 4 + i, 'ink')
    s.rect(top - 1, 2, 3, 3, 'red')
sign = Sprite(16, 16)
sign.rect(2, 2, 12, 7, 'ochre2'); sign.rect(3, 3, 10, 5, 'ochre'); sign.hline(4, 11, 5, 'ochre3')
sign.vline(7, 9, 14, 'ochre3'); sign.vline(8, 9, 14, 'ink')
bubble = Sprite(8, 10)
bubble.pattern(0, 0, [".kkkkk..", "kwwrwwk.", "kwwrwwk.", "kwwrwwk.", "kwwwwwk.", "kwwrwwk.", ".kkkkk..",
                      "..kk....", "..k....."], {'k': 'ink', 'w': 'white', 'r': 'red'})
cave_exit = Sprite(16, 16)
cave_exit.rect(0, 0, 16, 16, 'dry')
for y in range(2, 16, 3):
    cave_exit.hline(4, 11, y, 'ochre3')
cave_exit.vline(4, 0, 15, 'ochre2'); cave_exit.vline(11, 0, 15, 'ochre2')
home = Sprite(16, 16)  # buzón de casa (solo si la casa está configurada)
home.rect(5, 3, 7, 6, 'blue'); home.rect(6, 4, 5, 2, 'white'); home.vline(8, 9, 14, 'ink')
home.px(11, 3, 'red'); home.px(11, 4, 'red')
# cofres per categoria (data/loot.json): ferro, plata i llegendari (el de fusta és chest_closed/open)
def tier_chest(body, band, lock, opened, glow=None):
    s = Sprite(16, 16)
    cm = {'k': 'ink', 'o': body[0], 'O': body[1], 'y': lock, 'b': band, '.': 'asph3'}
    rows = CH if not opened else ["kkkkkkkkkkkkkk", "kOOOOOOOOOOOOk", "kkkkkkkkkkkkkk", "k............k"] + CH[3:]
    s.pattern(1, 5 if not opened else 2, rows, cm)
    for y in range(6 if not opened else 3, 14):   # flejes metálicos
        if s.a[y, 3, 3]: s.px(3, y, band)
        if s.a[y, 12, 3]: s.px(12, y, band)
    if glow and opened:
        for x in range(4, 12, 2): s.px(x, 4, glow); s.px(x + 1, 3, glow)
    return s


CHEST_TIERS = {'iron': (('stone2', 'stone3'), 'asph2', 'white2', None),
               'silver': (('white2', 'white3'), 'stone', 'sea', 'pool'),
               'legend': (('ochre', 'ochre2'), 'terra2', 'red', 'ochre')}
for tier, (body, band, lock, glow) in CHEST_TIERS.items():
    save(tier_chest(body, band, lock, False), f'chest_{tier}_closed')
    save(tier_chest(body, band, lock, True, glow), f'chest_{tier}_open')
torch = Sprite(16, 16)   # antorcha de pared: 2 frames (8 × 16)
for f in range(2):
    ox_ = f * 8
    torch.rect(ox_ + 3, 8, 2, 8, 'ochre3'); torch.rect(ox_ + 2, 7, 4, 2, 'asph3')
    flame = [(3, 2 + f), (4, 1 + f), (2, 4), (5, 4), (3, 5), (4, 5), (3, 3), (4, 3), (3, 4), (4, 4), (2 + f, 3)]
    for x, y in flame:
        torch.px(ox_ + x, y, 'ochre' if y >= 4 else 'red')
    torch.px(ox_ + 3, 5, 'white'); torch.px(ox_ + 4, 6, 'ochre')
save(torch, 'torch')

for name, spr in (('sword', sword), ('shield', shield), ('heart_full', heart_full), ('heart_empty', heart_empty),
                  ('postcard', postcard), ('notebook', notebook), ('chest_closed', chest_c), ('chest_open', chest_o),
                  ('lever_off', lever_a), ('lever_on', lever_b), ('sign', sign), ('bubble', bubble),
                  ('cave_exit', cave_exit), ('home_mailbox', home)):
    save(spr, name)


# ------------------------------------------------------------------------------------
# Vehículos: coche 32 × 16 (h), 16 × 32 (v), 24 × 24 (diagonales); tren 48 × 16 / 16 × 48 / 40 × 40
# ------------------------------------------------------------------------------------
def car_sprite(w, h, ang, pal, kind='car'):
    """Coche visto desde arriba (vista cenital, como el resto del mundo), rasterizado por geometría
    para cualquier ángulo: así las diagonales salen limpias y la vista vertical no es un giro del
    dibujo lateral. ang en grados (0 = hacia la derecha, 90 = hacia abajo).
    Coordenadas locales: u a lo largo (+ = morro), v a lo ancho. Medidas en px (4 px ≈ 1 m)."""
    import math
    body, light, dark = pal
    L2, W2 = (12.5, 5.5) if kind == 'car' else (13.5, 6.0)
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    cx, cy = (w - 1) / 2, (h - 1) / 2 - 0.5
    s = Sprite(w, h)
    region = {}
    for y in range(h):
        for x in range(w):
            dx, dy = x - cx, y - cy
            u = dx * ca + dy * sa
            v = -dx * sa + dy * ca
            au, av = abs(u), abs(v)
            # carrocería: rectángulo con esquinas redondeadas
            r = 2.6
            qu, qv = max(au - (L2 - r), 0), max(av - (W2 - r), 0)
            if qu * qu + qv * qv > r * r:
                continue
            c = body
            if kind == 'car':
                if 1.0 < u < 5.4 and av < W2 - 0.9:
                    c = 'sea' if (u - v * 0.6) > 4.2 else 'sea3'      # parabrisas con brillo
                elif -8.2 < u < -5.4 and av < W2 - 1.1:
                    c = 'sea3'                                        # luneta
                elif -5.4 <= u <= 1.0 and av < W2 - 1.0:
                    c = dark if av > W2 - 1.9 else light              # techo con perfil
                elif u > 5.4 and av < 0.8:
                    c = light                                         # nervio del capó
            else:  # furgoneta: cabina corta delante, caja larga
                if 7.2 < u < 10.2 and av < W2 - 0.9:
                    c = 'sea' if (u - v * 0.6) > 9.2 else 'sea3'
                elif u <= 6.4 and av < W2 - 1.2:
                    c = light if u > -10 else dark
                elif 6.4 < u <= 7.2 and av < W2 - 1.2:
                    c = dark
            if au > L2 - 2.0 and 1.2 < av < W2 - 1.0:
                c = 'white' if u > 0 else 'red'                       # faros y pilotos
            if av > W2 - 0.9 and c == body:
                c = dark                                              # costados en sombra
            region[(x, y)] = c
    # sombra al sur-este y contorno
    for (x, y) in list(region):
        for dx, dy in ((1, 1), (0, 1), (1, 2), (0, 2)):
            q = (x + dx, y + dy)
            if q not in region and 0 <= q[0] < w and 0 <= q[1] < h:
                s.px(q[0], q[1], (31, 26, 36, 70))
    for (x, y), c in region.items():
        edge = any((x + dx, y + dy) not in region for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        s.px(x, y, 'ink' if edge else c)
    # ruedas: asoman por los costados
    for wu in (-L2 + 4.2, L2 - 4.2):
        for side in (-1, 1):
            for du in (-1.0, 0.0, 1.0):
                u, v = wu + du, side * (W2 + 0.4)
                x = round(cx + u * ca - v * sa)
                y = round(cy + u * sa + v * ca)
                if (x, y) not in region:
                    s.px(x, y, 'asph3')
    # retrovisores
    for side in (-1, 1):
        u, v = 3.2, side * (W2 + 0.6)
        x = round(cx + u * ca - v * sa)
        y = round(cy + u * sa + v * ca)
        if (x, y) not in region:
            s.px(x, y, 'ink')
    return s


CAR_PALETTES = [('red', 'terra', 'terra2', 'car'), ('blue', 'blue', 'sea3', 'car'),
                ('white', 'white2', 'white3', 'van'), ('ochre', 'sand', 'ochre2', 'car')]
cars = []
for body, light, dark, kind in CAR_PALETTES:
    pal = (body, light, dark)
    cars.append((car_sprite(32, 16, 0, pal, kind), car_sprite(16, 32, 90, pal, kind),
                 car_sprite(24, 24, 45, pal, kind), car_sprite(24, 24, 135, pal, kind)))
save(sheet([c[0] for c in cars], 1), 'car_h')
save(sheet([c[1] for c in cars], 4), 'car_v')
save(sheet([c[2] for c in cars] + [c[3] for c in cars], 4), 'car_d')


def rotate_v(s):
    out = Sprite(s.h, s.w)
    out.a = s.a.transpose(1, 0, 2)[:, ::-1].copy()
    return out


def diag(s, size, flip):
    """Variante diagonal dibujada por muestreo (pixel art, sin filtrado)."""
    import math
    out = Sprite(size, size)
    c = (size - 1) / 2
    ang = math.radians(45 if not flip else -45)
    for y in range(size):
        for x in range(size):
            dx, dy = x - c, y - c
            sx = dx * math.cos(-ang) - dy * math.sin(-ang) + (s.w - 1) / 2
            sy = dx * math.sin(-ang) + dy * math.cos(-ang) + (s.h - 1) / 2
            ix, iy = int(round(sx)), int(round(sy))
            if 0 <= ix < s.w and 0 <= iy < s.h and s.a[iy, ix, 3]:
                out.a[y, x] = s.a[iy, ix]
    return out


def train_h(kind, loco):
    s = Sprite(48, 16)
    body, stripe = {'rodalies': ('white', 'red'), 'hs': ('white', 'blue'), 'freight': ('ochre2', 'ochre3')}[kind]
    s.rect(1, 3, 46, 10, body); s.hline(1, 46, 10, stripe); s.hline(1, 46, 11, stripe)
    s.hline(1, 46, 2, 'ink'); s.hline(1, 46, 13, 'ink'); s.vline(0, 3, 12, 'ink'); s.vline(47, 3, 12, 'ink')
    for x in range(5, 44, 7):
        s.rect(x, 5, 4, 3, 'sea3'); s.px(x, 5, 'sea')
    if loco:
        s.rect(40, 4, 6, 5, 'sea3'); s.vline(46, 4, 9, 'ochre')
    s.rect(4, 13, 6, 2, 'asph3'); s.rect(38, 13, 6, 2, 'asph3')
    return s


trains = []
for kind in ('rodalies', 'hs', 'freight'):
    for loco in (True, False):
        h = train_h(kind, loco)
        trains.append((h, rotate_v(h), diag(h, 40, False), diag(h, 40, True)))
save(sheet([t[0] for t in trains], 1), 'train_h')
save(sheet([t[1] for t in trains], 6), 'train_v')
save(sheet([t[2] for t in trains] + [t[3] for t in trains], 6), 'train_d')
barrier = Sprite(16, 16)
for x in range(0, 16, 4):
    barrier.rect(x, 6, 2, 3, 'red'); barrier.rect(x + 2, 6, 2, 3, 'white')
barrier.rect(0, 5, 2, 10, 'asph3')
lamp_off, lamp_on = Sprite(8, 16), Sprite(8, 16)
for s, c in ((lamp_off, 'asph3'), (lamp_on, 'red')):
    s.vline(3, 4, 15, 'asph3'); s.rect(1, 1, 6, 4, 'ink'); s.rect(2, 2, 2, 2, c); s.rect(5, 2, 1, 2, c)
save(barrier, 'barrier'); save(lamp_off, 'lamp_off'); save(lamp_on, 'lamp_on')


# ------------------------------------------------------------------------------------
# Hitos (landmarks): sprites grandes con huella sólida y puerta
# ------------------------------------------------------------------------------------
landmarks = {}


def landmark(lid, w, h, solid, door, overhead_rows=0, poi=None, entrance=None):
    s = Sprite(w * 16, h * 16)
    landmarks[lid] = {'sprite': f'landmark_{lid}', 'w_tiles': w, 'h_tiles': h, 'solid': solid,
                      'door': door, 'overhead_rows': overhead_rows, 'poi': poi or lid}
    if entrance:
        landmarks[lid]['entrance'] = entrance
    return s


def stone_wall(s, x, y, w, h, c=('stone', 'stone2', 'stone3'), seed=0):
    rng = rng_for('sw', x, y, w, h, seed)
    s.rect(x, y, w, h, c[0])
    for yy in range(y, y + h, 4):
        s.hline(x, x + w - 1, yy, c[1])
        off = 0 if ((yy - y) // 4) % 2 else 3
        for xx in range(x + off, x + w, 6):
            s.vline(xx, yy, min(y + h - 1, yy + 3), c[1])
    s.speckle(rng, [c[2]], 0.04, (x, y, w, h))


# Sant Bartomeu (fotos de Wikimedia Commons, 2026-10-04): fachada de piedra arenisca con rosetón y portal
# de dos columnas acanaladas con tímpano de medio punto; campanario a la izquierda con base cuadrada,
# cuerpo octogonal con arcos y, tras una terraza, un cuerpo estrecho con cúpula; a la derecha la casa
# rectoral encalada. 5 × 6 tiles, la puerta en la columna 2.
s = landmark('sant_bartomeu', 5, 6, [(x, y) for y in (3, 4, 5) for x in range(5)] + [(0, 2), (1, 2)], (2, 6))
rng = rng_for('bartomeu')


def ashlar(s, x0, y0, w, h, light='sand', mid='ochre', dark='ochre2', seed=0):
    r_ = rng_for('ash', x0, y0, seed)
    for yy in range(y0, y0 + h):
        for xx in range(x0, x0 + w):
            s.px(xx, yy, light if xx < x0 + w * .35 else mid)
    for yy in range(y0 + 3, y0 + h, 4):
        s.hline(x0, x0 + w - 1, yy, dark)
        off = 0 if ((yy - y0) // 4) % 2 else 3
        for xx in range(x0 + off, x0 + w, 7):
            s.vline(xx, yy - 3, yy, dark)
    s.speckle(r_, [dark, 'sand2'], 0.03, (x0, y0, w, h))
    s.vline(x0 + w - 1, y0, y0 + h - 1, dark)


# casa rectoral (derecha): encalada, teja y ventanas renacentistas con marco de piedra
s.rect(58, 44, 22, 52, 'white'); s.vline(58, 44, 95, 'white2'); s.vline(79, 44, 95, 'white3')
s.speckle(rng, ['white2'], 0.05, (58, 44, 22, 52))
s.rect(57, 40, 23, 5, 'terra'); s.hline(57, 79, 40, 'terra2'); s.hline(57, 79, 44, 'terra3')
for xx in range(58, 80, 3):
    s.px(xx, 42, 'terra2')
for wx, wy in ((62, 52), (71, 52), (62, 70), (71, 70)):
    s.rect(wx - 1, wy - 1, 7, 10, 'stone'); s.rect(wx, wy, 5, 8, 'ink'); s.rect(wx + 1, wy + 1, 3, 6, 'sea3')
    s.hline(wx - 1, wx + 5, wy - 2, 'stone2')
s.rect(66, 84, 6, 11, 'stone2'); s.rect(67, 85, 4, 10, 'ochre3')          # porta de la rectoria
# nau: façana de pedra amb frontó corbat i creu
ashlar(s, 20, 38, 40, 58, seed=1)
for i in range(21):
    top = 38 - int(12 * (1 - (i / 20.0) ** 2))
    for xx in (40 - i, 39 + i):
        s.vline(xx, top, 38, 'sand' if xx < 40 else 'ochre')
        s.px(xx, top, 'ochre2'); s.px(xx, top - 1, 'ink')
s.hline(20, 59, 38, 'ochre2'); s.hline(19, 60, 37, 'ink')
s.vline(40, 18, 25, 'ink'); s.vline(39, 18, 25, 'ink'); s.hline(37, 42, 20, 'ink')   # creu
# rosetó
for yy in range(-6, 7):
    for xx in range(-6, 7):
        d = (xx * xx + yy * yy) ** .5
        if d <= 6.5:
            s.px(40 + xx, 50 + yy, 'ink' if d > 5.3 else ('ochre' if d < 1.5 or xx == 0 or yy == 0 or abs(xx) == abs(yy) else 'blue'))
# portal: dues columnes estriades, timpà de mig punt i porta de fusta
for cx_ in (31, 47):
    s.rect(cx_, 64, 3, 32, 'sand'); s.vline(cx_ + 1, 66, 93, 'ochre2'); s.vline(cx_ + 2, 64, 95, 'ochre2')
    s.rect(cx_ - 1, 62, 5, 2, 'ochre'); s.hline(cx_ - 1, cx_ + 3, 61, 'ink')
s.hline(29, 51, 60, 'ochre2'); s.hline(29, 51, 59, 'sand')
for yy in range(62, 75):
    d = 74 - yy
    half = int(max(0, 7 * 7 - d * d) ** .5)
    s.hline(40 - half, 39 + half, yy, 'ink' if half >= 6 or yy == 62 else 'ochre2')
s.rect(35, 74, 10, 22, 'ink'); s.rect(36, 75, 8, 21, 'ochre3'); s.vline(40, 75, 95, 'terra3')
s.rect(34, 68, 12, 2, 'sand')
# campanar: base quadrada, cos octogonal amb arcs, terrassa i cos estret amb cúpula
ashlar(s, 0, 42, 22, 54, seed=2)
s.rect(8, 56, 5, 8, 'ink'); s.rect(9, 57, 3, 6, 'sea3')                   # finestra
s.hline(0, 21, 42, 'ink'); s.rect(0, 40, 22, 2, 'ochre2')                  # cornisa
ashlar(s, 3, 18, 16, 22, seed=3)
for yy in range(18, 40):
    s.px(3, yy, 'ochre2'); s.px(18, yy, 'ochre3')                          # arestes de l'octògon
    s.px(6, yy, 'sand2'); s.px(15, yy, 'ochre2')
for ax in (7, 12):                                                          # arcs del campanar
    s.rect(ax, 24, 3, 9, 'ink'); s.px(ax + 1, 23, 'ink')
s.rect(9, 27, 4, 3, 'ochre3')                                               # campana
s.rect(1, 15, 20, 3, 'sand'); s.hline(1, 20, 15, 'ink'); s.hline(1, 20, 17, 'ochre2')   # terrassa
for xx in range(2, 20, 2):
    s.px(xx, 14, 'ochre2')
ashlar(s, 6, 7, 10, 8, seed=4)
s.rect(9, 9, 2, 4, 'ink')
for yy in range(0, 7):                                                     # cúpula
    half = int(5 * (1 - ((6 - yy) / 6.0) ** 2) ** .5) if yy < 6 else 5
    s.hline(11 - half, 10 + half, yy + 1, 'sand' if yy < 3 else 'ochre')
    s.px(11 + half, yy + 1, 'ochre2')
s.px(10, 0, 'ink'); s.px(11, 0, 'ink')
s.speckle(rng, ['pine2'], 0.02, (0, 92, 80, 3))
s.hline(0, 79, 95, 'ink')
save(s, 'landmark_sant_bartomeu')

# Arc de Berà (s. I aC): arco de triunfo romano de un vano, 4 pilastras acanaladas con capitel
# corintio por cara, entablamento con la inscripción y ático. Piedra dorada, luz desde la izquierda.
# 5 × 4 tiles: se pasa por debajo por la columna central.
s = landmark('arc_de_bera', 5, 4, [(0, 3), (1, 3), (3, 3), (4, 3)], (2, 4), overhead_rows=3)
W_, H_ = 80, 64
rng = rng_for('arc')
for yy in range(H_):                               # sillares con luz a la izquierda
    for xx in range(W_):
        c = 'ochre' if xx < 26 else ('ochre2' if xx > 60 else 'ochre')
        s.px(xx, yy, c)
for yy in range(12, H_, 4):                        # hiladas
    s.hline(0, W_ - 1, yy, 'ochre2')
    off = 0 if (yy // 4) % 2 else 4
    for xx in range(off, W_, 9):
        s.vline(xx, yy, min(H_ - 1, yy + 3), 'ochre2')
s.speckle(rng, ['ochre3', 'ochre2', 'sand'], 0.05, (0, 12, W_, H_ - 12))
# ático y cornisa
s.rect(4, 0, 72, 7, 'ochre'); s.hline(4, 75, 0, 'ink'); s.vline(4, 0, 6, 'ink'); s.vline(75, 0, 6, 'ink')
s.hline(5, 74, 1, 'sand'); s.hline(4, 75, 6, 'ochre3')
s.rect(0, 7, W_, 3, 'sand'); s.hline(0, W_ - 1, 7, 'ink'); s.hline(0, W_ - 1, 9, 'ochre3')
for xx in range(1, W_, 3):                         # dentículos
    s.px(xx, 10, 'ochre3')
# friso con la inscripción (L·LICINIVS·L·F·SERG·SVRA…)
s.rect(10, 11, 60, 5, 'ochre'); s.hline(10, 69, 15, 'ochre3')
for xx in range(12, 68, 2):
    if rng.random() < 0.75:
        s.px(xx, 13, 'ochre3')
s.hline(0, W_ - 1, 17, 'ochre3'); s.hline(0, W_ - 1, 18, 'sand')
# vano del arco (transparente) con dovelas
cx, r_out, spring = 40, 12, 33
for yy in range(19, H_):
    if yy >= spring:
        half = r_out - 2
    else:
        d = spring - yy
        half = int(max(0, (r_out - 2) ** 2 - d * d) ** .5) if d < r_out - 2 else 0
    for xx in range(cx - half, cx + half):
        s.a[yy, xx] = (0, 0, 0, 0)
for k in range(0, 181, 6):                         # anillo de dovelas
    import math
    a = math.radians(180 - k)
    for rr in (r_out - 1, r_out):
        x_ = int(round(cx + rr * math.cos(a) - 0.5)); y_ = int(round(spring - rr * math.sin(a)))
        s.px(x_, y_, 'sand' if (k // 6) % 2 else 'ochre2')
s.px(cx - 1, spring - r_out - 1, 'ink'); s.px(cx, spring - r_out - 1, 'ink')      # clave
s.vline(cx - r_out + 2, spring, H_ - 1, 'ochre3'); s.vline(cx + r_out - 3, spring, H_ - 1, 'ochre3')
# pilastras acanaladas con capitel y basa
for px_ in (5, 19, 56, 70):
    s.rect(px_, 20, 6, 41, 'sand')
    s.vline(px_, 20, 60, 'ochre'); s.vline(px_ + 5, 20, 60, 'ochre3')
    s.vline(px_ + 2, 23, 58, 'ochre2'); s.vline(px_ + 4, 23, 58, 'ochre2')   # acanaladuras
    s.rect(px_ - 1, 19, 8, 3, 'ochre'); s.px(px_, 18, 'sand'); s.px(px_ + 5, 18, 'sand')  # capitel
    s.px(px_ + 1, 20, 'pine3'); s.px(px_ + 4, 20, 'pine3')                    # hojas de acanto (pátina)
    s.rect(px_ - 1, 59, 8, 2, 'ochre2')                                        # basa
# zócalo, hierba y pátina
s.rect(0, 61, cx - r_out + 2, 3, 'ochre2'); s.rect(cx + r_out - 2, 61, W_ - cx - r_out + 2, 3, 'ochre2')
s.hline(0, W_ - 1, 63, 'ink')
for xx in range(0, W_, 2):
    if rng.random() < 0.35 and not (cx - r_out + 2 <= xx < cx + r_out - 2):
        s.px(xx, 62, 'pine2'); s.px(xx, 61, 'pine')
for xx in range(W_ - 3, W_):
    s.vline(xx, 10, 62, 'ochre3')                  # canto en sombra
save(s, 'landmark_arc_de_bera')

# Roc de Sant Gaietà (fotos de Wikimedia Commons, 2026-10-04): poble mariner d'estil andalús. Torre de
# pedra emmerletada a l'esquerra, cases encalades amb ràfec de teula, arc de pas (la columna 1 es pot
# travessar), columnes de pedra del Mèdol, balcó de forja i testos amb flors. 4 × 5 tiles.
s = landmark('roc_sant_gaieta', 4, 5, [(x, y) for y in (3, 4) for x in (0, 2, 3)] + [(0, 2), (1, 2)], (1, 5))
rng = rng_for('roc')
stone_wall(s, 0, 4, 22, 76, seed=3)                         # torre
for x in range(0, 22, 5):
    s.rect(x, 0, 3, 5, 'stone2'); s.px(x, 0, 'stone')        # merlets
s.hline(0, 21, 5, 'stone3')
s.rect(8, 16, 5, 9, 'ink'); s.px(10, 15, 'ink'); s.rect(9, 18, 3, 6, 'sea3')
s.vline(21, 4, 79, 'stone3')
# casa blanca de dues plantes amb ràfec de teula (dreta)
s.rect(22, 26, 42, 54, 'white'); s.vline(22, 26, 79, 'white2'); s.vline(63, 26, 79, 'white3')
s.speckle(rng, ['white2'], 0.05, (22, 26, 42, 54))
s.rect(21, 22, 43, 4, 'terra'); s.hline(21, 63, 22, 'terra2'); s.hline(21, 63, 25, 'terra3')
for xx in range(22, 64, 3):
    s.px(xx, 26, 'terra2')                                   # ràfec
s.rect(44, 30, 8, 4, 'blush')                                # rajola de color
# finestres amb arc i balcó de forja
for wx in (40, 52):
    s.rect(wx, 34, 7, 10, 'ink'); s.hline(wx + 1, wx + 5, 33, 'ink'); s.rect(wx + 1, 35, 5, 9, 'sea3')
s.hline(38, 60, 45, 'ink'); s.hline(38, 60, 47, 'ink')
for xx in range(38, 61, 2):
    s.px(xx, 46, 'ink')
s.rect(40, 42, 3, 3, 'terra'); s.px(41, 41, 'red'); s.px(40, 41, 'pine2'); s.px(42, 41, 'pine2')
s.rect(55, 42, 3, 3, 'terra'); s.px(56, 41, 'red'); s.px(55, 41, 'pine2'); s.px(57, 41, 'pine2')
# arc de pas amb columnes de pedra
for yy in range(48, 80):
    half = 7 if yy > 55 else int(max(0, 49 - (55 - yy) ** 2) ** .5)
    s.hline(24 - half, 23 + half, yy, 'asph3' if yy > 70 else 'ink')
for cx_ in (14, 32):
    s.rect(cx_, 56, 3, 24, 'ochre'); s.vline(cx_ + 2, 56, 79, 'ochre2'); s.rect(cx_ - 1, 54, 5, 2, 'ochre2')
# finestra baixa amb reixa i test
s.rect(44, 60, 8, 9, 'ink'); s.rect(45, 61, 6, 7, 'sea3')
for xx in range(45, 51, 2):
    s.vline(xx, 61, 67, 'ink')
s.rect(56, 70, 5, 6, 'terra'); s.rect(55, 66, 7, 4, 'pine2'); s.px(57, 65, 'red'); s.px(59, 66, 'red')
s.rect(38, 72, 4, 5, 'terra2'); s.rect(37, 69, 6, 3, 'pine'); s.px(39, 68, 'blush')
s.hline(0, 63, 79, 'ink')
save(s, 'landmark_roc_sant_gaieta')

# Ermita de Berà (3 × 4)
s = landmark('ermita_bera', 3, 4, [(x, y) for y in (2, 3) for x in (0, 2)] + [(1, 2)], (1, 4))
stone_wall(s, 0, 16, 48, 48, c=('white', 'white2', 'white3'), seed=5)
s.rect(18, 0, 12, 18, 'white'); s.rect(21, 4, 6, 8, 'ink'); s.rect(23, 6, 2, 4, 'ochre')  # espadaña
for i in range(12):
    s.hline(i * 2, 47 - i * 2, 18 + i // 1 - 6 if False else 16 + i // 2, 'terra')
s.rect(17, 40, 14, 24, 'ochre3'); s.vline(24, 40, 63, 'ink'); s.hline(17, 30, 40, 'ink')
s.hline(0, 47, 63, 'ink')
save(s, 'landmark_ermita_bera')

# Pedrera de l'Elies: pared rocosa con la boca de la cueva (ficticia) (4 × 3)
s = landmark('pedrera_elies', 4, 3, [(0, 1), (0, 2), (3, 1), (3, 2), (1, 1), (2, 1)], (1, 3),
             entrance={'rect': [1, 2, 2, 1], 'target_scene': 'cova_pedrera', 'target_spawn': 'spawn_entrance',
                       'return_spawn': 'spawn_pedrera_door', 'requires': 'got_sword'})
rng = rng_for('pedrera')
for yy in range(48):
    for xx in range(64):
        top = 6 + int(4 * abs(((xx * 7) % 23) / 23 - .5))
        if yy >= top:
            s.px(xx, yy, rng.choice(['stone2', 'stone2', 'stone3', 'stone']))
for yy in range(10, 48, 7):
    s.hline(0, 63, yy, 'stone3')
for yy in range(26, 48):
    half = 11 if yy > 34 else int((121 - (34 - yy) ** 2) ** .5) if 34 - yy < 11 else 0
    s.hline(32 - half, 31 + half, yy, 'ink')
save(s, 'landmark_pedrera_elies')

# Torre del Cucurull: torre de defensa medieval de planta cuadrada, sillarejo, esquineras,
# aspilleras, puerta elevada y almenas, con la parte alta derruida a la derecha (2 × 4)
s = landmark('cucurull', 2, 4, [(0, 2), (1, 2), (0, 3), (1, 3)], (0, 4))
rng = rng_for('cucurull')
stone_wall(s, 3, 8, 26, 56, seed=6)
for yy in range(8, 64):                            # volumen: cara derecha en sombra
    s.hline(22, 28, yy, 'stone2')
s.speckle(rng, ['stone3'], 0.05, (22, 8, 7, 56))
for yy in range(8, 64, 6):                         # esquineras alternas
    s.rect(3, yy, 4 if (yy // 6) % 2 else 3, 3, 'white2'); s.rect(26, yy + 3, 3, 3, 'stone3')
for k, x in enumerate(range(3, 29, 5)):            # almenas (derruidas a la derecha)
    hgt = 7 if x < 18 else max(0, 7 - (x - 16))
    if hgt:
        s.rect(x, 8 - hgt, 3, hgt, 'stone'); s.px(x, 8 - hgt, 'white2')
s.hline(3, 28, 8, 'stone3')
for x_, y_ in ((22, 4), (25, 6), (20, 3)):         # piedras sueltas del derrumbe
    s.px(x_, y_, 'stone2')
s.rect(14, 18, 3, 7, 'ink'); s.px(15, 17, 'ink')   # aspilleras
s.rect(9, 32, 2, 6, 'ink'); s.rect(21, 30, 2, 6, 'ink')
s.rect(12, 44, 8, 12, 'ink'); s.rect(13, 45, 6, 11, 'ochre3')        # puerta elevada con arco
s.hline(13, 18, 43, 'ink'); s.px(12, 44, 'stone'); s.px(19, 44, 'stone')
s.vline(16, 45, 55, 'ink'); s.px(17, 50, 'ochre')
s.rect(11, 56, 10, 2, 'stone2')                    # rellano
for yy in range(58, 64):                           # escalera de piedra hasta la puerta
    s.hline(14 - (yy - 58) // 2, 18 + (yy - 58) // 2, yy, 'white3' if yy % 2 else 'stone2')
for x_, y_ in ((4, 40), (5, 41), (4, 42), (6, 43), (5, 46), (4, 47), (27, 20), (27, 21), (26, 22)):
    s.px(x_, y_, 'pine2')                          # hiedra
s.vline(3, 8, 63, 'stone3'); s.vline(29, 1, 63, 'ink'); s.hline(2, 29, 63, 'ink')
save(s, 'landmark_cucurull')

# Mirador Pujol de la Morella: barandilla y telescopio (3 × 2)
s = landmark('mirador_morella', 3, 2, [(2, 1)], (1, 2))
s.rect(0, 16, 48, 16, 'stone'); s.hline(0, 47, 16, 'white2'); s.hline(0, 47, 31, 'stone3')
for x in range(0, 48, 6):
    s.vline(x, 8, 16, 'ink')
s.hline(0, 47, 8, 'ink')
s.rect(36, 10, 8, 4, 'asph3'); s.rect(42, 9, 4, 3, 'blue'); s.vline(39, 14, 26, 'ink'); s.hline(36, 42, 27, 'ink')
save(s, 'landmark_mirador_morella')

# Roda de Mar: apeadero (4 × 3)
s = landmark('roda_de_mar', 4, 3, [(x, y) for y in (1, 2) for x in (0, 1, 3)], (2, 3))
stone_wall(s, 0, 12, 64, 36, c=('ochre', 'ochre2', 'ochre3'), seed=7)
s.rect(0, 4, 64, 10, 'terra2'); s.rect(2, 6, 60, 6, 'terra')
s.rect(26, 16, 12, 10, 'white'); s.rect(28, 18, 8, 6, 'blue')    # rótulo
s.rect(6, 28, 8, 10, 'sea3'); s.rect(50, 28, 8, 10, 'sea3')
s.rect(36, 30, 10, 18, 'ochre3'); s.vline(41, 30, 47, 'ink')
s.hline(0, 63, 47, 'ink')
save(s, 'landmark_roda_de_mar')

# --- edificios nuevos (2026-10): Ajuntament, Biblioteca Municipal y Castell de Creixell ------------------
def roof_tiles(s, x, y, w, h, c=('terra', 'terra2', 'terra3')):
    s.rect(x, y, w, h, c[0])
    for yy in range(y, y + h, 3):
        s.hline(x, x + w - 1, yy, c[1])
        for xx in range(x + (yy // 3) % 2 * 2, x + w, 4):
            s.px(xx, yy + 1, c[2])
    s.hline(x, x + w - 1, y, mix(c[0], 'white', .25))


def arched(s, x, y, w, h, frame, glass):
    """Ventana o puerta con arco de medio punto."""
    s.rect(x, y + 2, w, h - 2, frame)
    s.hline(x + 1, x + w - 2, y + 1, frame); s.hline(x + 2, x + w - 3, y, frame)
    s.rect(x + 1, y + 2, w - 2, h - 3, glass)
    s.hline(x + 2, x + w - 3, y + 1, glass)


# Ajuntament de Roda de Berà (5 × 4): fachada ocre de dos plantas, balcón central con las banderas,
# reloj en el frontón, planta baja de piedra con portal de arco y escalinata.
s = landmark('ajuntament', 5, 4, [(x, y) for y in (2, 3) for x in range(5)], (2, 4))
roof_tiles(s, 2, 2, 76, 8)
s.rect(30, 0, 20, 10, 'ochre'); s.hline(30, 49, 0, 'white'); s.vline(30, 0, 9, 'ochre2')   # frontón
s.rect(36, 2, 8, 7, 'white'); s.px(40, 3, 'ink'); s.vline(40, 3, 5, 'ink'); s.hline(40, 42, 5, 'ink')
s.rect(0, 10, 80, 30, 'ochre'); s.hline(0, 79, 10, 'white'); s.hline(0, 79, 11, 'ochre2')
s.rect(0, 40, 80, 24, 'stone'); stone_wall(s, 0, 40, 80, 22, seed=11)
s.hline(0, 79, 39, 'white'); s.hline(0, 79, 40, 'stone3')
for x in (6, 18, 54, 66):                        # ventanas de la planta noble con persianas
    s.rect(x - 2, 16, 2, 14, 'pine2'); s.rect(x + 8, 16, 2, 14, 'pine2')
    arched(s, x, 15, 8, 16, 'white2', 'sea3'); s.px(x + 2, 18, 'sea')
    s.hline(x - 1, x + 8, 31, 'white')
s.rect(30, 14, 20, 18, 'white2'); arched(s, 33, 14, 14, 18, 'white', 'sea3')     # balconera central
s.hline(27, 52, 29, 'ink'); s.hline(27, 52, 33, 'white'); s.hline(27, 52, 34, 'stone3')
for x in range(28, 52, 3): s.vline(x, 29, 32, 'ink')                            # barandilla
for i, (cols) in enumerate((('ochre', 'red'), ('red', 'ochre'), ('blue', 'blue'))):  # banderas
    fx = 31 + i * 7
    s.vline(fx, 12, 28, 'asph3')
    for yy in range(13, 19):
        for xx in range(fx + 1, fx + 6):
            c = cols[0] if (yy - 13) % 2 == 0 else cols[1]
            if i == 2: c = 'blue' if not ((xx + yy) % 4 == 0 and 14 <= yy <= 17) else 'ochre'
            s.px(xx, yy, c)
for x in (8, 66):                                  # ventanas de la planta baja con reja
    s.rect(x, 46, 6, 10, 'sea3'); s.rect(x - 1, 45, 8, 1, 'white2')
    for xx in range(x, x + 6, 2): s.vline(xx, 46, 55, 'ink')
arched(s, 31, 42, 18, 22, 'white2', 'ochre3')                                  # portal
s.vline(40, 46, 63, 'ink'); s.px(38, 54, 'ochre'); s.px(42, 54, 'ochre')
for k in range(3): s.hline(28 - k * 2, 51 + k * 2, 61 + k, 'white2' if k % 2 == 0 else 'stone')
s.vline(79, 10, 63, 'ochre3'); s.hline(0, 79, 63, 'ink')
save(s, 'landmark_ajuntament')

# Biblioteca Municipal Joan Martorell Coca (4 × 3): edificio blanco moderno con cristalera, rótulo y
# un libro abierto pintado en la fachada.
s = landmark('biblioteca', 4, 3, [(x, y) for y in (1, 2) for x in range(4)], (1, 3))
s.rect(0, 4, 64, 6, 'white2'); s.hline(0, 63, 4, 'white'); s.hline(0, 63, 9, 'stone3')   # cornisa
s.rect(0, 10, 64, 38, 'white'); s.vline(63, 10, 47, 'white3'); s.vline(62, 10, 47, 'white2')
s.rect(6, 14, 22, 8, 'blue'); s.rect(7, 15, 20, 6, mix('blue', 'white', .25))           # rótulo
for xx in range(9, 25, 3): s.vline(xx, 17, 18, 'white')
s.rect(36, 13, 22, 11, 'white2')                                                         # libro abierto
s.rect(37, 14, 9, 9, 'white'); s.rect(47, 14, 9, 9, 'white'); s.vline(46, 14, 23, 'stone3')
for yy in (16, 18, 20):
    s.hline(38, 44, yy, 'stone2'); s.hline(48, 54, yy, 'stone2')
s.rect(4, 27, 56, 18, 'asph3'); s.rect(5, 28, 54, 16, 'sea3')                           # cristalera
for xx in range(5, 59, 9): s.vline(xx, 28, 43, 'asph2')
for xx in range(6, 58, 9): s.px(xx, 29, 'sea'); s.px(xx + 1, 29, 'sea'); s.px(xx, 30, 'sea')
s.rect(23, 31, 10, 13, 'ochre2'); s.vline(28, 31, 43, 'ochre3')                         # puerta
s.rect(0, 45, 64, 3, 'stone2'); s.hline(0, 63, 47, 'ink')
save(s, 'landmark_biblioteca')

# Castell de Creixell (6 × 5): murallas con almenas, torre del homenaje redonda y portal con rastrillo.
s = landmark('castell_creixell', 6, 5, [(x, y) for y in (2, 3) for x in range(6)] + [(0, 4), (1, 4), (4, 4), (5, 4)], (2, 5),
             entrance={'rect': [2, 4, 2, 1], 'target_scene': 'masmorra_castell', 'target_spawn': 'spawn_entrance',
                       'return_spawn': 'spawn_castell_door', 'min_level': 3})
stone_wall(s, 0, 30, 96, 50, c=('ochre2', 'ochre3', 'terra3'), seed=21)                 # muralla
for x in range(0, 96, 8): s.rect(x, 26, 5, 5, 'ochre2'); s.hline(x, x + 4, 26, 'ochre')
s.hline(0, 95, 30, 'ochre')
stone_wall(s, 56, 4, 30, 50, c=('ochre', 'ochre2', 'ochre3'), seed=22)                  # torre
for yy in range(4, 54): s.hline(78, 85, yy, 'ochre2')
for x in range(56, 86, 6): s.rect(x, 0, 4, 5, 'ochre'); s.px(x, 0, 'sand')
s.rect(68, 16, 3, 8, 'ink'); s.rect(68, 32, 3, 8, 'ink')                                  # aspilleras
s.rect(10, 6, 20, 26, 'ochre2'); stone_wall(s, 10, 6, 20, 26, c=('ochre2', 'ochre3', 'terra3'), seed=23)
for x in range(10, 30, 6): s.rect(x, 2, 4, 5, 'ochre2')                                  # torre pequeña
s.rect(18, 14, 3, 6, 'ink')
s.rect(34, 50, 20, 30, 'ink')                                                            # portal
for yy in range(46, 52):
    half = 10 - (51 - yy) * 2
    if half > 0: s.hline(44 - half, 43 + half, yy, 'ink')
s.rect(35, 52, 18, 28, 'asph3')
for xx in range(36, 53, 3): s.vline(xx, 52, 70, 'asph2')                                  # rastrillo
for yy in range(55, 71, 4): s.hline(35, 52, yy, 'asph2')
for x_, y_ in ((4, 60), (5, 61), (90, 40), (91, 41), (12, 70), (60, 66)):
    s.px(x_, y_, 'pine2')                                                                # hierbas
s.vline(95, 26, 79, 'terra3'); s.hline(0, 95, 79, 'ink')
save(s, 'landmark_castell_creixell')

with open(os.path.join(ROOT, 'data/landmarks.json'), 'w') as f:
    json.dump(landmarks, f, indent=1)


# ------------------------------------------------------------------------------------
# Fuente bitmap (Unifont, 8 × 16, OFL) en formato ImageFont de LÖVE
# ------------------------------------------------------------------------------------
GLYPHS = (''.join(chr(c) for c in range(32, 127)) +
          'ÀÁÈÉÍÏÒÓÚÜÇÑàáèéíïòóúüçñ·¡¿«»€’—…©')
font_path = '/usr/share/fonts/opentype/unifont/unifont.otf'
uf = ImageFont.truetype(font_path, 16)
widths = []
for ch in GLYPHS:
    widths.append(8 if ord(ch) < 0x2000 else 8)
img = Image.new('RGBA', (sum(widths) + len(GLYPHS) + 1, 16), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)
x = 0
sep = (255, 0, 255, 255)
for ch, w in zip(GLYPHS, widths):
    for yy in range(16):
        img.putpixel((x, yy), sep)
    x += 1
    g = Image.new('L', (16, 16), 0)
    ImageDraw.Draw(g).text((0, 0), ch, font=uf, fill=255)
    for yy in range(16):
        for xx in range(w):
            if g.getpixel((xx, yy)) > 127:
                img.putpixel((x + xx, yy), (255, 255, 255, 255))
    x += w
for yy in range(16):
    img.putpixel((x, yy), sep)
img.save(os.path.join(ROOT, 'assets/runtime/font.png'))
with open(os.path.join(ROOT, 'assets/runtime/font.txt'), 'w', encoding='utf-8') as f:
    f.write(GLYPHS)
print('sprites ok:', len(os.listdir(OUT)), 'ficheros;', len(landmarks), 'hitos;', len(GLYPHS), 'glifos')


# ------------------------------------------------------------------------------------
# Acciones del protagonista (32 × 32): ataque (3 fases × 4 direcciones), defensa (4) y bici (2 × 4)
# ------------------------------------------------------------------------------------
def base_frame(colors, row, col):
    sh = character(colors)
    out = Sprite(16, 24)
    out.a = sh.a[row * 24:(row + 1) * 24, col * 16:(col + 1) * 16].copy()
    return out


def draw_sword(s, x0, y0, x1, y1):
    """Hoja de (x0,y0) a (x1,y1) con contorno; empuñadura en (x0,y0)."""
    import math
    n = max(abs(x1 - x0), abs(y1 - y0))
    for i in range(n + 1):
        x = round(x0 + (x1 - x0) * i / n)
        y = round(y0 + (y1 - y0) * i / n)
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if not s.a[y + dy, x + dx, 3] if 0 <= y + dy < s.h and 0 <= x + dx < s.w else False:
                s.px(x + dx, y + dy, 'ink')
    for i in range(n + 1):
        x = round(x0 + (x1 - x0) * i / n)
        y = round(y0 + (y1 - y0) * i / n)
        s.px(x, y, 'ochre2' if i < 2 else ('white' if i % 2 else 'white2'))


def action_sheet(colors):
    frames = []
    # (fila base, desplazamiento cuerpo, [(empuñadura, punta)] por fase)
    plans = {
        'down': (0, [((24, 14), (29, 6)), ((16, 22), (16, 31)), ((8, 20), (2, 26))]),
        'up': (1, [((24, 14), (29, 6)), ((16, 6), (16, 0)), ((8, 14), (2, 8))]),
        'left': (2, [((20, 12), (26, 3)), ((9, 16), (0, 16)), ((10, 20), (3, 27))]),
    }
    for d in ('down', 'up', 'left', 'right'):
        src = 'left' if d == 'right' else d
        row, phases = plans[src]
        for ph in range(3):
            s = Sprite(32, 32)
            body = base_frame(colors, row, 4)
            if ph == 1:  # el cuerpo se inclina un píxel hacia el golpe
                off = {'down': (0, 1), 'up': (0, -1), 'left': (-1, 0)}[src]
            else:
                off = (0, 0)
            (hx, hy), (tx, ty) = phases[ph]
            behind = src == 'up' or ph == 0
            if behind:
                draw_sword(s, hx, hy, tx, ty)
            s.blit(body, 8 + off[0], 6 + off[1])
            if not behind:
                draw_sword(s, hx, hy, tx, ty)
            frames.append(s.flip_h() if d == 'right' else s)
    # defensa: escudo delante
    shield_rows = [".kkkkkk.", "kWWrrWWk", "krrrrrrk", "kWWrrWWk", "kWWrrWWk", ".kWrrWk.", "..kkkk.."]
    cm = {'k': 'ink', 'W': 'ochre', 'r': 'red'}
    for d in ('down', 'up', 'left', 'right'):
        src = 'left' if d == 'right' else d
        row = {'down': 0, 'up': 1, 'left': 2}[src]
        s = Sprite(32, 32)
        body = base_frame(colors, row, 4)
        if src == 'up':
            s.pattern(12, 12, shield_rows, cm)
            s.blit(body, 8, 7)
        else:
            s.blit(body, 8, 7)
            if src == 'down':
                s.pattern(12, 17, shield_rows, cm)
            else:
                s.pattern(7, 15, shield_rows, cm)
        frames.append(s.flip_h() if d == 'right' else s)
    return sheet(frames, 4)


def bike_sheet(colors):
    import math
    frames = []
    bare = colors.get('_outfit', 'shorts') in ('shorts', 'dress', 'tshirt')
    leg = colors.get('s', 'skin') if bare else colors.get('b', 'blue')
    shoe = colors.get('o', 'terra3')
    for d in ('down', 'up', 'left', 'right'):
        src = 'left' if d == 'right' else d
        row = {'down': 0, 'up': 1, 'left': 2}[src]
        for f in range(2):
            s = Sprite(32, 32)
            body = base_frame(colors, row, 4)
            top = Sprite(16, 24)
            top.a[:18] = body.a[:18]
            if src == 'left':
                # ruedas a izquierda y derecha, cuadro rojo
                for cx in (9, 23):
                    for a in range(0, 360, 15):
                        s.px(round(cx + 4 * math.cos(math.radians(a))), round(26 + 4 * math.sin(math.radians(a))), 'ink')
                    s.px(cx, 26, 'asph2')
                s.hline(10, 22, 23, 'red'); s.vline(16, 20, 25, 'red'); s.px(9, 22, 'red'); s.px(8, 21, 'ink')
                s.hline(6, 9, 20, 'ink')   # manillar
                s.blit(top, 9, 3)
                # piernas pedaleando
                lx = 15 + (2 if f else -1)
                s.vline(lx, 21, 24, leg); s.px(lx, 25, shoe)
                s.vline(lx + 2, 21, 23 - f, leg)
            else:
                # vista frontal/trasera: rueda de canto (neumático con brillo), cuadro, manillar y pedales
                s.rect(14, 22, 4, 10, 'ink'); s.rect(15, 23, 2, 8, 'asph3'); s.vline(15, 24, 29, 'asph2')
                s.rect(15, 19, 2, 4, 'red')                                  # horquilla / cuadro
                if src == 'up':
                    s.hline(8, 23, 15, 'ink'); s.rect(7, 14, 2, 3, 'asph3'); s.rect(23, 14, 2, 3, 'asph3')
                s.blit(top, 8, 1 if src == 'down' else 2)
                lo, hi = (24, 21) if f else (21, 24)                         # pedaleo: un pie arriba, otro abajo
                for x, yb in ((12, lo), (19, hi)):
                    s.vline(x, 18, yb - 1, leg); s.vline(x + 1, 18, yb - 1, leg)
                    s.rect(x - 1 if x < 16 else x, yb, 3, 2, shoe)
                if src == 'down':                                            # manillar delante, con puños
                    s.hline(8, 23, 15, 'ink'); s.rect(7, 14, 2, 3, 'asph3'); s.rect(23, 14, 2, 3, 'asph3')
                    s.px(10, 14, colors.get('s', 'skin')); s.px(21, 14, colors.get('s', 'skin'))
                    s.rect(14, 16, 4, 2, 'white')                            # faro
            frames.append(s.flip_h() if d == 'right' else s)
    return sheet(frames, 2)


def vehicle_sheet(colors, kind):
    """Patinete eléctrico, scooter 125 y moto de enduro (32 × 32, 2 frames × 4 direcciones como la bici).
    De lado: el vehículo entero con el jugador encima; de frente/espalda: de canto, con faro o piloto."""
    frames = []
    bare = colors.get('_outfit', 'shorts') in ('shorts', 'dress', 'tshirt')
    leg = colors.get('s', 'skin') if bare else colors.get('b', 'blue')
    shoe = colors.get('o', 'terra3')
    body_c = {'patinete': ('asph3', 'asph2', 'sea'), 'scooter': ('red', 'terra2', 'white'),
              'motocross': ('ochre', 'ochre2', 'asph3')}[kind]
    for d in ('down', 'up', 'left', 'right'):
        src = 'left' if d == 'right' else d
        row = {'down': 0, 'up': 1, 'left': 2}[src]
        for f in range(2):
            s = Sprite(32, 32)
            body = base_frame(colors, row, 4)
            top = Sprite(16, 24)
            top.a[:18] = body.a[:18]
            wheel_r = 3 if kind == 'patinete' else 4
            if src == 'left':
                xs = (8, 24) if kind != 'patinete' else (9, 23)
                for cx in xs:              # ruedas (tacos en la de enduro, giran con el frame)
                    for a in range(0, 360, 15):
                        px_ = round(cx + wheel_r * math.cos(math.radians(a))); py_ = round(27 + wheel_r * math.sin(math.radians(a)))
                        s.px(px_, py_, 'ink' if not (kind == 'motocross' and (a // 15 + f) % 3 == 0) else 'asph2')
                    s.px(cx, 27, 'stone2')
                c1, c2, c3 = body_c
                if kind == 'patinete':
                    s.hline(9, 23, 25, c1); s.hline(10, 22, 24, c2)          # plataforma
                    s.vline(9, 13, 24, 'asph2'); s.hline(6, 10, 13, 'ink')   # barra y manillar
                    s.blit(top, 10, 2)
                    s.vline(15, 20, 23, leg); s.vline(17, 20, 23, leg); s.px(15, 24, shoe); s.px(17, 24, shoe)
                else:
                    if kind == 'scooter':
                        s.rect(16, 19, 11, 6, c1); s.rect(16, 19, 11, 1, c2); s.rect(19, 18, 7, 2, 'ink')   # carrocería y asiento
                        s.rect(9, 17, 4, 9, c1); s.px(9, 18, c3); s.hline(10, 18, 25, c2)
                    else:
                        s.rect(14, 18, 12, 4, c1); s.rect(18, 17, 8, 2, 'ink'); s.vline(10, 16, 26, 'stone3')   # depósito, sillín y horquilla
                        s.hline(12, 26, 23, 'asph3'); s.px(26, 22, 'stone2'); s.px(27, 22, 'stone2')        # chasis y escape
                    s.hline(7, 11, 15, 'ink'); s.px(7, 16, c3)                          # manillar y faro
                    s.blit(top, 12, 1)
                    s.vline(18, 19, 22, leg); s.hline(15, 18, 22 + f, leg); s.px(14, 22 + f, shoe)
            else:
                s.rect(14, 22, 4, 10, 'ink'); s.rect(15, 23, 2, 8, 'asph3')            # rueda de canto
                c1, c2, c3 = body_c
                if kind == 'scooter':
                    s.rect(11, 19, 10, 6, c1); s.rect(12, 19, 8, 2, c2)
                elif kind == 'motocross':
                    s.rect(12, 18, 8, 5, c1); s.rect(12, 17, 8, 1, c2)
                else:
                    s.rect(15, 14, 2, 9, 'asph2')
                if src == 'up' and kind != 'patinete':
                    s.rect(14, 23, 4, 2, 'red')                                        # piloto trasero
                s.blit(top, 8, 0 if kind == 'patinete' else 1)
                s.hline(8, 23, 15, 'ink'); s.rect(7, 14, 2, 3, 'asph3'); s.rect(23, 14, 2, 3, 'asph3')
                if kind == 'patinete':
                    s.vline(13, 18, 22, leg); s.vline(18, 18, 22, leg); s.px(13, 23, shoe); s.px(18, 23, shoe)
                else:
                    s.vline(10, 19, 22, leg); s.vline(21, 19, 22, leg); s.px(10, 23, shoe); s.px(21, 23, shoe)
                if src == 'down':
                    s.rect(14, 17 if kind != 'patinete' else 13, 4, 2, 'white')        # faro
            frames.append(s.flip_h() if d == 'right' else s)
    return sheet(frames, 2)


import math  # noqa: E402
save(action_sheet(PLAYER), 'player_action')
for _veh in ('patinete', 'scooter', 'motocross'):
    save(vehicle_sheet(PLAYER, _veh), f'player_{_veh}')
save(bike_sheet(PLAYER), 'player_bike')
# aspectos (data/skins.json): mismas hojas con otros colores y sombrero
for sk in json.load(open(os.path.join(ROOT, 'data/skins.json')))['skins']:
    if sk['id'] == 'default':
        continue
    cols = spec_of(sk['colors'], sk.get('hat'), sk.get('hair'), sk.get('outfit'), sk.get('extra'))
    save(character(cols), f"player_{sk['id']}")
    save(action_sheet(cols), f"player_{sk['id']}_action")
    save(bike_sheet(cols), f"player_{sk['id']}_bike")
    for _veh in ('patinete', 'scooter', 'motocross'):
        save(vehicle_sheet(cols, _veh), f"player_{sk['id']}_{_veh}")
# tráfico (src/systems/traffic.lua): motos, la moto de la Policia Local y patinetes con conductores del pueblo
for _veh, _npc, _name in (('scooter', 'npc_postie', 'traffic_moto_1'), ('scooter', 'npc_lady', 'traffic_moto_2'),
                          ('motocross', 'npc_police', 'traffic_police_1'), ('patinete', 'npc_tourist', 'traffic_patinete_1'),
                          ('patinete', 'npc_kid', 'traffic_patinete_2')):
    save(vehicle_sheet(NPCS[_npc], _veh), _name)
# ------------------------------------------------------------------------------------
# Fase 6: rètols i distintius dels edificis especials (lletres de 3 × 5 px), escut de Roda (una roda!),
# bandera, llum de policia, creu de farmàcia/CAP, bústia groga de Correus i carros del súper.
# ------------------------------------------------------------------------------------
FONT35 = {
    'A': ['.#.', '#.#', '###', '#.#', '#.#'], 'B': ['##.', '#.#', '##.', '#.#', '##.'], 'C': ['.##', '#..', '#..', '#..', '.##'],
    'D': ['##.', '#.#', '#.#', '#.#', '##.'], 'E': ['###', '#..', '##.', '#..', '###'], 'F': ['###', '#..', '##.', '#..', '#..'],
    'G': ['.##', '#..', '#.#', '#.#', '.##'], 'H': ['#.#', '#.#', '###', '#.#', '#.#'], 'I': ['###', '.#.', '.#.', '.#.', '###'],
    'J': ['..#', '..#', '..#', '#.#', '.#.'], 'K': ['#.#', '#.#', '##.', '#.#', '#.#'], 'L': ['#..', '#..', '#..', '#..', '###'],
    'M': ['#.#', '###', '###', '#.#', '#.#'], 'N': ['##.', '#.#', '#.#', '#.#', '#.#'], 'O': ['.#.', '#.#', '#.#', '#.#', '.#.'],
    'P': ['##.', '#.#', '##.', '#..', '#..'], 'Q': ['.#.', '#.#', '#.#', '##.', '.##'], 'R': ['##.', '#.#', '##.', '#.#', '#.#'],
    'S': ['.##', '#..', '.#.', '..#', '##.'], 'T': ['###', '.#.', '.#.', '.#.', '.#.'], 'U': ['#.#', '#.#', '#.#', '#.#', '###'],
    'V': ['#.#', '#.#', '#.#', '#.#', '.#.'], 'X': ['#.#', '#.#', '.#.', '#.#', '#.#'], 'Y': ['#.#', '#.#', '.#.', '.#.', '.#.'],
    'Z': ['###', '..#', '.#.', '#..', '###'], ' ': ['...', '...', '...', '...', '...'], '·': ['...', '...', '.#.', '...', '...'],
}


# més lletres per als rètols dels locals (data/locals.json): W, xifres i signes
FONT35.update({
    'W': ['#.#', '#.#', '#.#', '###', '#.#'], '&': ['.#.', '#.#', '.#.', '#.#', '.##'], "'": ['.#.', '.#.', '...', '...', '...'],
    '.': ['...', '...', '...', '...', '.#.'], '-': ['...', '...', '###', '...', '...'],
    '0': ['###', '#.#', '#.#', '#.#', '###'], '1': ['.#.', '##.', '.#.', '.#.', '###'], '2': ['##.', '..#', '.#.', '#..', '###'],
    '3': ['##.', '..#', '.#.', '..#', '##.'], '4': ['#.#', '#.#', '###', '..#', '..#'], '5': ['###', '#..', '##.', '..#', '##.'],
    '6': ['.##', '#..', '###', '#.#', '###'], '7': ['###', '..#', '.#.', '.#.', '.#.'], '8': ['###', '#.#', '###', '#.#', '###'],
    '9': ['###', '#.#', '###', '..#', '##.'],
})


def text35(spr, x, y, text, col):
    for ch in text.upper():
        g = FONT35.get(ch, FONT35[' '])
        for j, row in enumerate(g):
            for i, c in enumerate(row):
                if c == '#':
                    spr.px(x + i, y + j, col)
        x += 4


def board(text, bg, fg, edge, pad=3, icon=None):
    w = len(text) * 4 - 1 + pad * 2 + (8 if icon else 0)
    spr = Sprite(w, 11)
    spr.rect(0, 0, w, 11, edge)
    spr.rect(1, 1, w - 2, 9, bg)
    spr.hline(1, w - 2, 1, mix(bg, 'white', .25) if isinstance(bg, str) else bg)
    x = pad + (8 if icon else 0)
    text35(spr, x, 3, text, fg)
    if icon:
        icon(spr, pad, 2)
    return spr


def _star(spr, x, y):
    for dx, dy in ((2, 0), (1, 1), (2, 1), (3, 1), (0, 2), (1, 2), (2, 2), (3, 2), (4, 2), (1, 3), (3, 3), (0, 4), (4, 4)):
        spr.px(x + dx, y + dy, 'ochre')


def _horn(spr, x, y):     # corn de Correus
    for dx, dy in ((0, 2), (1, 1), (1, 2), (1, 3), (2, 2), (3, 2), (4, 1), (4, 3), (5, 0), (5, 4), (4, 2)):
        spr.px(x + dx, y + dy, 'blue')


def _bell(spr, x, y):
    spr.rect(x + 1, y + 1, 3, 3, 'ochre'); spr.hline(x, y + 4, y + 4, 'ochre2'); spr.hline(x, x + 4, y + 4, 'ochre2')
    spr.px(x + 2, y, 'ochre2'); spr.px(x + 2, y + 5, 'ink')


save(board('POLICIA', mix('blue', 'ink', .35), 'white', 'ink', icon=_star), 'sign_police')
save(board('CAP', 'white', 'pine3', 'ink'), 'sign_cap')
save(board('ESCOLA', 'ochre', 'terra3', 'ink', icon=_bell), 'sign_escola')
save(board('AJUNTAMENT', 'white', 'terra3', 'ink'), 'sign_ajuntament')
save(board('CORREUS', 'ochre', 'blue', 'ink', icon=_horn), 'sign_correus')
for _id, _txt, _bg, _fg in (('bonpreu', 'BONPREU', 'terra', 'white'), ('lidl', 'LIDL', 'blue', 'ochre'),
                            ('lidl_platja', 'LIDL', 'blue', 'ochre'), ('mercadona', 'MERCADONA', 'pine2', 'white'),
                            ('spar', 'SPAR', 'red', 'white'), ('aldi', 'ALDI', mix('blue', 'ink', .3), 'ochre'),
                            ('supercor', 'SUPERCOR', 'pine3', 'white')):
    save(board(_txt, _bg, _fg, 'ink'), 'sign_' + _id)
# rètols de llocs que l'OSM no té com a servei: gasolineres, grans botigues, hípica i poliesportiu
for _id, _txt, _bg, _fg in (('benzinera', 'BENZINERA', 'red', 'white'), ('leroy', 'LEROY MERLIN', 'pine2', 'white'),
                            ('garden', 'GARDEN PAGES', 'pine3', 'white'), ('hipica', 'HIPICA', 'terra3', 'white'),
                            ('poliesportiu', 'POLIESPORTIU', mix('blue', 'ink', .2), 'white')):
    save(board(_txt, _bg, _fg, 'ink'), 'sign_' + _id)


def _horse(coat, mane):
    spr = Sprite(24, 18)
    spr.rect(5, 6, 13, 6, coat)                              # cos
    spr.rect(16, 2, 4, 6, coat); spr.rect(19, 3, 3, 3, coat)  # coll i cap
    spr.px(21, 5, 'ink'); spr.px(19, 2, mane); spr.px(18, 1, coat)
    spr.vline(16, 2, 7, mane); spr.vline(15, 3, 6, mane)    # crinera
    spr.vline(4, 6, 11, mane); spr.px(3, 10, mane)          # cua
    for x in (6, 8, 15, 17):                                # potes
        spr.vline(x, 12, 16, coat); spr.px(x, 16, 'ink')
    spr.hline(5, 17, 12, mix(coat, 'ink', .3))
    out = Sprite(24, 18)
    for y in range(18):
        for x in range(24):
            if spr.a[y, x, 3]:
                out.a[y, x] = spr.a[y, x]
            elif any(0 <= x + dx < 24 and 0 <= y + dy < 18 and spr.a[y + dy, x + dx, 3]
                     for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out.px(x, y, 'ink')
    return out


save(_horse('terra2', 'ink'), 'horse_brown')
save(_horse('white2', 'stone3'), 'horse_white')
save(_horse('ochre3', 'terra3'), 'horse_chestnut')
# rètols dels locals i comerços reals (data/locals.json, tools/make_locals.py)
for _l in json.load(open(os.path.join(ROOT, 'data/locals.json')))['locals']:
    save(board(_l['sign'], _l['bg'], _l['fg'], 'ink'), 'sign_local_' + _l['id'])
# xiringuito de platja (Guinguetes del directori): caseta de fusta amb sostre de canyís i para-sol
def _chiringuito():
    spr = Sprite(32, 30)
    spr.rect(3, 12, 26, 15, 'ochre2'); spr.rect(4, 13, 24, 13, 'ochre')
    for x in range(5, 28, 3):
        spr.vline(x, 13, 25, 'ochre3')
    spr.rect(3, 18, 26, 3, 'terra3'); spr.hline(3, 28, 18, 'sand')     # taulell
    spr.rect(10, 21, 12, 5, 'ink'); spr.rect(11, 22, 4, 3, 'sea2'); spr.rect(17, 22, 4, 3, 'sun')   # obertura i ampolles
    for y in range(0, 13):                                              # sostre de canyís
        w = 16 - abs(y - 9) if y < 9 else 16
        spr.hline(16 - w, 15 + w, y + 2, 'sand2' if (y % 2) else 'ochre2')
    spr.hline(0, 31, 14, 'ochre3'); spr.rect(2, 26, 2, 4, 'ochre3'); spr.rect(28, 26, 2, 4, 'ochre3')
    return spr


def _parasol(col):
    spr = Sprite(18, 22)
    spr.vline(8, 6, 21, 'stone3'); spr.vline(9, 6, 21, 'white3')
    for y in range(0, 7):
        w = min(8, 2 + y * 2)
        for x in range(9 - w, 9 + w):
            spr.px(x, y, col if ((x - 9 + w) // 3) % 2 == 0 else 'white')
    spr.hline(1, 16, 7, 'ink')
    return spr


# autocaravana aparcada (pàrquing d'autocaravanes, map-overrides extra_features «caravans»): vista de dalt, 3 caselles
def _caravan(stripe, stripe2):
    spr = Sprite(20, 50)
    spr.rect(2, 4, 16, 44, 'ink')                                    # contorn
    spr.rect(3, 5, 14, 42, 'white'); spr.rect(3, 5, 14, 2, 'white2')
    spr.rect(4, 6, 12, 7, 'sea3'); spr.rect(5, 7, 10, 2, 'sea2')      # parabrisa (davant, a dalt)
    spr.rect(3, 15, 14, 5, 'white2')                                  # cabina
    spr.rect(5, 24, 10, 8, 'white3'); spr.rect(6, 25, 8, 6, 'stone2')  # claraboia
    spr.rect(6, 36, 8, 5, 'white3'); spr.rect(7, 37, 2, 3, 'asph3'); spr.rect(11, 37, 2, 3, 'asph3')   # aire i ventilació
    spr.vline(3, 20, 46, stripe); spr.vline(16, 20, 46, stripe)       # franges
    spr.vline(4, 22, 44, stripe2); spr.vline(15, 22, 44, stripe2)
    for y in (10, 38):                                                # rodes
        spr.rect(0, y, 2, 5, 'ink'); spr.rect(18, y, 2, 5, 'ink')
    spr.hline(4, 15, 47, 'stone3')
    return spr


save(_caravan('sea2', 'sea'), 'caravan_a')
save(_caravan('terra', 'terra2'), 'caravan_b')
save(_caravan('pine2', 'pine'), 'caravan_c')
save(_chiringuito(), 'chiringuito')
save(_parasol('red'), 'parasol_red')
save(_parasol('sea2'), 'parasol_blue')
# llum de policia (2 fotogrames: blau i vermell alterns)
_sir = Sprite(32, 6)
for _f in range(2):
    _sir.rect(_f * 16 + 2, 1, 12, 4, 'ink')
    _sir.rect(_f * 16 + 3, 2, 5, 2, 'blue' if _f == 0 else mix('blue', 'ink', .5))
    _sir.rect(_f * 16 + 8, 2, 5, 2, mix('red', 'ink', .5) if _f == 0 else 'red')
save(_sir, 'siren')
# creu del CAP (2 fotogrames: encesa i més brillant)
_cr = Sprite(28, 14)
for _f in range(2):
    g1, g2 = ('pine2', 'pine') if _f == 0 else ('pine', mix('pine', 'white', .45))
    ox = _f * 14
    _cr.rect(ox + 4, 0, 6, 14, 'ink'); _cr.rect(ox, 4, 14, 6, 'ink')
    _cr.rect(ox + 5, 1, 4, 12, g1); _cr.rect(ox + 1, 5, 12, 4, g1)
    _cr.rect(ox + 6, 2, 2, 10, g2); _cr.rect(ox + 2, 6, 10, 2, g2)
save(_cr, 'cross_cap')
# escut de Roda de Berà: una roda daurada sobre camper blau
_sh = Sprite(12, 14)
_sh.rect(0, 0, 12, 10, 'ink'); _sh.rect(1, 1, 10, 9, 'blue')
for _y in range(10, 14):
    _sh.hline(_y - 9, 11 - (_y - 9), _y, 'ink')
    if _y < 13: _sh.hline(_y - 8, 10 - (_y - 8), _y, 'blue')
for _a in range(0, 360, 30):
    _sh.px(round(6 + 3 * math.cos(math.radians(_a))), round(6 + 3 * math.sin(math.radians(_a))), 'ochre')
_sh.vline(6, 3, 9, 'ochre2'); _sh.hline(3, 9, 6, 'ochre2'); _sh.px(6, 6, 'ochre')
save(_sh, 'shield_roda')
# bandera (senyera) que oneja: 2 fotogrames de 16 × 24
_fl = Sprite(32, 24)
for _f in range(2):
    ox = _f * 16
    _fl.vline(ox + 1, 0, 23, 'stone3'); _fl.px(ox + 1, 0, 'ochre')
    for _i in range(12):
        dy = (1 if ((_i // 3 + _f) % 2) else 0)
        for _j in range(8):
            _fl.px(ox + 2 + _i, 1 + _j + dy, 'red' if _j in (1, 3, 5, 7) and _j < 8 else 'ochre')
save(_fl, 'flag_senyera')
# bústia groga de Correus (12 × 20) i carro del súper (16 × 12)
_mb = Sprite(12, 20)
_mb.rect(1, 4, 10, 16, 'ink'); _mb.rect(2, 5, 8, 14, 'ochre'); _mb.rect(1, 1, 10, 4, 'ink'); _mb.rect(2, 2, 8, 3, 'ochre2')
_mb.rect(3, 8, 6, 1, 'ink'); _mb.rect(4, 12, 4, 4, 'blue'); _mb.vline(2, 5, 18, mix('ochre', 'white', .3))
save(_mb, 'mailbox_correus')
_ct = Sprite(16, 12)
for _x in range(2, 14, 2): _ct.vline(_x, 1, 7, 'stone2')
for _y in (1, 4, 7): _ct.hline(2, 13, _y, 'stone2')
_ct.hline(0, 2, 0, 'red'); _ct.vline(14, 1, 8, 'stone3'); _ct.hline(3, 13, 8, 'stone3')
_ct.px(4, 10, 'ink'); _ct.px(12, 10, 'ink'); _ct.px(4, 9, 'asph3'); _ct.px(12, 9, 'asph3')
save(_ct, 'cart')
bike_icon = Sprite(16, 16)
import math as _m
for cx in (4, 12):
    for a_ in range(0, 360, 20):
        bike_icon.px(round(cx + 3 * _m.cos(_m.radians(a_))), round(11 + 3 * _m.sin(_m.radians(a_))), 'ink')
bike_icon.hline(5, 11, 8, 'red'); bike_icon.px(8, 9, 'red'); bike_icon.hline(2, 5, 6, 'ink')
save(bike_icon, 'bike_icon')
print('acciones y bici ok')


# ------------------------------------------------------------------------------------
# Fase 6: el Drac del cim (64 × 48: aletejant ×2, foc, i les versions blanques de dany), projectils
# (bola de foc, ràfaga de vent) i objectes clau (bastó màgic, cristall del drac)
# ------------------------------------------------------------------------------------
from PIL import ImageDraw as _ID  # noqa: E402
import numpy as _np  # noqa: E402


def _outline(spr, col='ink'):
    a = spr.a
    solid = a[:, :, 3] > 0
    edge = _np.zeros_like(solid)
    edge[1:, :] |= solid[:-1, :]; edge[:-1, :] |= solid[1:, :]
    edge[:, 1:] |= solid[:, :-1]; edge[:, :-1] |= solid[:, 1:]
    edge &= ~solid
    a[edge] = rgba(col)
    return spr


def dragon_frame(flap, breath):
    im = Image.new('RGBA', (64, 48), (0, 0, 0, 0))
    d = _ID.Draw(im)
    body, body2, belly, wing, wing2 = rgba('pine2'), rgba('pine3'), rgba('sun'), mix('pine3', 'deep', .35), rgba('pine')
    horn = rgba('ochre')
    # ales (amunt o avall)
    if flap == 0:
        lw = [(24, 24), (4, 4), (10, 18), (2, 22), (12, 28), (8, 34), (22, 32)]
    else:
        lw = [(24, 24), (2, 26), (8, 30), (4, 38), (14, 36), (14, 42), (24, 34)]
    rw = [(64 - x, y) for x, y in lw]
    for w in (lw, rw):
        d.polygon(w, fill=wing)
        for p in w[1:6:2]:
            d.line([w[0], p], fill=wing2, width=1)
    # cua
    d.line([(32, 36), (40, 42), (48, 43), (54, 40)], fill=body2, width=4)
    d.polygon([(54, 36), (60, 40), (54, 44)], fill=horn)
    # cos i panxa
    d.ellipse([19, 21, 45, 41], fill=body)
    d.ellipse([24, 26, 40, 41], fill=belly)
    for y in (29, 32, 35, 38):
        d.line([(26, y), (38, y)], fill=mix('sun', 'ochre', .5), width=1)
    # potes
    d.rectangle([21, 38, 25, 44], fill=body2); d.rectangle([39, 38, 43, 44], fill=body2)
    for x in (21, 23, 25, 39, 41, 43):
        im.putpixel((x, 45), rgba('white'))
    # coll i cap
    d.rectangle([28, 15, 36, 24], fill=body)
    d.ellipse([22, 4, 42, 20], fill=body)
    d.ellipse([26, 12, 38, 22], fill=mix('pine2', 'sun', .35))   # musell
    d.polygon([(24, 8), (19, 0), (27, 5)], fill=horn); d.polygon([(40, 8), (45, 0), (37, 5)], fill=horn)
    for x in (27, 36):   # ulls
        d.rectangle([x, 9, x + 2, 11], fill=rgba('white'))
        im.putpixel((x + 1, 10), rgba('red') if breath else rgba('ink'))
    im.putpixel((30, 16), rgba('ink')); im.putpixel((34, 16), rgba('ink'))
    if breath:   # boca oberta amb foc
        d.ellipse([28, 17, 36, 23], fill=rgba('ink'))
        d.ellipse([29, 18, 35, 23], fill=rgba('red'))
        d.ellipse([30, 19, 34, 23], fill=rgba('ochre'))
        d.rectangle([31, 21, 33, 23], fill=rgba('sun'))
    else:
        d.line([(29, 19), (35, 19)], fill=rgba('ink'))
    s = Sprite(64, 48)
    s.a = _np.array(im)
    return _outline(s)


def _white(s):
    h = Sprite(s.w, s.h)
    h.a = s.a.copy()
    m = h.a[:, :, 3] > 0
    h.a[m, :3] = (255, 255, 255)
    return h


_dr = [dragon_frame(0, False), dragon_frame(1, False), dragon_frame(0, True)]
save(sheet(_dr + [_white(s) for s in _dr], 3), 'dragon')

# bola de foc (12 × 12, 2 fotogrames) i ràfaga de vent (16 × 16, 2 fotogrames)
_fb = Sprite(24, 12)
for _f in range(2):
    for _y in range(12):
        for _x in range(12):
            r = math.hypot(_x - 5.5, _y - 5.5) + (0.6 if (_x + _y + _f) % 3 == 0 else 0)
            c = 'white' if r < 1.6 else 'sun' if r < 2.8 else 'ochre' if r < 4.0 else 'red' if r < 5.2 else None
            if c: _fb.px(_f * 12 + _x, _y, c)
save(_fb, 'fireball')
_gu = Sprite(32, 16)
for _f in range(2):
    for _k, (_r, _c) in enumerate(((6.5, 'white'), (4.5, 'pool'), (2.5, 'white'))):
        for _a in range(0, 300, 12):
            a = math.radians(_a + _f * 60 + _k * 40)
            _gu.px(_f * 16 + round(7.5 + _r * math.cos(a)), round(7.5 + _r * math.sin(a) * 0.8), _c)
save(_gu, 'gust')
# bastó màgic i cristall del drac (icones 16 × 16)
_st = Sprite(16, 16)
for _i in range(11):
    _st.px(3 + _i, 14 - _i, 'terra3'); _st.px(4 + _i, 14 - _i, 'terra2')
_st.rect(11, 1, 4, 4, 'sea'); _st.rect(12, 2, 2, 2, 'pool'); _st.px(12, 2, 'white')
save(_outline(_st), 'staff')
_cy = Sprite(16, 16)
_cy.pattern(3, 1, ["....WW....", "...WPPP...", "..WPPSSP..", ".WPPSSSSP.", "WPPSSSSSSP", ".PPSSSSSP.",
                   "..PSSSSP..", "..PSSSSP..", "...PSSP...", "...PSSP...", "....PP...."],
            {'W': 'white', 'P': 'pool', 'S': 'sea'})
save(_outline(_cy), 'crystal')
print('drac i màgia ok')


# ------------------------------------------------------------------------------------
# Tráfico y fauna (modelos de coche 5-12, animales de calle y salvajes). Hojas nuevas, no tocan las anteriores.
# ------------------------------------------------------------------------------------
CAR2_MODELS = [
    # nom, carrocería/claro/oscuro, mides i finestres (u: eix llarg, + = morro)
    dict(name='hatch', pal=('pine2', 'pine', 'pine3'), L2=10.5, W2=5.2, ws=(0.6, 3.6), roof=(-4.0, 0.6),
         rear=(-7.4, -4.0)),
    dict(name='taxi', pal=('sun', 'sand', 'ochre2'), L2=12.5, W2=5.5, ws=(1.0, 5.4), roof=(-5.4, 1.0),
         rear=(-8.2, -5.4), sign=(-3.4, -1.0, 1.8)),
    dict(name='suv', pal=('asph2', 'stone3', 'asph3'), L2=13.0, W2=6.0, ws=(2.0, 5.2), roof=(-9.0, 2.0),
         rear=(-10.6, -9.0), rails=True),
    dict(name='pickup', pal=('stone', 'stone2', 'stone3'), L2=13.5, W2=5.8, ws=(4.0, 7.0), roof=(0.4, 4.0),
         bed=(-12.0, -1.6)),
    dict(name='mini', pal=('pool', 'sea', 'sea2'), L2=9.0, W2=5.0, ws=(0.4, 3.0), roof=(-3.6, 0.4),
         rear=(-6.2, -3.6)),
    dict(name='hatch2', pal=('asph3', 'asph2', 'ink'), L2=10.5, W2=5.2, ws=(0.6, 3.6), roof=(-4.0, 0.6),
         rear=(-7.4, -4.0)),
    dict(name='suv2', pal=('white2', 'white', 'white3'), L2=13.0, W2=6.0, ws=(2.0, 5.2), roof=(-9.0, 2.0),
         rear=(-10.6, -9.0), rails=True),
    dict(name='sedan', pal=('stone2', 'stone3', 'stone'), L2=12.5, W2=5.5, ws=(1.0, 5.4), roof=(-5.4, 1.0),
         rear=(-8.2, -5.4)),
]


def car_sprite2(w, h, ang, m):
    import math
    body, light, dark = m['pal']
    L2, W2 = m['L2'], m['W2']
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    cx, cy = (w - 1) / 2, (h - 1) / 2 - 0.5
    s = Sprite(w, h)
    region = {}
    for y in range(h):
        for x in range(w):
            dx, dy = x - cx, y - cy
            u = dx * ca + dy * sa
            v = -dx * sa + dy * ca
            au, av = abs(u), abs(v)
            r = 2.4
            qu, qv = max(au - (L2 - r), 0), max(av - (W2 - r), 0)
            if qu * qu + qv * qv > r * r:
                continue
            c = body
            inside = av < W2 - 0.9
            if 'bed' in m and m['bed'][0] < u < m['bed'][1] and av < W2 - 1.0:
                c = 'asph3' if av < W2 - 1.8 and m['bed'][0] + 0.8 < u < m['bed'][1] - 0.8 else dark
            elif m['ws'][0] < u < m['ws'][1] and inside:
                c = 'sea' if (u - v * 0.6) > (m['ws'][0] + m['ws'][1]) / 2 else 'sea3'
            elif m.get('rear') and m['rear'][0] < u < m['rear'][1] and av < W2 - 1.1:
                c = 'sea3'
            elif m['roof'][0] <= u <= m['roof'][1] and av < W2 - 1.0:
                c = dark if av > W2 - 1.9 else light
                if m.get('rails') and W2 - 2.6 < av < W2 - 2.0:
                    c = 'asph3'
                if m.get('sign') and m['sign'][0] < u < m['sign'][1] and av < m['sign'][2] / 2 + 0.6:
                    c = 'white' if u < (m['sign'][0] + m['sign'][1]) / 2 else 'red'
            elif u > m['ws'][1] and av < 0.8:
                c = light
            if au > L2 - 2.0 and 1.2 < av < W2 - 1.0:
                c = 'white' if u > 0 else 'red'
            if av > W2 - 0.9 and c == body:
                c = dark
            region[(x, y)] = c
    for (x, y) in list(region):
        for dx, dy in ((1, 1), (0, 1), (1, 2), (0, 2)):
            q = (x + dx, y + dy)
            if q not in region and 0 <= q[0] < w and 0 <= q[1] < h:
                s.px(q[0], q[1], (31, 26, 36, 70))
    for (x, y), c in region.items():
        edge = any((x + dx, y + dy) not in region for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        s.px(x, y, 'ink' if edge else c)
    for wu in (-L2 + 4.0, L2 - 4.0):
        for side in (-1, 1):
            for du in (-1.0, 0.0, 1.0):
                u, v = wu + du, side * (W2 + 0.4)
                x = round(cx + u * ca - v * sa)
                y = round(cy + u * sa + v * ca)
                if (x, y) not in region and 0 <= x < w and 0 <= y < h:
                    s.px(x, y, 'asph3')
    for side in (-1, 1):
        u, v = m['ws'][0] + 0.5, side * (W2 + 0.6)
        x = round(cx + u * ca - v * sa)
        y = round(cy + u * sa + v * ca)
        if (x, y) not in region and 0 <= x < w and 0 <= y < h:
            s.px(x, y, 'ink')
    return s


_c2 = [(car_sprite2(32, 16, 0, m), car_sprite2(16, 32, 90, m), car_sprite2(24, 24, 45, m),
        car_sprite2(24, 24, 135, m)) for m in CAR2_MODELS]
save(sheet([c[0] for c in _c2], 1), 'car2_h')
save(sheet([c[1] for c in _c2], 4), 'car2_v')
save(sheet([c[2] for c in _c2] + [c[3] for c in _c2], 4), 'car2_d')
# furgonetes de reparto (kind 'van', mateixa geometria que la blanca) en dos colors més
_v2 = [(car_sprite(32, 16, 0, p, 'van'), car_sprite(16, 32, 90, p, 'van'), car_sprite(24, 24, 45, p, 'van'),
        car_sprite(24, 24, 135, p, 'van')) for p in (('red', 'terra', 'terra2'), ('pine2', 'pine', 'pine3'))]
save(sheet([c[0] for c in _v2], 1), 'van2_h')
save(sheet([c[1] for c in _v2], 4), 'van2_v')
save(sheet([c[2] for c in _v2] + [c[3] for c in _v2], 4), 'van2_d')


# vehicles de servei aparcats davant de la Policia Local i del CAP (colors 15 i 16 de parked_car)
def _svc_overlay(spr, w, h, ang, marks):
    import math
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    cx, cy = (w - 1) / 2, (h - 1) / 2 - 0.5
    for u, v, c in marks:
        x, y = round(cx + u * ca - v * sa), round(cy + u * sa + v * ca)
        if 0 <= x < w and 0 <= y < h and spr.a[y, x, 3]:
            spr.px(x, y, c)
    return spr


def _svc(kind, pal, marks):
    out = []
    for w, h, ang in ((32, 16, 0), (16, 32, 90), (24, 24, 45), (24, 24, 135)):
        out.append(_svc_overlay(car_sprite(w, h, ang, pal, kind), w, h, ang, marks))
    return out


_police_marks = [(u / 2, v / 2, 'blue' if abs(v) > 1 else 'foam') for u in (-1, 0, 1) for v in range(-6, 7)]
_amb_marks = ([(u / 2, 0, 'red') for u in range(-5, 6)] + [(-0.5, v / 2, 'red') for v in range(-5, 6)]
              + [(7 + u / 2, v / 2, 'blue') for u in (0, 1) for v in range(-6, 7)])
# trànsit (2026-10-05): camió de bombers (escala), camió de repartiment (cabina blava) i excavadora (erugues i braç)
_fire_marks = ([(u / 2, v, 'white2') for u in range(-24, 11) for v in (-2.5, 2.5)]
               + [(u, v / 2, 'stone') for u in range(-12, 6, 2) for v in range(-4, 5)]
               + [(7, v / 2, 'blue') for v in range(-6, 7)])
_truck_marks = ([(u / 2, v / 2, 'blue') for u in range(21, 27) for v in range(-10, 11)]
                + [(u / 2, v, 'red') for u in range(-26, 12) for v in (-5.2, 5.2)])
_dig_marks = ([(u / 2, v, 'asph3') for u in range(-26, 26) for v in (-5.5, 5.5)]
              + [(u / 2, 0, 'ochre3') for u in range(0, 26)] + [(12.5, v / 2, 'stone3') for v in range(-3, 4)]
              + [(-6 + u / 2, v / 2, 'asph2') for u in range(0, 8) for v in range(-6, 7)])
_svc_cars = [_svc('car', ('white', 'white2', 'blue'), _police_marks), _svc('van', ('sun', 'white', 'pine2'), _amb_marks),
             _svc('van', ('red', 'terra', 'terra2'), _fire_marks), _svc('van', ('white', 'white2', 'stone3'), _truck_marks),
             _svc('van', ('sun', 'sun', 'ochre3'), _dig_marks)]
save(sheet([c[0] for c in _svc_cars], 1), 'svc_h')
save(sheet([c[1] for c in _svc_cars], 4), 'svc_v')
save(sheet([c[2] for c in _svc_cars] + [c[3] for c in _svc_cars], 4), 'svc_d')


# --- casc superposat (src/entities/player.lua): per a les aparences que no són l'avatar del perfil, que no porten
# el casc a la fulla. 16 × 24 com el personatge; columnes: avall, amunt, esquerra, dreta; files: bici/moto, hípica
def _helmet_overlay():
    from chars import Px, hat
    out = []
    for kind in ('helmet', 'helmet_ride'):
        fr = []
        for d in ('down', 'up', 'left'):
            px = Px(); hat(px, d, {}, kind); fr.append(px.sprite())
        fr.append(fr[2].flip_h())
        out += fr
    return out


save(sheet(_helmet_overlay(), 4), 'helmet_overlay')


# --- puzles de les masmorres (src/systems/puzzles.lua): 16 × 16 → bloc, placa (amunt, avall), runes I-IV
# (apagades, enceses), braser (apagat, foc 1, foc 2) i paret secreta amb l'estrella
def _puzzle_frames():
    fr = []
    b = Sprite(16, 16)                                    # bloc de pedra que s'empeny
    b.rect(1, 2, 14, 13, 'stone2'); b.rect(1, 2, 14, 2, 'stone'); b.rect(1, 13, 14, 2, 'stone3')
    b.rect(3, 5, 4, 3, 'stone'); b.rect(9, 8, 4, 3, 'stone'); b.hline(1, 14, 9, 'stone3'); b.vline(8, 2, 8, 'stone3')
    for x in (1, 14): b.vline(x, 2, 14, 'ink')
    b.hline(1, 14, 1, 'ink'); b.hline(1, 14, 15, 'ink')
    fr.append(b)
    for down in (False, True):                            # placa de pressió
        p = Sprite(16, 16)
        p.rect(2, 3, 12, 11, 'stone3'); p.rect(3, 4 + down, 10, 9 - down, 'ochre2' if down else 'ochre')
        p.rect(4, 5 + down, 8, 2, 'sand' if not down else 'ochre')
        if down: p.rect(5, 8, 6, 3, 'ochre3')
        fr.append(p)
    glyphs = {1: [(7, 4, 1, 8)], 2: [(5, 4, 1, 8), (9, 4, 1, 8)], 3: [(4, 4, 1, 8), (7, 4, 1, 8), (10, 4, 1, 8)],
              4: [(4, 4, 1, 8), (6, 4, 1, 4), (7, 8, 1, 2), (8, 10, 1, 2), (9, 8, 1, 2), (10, 4, 1, 4)]}
    for lit in (False, True):                             # runes romanes
        for n in (1, 2, 3, 4):
            r = Sprite(16, 16)
            r.rect(2, 1, 12, 14, 'stone2'); r.rect(3, 2, 10, 12, 'stone' if not lit else 'sea')
            r.hline(2, 13, 1, 'ink'); r.hline(2, 13, 14, 'ink'); r.vline(2, 1, 14, 'ink'); r.vline(13, 1, 14, 'ink')
            for gx, gy, gw, gh in glyphs[n]:
                r.rect(gx, gy, gw, gh, 'foam' if lit else 'stone3')
            r.hline(4, 11, 3, 'foam' if lit else 'stone3'); r.hline(4, 11, 12, 'foam' if lit else 'stone3')
            fr.append(r)
    for f in range(3):                                    # braser
        z = Sprite(16, 16)
        z.rect(4, 12, 8, 3, 'stone3'); z.rect(6, 9, 4, 3, 'stone2'); z.rect(3, 7, 10, 3, 'asph3'); z.hline(3, 12, 7, 'stone2')
        if f:
            z.rect(5, 2 + f, 6, 5 - f, 'red'); z.rect(6, 1 + f, 4, 4, 'ochre'); z.rect(7, 3 + f, 2, 2, 'white'); z.px(7 + f % 2, f, 'ochre')
        fr.append(z)
    w = Sprite(16, 16)                                    # paret secreta (esquerda i estrella)
    w.rect(0, 0, 16, 16, 'stone2')
    for y in (4, 9, 14): w.hline(0, 15, y, 'stone3')
    for y, xs in ((0, (5, 12)), (5, (2, 9)), (10, (6, 13))):
        for x in xs: w.vline(x, y, y + 3, 'stone3')
    for x, y in ((7, 3), (8, 4), (7, 5), (8, 6), (9, 7), (8, 8)): w.px(x, y, 'ink')
    for x, y in ((11, 9), (10, 10), (11, 11), (12, 10), (10, 12), (12, 12), (11, 12)): w.px(x, y, 'sun')
    fr.append(w)
    return fr


save(sheet(_puzzle_frames(), 8), 'puzzle')


# --- encàrrecs dels veïns (src/systems/errands.lua, town.lua): 16 × 16 → barra de pa, bossa de la compra,
# regadora, tovallola (vista de dalt, a sota del cos), gotes d'aigua i espurna de tall de cabell nou
def _errand_frames():
    fr = []
    b = Sprite(16, 16)                                    # barra de pa (en diagonal, a la mà)
    for i in range(10):
        b.rect(3 + i, 12 - i, 2, 2, 'ochre')
        b.px(3 + i, 13 - i, 'ochre3')
    for i in (2, 5, 8): b.px(4 + i, 11 - i, 'sand')
    b.px(12, 2, 'ochre2'); b.px(3, 13, 'ochre2')
    fr.append(b)
    g = Sprite(16, 16)                                    # bossa de la compra amb verdura
    g.rect(4, 7, 9, 8, 'white2'); g.hline(4, 12, 14, 'stone3'); g.vline(4, 7, 14, 'stone3'); g.vline(12, 7, 14, 'stone3')
    g.rect(5, 9, 7, 2, 'blue')
    g.vline(6, 3, 6, 'pine'); g.vline(7, 4, 6, 'pine2'); g.rect(9, 4, 2, 3, 'red'); g.px(10, 3, 'pine')
    g.hline(5, 6, 6, 'stone3'); g.hline(10, 11, 6, 'stone3')
    fr.append(g)
    c = Sprite(16, 16)                                    # regadora
    c.rect(3, 7, 7, 6, 'pine2'); c.hline(3, 9, 7, 'pine'); c.hline(3, 9, 12, 'pine3')
    c.vline(2, 8, 10, 'pine3'); c.px(1, 9, 'pine3')
    for i in range(4): c.px(10 + i, 9 - i, 'pine2')
    c.rect(13, 4, 2, 2, 'pine')
    c.hline(4, 8, 5, 'stone3'); c.px(4, 6, 'stone3'); c.px(8, 6, 'stone3')
    fr.append(c)
    t = Sprite(16, 16)                                    # tovallola de ratlles (vista de dalt)
    t.rect(2, 0, 12, 16, 'white')
    for y in range(0, 16, 4): t.rect(2, y, 12, 2, 'red')
    t.vline(2, 0, 15, 'white3'); t.vline(13, 0, 15, 'white3')
    fr.append(t)
    d = Sprite(16, 16)                                    # gotes d'aigua
    for x, y in ((4, 4), (8, 8), (12, 5), (6, 11), (11, 12)):
        d.px(x, y, 'foam'); d.px(x, y + 1, 'sea')
    fr.append(d)
    k = Sprite(16, 16)                                    # espurna (tall de cabell nou)
    for x, y in ((7, 3), (7, 4), (5, 6), (6, 6), (8, 6), (9, 6), (7, 8), (7, 9), (7, 6)):
        k.px(x, y, 'sun')
    k.px(12, 10, 'white'); k.px(3, 11, 'white')
    fr.append(k)
    return fr


save(sheet(_errand_frames(), 6), 'errands')


# --- animals de granja (src/systems/farm.lua): fulles de 4 fotogrames mirant a l'esquerra (quiet, camina 1,
# camina 2, menja amb el cap baix); el joc les gira per anar a la dreta. 24 × 20 (ruc, cavall, porc, ovella) i
# 16 × 16 (gallina). Silueta amb contorn de tinta com la resta de personatges.
def _ink_outline(sp):
    a = sp.a
    op = a[:, :, 3] > 0
    out = Sprite(sp.w, sp.h); out.a = a.copy()
    for y in range(sp.h):
        for x in range(sp.w):
            if not op[y, x] and any(0 <= x + dx < sp.w and 0 <= y + dy < sp.h and op[y + dy, x + dx]
                                    for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                out.px(x, y, 'ink')
    return out


def _quad(kind, frame):
    s = Sprite(24, 20)
    spec = {'ruc': ('stone2', 'stone3', 'white2'), 'cavall': ('terra2', 'terra3', 'ochre3'),
            'porc': ('blush', 'skin2', 'blush'), 'ovella': ('white', 'white3', 'asph2')}[kind]
    c, dark, extra = spec
    eat = frame == 3
    by = 7 if kind in ('ruc', 'cavall') else 9
    bw = 13 if kind in ('ruc', 'cavall') else 12
    bx = 8
    bh = 6 if kind in ('ruc', 'cavall') else 6
    # potes (davant a l'esquerra): els fotogrames 1 i 2 les mouen alternades
    legs = [bx + 1, bx + 4, bx + bw - 5, bx + bw - 2]
    off = {0: (0, 0), 1: (-1, 1), 2: (1, -1), 3: (0, 0)}[frame]
    lc = 'asph2' if kind == 'ovella' else dark
    leg_h = 5 if kind in ('ruc', 'cavall') else 3
    for i, lx in enumerate(legs):
        dxl = off[0] if i % 2 == 0 else off[1]
        s.rect(lx + dxl, by + bh, 2, leg_h, lc)
        if kind == 'cavall': s.px(lx + dxl, by + bh + leg_h - 1, 'ink')
    # cos (cantonades arrodonides)
    s.rect(bx, by, bw, bh, c)
    for x, y in ((bx, by), (bx + bw - 1, by), (bx, by + bh - 1), (bx + bw - 1, by + bh - 1)):
        s.a[y, x] = 0
    s.hline(bx + 1, bx + bw - 2, by + bh - 1, dark)
    if kind == 'ovella':   # llana arrissada
        for x in range(bx, bx + bw, 2): s.px(x, by - 1, c); s.px(x + 1, by + bh, 'white2')
        for x, y in ((bx + 3, by + 2), (bx + 7, by + 3), (bx + 10, by + 1)): s.px(x, y, 'white2')
    if kind == 'porc':
        s.px(bx + bw, by + 1, dark); s.px(bx + bw + 1, by, dark)          # cueta enrotllada
    else:
        s.vline(bx + bw, by + 1, by + 5, dark if kind != 'ovella' else 'white2')   # cua
        if kind == 'cavall': s.vline(bx + bw + 1, by + 2, by + 7, 'terra3')
    # coll i cap
    hy = by + (4 if eat else -3) if kind in ('ruc', 'cavall') else by + (3 if eat else 0)
    if kind in ('ruc', 'cavall'):
        s.rect(bx - 1, min(hy + 2, by), 3, by - min(hy + 2, by) + 2, c)   # coll
        s.rect(bx - 5, hy, 6, 4, c); s.rect(bx - 6, hy + 1, 2, 3, extra)    # cap i morro
        s.px(bx - 3, hy + 1, 'ink')                                         # ull
        if kind == 'ruc':
            s.rect(bx - 1, hy - 4, 1, 4, c); s.rect(bx + 1, hy - 4, 1, 4, c); s.px(bx - 1, hy - 4, dark); s.px(bx + 1, hy - 4, dark)
        else:
            s.px(bx - 1, hy - 1, c); s.px(bx, hy - 1, c)
            s.vline(bx + 1, hy, by + 1, 'terra3'); s.vline(bx + 2, hy + 1, by + 1, 'terra3')   # crinera
    elif kind == 'porc':
        s.rect(bx - 5, hy, 6, 5, c); s.rect(bx - 7, hy + 2, 2, 2, 'skin2'); s.px(bx - 7, hy + 2, 'terra3')
        s.px(bx - 3, hy + 1, 'ink'); s.rect(bx - 2, hy - 1, 2, 2, dark)
    else:   # ovella: cap negre
        s.rect(bx - 4, hy, 5, 4, 'asph2'); s.px(bx - 3, hy + 1, 'white'); s.rect(bx - 1, hy, 2, 1, 'asph3')
    return _ink_outline(s)


def _hen(frame):
    s = Sprite(16, 16)
    eat = frame == 3
    off = {0: (0, 0), 1: (-1, 1), 2: (1, -1), 3: (0, 0)}[frame]
    s.vline(6 + off[0], 12, 14, 'ochre'); s.vline(9 + off[1], 12, 14, 'ochre')     # potes
    s.rect(5, 7, 7, 5, 'white'); s.rect(6, 6, 5, 1, 'white'); s.hline(6, 10, 11, 'white2')
    s.rect(11, 5, 2, 4, 'white'); s.px(12, 4, 'white')                             # cua
    s.rect(9, 8, 2, 2, 'white2')                                                    # ala
    hy = 7 if eat else 3
    s.rect(3, hy, 3, 4, 'white'); s.px(3, hy + 1, 'ink'); s.px(2, hy + 2, 'ochre'); s.px(1, hy + 2, 'ochre')
    s.px(4, hy - 1, 'red'); s.px(3, hy - 1, 'red'); s.px(3, hy + 3, 'red')         # cresta i barba
    return _ink_outline(s)


for _k in ('ruc', 'cavall', 'porc', 'ovella'):
    save(sheet([_quad(_k, f) for f in range(4)], 4), f'farm_{_k}')
save(sheet([_hen(f) for f in range(4)], 4), 'farm_gallina')


# --- velers al mar (src/systems/sailboats.lua): 24 × 24, 8 rumbs (0 = dreta, en sentit horari) × 2 colors de vela
def sail_sprite(ang, sail, stripe):
    import math
    ca, sa = math.cos(math.radians(ang)), math.sin(math.radians(ang))
    s = Sprite(24, 24)
    cx, cy = 11.5, 11.5
    hull = {}
    for y in range(24):
        for x in range(24):
            dx, dy = x - cx, y - cy
            u, v = dx * ca + dy * sa, -dx * sa + dy * ca
            w = 3.6 * (1 - max(0, u - 2) / 8.5) if u > 2 else 3.6 * (1 - max(0, -u - 6) / 5)
            if -9 < u < 10.5 and abs(v) < max(0.6, w):
                hull[(x, y)] = 'sand2' if abs(v) < w - 1.2 else 'white'
    for (x, y), c in hull.items():                       # estela i ombra
        for ddx, ddy in ((1, 1), (0, 1)):
            q = (x + ddx, y + ddy)
            if q not in hull: s.px(q[0], q[1], (31, 26, 36, 60))
    for (x, y), c in hull.items():
        edge = any((x + a, y + b) not in hull for a, b in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        s.px(x, y, 'ink' if edge else c)
    # coberta de fusta i vela (triangle cap a sotavent)
    for k in range(-5, 4):
        x, y = round(cx + k * ca), round(cy + k * sa)
        if (x, y) in hull: s.px(x, y, 'ochre2')
    for y in range(24):                                   # vela inflada cap a sotavent, del pal a la popa
        for x in range(24):
            dx, dy = x - cx, y - cy
            u, v = dx * ca + dy * sa, -dx * sa + dy * ca
            if -7.5 <= u <= 1.5:
                bulge = 0.8 + 6.0 * math.sin(math.pi * (u + 7.5) / 9.0)
                if 0 <= v <= bulge:
                    s.px(x, y, 'ink' if bulge - v < 0.7 else stripe if bulge - v < 1.7 else (sail if v > 0.8 else 'stone2'))
    for k in range(-7, 2):                                # botavara
        x, y = round(cx + k * ca), round(cy + k * sa)
        s.px(x, y, 'stone3')
    x, y = round(cx + 1.5 * ca), round(cy + 1.5 * sa)
    s.px(x, y, 'asph3')                                   # pal
    return s


_sails = []
for _sail, _stripe in (('white', 'red'), ('white2', 'blue')):
    for _k in range(8):
        _sails.append(sail_sprite(_k * 45, _sail, _stripe))
save(sheet(_sails, 8), 'sailboat')


# --- animals 16 × 16 (mirant a l'esquerra): 6 fotogrames = pas1, pas2, repòs, especial, aleteig1, aleteig2
def critter(rows, cm):
    from chars import Px
    px = Px()
    top = 15 - len(rows)
    for j, row in enumerate(rows):
        for i, ch in enumerate(row.ljust(16, '.')[:16]):
            if ch in cm:
                px.put(i, top + j, cm[ch])
    out = Sprite(16, 16)
    out.a = px.sprite().a[:16].copy()
    return out


DOG_W1 = ["..d.............",
          ".dDD.........D..",
          "nDeDDDDDDDDDDD..",
          ".LDDDDDDDDDDD...",
          "..LDDDDDDDDDD...",
          "...l.l....l.l...",
          "...l.l....l.l..."]
DOG_W2 = DOG_W1[:5] + ["....l.l..l.l.....", "....l.l..l.l....."]
DOG_SIT = ["................",
           "..d.............",
           ".dDD............",
           "nDeD............",
           ".DDDD...........",
           "..DDDD..........",
           "..DDDDD.........",
           "..DDDDDDD.......",
           "..LDDDDDDDD.....",
           "..lllDDDDDDD....",
           "...lllllllll...."]
DOG_BARK = ["..d.............",
            ".dDD.........D..",
            "nDeDDDDDDDDDDD..",
            "rLDDDDDDDDDDD...",
            "..LDDDDDDDDDD...",
            "...l.l....l.l...",
            "...l.l....l.l..."]
CAT_W1 = ["..............c.",
          ".c.c..........c.",
          ".CCC.........cC.",
          "nCeCCCCCCCCCCC..",
          ".LCCCCCCCCCCC...",
          "..LCCCCCCCCC....",
          "...l.l....l.l...",
          "...l.l....l.l..."]
CAT_W2 = CAT_W1[:6] + ["....l.l..l.l....", "....l.l..l.l...."]
CAT_SIT = ["................",
           ".c.c............",
           ".CCC............",
           "nCeC............",
           ".CCC.....c......",
           "..CCC...cC......",
           "..CCCCCCCC......",
           "..CCCCCCCC......",
           "..lCCCCCCl......"]
CAT_SLEEP = ["................",
             "................",
             "................",
             "....CCCCCCC.....",
             "..cCCCCCCCCC....",
             ".CCeCCCCCCCCC...",
             "nCCCCCCCCCCCcc..",
             ".LCCCCCCCCCCcc.."]
BIRD_STAND = [".BB.....",
              "kBeB....",
              ".BBBB.BB",
              "..BWWBB.",
              "..bWWbb.",
              "...bbb..",
              "...l.l.."]
BIRD_PECK = ["........",
             "........",
             "...BBBB.",
             "BBBWWBBB",
             "kBebWbb.",
             "..bbbb..",
             "..l.l..."]
BIRD_FLY1 = ["..W...W.",
             "..WW.WW.",
             "kBeBBBB.",
             ".bbbbbbB",
             "..bbbb.."]
BIRD_FLY2 = ["........",
             "kBeBBBBB",
             ".bbbbbbB",
             "..WWWW..",
             "..W..W.."]


def _cm(body, dark, belly, ear=None, extra=None):
    cm = {'D': body, 'C': body, 'B': body, 'd': dark, 'c': dark, 'W': dark, 'L': belly, 'b': belly,
          'n': 'ink', 'e': 'ink', 'l': 'ink', 'r': 'red', 'k': 'sun'}
    if extra:
        cm.update(extra)
    return cm


def _animal_sheet(name, frames, cm):
    save(sheet([critter(f, cm) for f in frames], 6), name)


for _n, _c in (('brown', ('terra3', 'ink', 'sand')), ('golden', ('sand2', 'ochre2', 'white2')),
               ('black', ('asph3', 'ink', 'stone')), ('white', ('white2', 'stone2', 'white'))):
    _animal_sheet('animal_dog_' + _n, [DOG_W1, DOG_W2, DOG_SIT, DOG_BARK, DOG_W1, DOG_W2], _cm(*_c))
for _n, _c in (('orange', ('ochre3', 'terra3', 'white2')), ('grey', ('stone2', 'stone', 'white2')),
               ('black', ('asph3', 'ink', 'asph2')), ('white', ('white2', 'stone2', 'white'))):
    _animal_sheet('animal_cat_' + _n, [CAT_W1, CAT_W2, CAT_SIT, CAT_SLEEP, CAT_W1, CAT_W2], _cm(*_c))
for _n, _c in (('sparrow', ('terra3', 'asph3', 'sand')), ('pigeon', ('stone', 'asph2', 'stone3')),
               ('gull', ('white', 'stone', 'white2'))):
    _animal_sheet('animal_bird_' + _n, [BIRD_STAND, BIRD_PECK, BIRD_STAND, BIRD_PECK, BIRD_FLY1, BIRD_FLY2],
                  _cm(*_c))

# --- enemics salvatges (mateix format que enemy_boar: pas1, pas2, ferit1, ferit2)
FOX_1 = ["..F.F...........",
         ".FFFFF..........",
         "nFeFFFFFFF...ff.",
         ".WWFFFFFFFFFFFFt",
         "..WFFFFFFFFFFFt.",
         "...fFFFFFFFFf...",
         "...l.l....l.l...",
         "...l.l....l.l..."]
FOX_2 = FOX_1[:6] + ["....l.l..l.l....", "....l.l..l.l...."]
WOLF_1 = [".G.G............",
          ".GGGGG..........",
          "nGeGGGGGGG...gg.",
          "WWGGGGGGGGGGGGg.",
          ".WGGGGGGGGGGGGg.",
          "..gGGGGGGGGGGg..",
          "..GGGGGGGGGGGg..",
          "..l.l....l.l....",
          "..l.l....l.l...."]
WOLF_2 = WOLF_1[:7] + ["...l.l..l.l.....", "...l.l..l.l....."]
SNAKE_1 = ["..HH............",
           ".HyHH...........",
           ".rHHH...........",
           "..HHH..HHH......",
           "..HhHHHHhHH.....",
           "...HHHHH..HHH...",
           "..........HHHHt."]
SNAKE_2 = ["................",
           "..HH............",
           ".HyHH...........",
           ".rHHH....HH.....",
           "..HHHH.HHhHH....",
           "...hHHHHH..HH...",
           "..........HHHHt."]
FOX_CM = {'F': 'terra', 'f': 'terra2', 'W': 'white', 't': 'white', 'n': 'ink', 'e': 'ink', 'l': 'ink'}
WOLF_CM = {'G': 'stone', 'g': 'asph2', 'W': 'stone3', 'n': 'ink', 'e': 'red', 'l': 'ink'}
SNAKE_CM = {'H': 'pine3', 'h': 'sun', 'y': 'sun', 'r': 'red', 't': 'pine2'}
for _name, _frames, _cm2 in (('enemy_fox', (FOX_1, FOX_2), FOX_CM), ('enemy_wolf', (WOLF_1, WOLF_2), WOLF_CM),
                              ('enemy_snake', (SNAKE_1, SNAKE_2), SNAKE_CM)):
    _sprs = [creature(fr, _cm2) for fr in _frames]
    _hurt = []
    for _s in _sprs:
        _hh = Sprite(16, 16)
        _hh.a = _s.a.copy()
        _hh.a[_hh.a[:, :, 3] > 0, :3] = (255, 255, 255)
        _hurt.append(_hh)
    save(sheet(_sprs + _hurt, 4), _name)
print('cotxes, animals i salvatges ok')
