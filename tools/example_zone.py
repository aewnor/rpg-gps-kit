#!/usr/bin/env python3
"""Crea la zona de ejemplo «Escola Salvador Espriu» (formato del editor). Solo si no existe."""
import json
import os
import sys

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
PATH = os.path.join(ROOT, 'maps/source/zones/escola_espriu.json')


def roof_mask(cells, x, y):
    m = 0
    for bit, (dx, dy) in ((1, (0, -1)), (2, (1, 0)), (4, (0, 1)), (8, (-1, 0))):
        if (x + dx, y + dy) in cells:
            m |= bit
    return m


def building(L, w, x0, y0, bw, bh, roof='terra', wall='white', door_x=None):
    """Tejado (bh-1 filas) + fachada con ventanas y una puerta."""
    cells = {(x, y) for x in range(x0, x0 + bw) for y in range(y0, y0 + bh - 1)}
    for (x, y) in cells:
        m = roof_mask(cells, x, y) | (4 if y == y0 + bh - 2 else 0)
        L['structures'][y * w + x] = f'r_{roof}_{m}'
    fy = y0 + bh - 1
    for x in range(x0, x0 + bw):
        pos = 's' if bw == 1 else 'l' if x == x0 else 'r' if x == x0 + bw - 1 else 'm'
        kind = 'door' if x == door_x else 'win'
        L['structures'][fy * w + x] = f'f_{wall}_{pos}_{kind}'
    return fy


def area(w, h, fill):
    return {'ground': [fill] * (w * h), 'detail': [''] * (w * h), 'structures': [''] * (w * h),
            'overhead': [''] * (w * h), 'height': [0] * (w * h)}


def main():
    if os.path.exists(PATH) and '--force' not in sys.argv:
        print('ya existe', PATH)
        return
    # parcela real de la escuela (OSM way 610180879 + ortofoto): sin calles ni aparcamiento dentro
    W, H = 19, 21
    z = {'id': 'escola_espriu', 'name': 'Escola Salvador Espriu', 'scene': 'overworld', 'x': 564, 'y': 847,
         'w': W, 'h': H}
    z.update(area(W, H, 'g_urban_0'))
    put = lambda layer, x, y, t: z[layer].__setitem__(y * W + x, t)
    # tanca perimetral amb entrada al sud (cap a l'aparcament)
    for x in range(W):
        for y in (0, H - 1):
            if not (y == H - 1 and 8 <= x <= 10):
                put('structures', x, y, 'o_fence')
    for y in range(H):
        put('structures', 0, y, 'o_fence'); put('structures', W - 1, y, 'o_fence')
    # pati al nord: pista de bàsquet
    for y in range(2, 9):
        for x in range(2, 11):
            put('ground', x, y, 'g_court_0')
    for x in range(2, 11):
        put('ground', x, 5, 'g_court_line_h')
    put('structures', 6, 2, 'o_basket'); put('structures', 6, 8, 'o_basket')
    # terrassa elevada (desnivell) amb escales i bancs
    for y in range(2, 9):
        for x in range(12, 17):
            z['height'][y * W + x] = 1
            put('ground', x, y, 'g_park_0')
    put('ground', 14, 8, 'st_stone_v')
    put('structures', 13, 3, 'o_bench'); put('structures', 15, 3, 'o_bench')
    put('structures', 14, 5, 'o_lamp')
    # edifici principal al sud, façana cap a l'entrada
    fy = building(z, W, 2, 11, 15, 7, roof='flat', wall='white', door_x=9)
    for x in range(2, 17):
        put('ground', x, fy + 1, 'd_paving_15')
    for y in range(fy + 1, H):
        for x in (8, 9, 10):
            put('ground', x, y, 'd_paving_15')
    for (x, y) in ((3, 19), (15, 19), (1, 9)):
        put('structures', x, y, 'tree_pine0_bot'); put('overhead', x, y - 1, 'tree_pine0_top')
    z['objects'] = [
        {'type': 'door', 'x': 9, 'y': fy, 'interior': 'escola_espriu_1_int'},
        {'type': 'sign', 'x': 12, 'y': 19, 'say': ['Escola Salvador Espriu', "Horari: de 9 a 17 h (inventat)."]},
        {'type': 'npc', 'x': 4, 'y': 9, 'sprite': 'npc_girl', 'name': 'La Núria', 'wander': 2,
         'say': ["Hola! Saps que la terrassa té escales?", "Només hi pots pujar per allà."]},
    ]
    IW, IH = 20, 14
    it = area(IW, IH, 'i_floor_wood_0')
    ip = lambda layer, x, y, t: it[layer].__setitem__(y * IW + x, t)
    for x in range(IW):
        ip('structures', x, 0, 'i_wall_top')
        ip('structures', x, 1, 'i_wall_window' if x in (2, 5, 14, 17) else 'i_wall')
    ip('structures', 9, 1, 'i_board_l'); ip('structures', 10, 1, 'i_board_r'); ip('structures', 12, 1, 'i_clock')
    for y in range(IH):
        ip('structures', 0, y, 'i_wall_top'); ip('structures', IW - 1, y, 'i_wall_top')
    for x in range(IW):
        if x != 9:
            ip('structures', x, IH - 1, 'i_wall_top')
    ip('ground', 9, IH - 1, 'i_exit')
    for y in (6, 8, 10):
        for x in (3, 4, 7, 8, 11, 12, 15, 16):
            ip('structures', x, y, 'i_desk'); ip('ground', x, y + 1, 'i_floor_wood_1')
            ip('structures', x, y + 1, 'i_chair')
    ip('structures', 9, 3, 'i_table'); ip('structures', 10, 3, 'i_table')
    ip('structures', 1, 3, 'i_shelf'); ip('structures', 1, 4, 'i_shelf'); ip('structures', 18, 3, 'i_plant')
    for x in range(5, 15):
        ip('ground', x, 12, 'i_rug_c')
    it.update({'name': 'Aula', 'w': IW, 'h': IH, 'spawn': [9, 12], 'objects': [
        {'type': 'exit', 'x': 9, 'y': IH - 1},
        {'type': 'npc', 'x': 11, 'y': 4, 'sprite': 'npc_postie', 'name': 'La mestra Anna',
         'say': ["Benvingut a l'escola!", "Avui estudiem el mapa de Roda de Berà.", "Has trobat ja tots els llocs del quadern?"]},
    ]})
    z['interiors'] = {'escola_espriu_1_int': it}
    with open(PATH, 'w') as f:
        json.dump(z, f, ensure_ascii=False)
    print('zona de exemple creada', PATH)


if __name__ == '__main__':
    main()
