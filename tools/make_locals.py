#!/usr/bin/env python3
"""Locals i comerços reals del poble → data/locals.json. Font: un directori de comerços (cartography/comerc-rodadebera.json,
format del de l'Ajuntament de Roda de Berà) si n'hi ha; si no, les botigues i locals amb nom de l'OSM del lloc
(cartography/municipio.osm.gz). Surt: tipus de local, casella del mapa i text i colors del rètol.

El rètol de cada local el dibuixa tools/make_sprites.py (sign_local_<id>) i el penja decorate_map.locals()
damunt de la porta de l'edifici real més proper. Els que ja tenen rètol propi (súpers amb personatge de
servei, gasolineres, Leroy Merlin) i els que no tenen coordenades no hi entren."""
import json
import os
import re
import unicodedata

from osmlib import MAP_TILES, to_tile

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
SRC = os.path.join(ROOT, 'cartography/comerc-rodadebera.json')
OUT = os.path.join(ROOT, 'data/locals.json')

# categoria del directori → tipus de local (colors del rètol i, a la platja, xiringuito)
KIND = {
    'Càmping': 'stay', 'Hotels': 'stay', 'Cases Rurals': 'stay',
    'Supermercats': 'super', 'Fleca i Pastisseries': 'bakery', 'Carnisseria i Xarcuteria': 'butcher',
    'Pescadería': 'fish', 'Flors i Plantes': 'garden',
    'Bars Musicals': 'music', 'Geladeries': 'icecream', 'Guinguetes': 'beachbar',
    'Menjars per emportar': 'takeaway', 'Bars i Restaurants': 'restaurant',
    'Indústries': 'industry', 'Farmàcies i Parafarmàcies': 'pharmacy', 'Centre de Salut': 'health',
    'Dentistes': 'health', 'Fisioteràpia': 'health', 'Òptiques': 'health', 'Residències 3º edat': 'health',
    'Perruqueries': 'beauty', 'Estètica': 'beauty', 'Animals': 'animals',
    'Centre Esportiu': 'sport', 'Club Esportiu': 'sport', 'Escoles de Surfing': 'sport', 'Nàutica i Pesca': 'sport',
    'Acadèmies': 'school', 'Entitats Bancàries': 'bank',
    'Tallers de Reparació i Recanvis': 'garage', 'Venda de Vehicles': 'garage', 'Caravanes': 'garage',
}
GROUP_KIND = {5: 'shop', 20: 'trade', 54: 'office', 64: 'garage', 39: 'health', 33: 'sport', 48: 'restaurant', 1: 'stay'}
# (fons, lletra) del rètol per tipus: colors de la paleta (data/palette.json)
COLORS = {
    'stay': ('sea3', 'white'), 'super': ('red', 'white'), 'bakery': ('ochre', 'terra3'), 'butcher': ('terra2', 'white'),
    'fish': ('sea2', 'white'), 'garden': ('pine2', 'white'), 'music': ('ink', 'sun'), 'icecream': ('blush', 'terra3'),
    'beachbar': ('sun', 'terra3'), 'takeaway': ('ochre2', 'white'), 'restaurant': ('terra3', 'sand'),
    'industry': ('asph3', 'white'), 'pharmacy': ('pine3', 'white'), 'health': ('white', 'pine3'),
    'beauty': ('blush', 'ink'), 'animals': ('pine', 'ink'), 'sport': ('blue', 'white'), 'school': ('ochre', 'blue'),
    'bank': ('blue', 'sun'), 'garage': ('stone3', 'white'), 'shop': ('white', 'terra3'), 'trade': ('stone2', 'ink'),
    'office': ('white2', 'asph3'),
}
# ja tenen rètol (data/services.json, decorate_map.canopies i SHOP_SIGNS) o no es veuen des del carrer
SKIP = {'aldi', 'bon-preu', 'lidl', 'spar', 'leroy-merlin', 'esclatoil', 'petrocat', 'repsol-vallespir',
        'repsol-hispano-suiza', 'casino-municipal', 'can-roig'}
DROP_WORDS = ('restaurant', 'restaurante', 'centre', 'bar', 'sl', 'scp', 's.l', 'de', 'del', 'la', 'el', 'les', 'els', 'i')
MAX = 16   # lletres del rètol (4 px cada una)


def ascii_up(s):
    s = unicodedata.normalize('NFKD', s).encode('ascii', 'ignore').decode().upper()
    return re.sub(r'[^A-Z0-9&\'. -]', '', s).strip()


def sign_text(name):
    t = ascii_up(name)
    if len(t) <= MAX:
        return t
    words = t.split()
    keep = [w for w in words if w.lower().strip('.') not in DROP_WORDS and (len(w) > 1 or w == '&')] or words
    t = ' '.join(keep)
    while len(t) > MAX and len(keep) > 1:
        keep = keep[:-1]
        t = ' '.join(keep)
    return t[:MAX].strip()


def osm_named():
    """Locals amb nom a l'OSM actual (botigues, restaurants, farmàcies…): (paraules del nom, casella)."""
    import gzip
    import xml.etree.ElementTree as ET
    from osmlib import to_tile_f
    root = ET.parse(gzip.open(os.path.join(ROOT, 'cartography/municipio.osm.gz'))).getroot()
    nodes = {el.get('id'): (float(el.get('lon')), float(el.get('lat'))) for el in root if el.tag == 'node'}
    out = []
    for el in root:
        if el.tag not in ('node', 'way'):
            continue
        t = {c.get('k'): c.get('v') for c in el if c.tag == 'tag'}
        if not t.get('name') or not any(k in t for k in ('shop', 'amenity', 'craft', 'office', 'tourism', 'healthcare')):
            continue
        if el.tag == 'node':
            p = to_tile_f(*nodes[el.get('id')])
        else:
            pts = [to_tile_f(*nodes[n.get('ref')]) for n in el if n.tag == 'nd' and n.get('ref') in nodes]
            if not pts:
                continue
            p = (sum(q[0] for q in pts) / len(pts), sum(q[1] for q in pts) / len(pts))
        out.append((words(t['name']), (int(p[0]), int(p[1]))))
    return out


STOP = {'restaurant', 'restaurante', 'bar', 'cafe', 'the', 'del', 'els', 'les', 'sl', 'scp', 'roda', 'bara', 'bera',
        'centre', 'de', 'roc', 'sant', 'gaieta'}


def words(name):
    s = unicodedata.normalize('NFKD', name).encode('ascii', 'ignore').decode().lower()
    return {w for w in re.sub(r'[^a-z0-9 ]', ' ', s).split() if len(w) > 2 and w not in STOP}


# etiquetes OSM → tipus de local (si no hi ha directori de comerços)
OSM_KIND = [
    ('tourism', ('hotel', 'guest_house', 'camp_site', 'hostel', 'apartment'), 'stay'),
    ('shop', ('bakery', 'pastry', 'confectionery'), 'bakery'), ('shop', ('butcher', 'deli'), 'butcher'),
    ('shop', ('seafood',), 'fish'), ('shop', ('florist', 'garden_centre'), 'garden'),
    ('shop', ('supermarket', 'convenience', 'greengrocer'), 'super'), ('amenity', ('ice_cream',), 'icecream'),
    ('amenity', ('fast_food',), 'takeaway'), ('amenity', ('restaurant', 'cafe', 'bar', 'pub'), 'restaurant'),
    ('amenity', ('pharmacy',), 'pharmacy'), ('healthcare', None, 'health'), ('amenity', ('dentist', 'doctors', 'clinic'), 'health'),
    ('shop', ('optician',), 'health'), ('shop', ('hairdresser', 'beauty', 'cosmetics'), 'beauty'),
    ('shop', ('pet',), 'animals'), ('amenity', ('veterinary',), 'animals'), ('leisure', ('sports_centre', 'fitness_centre'), 'sport'),
    ('amenity', ('bank',), 'bank'), ('shop', ('car', 'car_repair', 'motorcycle', 'tyres'), 'garage'),
    ('amenity', ('car_repair',), 'garage'), ('craft', None, 'trade'), ('office', None, 'office'), ('shop', None, 'shop'),
]


def osm_locals():
    """Sense directori: cada botiga, bar o local amb nom de l'OSM, a la seva casella."""
    import gzip
    import xml.etree.ElementTree as ET
    from osmlib import to_tile_f
    root = ET.parse(gzip.open(os.path.join(ROOT, 'cartography/municipio.osm.gz'))).getroot()
    nodes = {el.get('id'): (float(el.get('lon')), float(el.get('lat'))) for el in root if el.tag == 'node'}
    out, seen = [], set()
    for el in root:
        if el.tag not in ('node', 'way'):
            continue
        t = {c.get('k'): c.get('v') for c in el if c.tag == 'tag'}
        if not t.get('name'):
            continue
        kind = next((k for key, vals, k in OSM_KIND if key in t and (vals is None or t[key] in vals)), None)
        if not kind:
            continue
        if el.tag == 'node':
            p = to_tile_f(*nodes[el.get('id')])
        else:
            pts = [to_tile_f(*nodes[n.get('ref')]) for n in el if n.tag == 'nd' and n.get('ref') in nodes]
            if not pts:
                continue
            p = (sum(q[0] for q in pts) / len(pts), sum(q[1] for q in pts) / len(pts))
        x, y = int(p[0]), int(p[1])
        slug = re.sub(r'[^a-z0-9]+', '_', unicodedata.normalize('NFKD', t['name'].lower()).encode('ascii', 'ignore').decode()).strip('_')
        lid = (slug or 'local')[:36]
        if lid in seen:
            lid = f'{lid}_{el.get("id")[-4:]}'
        if not (0 <= x < MAP_TILES and 0 <= y < MAP_TILES) or lid in seen:
            continue
        seen.add(lid)
        bg, fg = COLORS[kind]
        out.append({'id': lid, 'name': t['name'], 'kind': kind, 'tile': [x, y], 'sign': sign_text(t['name']),
                    'bg': bg, 'fg': fg, 'verified': True, 'source': 'osm'})
    return out


def main():
    if not os.path.exists(SRC):
        out = osm_locals()
        with open(OUT, 'w') as f:
            json.dump({'_doc': 'Generat per tools/make_locals.py des de l\'OSM del lloc. No editar a mà.', 'locals': out},
                      f, ensure_ascii=False, indent=1)
            f.write('\n')
        print(f'{len(out)} locals de l\'OSM → data/locals.json')
        return
    src = json.load(open(SRC))['negocis']
    try:
        rev = json.load(open(os.path.join(ROOT, 'data/locals-revisio.json')))
    except OSError:
        rev = {}
    osm = osm_named()
    out, seen = [], set()
    for b in src:
        if b['lat'] is None or b['slug'] in SKIP or b['slug'] in seen:
            continue
        x, y = to_tile(b['lon'], b['lat'])
        if not (0 <= x < MAP_TILES and 0 <= y < MAP_TILES):
            continue
        seen.add(b['slug'])
        lid = b['slug'].replace('-', '_')[:40]
        r = rev.get(lid, {})
        if r.get('hide'):
            continue
        kind = KIND.get(b['categoria']) or GROUP_KIND.get(b['grup'], 'shop')
        bg, fg = COLORS[kind]
        # verificat el 2026: el mateix nom a l'OSM actual a menys de 80 casselles (i llavors la seva posició,
        # més precisa que la del directori) o revisat a mà (data/locals-revisio.json)
        ws, verified, source = words(b['name']), False, 'directori'
        best = None
        for ow, p in osm:
            common = ws & ow
            if ws and ow and common and (len(common) >= min(len(ws), len(ow)) or len(common) >= 2):
                d = ((p[0] - x) ** 2 + (p[1] - y) ** 2) ** .5
                if d < 80 and (best is None or d < best[0]):
                    best = (d, p)
        if best:
            x, y = best[1]
            verified, source = True, 'osm'
        if 'tile' in r:
            x, y = r['tile']
            source = 'revisio'
        if 'verified' in r:
            verified = r['verified']
        out.append({'id': lid, 'name': b['name'], 'kind': kind, 'tile': [x, y], 'sign': sign_text(b['name']),
                    'bg': bg, 'fg': fg, 'verified': verified, 'source': source})
    doc = {'_doc': 'Generat per tools/make_locals.py des de cartography/comerc-rodadebera.json. No editar a mà.',
           'locals': out}
    with open(OUT, 'w') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
        f.write('\n')
    kinds = {}
    for l in out:
        kinds[l['kind']] = kinds.get(l['kind'], 0) + 1
    print(f'{len(out)} locals → data/locals.json ({sum(1 for l in out if l["verified"])} verificats)', kinds)


if __name__ == '__main__':
    main()
