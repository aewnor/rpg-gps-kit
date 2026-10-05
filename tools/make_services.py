#!/usr/bin/env python3
"""Serveis del poble a partir de l'OSM del lloc → data/services.json (src/systems/services.lua).

  python3 tools/make_services.py        (després de tools/new_location.py; abans de tools/import_osm.py)

Per a cada edifici o punt amb aquestes etiquetes, un personatge davant de l'edifici real (camp "osm"), amb
l'interior propi que toca (procgen.poi o P.store):
  amenity=townhall → ajuntament · police → policia · post_office → correus · doctors|clinic|hospital → metge
  amenity=school (el més gran) → escola · library → biblioteca · shop=supermarket|convenience → súpers (fins a 4)
  shop=doityourself|hardware → bricolatge · leisure=sports_centre → poliesportiu · leisure=pitch (futbol) → camp
  railway=station → estació · amenity=restaurant|cafe|bar → restaurants (fins a 6)
Els noms dels personatges són genèrics (cap persona real). Els estocs de les botigues, de STOCK.
"""
import json
import os

from osmlib import OSM

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))

STOCK = {
    'super': ['poma', 'pa', 'aigua', 'botiqui', 'mandarina', 'ametlles', 'suc_raim', 'arros', 'pasta', 'conserva', 'llet',
              'formatge', 'tomaquet'],
    'diy': ['llanterna', 'casc_miner', 'armilla_explorador', 'destral_bosc', 'martell_pedrera', 'mapa_muntanya'],
}
RULES = [
    # (id base, kind, label per defecte, nom del personatge, sprite, funció de tags, quants)
    ('ajuntament', 'townhall', 'Ajuntament', "L'alcaldessa", 'npc_lady', lambda t: t.get('amenity') == 'townhall', 1),
    ('policia', 'police', 'Policia Local', 'Agent de policia', 'npc_police', lambda t: t.get('amenity') == 'police', 1),
    ('correus', 'post', 'Correus', 'El carter', 'npc_postie', lambda t: t.get('amenity') == 'post_office', 1),
    ('metge', 'doctor', 'Centre de salut', 'La metgessa', 'npc_doctor',
     lambda t: t.get('amenity') in ('doctors', 'clinic', 'hospital') or t.get('healthcare') in ('centre', 'doctor'), 1),
    ('escola', 'school', 'Escola', 'La mestra', 'npc_teacher', lambda t: t.get('amenity') == 'school', 1),
    ('biblioteca', 'library', 'Biblioteca', 'La bibliotecària', 'npc_librarian', lambda t: t.get('amenity') == 'library', 1),
    ('super', 'super', 'Supermercat', 'La caixera', 'npc_clerk',
     lambda t: t.get('shop') in ('supermarket', 'convenience'), 4),
    ('bricolatge', 'shop', 'Botiga de bricolatge', 'El venedor', 'npc_clerk',
     lambda t: t.get('shop') in ('doityourself', 'hardware'), 1),
    ('poliesportiu', 'sports', 'Poliesportiu', 'La monitora', 'npc_coach', lambda t: t.get('leisure') == 'sports_centre', 1),
    ('camp_futbol', 'sports', 'Camp de futbol', "L'àrbitre", 'npc_police',
     lambda t: t.get('leisure') == 'pitch' and t.get('sport') == 'soccer', 1),
    ('estacio', 'station', 'Estació', "El cap d'estació", 'npc_police', lambda t: t.get('railway') == 'station', 2),
    ('rest', 'restaurant', 'Restaurant', 'El cambrer', 'npc_sailor',
     lambda t: t.get('amenity') in ('restaurant', 'cafe', 'bar'), 6),
]


def area_of(osm, wid):
    pts = [osm.nodes[r] for r in osm.ways[wid][1] if r in osm.nodes]
    if len(pts) < 3:
        return 0.0
    a = 0.0
    for (x1, y1), (x2, y2) in zip(pts, pts[1:] + pts[:1]):
        a += x1 * y2 - x2 * y1
    return abs(a)


def main():
    osm = OSM(os.path.join(ROOT, 'cartography/municipio.osm.gz'))
    items = [('way/' + wid, tags, area_of(osm, wid)) for wid, (tags, refs) in osm.ways.items()]
    items += [('node/' + nid, tags, 0.0) for nid, tags in osm.node_tags.items()]
    out, used = [], set()
    for base, kind, label, who, sprite, match, n in RULES:
        found = sorted((it for it in items if match(it[1]) and it[0] not in used), key=lambda it: -it[2])[:n]
        for k, (ref, tags, _) in enumerate(found):
            used.add(ref)
            sid = base if n == 1 or k == 0 else f'{base}_{k + 1}'
            name = tags.get('name:ca') or tags.get('name') or label
            sv = {'id': sid, 'kind': kind, 'label': name, 'name': who, 'sprite': sprite, 'osm': ref}
            if base == 'bricolatge':
                sv['poi'], sv['stock'] = 'diy', list(STOCK['diy'])
            elif kind in STOCK:
                sv['stock'] = list(STOCK[kind])
            if base == 'camp_futbol':
                sv['poi'] = 'football'
            if kind == 'restaurant':
                sv['name'] = 'El cambrer · ' + name if k % 2 == 0 else 'La cambrera · ' + name
            out.append(sv)
    doc = {'_doc': 'Serveis del poble generats de l\'OSM per tools/make_services.py (es poden editar a mà: noms, estocs, '
                   'offset [dx, dy] o «runtime» + «pos»). kind: townhall | police | post | doctor | school | library | '
                   'shop | super | sports | station | restaurant; poi: interior (diy, football…) si no és el del kind.', 'services': out}
    with open(os.path.join(ROOT, 'data/services.json'), 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    print(len(out), 'serveis:', ', '.join(s['id'] for s in out))


if __name__ == '__main__':
    main()
