#!/usr/bin/env python3
"""Missions «Coneix el teu poble» per al lloc del joc → data/missions.json (src/systems/missions.lua).

  python3 tools/make_missions.py     (després de make_streets.py i make_services.py)

- Capítol «poble», nou: anar a casa, als serveis que hi hagi (escola, centre de salut, biblioteca, ajuntament, súper,
  policia) i a les places, parcs i escoles amb nom (data/streets.json), i passejar pels carrers més llargs.
- Capítols genèrics de data/missions.base.json (els de Roda de Berà que no depenen del lloc): família i amics (les
  plantilles per als personatges del perfil), seguretat i civisme, la colla, el taller i les granges. Els llocs de
  Roda que hi surten (parcs, places) es canvien per llocs d'aquí; els capítols que només tenien sentit a Roda
  (el drac de la muntanya, el tresor, la pesca, Correus) no es copien.
"""
import json
import os

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
KEEP = ['familia', 'seguretat', 'colla', 'taller', 'granja']
SERVICE_MISSIONS = [   # id del servei, títol, text del pas, intro
    ('escola', 'Camina fins a l\'escola', 'Arriba a {label}', ['Saps on és l\'escola?',
     'Segueix la fletxa de dalt: et diu cap on has d\'anar i quants metres falten.']),
    ('metge', 'On és el centre de salut?', 'Arriba a {label}', ['Si algun dia et fa mal la panxa, aquí t\'ajuden.']),
    ('biblioteca', 'Visita la biblioteca', 'Arriba a {label}', ['A la biblioteca hi ha llibres i contes per llegir.']),
    ('ajuntament', 'Coneix l\'ajuntament', 'Arriba a {label}', ['A l\'ajuntament treballen per al poble.']),
    ('super', 'Anem a comprar', 'Arriba a {label}', ['Al súper hi ha fruita, pa i moltes coses.']),
    ('policia', 'La Policia Local', 'Arriba a {label}', ['Si et perds, la policia t\'ajuda a tornar a casa.']),
]


def load(rel, default):
    try:
        with open(os.path.join(ROOT, rel), encoding='utf-8') as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def subst(obj, mapping):
    """Canvia noms de llocs i objectius a totes les cadenes (recursiu)."""
    if isinstance(obj, str):
        for a, b in mapping.items():
            obj = obj.replace(a, b)
        return obj
    if isinstance(obj, list):
        return [subst(v, mapping) for v in obj]
    if isinstance(obj, dict):
        return {k: subst(v, mapping) for k, v in obj.items()}
    return obj


DOORS = {'door_pedrera_elies': 'door_pedrera', 'door_castell_creixell': 'door_castell', 'door_cucurull': 'door_cucurull'}


def fix_targets(obj, supers):
    """Passos «buy» (at: botigues) i «door:» de Roda → els del lloc; sense súpers, es treuen les plantilles de compra."""
    if isinstance(obj, dict):
        out = {}
        for k, v in obj.items():
            if k == 'templates' and isinstance(v, dict):
                v = {tk: tv for tk, tv in v.items()
                     if supers or not any(st.get('type') == 'buy' for st in tv.get('steps', []))}
            if k == 'at' and isinstance(v, list):
                v = supers[:3]
            out[k] = fix_targets(v, supers)
        return out
    if isinstance(obj, list):
        return [fix_targets(v, supers) for v in obj]
    if isinstance(obj, str):
        for a, b in DOORS.items():
            obj = obj.replace(a, b)
    return obj


def article(name):
    low = name.lower()
    if low.startswith(('plaça', 'escola', 'llar')):
        return 'la ' + name
    if low[:1] in 'aeiouàèéíòóú':
        return "l'" + name
    return 'el ' + name


def perles(areas):
    """Les Perles del Drac (src/systems/perles.lua) a les places i parcs amb nom d'aquí (fins a 7)."""
    p = os.path.join(ROOT, 'data/perles.json')
    doc = load('data/perles.json', {'premi': 'armadura_drac'})
    names = list(dict.fromkeys(a['n'] for a in areas))[:7]
    doc['perles'] = [{'id': f'perla_{i + 1}', 'near': 'area:' + n, 'offset': [0, 2],
                      'pista': f"Busca-la a {article(n)}."} for i, n in enumerate(names)]
    with open(p, 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    print(len(names), 'perles del drac:', ', '.join(names))


def main():
    streets = load('data/streets.json', {'lines': [], 'areas': []})
    services = {s['id']: s for s in load('data/services.json', {'services': []})['services']}
    base = load('data/missions.base.json', None) or load('data/missions.json', {'chapters': []})
    areas = [a for a in streets.get('areas', []) if a.get('n')]
    parks = [a['n'] for a in areas if a.get('k') == 'park'] or [a['n'] for a in areas]
    places = [a['n'] for a in areas]

    poble = {'id': 'poble', 'title': 'Coneix el teu poble', 'unlock': 0, 'missions': [
        {'id': 'casa', 'cat': 'nav', 'title': 'Torna a casa', 'xp': 25, 'coins': 4, 'needs': 'home',
         'intro': ['Saps tornar a casa tu sol?', 'La fletxa de dalt t\'hi porta.'],
         'steps': [{'type': 'goto', 'target': 'home', 'radius': 24, 'text': 'Arriba a casa'}]}]}
    for sid, title, text, intro in SERVICE_MISSIONS:
        sv = services.get(sid)
        if sv:
            poble['missions'].append({'id': 'srv_' + sid, 'cat': 'nav', 'title': title, 'xp': 30, 'coins': 5, 'intro': intro,
                                      'steps': [{'type': 'goto', 'target': 'service:' + sid, 'radius': 40,
                                                 'text': text.format(label=sv['label'])}]})
    seen = set()
    for k, a in enumerate(areas):
        if a['n'] in seen or len(seen) >= 5:
            continue
        seen.add(a['n'])
        poble['missions'].append({'id': f'lloc_{k}', 'cat': 'nav', 'title': 'Ves a ' + article(a['n']), 'xp': 30, 'coins': 5,
                                  'intro': [f"Saps on és {article(a['n'])}?", 'Segueix la fletxa!'],
                                  'steps': [{'type': 'goto', 'target': 'area:' + a['n'], 'radius': 44,
                                             'text': 'Arriba a ' + article(a['n'])}]})
    # els carrers més llargs amb nom (sense autopistes ni carreteres)
    lens = {}
    for ln in streets.get('lines', []):
        n = ln.get('n', '')
        if not n or any(w in n.lower() for w in ('autopista', 'autovia', 'carretera', 'ap-', 'n-', 'c-')):
            continue
        p = ln['p']
        lens[n] = lens.get(n, 0) + sum(((p[i + 2] - p[i]) ** 2 + (p[i + 3] - p[i + 1]) ** 2) ** 0.5 for i in range(0, len(p) - 2, 2))
    top = sorted(lens, key=lambda n: -lens[n])[:3]
    if top:
        poble['missions'].append({'id': 'carrers', 'cat': 'nav', 'title': 'Passeja pels carrers', 'xp': 40, 'coins': 6,
                                  'intro': ['Cada carrer té un nom. Quan hi entres, surt un cartell.'],
                                  'steps': [{'type': 'goto', 'target': 'street:' + n, 'radius': 32, 'text': 'Passa pel ' + n
                                             if not n.lower().startswith(('avinguda', 'plaça', 'rambla', 'ronda')) else 'Passa per ' + article(n)}
                                            for n in top]})

    out = [poble]
    for c in base.get('chapters', []):
        if c.get('id') not in KEEP:
            continue
        # llocs de Roda que surten al capítol → llocs d'aquí
        txt = json.dumps(c, ensure_ascii=False)
        olds = []
        for part in txt.split('area:')[1:]:
            name = part.split('"')[0]
            if name not in olds:
                olds.append(name)
        mapping = {}
        for i, old in enumerate(olds):
            pool = parks if 'parc' in old.lower() else places
            new = pool[i % len(pool)] if pool else None
            if new:
                mapping['area:' + old] = 'area:' + new
                mapping[old] = new
        c = subst(c, mapping)
        # botigues i portes de Roda dins les plantilles → les d'aquí (súpers de make_services.py; portes de decorate_map)
        supers = [i for i, sv in services.items() if sv.get('kind') in ('super', 'shop') and 'poma' in sv.get('stock', [])]
        c = fix_targets(c, supers)
        if c['id'] == 'colla':
            ch = c.get('chain', {})
            ch['places'] = [{'text': article(n), 'target': 'area:' + n} for n in list(dict.fromkeys(places))[:6]]
            ch['fallback'] = [f for f in ch.get('fallback', []) if f.get('target', '').split(':')[-1] in services]
            for f in ch['fallback']:
                f['name'] = {'escola': 'la mestra', 'metge': 'la metgessa', 'policia': "l'agent de policia"}.get(
                    f['target'].split(':')[-1], f['name'])
            if len(ch['places']) < 3:
                continue   # (calen llocs amb nom per a la colla)
        if c['id'] == 'familia':
            if not parks:
                c['missions'] = [m for m in c.get('missions', []) if 'area:' not in json.dumps(m)]
        if c['id'] == 'granja':
            c = subst(c, {'Al sud de l\'autopista hi ha granges': 'A les afores del poble hi ha granges'})
        if c.get('after') and c['after'] not in [o['id'] for o in out] + ['poble']:
            c.pop('after')
        out.append(c)
    perles(areas)
    doc = {'_doc': base.get('_doc', ''), 'chapters': out}
    with open(os.path.join(ROOT, 'data/missions.json'), 'w', encoding='utf-8') as f:
        json.dump(doc, f, ensure_ascii=False, indent=1)
    print(f"{sum(len(c.get('missions', [])) for c in out)} missions en {len(out)} capítols:",
          ', '.join(f"{c['id']} ({len(c.get('missions', []))})" for c in out))


if __name__ == '__main__':
    main()
