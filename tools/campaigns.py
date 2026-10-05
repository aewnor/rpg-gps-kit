#!/usr/bin/env python3
"""Campañas de misiones = capítulos de data/missions.json (src/systems/missions.lua).

Una sola fuente de verdad (data/missions.json); este módulo da:
  - reference(): identificadores válidos (servicios, objetos, áreas, calles, escenas, spots, cofres, eventos)
  - validate(chapter, ref, chapters): errores (bloquean el guardado) y avisos
  - export_doc(id): JSON autodescriptivo para descargar y pasar a un LLM (instrucciones + referencia + campaña)
  - parse_import(doc): acepta ese documento, el capítulo suelto o un parche {format: roda-rpg-campaign-patch}
  - apply_patch(chapter, patch): aplica un parche (lo que devuelve la IA integrada)
  - llm_prompt(...): mensajes para el LLM integrado (/api/campaigns/llm del editor)
  - save_chapter / delete_chapter / reorder: escriben missions.json con copia en data/.history/

Lo usan tools/web_server.py (editor /editor/missions.html), tools/campaign.py (CLI) y validate_content.py.
Sin dependencias fuera de la biblioteca estándar.
"""
import copy
import json
import os
import re
import secrets
import shutil
import tempfile
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
MISSIONS = os.path.join(ROOT, 'data/missions.json')
HISTORY = os.path.join(ROOT, 'data/.history')

FORMAT = 'roda-rpg-campaign'
PATCH_FORMAT = 'roda-rpg-campaign-patch'
VERSION = 1

ID_RE = re.compile(r'^[a-z][a-z0-9_]{1,39}$')
TPL_KEY_RE = re.compile(r'^[a-z][a-z0-9_]{1,30}$')
CATS = {'nav': 'Orientació', 'social': 'Família i amics', 'safety': 'Seguretat i civisme', 'job': 'Encàrrecs',
        'epic': 'Aventura'}
ROLES = ['amiga', 'amic', 'avia', 'avi', 'tieta', 'tiet', 'cosina', 'cosi']
NEAREST = ['crosswalk', 'light', 'recycling', 'bus_stop']
BOSSES = ['boss:dragon']
EVENTS = ['wallet_started', 'wallet_returned', 'parent_pare', 'parent_mare', 'fish_caught', 'fish_species_5',
          'ally_help', 'ally_help_3', 'ally_found', 'wood_3', 'crafted', 'farm_pinso', 'animal_fed', 'animals_3',
          'egg']   # + home_<id personatge>
PLACEHOLDERS = ['name', 'id', 'role', 'parents', 'parent1', 'parent2', 'name2', 'id2', 'parents2',
                'who', 'who_target', 'place', 'place_target', 'k', 'n']

# tipo de paso → (campos obligatorios, campos propios opcionales, descripción para el LLM)
STEP_TYPES = {
    'goto': (['target'], ['radius', 'alt'], "anar a un lloc; radius en píxels (16 px = 1 casella de 4 m; 24-48 habitual); alt: objectius alternatius (el més proper)"),
    'talk': (['target'], [], 'parlar amb un servei o personatge'),
    'deliver': (['item', 'target'], ['count'], "lliurar un objecte (que el jugador ha de tenir) parlant amb l'objectiu"),
    'buy': (['items', 'at'], ['alt'], "comprar tots els objectes de 'items' en alguna botiga de 'at' (ids de servei)"),
    'have': (['item'], ['count'], "tenir l'objecte (p. ex. obrint un cofre o rebent-lo)"),
    'enter': (['scene'], [], 'entrar a una escena (cova, interior)'),
    'level': (['count'], [], 'arribar al nivell count'),
    'defeat': (['target'], [], 'vèncer un enemic final (boss:dragon)'),
    'event': (['event'], [], "esdeveniment del món: wallet_started, wallet_returned, parent_pare, parent_mare, fish_caught (has pescat un peix), fish_species_5 (5 espècies al quadern), home_<id> (entrar a casa d'un personatge)"),
    'crosswalk': ([], ['count'], 'creuar count passos de vianants'),
    'light': ([], ['count'], 'creuar count semàfors en verd'),
    'recycle': ([], ['count'], 'reciclar count vegades'),
    'bus': ([], ['count'], "agafar l'autobús count vegades"),
    'meet_olaf': (['target'], [], "trobar l'Olaf (el gat) on s'ha escapat"),
}
STEP_COMMON = ['type', 'text', 'target', 'give', 'say', 'who', 'inside', 'done_text', 'join', 'leave']
MISSION_KEYS = ['id', 'cat', 'title', 'xp', 'coins', 'min_level', 'needs', 'give', 'give_coins', 'reward_item',
                'intro', 'steps', 'rank', 'roles', 'friend']
CHAPTER_KEYS = ['id', 'title', 'after', 'unlock', 'parallel', 'missions', 'templates', 'pair_templates',
                'pair_max', 'chain']
MAX_MISSIONS = 150


# ---------------------------------------------------------------- lectura y escritura
def read_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)


def load():
    return read_json(MISSIONS)


def dump(data):
    # mismo formato que el fichero existente (indent=1, sin salto final): diffs pequeños en git
    return json.dumps(data, ensure_ascii=False, indent=1)


def write(data, history=True):
    """Escritura atómica con copia previa en data/.history/ (no se guarda en git)."""
    if history and os.path.exists(MISSIONS):
        os.makedirs(HISTORY, exist_ok=True)
        shutil.copy2(MISSIONS, os.path.join(HISTORY, f'missions-{time.strftime("%Y%m%d-%H%M%S")}-{secrets.token_hex(3)}.json'))
        olds = sorted(f for f in os.listdir(HISTORY) if f.startswith('missions-'))
        for f in olds[:-200]:
            os.unlink(os.path.join(HISTORY, f))
    fd, tmp = tempfile.mkstemp(prefix='.missions-', dir=os.path.dirname(MISSIONS))
    try:
        with os.fdopen(fd, 'w', encoding='utf-8') as f:
            f.write(dump(data))
            f.flush()
            os.fsync(f.fileno())
        os.replace(tmp, MISSIONS)
    finally:
        if os.path.exists(tmp):
            os.unlink(tmp)


def find(data, cid):
    for i, c in enumerate(data.get('chapters', [])):
        if c.get('id') == cid:
            return i, c
    return -1, None


# ---------------------------------------------------------------- referencia
def _runtime_named(kind):
    """Nombres de objetos 'spot'/'chest' del mapa compilado (maps/runtime/overworld/index.lua)."""
    path = os.path.join(ROOT, 'maps/runtime/overworld/index.lua')
    try:
        with open(path, encoding='utf-8') as f:
            txt = f.read()
    except OSError:
        return None
    out = {}
    for m in re.finditer(r'\{id=\d+,name="([a-z0-9_]+)",type="' + kind + r'"[^{}]*(?:\{([^{}]*)\})?', txt):
        props = m.group(2) or ''
        lab = re.search(r'label="([^"]*)"', props)
        item = re.search(r'item="([^"]*)"', props)
        tier = re.search(r'tier="([^"]*)"', props)
        out[m.group(1)] = (lab.group(1) if lab else ('conté ' + item.group(1)) if item else
                           ('cofre ' + tier.group(1) + ", botí a l'atzar") if tier else '')
    return out


def _chest_items():
    """Objeto concreto → cofres que lo contienen en cualquier escena ('escena/cofre')."""
    out = {}
    base = os.path.join(ROOT, 'maps/runtime')
    for scene in sorted(os.listdir(base)) if os.path.isdir(base) else []:
        try:
            with open(os.path.join(base, scene, 'index.lua'), encoding='utf-8') as f:
                txt = f.read()
        except OSError:
            continue
        for m in re.finditer(r'name="([a-z0-9_]+)",type="chest"[^{}]*\{[^{}]*item="([a-z0-9_]+)"', txt):
            out.setdefault(m.group(2), []).append(scene + '/' + m.group(1))
    return out


def reference(full=True):
    """Identificadores válidos para objetivos, objetos y escenas. full=False omite las calles (prompt corto)."""
    d = lambda p: read_json(os.path.join(ROOT, 'data', p))
    services = {}
    for s in d('services.json')['services']:
        e = {'label': s.get('label', s['id']), 'npc': s.get('name', ''), 'kind': s.get('kind', '')}
        stock = list(s.get('fixed') or []) if s.get('rotating') else list(s.get('stock') or [])
        if stock:
            e['sells'] = stock
        if s.get('rotating'):
            e['sells_sometimes'] = [x for x in s.get('stock') or [] if x not in stock]
        services[s['id']] = e
    items = {k: {'name': v.get('name', k), 'kind': v.get('kind', '')} for k, v in d('items.json').items()
             if not k.startswith('_') and isinstance(v, dict)}
    streets = d('streets.json')
    areas = {}
    for a in streets.get('areas', []):
        areas.setdefault(a['n'], a.get('k', ''))
    scenes = [k for k in d('scenes.json') if not k.startswith('_')]
    zdir = os.path.join(ROOT, 'maps/source/zones')
    for f in sorted(os.listdir(zdir)) if os.path.isdir(zdir) else []:
        if f.endswith('.json'):
            try:
                z = read_json(os.path.join(zdir, f))
                scenes.extend(k for k in (z.get('interiors') or {}) if k not in scenes)
            except (OSError, ValueError, AttributeError):
                pass
    ref = {
        'services': services, 'items': items, 'areas': areas, 'scenes': scenes,
        'spots': _runtime_named('spot'), 'chests': _runtime_named('chest'), 'doors': _runtime_named('door'), 'chest_items': _chest_items(),
        'events': EVENTS + ['home_<id del personatge>'], 'roles': ROLES, 'nearest': NEAREST, 'bosses': BOSSES,
        'cats': CATS, 'placeholders': PLACEHOLDERS,
        'step_types': {k: {'required': v[0], 'optional': v[1] + [c for c in STEP_COMMON if c not in v[0] and c != 'type'],
                           'what': v[2]} for k, v in STEP_TYPES.items()},
    }
    if full:
        ref['streets'] = sorted({l['n'] for l in streets.get('lines', []) if l.get('n')})
    return ref


# ---------------------------------------------------------------- validación
def _has_ph(v):
    return isinstance(v, str) and '{' in v


def check_target(t, ref, step_type=None):
    """Error (texto) si el objetivo no existe; None si vale."""
    if not isinstance(t, str) or not t:
        return 'objectiu buit'
    if re.fullmatch(r'\{[a-z_0-9]+\}', t):
        return None                                     # {who_target}, {place_target}: los rellena el motor
    if t == 'home' or t == 'wallet':
        return None
    kind, _, arg = t.partition(':')
    if _has_ph(arg):
        return None if kind in ('friend', 'friendhome', 'area', 'service', 'street', 'spot', 'chest', 'door') else f'tipus d\'objectiu desconegut «{kind}»'
    if kind == 'area':
        return None if arg in ref['areas'] else f'àrea desconeguda «{arg}»'
    if kind == 'street':
        if ref.get('streets') is None:
            return None
        return None if arg in ref['streets'] else f'carrer desconegut «{arg}»'
    if kind == 'service':
        return None if arg in ref['services'] else f'servei desconegut «{arg}»'
    if kind in ('friend', 'friendhome'):
        return None if re.fullmatch(r'[a-z0-9_]{1,40}', arg) else f'personatge no vàlid «{arg}»'
    if kind in ('spot', 'chest', 'door'):
        names = ref.get(kind + 's')
        if names is None:
            return None                                 # mapa sin compilar: no se puede comprobar
        return None if arg in names else f'{kind} desconegut «{arg}»'
    if kind == 'nearest':
        return None if arg in NEAREST else f'nearest:{arg} no existeix (val: {", ".join(NEAREST)})'
    if kind == 'boss':
        return None if t in BOSSES and step_type == 'defeat' else f'enemic final desconegut «{t}»'
    return f'tipus d\'objectiu desconegut «{kind}»'


def _int(v, lo, hi):
    return type(v) is int and lo <= v <= hi


def _str_list(v, n=12, ln=220):
    return isinstance(v, list) and 0 < len(v) <= n and all(isinstance(x, str) and 0 < len(x) <= ln for x in v)


def validate_mission(m, ref, where, errors, warnings, template=False):
    if not isinstance(m, dict):
        errors.append(f'{where}: no és un objecte')
        return
    for k in m:
        if k not in MISSION_KEYS:
            warnings.append(f'{where}: camp desconegut «{k}» (el joc l\'ignora)')
    if not template:
        if not isinstance(m.get('id'), str) or not ID_RE.fullmatch(m['id']):
            errors.append(f'{where}: id no vàlid (minúscules, xifres i _, 2-40)')
    if m.get('cat') not in CATS:
        errors.append(f'{where}: cat ha de ser una de {", ".join(CATS)}')
    if not isinstance(m.get('title'), str) or not m['title'].strip():
        errors.append(f'{where}: falta el títol')
    elif len(m['title']) > 60:
        warnings.append(f'{where}: títol llarg ({len(m["title"])} caràcters; millor ≤ 60)')
    for k, hi in (('xp', 1000), ('coins', 500)):
        if not _int(m.get(k), 0, hi):
            errors.append(f'{where}: {k} ha de ser un enter entre 0 i {hi}')
    for k, lo, hi in (('min_level', 1, 50), ('give_coins', 1, 200), ('rank', 0, 99)):
        if k in m and not _int(m[k], lo, hi):
            errors.append(f'{where}: {k} ha de ser un enter entre {lo} i {hi}')
    if 'needs' in m and m['needs'] != 'home':
        errors.append(f"{where}: needs només pot ser 'home'")
    if 'intro' in m:
        if not _str_list(m['intro'], 6, 240):
            errors.append(f'{where}: intro ha de ser una llista de 1 a 6 frases')
        else:
            for line in m['intro']:
                if len(line) > 160:
                    warnings.append(f'{where}: frase d\'intro llarga ({len(line)}; millor ≤ 160)')
    for k in ('give', 'reward_item'):
        if k in m:
            check_item(m[k], ref, f'{where}: {k}', errors)
    if not template:
        ph = sorted(set(re.findall(r'\{([a-z0-9_]+)\}', json.dumps(m, ensure_ascii=False))))
        if ph:
            errors.append(f'{where}: els marcadors {{{"}, {".join(ph)}}} només funcionen a les plantilles (templates, pair_templates, chain)')
    if 'roles' in m:
        if not template:
            errors.append(f'{where}: roles només serveix a les plantilles (templates)')
        elif not isinstance(m['roles'], list) or any(r not in ROLES for r in m['roles']):
            errors.append(f'{where}: roles ha de ser una llista de {", ".join(ROLES)}')
    steps = m.get('steps')
    if not isinstance(steps, list) or not steps:
        errors.append(f'{where}: cal almenys un pas')
        return
    if len(steps) > 12:
        errors.append(f'{where}: massa passos ({len(steps)}; màxim 12)')
    for i, s in enumerate(steps):
        validate_step(s, ref, f'{where} pas {i + 1}', errors, warnings)


def check_item(v, ref, where, errors):
    if not isinstance(v, str) or not v:
        errors.append(f'{where}: objecte buit')
    elif not _has_ph(v) and v not in ref['items']:
        errors.append(f'{where}: objecte desconegut «{v}» (cal crear-lo a data/items.json)')


def validate_step(s, ref, where, errors, warnings):
    if not isinstance(s, dict):
        errors.append(f'{where}: no és un objecte')
        return
    t = s.get('type')
    if t not in STEP_TYPES:
        errors.append(f'{where}: tipus de pas desconegut «{t}»')
        return
    req, opt, _ = STEP_TYPES[t]
    for k in req:
        if k not in s:
            errors.append(f'{where}: al pas {t} li falta «{k}»')
    for k in s:
        if k not in req and k not in opt and k not in STEP_COMMON:
            warnings.append(f'{where}: camp «{k}» no fa res en un pas {t}')
    if not isinstance(s.get('text'), str) or not s['text'].strip():
        errors.append(f'{where}: falta el text del pas (el que surt a la brúixola)')
    elif len(s['text']) > 70:
        warnings.append(f'{where}: text del pas llarg ({len(s["text"])}; millor ≤ 70)')
    if 'target' in s:
        e = check_target(s['target'], ref, t)
        if e:
            errors.append(f'{where}: {e}')
    elif t in ('crosswalk', 'light', 'recycle', 'bus'):
        warnings.append(f'{where}: sense target la brúixola no indica res (p. ex. nearest:{ {"crosswalk": "crosswalk", "light": "light", "recycle": "recycling", "bus": "bus_stop"}[t]})')
    for k in ('alt',):
        if k in s:
            if not isinstance(s[k], list) or not s[k]:
                errors.append(f'{where}: {k} ha de ser una llista d\'objectius')
            else:
                for a in s[k]:
                    e = check_target(a, ref, t)
                    if e:
                        errors.append(f'{where}: alt: {e}')
    if 'radius' in s and not _int(s['radius'], 8, 400):
        errors.append(f'{where}: radius ha de ser un enter entre 8 i 400')
    if 'count' in s and not _int(s['count'], 1, 99):
        errors.append(f'{where}: count ha de ser un enter entre 1 i 99')
    for k in ('item', 'give'):
        if k in s:
            check_item(s[k], ref, f'{where}: {k}', errors)
    if t == 'buy':
        items, at = s.get('items'), s.get('at')
        if not isinstance(items, list) or not items:
            errors.append(f'{where}: items ha de ser una llista d\'objectes')
            items = []
        if not isinstance(at, list) or not at:
            errors.append(f'{where}: at ha de ser una llista de botigues (ids de servei)')
            at = []
        for sv in at:
            if sv not in ref['services']:
                errors.append(f'{where}: botiga desconeguda «{sv}»')
        for it in items:
            check_item(it, ref, f'{where}: items', errors)
            if it in ref['items'] and at:
                sold = [sv for sv in at if it in ref['services'].get(sv, {}).get('sells', [])]
                some = [sv for sv in at if it in ref['services'].get(sv, {}).get('sells_sometimes', [])]
                if not sold and not some:
                    errors.append(f'{where}: «{it}» no es ven a {", ".join(at)}')
                elif not sold:
                    warnings.append(f'{where}: «{it}» només es ven alguns dies a {", ".join(some)}')
    if t == 'enter' and 'scene' in s and not _has_ph(s['scene']) and s['scene'] not in ref['scenes']:
        errors.append(f'{where}: escena desconeguda «{s["scene"]}»')
    if t == 'event' and 'event' in s:
        ev = s['event']
        if not (ev in EVENTS or (isinstance(ev, str) and re.fullmatch(r'home_(\{id\}|\{id2\}|[a-z0-9_]{1,40})', ev))):
            errors.append(f'{where}: esdeveniment desconegut «{ev}»')
    if t == 'defeat' and s.get('target') not in BOSSES:
        pass                                            # check_target ya lo marca
    for k in ('say', 'done_text'):
        if k in s and not _str_list(s[k], 6, 240):
            errors.append(f'{where}: {k} ha de ser una llista de 1 a 6 frases')
    if 'who' in s and (not isinstance(s['who'], str) or not s['who'] or len(s['who']) > 40):
        errors.append(f'{where}: who ha de ser un nom curt')
    if 'say' in s and 'who' not in s:
        warnings.append(f'{where}: say sense who (qui ho diu?)')
    if 'inside' in s and (not isinstance(s['inside'], str) or not re.fullmatch(r'[a-z0-9_]{2,40}', s['inside'])):
        errors.append(f'{where}: inside ha de ser un prefix d\'escena')


def validate(ch, ref, chapters=None):
    """(errores, avisos) de un capítulo. chapters: los demás capítulos (ids únicos y `after`)."""
    errors, warnings = [], []
    if not isinstance(ch, dict):
        return ['La campanya ha de ser un objecte JSON'], []
    cid = ch.get('id')
    if not isinstance(cid, str) or not ID_RE.fullmatch(cid):
        errors.append('id de campanya no vàlid (minúscules, xifres i _, 2-40)')
    if not isinstance(ch.get('title'), str) or not ch['title'].strip() or len(ch['title']) > 60:
        errors.append('cal un títol de campanya (≤ 60 caràcters)')
    for k in ch:
        if k not in CHAPTER_KEYS and not k.startswith('_'):
            warnings.append(f'camp de campanya desconegut «{k}»')
    if not _int(ch.get('unlock', 0), 0, 99):
        errors.append('unlock ha de ser un enter entre 0 i 99')
    if 'parallel' in ch and not isinstance(ch['parallel'], bool):
        errors.append('parallel ha de ser true o false')
    if 'pair_max' in ch and not _int(ch['pair_max'], 0, 10):
        errors.append('pair_max ha de ser un enter entre 0 i 10')
    others = [c for c in (chapters or []) if isinstance(c, dict) and c.get('id') != cid]
    by_id = {c.get('id'): c for c in others}
    if 'after' in ch:
        aft = ch['after']
        if aft == cid:
            errors.append('after no pot ser la mateixa campanya')
        elif aft not in by_id:
            errors.append(f'after: campanya desconeguda «{aft}»')
        else:
            seen, cur = {cid}, aft
            while cur in by_id and cur not in seen:
                seen.add(cur)
                cur = by_id[cur].get('after')
            if cur in seen:
                errors.append('after fa un cercle entre campanyes')
            n = len(by_id[aft].get('missions') or [])
            if ch.get('unlock', 0) > n and not (by_id[aft].get('templates') or by_id[aft].get('chain')):
                errors.append(f'unlock ({ch.get("unlock")}) és més gran que les missions de «{aft}» ({n}): no s\'obriria mai')
    missions = ch.get('missions', [])
    if not isinstance(missions, list):
        errors.append('missions ha de ser una llista')
        missions = []
    if len(missions) > MAX_MISSIONS:
        errors.append(f'massa missions ({len(missions)}; màxim {MAX_MISSIONS})')
    if not missions and not ch.get('templates') and not ch.get('chain'):
        warnings.append('la campanya no té cap missió')
    taken = {}
    for c in others:
        for m in c.get('missions') or []:
            if isinstance(m, dict):
                taken[m.get('id')] = c.get('id')
    seen = set()
    for i, m in enumerate(missions):
        mid = m.get('id') if isinstance(m, dict) else None
        where = f'missió {i + 1}' + (f' ({mid})' if mid else '')
        validate_mission(m, ref, where, errors, warnings)
        if mid in seen:
            errors.append(f'{where}: id repetit dins la campanya')
        elif mid in taken:
            errors.append(f'{where}: l\'id ja existeix a la campanya «{taken[mid]}»')
        seen.add(mid)
    for key in ('templates', 'pair_templates'):
        tpls = ch.get(key)
        if tpls is None:
            continue
        if not isinstance(tpls, dict):
            errors.append(f'{key} ha de ser un objecte {{clau: plantilla}}')
            continue
        for k, t in tpls.items():
            if not TPL_KEY_RE.fullmatch(k):
                errors.append(f'{key}.{k}: clau no vàlida')
            validate_mission(t, ref, f'{key}.{k}', errors, warnings, template=True)
    chain = ch.get('chain')
    if chain is not None:
        if not isinstance(chain, dict) or not isinstance(chain.get('slot'), dict):
            errors.append('chain ha de tenir slot (plantilla de cada cap de la colla)')
        else:
            validate_mission(chain['slot'], ref, 'chain.slot', errors, warnings, template=True)
            if 'final' in chain:
                validate_mission(chain['final'], ref, 'chain.final', errors, warnings, template=True)
            for p in chain.get('places') or []:
                e = check_target(p.get('target') if isinstance(p, dict) else None, ref)
                if e:
                    errors.append(f'chain.places: {e}')
            for f in chain.get('fallback') or []:
                e = check_target(f.get('target') if isinstance(f, dict) else None, ref)
                if e:
                    errors.append(f'chain.fallback: {e}')
    _flow_checks(missions, ref, others, warnings)
    return errors, warnings


def _flow_checks(missions, ref, others, warnings):
    """Avisos de jugabilidad (no bloquean): entregar o tener algo que nadie da, cofres ya usados en otra misión."""
    in_chests = set(ref.get('chest_items') or {})      # objetos que da algún cofre del juego (también en cuevas)
    used = {}
    for c in others:
        for m in c.get('missions') or []:
            for s in (m.get('steps') or []) if isinstance(m, dict) else []:
                if isinstance(s, dict) and isinstance(s.get('target'), str) and s['target'].startswith('chest:'):
                    used[s['target']] = m.get('id')
    given = set()
    for m in missions:
        if not isinstance(m, dict):
            continue
        if isinstance(m.get('give'), str):
            given.add(m['give'])
        for s in m.get('steps') or []:
            if not isinstance(s, dict):
                continue
            tgt = s.get('target') if isinstance(s.get('target'), str) else ''
            if tgt in used:
                warnings.append(f'{m.get("id")}: {tgt} ja el fa servir la missió «{used[tgt]}» (un cofre només s\'obre un cop)')
            if tgt == 'wallet':
                given.add('cartera')
            it = s.get('item')
            if s.get('type') in ('deliver', 'have') and isinstance(it, str) and it not in given | in_chests and not _has_ph(it):
                verb = 'lliura' if s['type'] == 'deliver' else 'demana tenir'
                warnings.append(f'{m.get("id")}: {verb} «{it}» però cap pas anterior de la campanya el dona (give, buy o un cofre que el contingui)')
            if isinstance(s.get('give'), str):
                given.add(s['give'])
            if s.get('type') == 'buy':
                given.update(x for x in s.get('items') or [] if isinstance(x, str))


def validate_all(data, ref=None):
    ref = ref or reference()
    out = {}
    chapters = data.get('chapters', [])
    for c in chapters:
        out[c.get('id')] = validate(c, ref, chapters)
    return out


# ---------------------------------------------------------------- diff, import, parche
def diff(old, new):
    """Resumen por misión: añadidas, quitadas, cambiadas (con claves) y campos de campaña cambiados."""
    old = old or {}
    om = {m.get('id'): m for m in old.get('missions', []) if isinstance(m, dict)}
    nm = {m.get('id'): m for m in new.get('missions', []) if isinstance(m, dict)}
    out = {'added': [k for k in nm if k not in om], 'removed': [k for k in om if k not in nm], 'changed': {}, 'chapter': []}
    for k in nm:
        if k in om and nm[k] != om[k]:
            keys = sorted({x for x in set(nm[k]) | set(om[k]) if nm[k].get(x) != om[k].get(x)})
            out['changed'][k] = keys
    for k in sorted(set(old) | set(new)):
        if k != 'missions' and old.get(k) != new.get(k):
            out['chapter'].append(k)
    oo = [k for k in om if k in nm]
    no = [k for k in nm if k in om]
    out['reordered'] = oo != no
    return out


def apply_patch(ch, patch):
    """Parche: {set: {...}, upsert: [misiones], remove: [ids], order: [ids], templates: {k: plantilla|null}}."""
    ch = copy.deepcopy(ch)
    if not isinstance(patch, dict):
        raise ValueError('el pegat ha de ser un objecte')
    for k, v in (patch.get('set') or {}).items():
        if k in ('id', 'missions'):
            continue
        if k in CHAPTER_KEYS:
            if v is None:
                ch.pop(k, None)
            else:
                ch[k] = v
    missions = ch.setdefault('missions', [])
    rm = set(patch.get('remove') or [])
    missions[:] = [m for m in missions if m.get('id') not in rm]
    existing = {m.get('id') for m in missions}
    for m in patch.get('upsert') or []:
        if not isinstance(m, dict) or not isinstance(m.get('id'), str):
            raise ValueError('cada missió del pegat necessita id')
        # una plantilla (roles o {name}/{id}) que el LLM ha puesto en upsert va a templates
        if m['id'] not in existing and ('roles' in m or re.search(r'\{(name|id|parents)\}', json.dumps(m, ensure_ascii=False))):
            t = dict(m)
            key = t.pop('id')
            t.pop('_after', None)
            ch.setdefault('templates', {})[key] = t
            continue
        for i, o in enumerate(missions):
            if o.get('id') == m['id']:
                missions[i] = m
                break
        else:
            pos = m.pop('_after', None)
            idx = next((i + 1 for i, o in enumerate(missions) if o.get('id') == pos), len(missions))
            missions.insert(idx, m)
        m.pop('_after', None)
    order = patch.get('order')
    if isinstance(order, list) and order:
        rank = {k: i for i, k in enumerate(order)}
        missions.sort(key=lambda m: rank.get(m.get('id'), len(rank)))
    for key in ('templates', 'pair_templates'):
        for k, t in (patch.get(key) or {}).items():
            tp = ch.setdefault(key, {})
            if t is None:
                tp.pop(k, None)
            else:
                tp[k] = t
    return ch


def parse_import(doc, base=None):
    """Documento exportado, capítulo suelto o parche → capítulo. base: capítulo actual (para parches)."""
    if not isinstance(doc, dict):
        raise ValueError('El JSON ha de ser un objecte')
    fmt = doc.get('format')
    if fmt == PATCH_FORMAT or ('upsert' in doc and 'missions' not in doc and 'campaign' not in doc):
        if base is None:
            raise ValueError('Un pegat necessita una campanya oberta a qui aplicar-se')
        return apply_patch(base, doc.get('patch', doc)), doc.get('notes')
    if fmt not in (None, FORMAT):
        raise ValueError(f'Format desconegut «{fmt}»')
    ch = doc.get('campaign', doc) if fmt == FORMAT or 'campaign' in doc else doc
    if not isinstance(ch, dict):
        raise ValueError('Falta el camp campaign')
    v = doc.get('version', VERSION)
    if fmt == FORMAT and v != VERSION:
        raise ValueError(f'Versió {v} no suportada (aquest editor és la {VERSION})')
    ch = {k: v for k, v in ch.items() if k in CHAPTER_KEYS}
    return ch, doc.get('notes')


# ---------------------------------------------------------------- export y LLM
GUIDE = """Ets un dissenyador de missions del joc «Roda de Berà RPG» (LÖVE, pixel art), ambientat al poble real de Roda de Berà (Tarragonès). L'infant que hi juga té entre 6 i 10 anys i aprèn el poble: orientar-se, conèixer serveis, seguretat viària, civisme i aventures suaus (cova, drac amable).

Regles de contingut:
- Tots els textos del joc en CATALÀ, frases curtes i amables (títol ≤ 60 caràcters, cada frase d'intro/say/done_text ≤ 160, text de pas ≤ 70 que comenci amb verb: «Ves a…», «Parla amb…»).
- Res de violència explícita, por, temes d'adults ni dades personals. Es pot «vèncer» el Drac només amb el pas defeat existent.
- Només llocs, serveis, objectes, escenes, spots i cofres que surten a «reference». No t'inventis cap id: si cal un objecte nou, fes servir un que existeixi semblant i explica-ho a notes.
- Una missió = id únic (minúscules, xifres i _), cat (nav|social|safety|job|epic), title, xp (20-150), coins (2-25), intro (1-3 frases), steps (1-5 passos). Opcionals: min_level, needs:'home', give (objecte en començar), give_coins, reward_item (objecte en acabar).
- Dins una campanya, les missions es fan en ordre (llevat de parallel=true). La campanya s'obre quan s'han fet «unlock» missions de la campanya «after».
- Un objecte que s'ha de lliurar (deliver) o tenir (have) l'ha de donar abans un pas (give), una compra (buy, a una botiga que el vengui segons reference.services[].sells) o un cofre (chest:<nom> que el contingui).
- Objectius (target): area:<nom d'àrea>, street:<nom de carrer>, service:<id>, friend:<rol o id>, friendhome:<id>, home, spot:<nom>, chest:<nom>, wallet, nearest:crosswalk|light|recycling|bus_stop, boss:dragon (només defeat).
- A les plantilles (templates, pair_templates, chain) es poden fer servir marcadors {name} {id} {role} {parents} {parent1} {parent2} (i {name2} {id2} a pair_templates; {who_target} {place} {place_target} {n} a chain). A les missions normals, no.
- Cada pas pot portar give (objecte que es rep en acabar el pas), say + who (diàleg en acabar-lo) i done_text (frases en lliurar). inside (prefix d'escena) només quan l'objectiu és dins d'una cova o interior; a l'exterior no el posis.
- Un cofre (chest) només s'obre una vegada en tota la partida: no facis servir cofres que ja surten a les missions de context. Els cofres de fusta donen un botí a l'atzar (no serveixen per a «have» d'un objecte concret).
- Si el jugador pot tenir ja l'objecte d'abans, el pas «have» es completa sol: millor objectes de missió nous que dona un pas (give)."""

LLM_FILE_HOWTO = """COM AMPLIAR AQUESTA CAMPANYA AMB UN LLM (ChatGPT, Claude, Gemini…):
1. Enganxa tot aquest fitxer al xat i demana el canvi (p. ex. «afegeix 3 missions noves de seguretat viària al voltant de l'escola» o «millora els textos perquè siguin més divertits»).
2. Demana que et torni EL MATEIX FITXER JSON complet amb «campaign» modificat (sense comentaris ni text fora del JSON). Les claus «guide», «how_to», «reference» i «context» es poden deixar igual o treure.
3. A l'editor de missions (/editor/missions.html) fes «⬆️ Importar», enganxa'l i revisa els canvis i avisos abans de guardar."""


def other_summary(data, cid):
    out = []
    for c in data.get('chapters', []):
        if c.get('id') == cid:
            continue
        out.append({'id': c.get('id'), 'title': c.get('title'), 'after': c.get('after'), 'unlock': c.get('unlock', 0),
                    'missions': [{'id': m.get('id'), 'title': m.get('title')} for m in c.get('missions') or []]})
    return out


def export_doc(data, cid, ref=None):
    i, ch = find(data, cid)
    if ch is None:
        raise KeyError(cid)
    return {
        'format': FORMAT, 'version': VERSION, 'game': 'Roda de Berà RPG',
        'exported': time.strftime('%Y-%m-%dT%H:%M:%S%z'),
        'how_to': LLM_FILE_HOWTO, 'guide': GUIDE,
        'context': {'position': i + 1, 'other_campaigns': other_summary(data, cid), 'engine_doc': data.get('_doc', '')},
        'reference': ref or reference(),
        'campaign': ch,
    }


def _compact_ref(ref):
    """Referencia mínima para el prompt (tokens limitados en Groq)."""
    return {
        'services': {k: [v['label'], v['npc']] + ([v['sells']] if v.get('sells') else []) for k, v in ref['services'].items()},
        'items': {k: v['name'] for k, v in ref['items'].items()},
        'areas': list(ref['areas']),
        'scenes': ref['scenes'], 'spots': ref['spots'] or {}, 'chests': ref['chests'] or {},
        'chest_items': ref.get('chest_items') or {},
        'events': ref['events'], 'roles': ref['roles'],
        'step_types': {k: [v['required'], v['what']] for k, v in ref['step_types'].items()},
    }


def llm_messages(data, ch, instruction, ref, errors=None, previous=None):
    """Mensajes para el LLM integrado: responde SOLO un parche JSON (sale mucho más corto que la campaña)."""
    system = (GUIDE + "\n\nRespon NOMÉS amb un objecte JSON (sense text fora) amb aquesta forma:\n"
              '{"notes":"què has canviat i per què, en català, 1-3 frases",'
              '"set":{"title":"…"},'                       # opcional
              '"upsert":[{missió completa nova o modificada; per inserir-la després d\'una altra posa "_after":"id"}],'
              '"remove":["id de missió a treure"],'
              '"templates":{"clau":{plantilla completa SENSE id, amb roles i marcadors {name} {id}} o null}}\n'
              'Les plantilles per personatge (amb roles o marcadors com {name}) van SEMPRE a templates, mai a upsert. '
              'Inclou només el que canvia: una missió modificada va sencera a upsert amb el mateix id; les que no toques no les repeteixis. '
              'Ids nous: únics, en minúscules, que no coincideixin amb cap de context.\n\nreference = '
              + json.dumps(_compact_ref(ref), ensure_ascii=False, separators=(',', ':')))
    user = ('Context (altres campanyes, no les toquis): '
            + json.dumps(other_summary(data, ch.get('id')), ensure_ascii=False, separators=(',', ':'))
            + '\n\nCampanya actual:\n' + json.dumps(ch, ensure_ascii=False, separators=(',', ':'))
            + '\n\nEncàrrec: ' + instruction.strip())
    msgs = [{'role': 'system', 'content': system}, {'role': 'user', 'content': user}]
    if errors and previous:
        msgs.append({'role': 'assistant', 'content': previous})
        msgs.append({'role': 'user', 'content': 'El pegat té aquests errors; torna\'l corregit sencer (mateix format):\n- '
                     + '\n- '.join(errors[:25])})
    return msgs


def parse_llm(text):
    """Extrae el JSON de la respuesta (tolera ```json …``` alrededor)."""
    t = (text or '').strip()
    m = re.search(r'\{.*\}', t, re.S)
    if not m:
        raise ValueError('La IA no ha tornat JSON')
    return json.loads(m.group(0))


# ---------------------------------------------------------------- operaciones sobre el fichero
def save_chapter(data, cid, ch, ref=None):
    """Sustituye (o crea, o renombra si ch.id ≠ cid) un capítulo. Devuelve (data, errores, avisos)."""
    ref = ref or reference()
    data = copy.deepcopy(data)
    chapters = data.setdefault('chapters', [])
    i, _ = find(data, cid)
    others = [c for c in chapters if c.get('id') != cid]
    if ch.get('id') != cid and find({'chapters': others}, ch.get('id'))[1] is not None:
        return data, [f'Ja hi ha una campanya amb l\'id «{ch.get("id")}»'], []
    errors, warnings = validate(ch, ref, others)
    if errors:
        return data, errors, warnings
    ch = {k: ch[k] for k in CHAPTER_KEYS if k in ch} | {k: v for k, v in ch.items() if k not in CHAPTER_KEYS and k.startswith('_')}
    if i >= 0:
        chapters[i] = ch
        if ch['id'] != cid:                             # renombrar: las que dependían de la vieja la siguen
            for c in chapters:
                if c.get('after') == cid:
                    c['after'] = ch['id']
    else:
        chapters.append(ch)
    return data, [], warnings


def delete_chapter(data, cid):
    data = copy.deepcopy(data)
    i, _ = find(data, cid)
    if i < 0:
        raise KeyError(cid)
    deps = [c['id'] for c in data['chapters'] if c.get('after') == cid]
    if deps:
        raise ValueError('No es pot esborrar: en depenen ' + ', '.join(deps))
    if i == 0:
        raise ValueError('La primera campanya és la inicial del joc; no es pot esborrar')
    del data['chapters'][i]
    return data


def reorder(data, ids):
    data = copy.deepcopy(data)
    cur = [c['id'] for c in data['chapters']]
    if sorted(cur) != sorted(ids):
        raise ValueError('La llista d\'ordre no coincideix amb les campanyes')
    by = {c['id']: c for c in data['chapters']}
    data['chapters'] = [by[k] for k in ids]
    return data
