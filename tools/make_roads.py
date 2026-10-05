"""Eixos de totes les vies (OSM highway=*) → data/roads.json, per a la conducció guiada (src/systems/roads.lua):
el vehicle segueix l'eix de la carretera o el camí, no la superfície (a la ciutat, voreres, places i calçada
són totes «pavimentades» i no se'n pot treure on és la carretera). Classe: 'road' (per a cotxes), 'track'
(pistes) o 'path' (camins, carrils bici i carrers de vianants). Coordenades en píxels del món, simplificades a 2 px.
Ràpid: python3 tools/make_roads.py"""
import json
import os

from osmlib import OSM
from make_streets import simplify, px

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CLASS = {'motorway': 'road', 'trunk': 'road', 'primary': 'road', 'secondary': 'road', 'tertiary': 'road',
         'unclassified': 'road', 'residential': 'road', 'living_street': 'road', 'service': 'road', 'road': 'road',
         'motorway_link': 'road', 'trunk_link': 'road', 'primary_link': 'road', 'secondary_link': 'road',
         'tertiary_link': 'road', 'track': 'track', 'pedestrian': 'path', 'path': 'path', 'cycleway': 'path',
         'footway': 'path', 'bridleway': 'path'}


def main():
    osm = OSM(os.path.join(ROOT, 'cartography/municipio.osm.gz'))
    lines = []
    for wid, (tags, refs) in osm.ways.items():
        c = CLASS.get(tags.get('highway'))
        if not c or tags.get('area') == 'yes':
            continue
        pts = px(osm, refs)
        if len(pts) < 2:
            continue
        pts = simplify(pts, 2)
        line = {'c': c, 'p': [v for q in pts for v in q]}
        if tags.get('oneway') == 'yes' or tags.get('junction') == 'roundabout':
            line['o'] = 1
        lines.append(line)
    out = {'_doc': 'Generat per tools/make_roads.py a partir de l\'OSM (© OpenStreetMap, ODbL). Píxels del món.',
           'lines': lines}
    path = os.path.join(ROOT, 'data/roads.json')
    with open(path, 'w') as f:
        json.dump(out, f, separators=(',', ':'))
    print(len(lines), 'vies,', os.path.getsize(path) // 1024, 'KB')


if __name__ == '__main__':
    main()
