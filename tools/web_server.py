#!/usr/bin/env python3
"""Servidor de la versión web (/) y del editor de zonas (/editor/) con su API.

  GET  /                     juego (build/web)
  GET  /editor/              editor (web/editor)
  GET  /data/<escena>/<f>    datos compilados (maps/runtime) para que el editor dibuje el mapa
  GET  /assets/<f>           atlas y sprites (assets/runtime) · /assets/tiles.json y /assets/palette.json (data/)
  GET  /api/zones            lista de zonas · GET/PUT/DELETE /api/zones/<id>
  POST /api/publish          recompila mapas y regenera la web (en segundo plano)
  GET  /api/publish          estado y registro de la última publicación
  GET/PUT /api/npcs          personajes sueltos por el mapa (maps/source/npcs.json)
  GET/PUT /api/map_edits     retoques sueltos del mapa fuera de las zonas (maps/source/map-edits.json)
  POST /api/npc_chat         conversación de un personaje con IA (Groq vía el /api/groq del hub;
                             si falla, contesta con sus frases fijas)
  POST /api/procgen          interior procedural {kind: house|shop|block, seed} (src/world/procgen.lua)
  POST /api/sat2pixel        capas de pixel art desde la ortofoto PNOA {x, y, w, h} o una imagen
                             propia {image: dataURL, w, h} (tools/sat2pixel.py)
  GET  /api/campaigns        campañas de misiones (capítulos de data/missions.json) · /api/campaigns/reference
  GET/PUT/DELETE /api/campaigns/<id> · GET /api/campaigns/<id>/export (JSON para descargar y pasar a un LLM)
  POST /api/campaigns/validate · /import (exportado, capítulo o parche) · /order · /llm (mejora con IA:
                             parche propuesto por Groq, validado; no guarda nada)
  POST /api/private_home     casa del jugador para la versión web: home.json y casa_privada.json del
                             directorio de datos LOCAL de LÖVE (nunca en el paquete ni en el repositorio);
                             sin PIN, solo desde la red local

Editor protegido por sesión adulta validada con el hub. Cada guardado deja copia en maps/source/zones/.history/.
"""
import json
import os
import re
import shutil
import subprocess
import sys
import collections
import ipaddress
import random
import threading
import time
import urllib.request
import urllib.error
import secrets
import hashlib
import tempfile
import socket
from http.cookies import SimpleCookie
from functools import wraps
from http.server import SimpleHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import unquote, urlparse

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0,os.path.dirname(__file__))
from web_release import activate_release
import campaigns as Campaigns
ZONES = os.path.join(ROOT, 'maps/source/zones')
HISTORY = os.path.join(ZONES, '.history')
ID_RE = re.compile(r'^[a-z0-9_]{2,40}$')
NPCS = os.path.join(ROOT, 'maps/source/npcs.json')
MAP_EDITS = os.path.join(ROOT, 'maps/source/map-edits.json')
EDIT_KEY_RE = re.compile(r'^\d{1,4},\d{1,4}$')


class APIError(Exception):
    def __init__(self, code, message):
        self.code, self.message = code, message

HUB_ADULT = os.environ.get('HUB_ADULT_URL', 'http://127.0.0.1:8090/api/adult-check')
sessions = {}
auth_attempts = {}
auth_lock = threading.Lock()
ALLOWED_HOSTS = set(os.environ.get('RODA_ALLOWED_HOSTS', 'localhost,127.0.0.1').split(',')) | {socket.gethostname()}

def verify_adult(pin):
    try:
        request = urllib.request.Request(HUB_ADULT, data=json.dumps({'pin': pin}).encode(), headers={'Content-Type':'application/json'})
        with urllib.request.urlopen(request, timeout=5) as response:
            return response.status == 200 and json.loads(response.read(4096)).get('ok') is True
    except urllib.error.HTTPError as e:
        if e.code == 429: raise APIError(429, 'Massa intents; espera uns segons')
        return False
    except (OSError, ValueError):
        raise APIError(503, 'No es pot contactar amb el hub')

def api_route(fn):
    @wraps(fn)
    def wrapped(self):
        try:
            path = urlparse(self.path).path
            if path.startswith('/api/'):
                host = self.headers.get('Host','')
                if urlparse('http://' + host).hostname not in ALLOWED_HOSTS:
                    raise APIError(403, 'Origen no permès')
                origin = self.headers.get('Origin')
                if origin and origin != 'http://' + host:
                    raise APIError(403, 'Origen no permès')
                if self.command != 'GET':
                    # Custom header + JSON prevent a cross-site simple POST (also same-site different ports).
                    if self.headers.get('X-Roda-Request') != '1':
                        raise APIError(403, 'Petició no permesa')
                # la casa del jugador no pide PIN (los niños juegan sin él);
                # sigue limitada a la red local en el propio endpoint (local_client)
                if path not in ('/api/adult-check','/api/npc_chat','/api/private_home') + SYNC_PATHS and not (path == '/api/config' and self.command == 'POST'):
                    self.require_adult()
                if self.command != 'GET': self.body_json()
            return fn(self)
        except APIError as e:
            self.close_connection = True
            return self.send_json({'error':e.message}, e.code)
        except (ValueError, TypeError, KeyError, AttributeError):
            self.close_connection = True
            return self.send_json({'error':'Dades no vàlides'}, 400)
        except OSError:
            self.close_connection = True
            return self.send_json({'error':'No es pot llegir o desar; torna-ho a provar'}, 503)
    return wrapped

def read_json(path):
    with open(path, encoding='utf-8') as f:
        return json.load(f)

def map_size():
    path=os.path.join(ROOT,'maps/runtime/overworld/index.lua')
    with open(path,encoding='utf-8') as f:header=f.read(256)
    width=re.search(r'\bwidth=(\d+)',header);height=re.search(r'\bheight=(\d+)',header)
    if not width or not height: raise APIError(503,'Dimensions del mapa no disponibles')
    return int(width.group(1)),int(height.group(1))


def validate_chat(req):
    if not isinstance(req,dict) or not isinstance(req.get('npc',{}),dict): return 'Personatge no vàlid'
    npc=req.get('npc',{})
    for obj,k,n in [(npc,'say',20),(req,'history',8)]:
        if k in obj and (not isinstance(obj[k],list) or len(obj[k])>n): return 'Llista no vàlida'
    if any(not isinstance(x,str) or len(x)>200 for x in npc.get('say',[])): return 'Text no vàlid'
    if any(not isinstance(x,dict) or not isinstance(x.get('text',''),str) or len(x.get('text',''))>320 for x in req.get('history',[])): return 'Historial no vàlid'
    for obj,k,n in [(npc,'name',40),(npc,'persona',600),(npc,'place',80),(req,'ask',120)]:
        if k in obj and (not isinstance(obj[k],str) or len(obj[k])>n): return 'Text no vàlid'


# One short lock for editor documents; never held during map compilation or network calls.
document_lock=threading.RLock()

def revision(path):
    if not os.path.exists(path): return '"missing"'
    with open(path,'rb') as f: data=f.read()
    st=os.stat(path)
    return '"'+hashlib.sha256(data+str((st.st_mtime_ns,st.st_ino)).encode()).hexdigest()+'"'

def write_document(path, data, expected, delete=False):
    with document_lock:
        if not expected: raise APIError(428,'Cal carregar la versió abans de desar')
        current=revision(path)
        if current!=expected: raise APIError(409,'Hi ha canvis d’una altra pestanya. Conserva el teu esborrany i torna a carregar.')
        if os.path.exists(path):
            try: read_json(path)
            except ValueError: raise APIError(503,'Fitxer danyat: cal recuperar una còpia')
            os.makedirs(HISTORY,exist_ok=True)
            backup=os.path.join(HISTORY,os.path.basename(path)[:-5]+'-'+str(time.time_ns())+'-'+secrets.token_hex(4)+'.json')
            shutil.copy2(path,backup)
        if delete:
            if not os.path.exists(path): raise APIError(404,'No existeix')
            os.unlink(path)
        else:
            os.makedirs(os.path.dirname(path),exist_ok=True)
            fd,tmp=tempfile.mkstemp(prefix='.roda-',dir=os.path.dirname(path))
            try:
                with os.fdopen(fd,'w',encoding='utf-8') as f:
                    json.dump(data,f,ensure_ascii=False,separators=(',',':'));f.flush();os.fsync(f.fileno())
                os.replace(tmp,path)
            finally:
                if os.path.exists(tmp): os.unlink(tmp)
        return revision(path)


def validate_map_edits(d):
    if not isinstance(d, dict) or not isinstance(d.get('cells'), dict):
        return 'se esperaba {"cells": {...}}'
    if len(d['cells']) > 200000:
        return 'demasiados retoques'
    tiles = read_json(os.path.join(ROOT, 'data/tiles.json'))['tiles']
    width,height=map_size()
    for k, v in d['cells'].items():
        if not isinstance(k,str) or not EDIT_KEY_RE.match(k) or not isinstance(v, dict):
            return f'celda inválida {k}'
        x,y=map(int,k.split(','))
        if not (0<=x<width and 0<=y<height): return 'Cel·la fora del mapa'
        for layer, name in v.items():
            if layer not in ('ground', 'detail', 'structures', 'overhead'):
                return f'capa inválida {layer}'
            if name is not None and (not isinstance(name,str) or (name and name not in tiles)):
                return f'tile desconocido {name}'
    return None
def _identity():
    """t.identity de conf.lua (cada joc del kit té la seva carpeta de partides)."""
    try:
        m = re.search(r"t\.identity\s*=\s*'([^']+)'", open(os.path.join(ROOT, 'conf.lua'), encoding='utf-8').read())
        return m.group(1) if m else 'roda-rpg'
    except OSError:
        return 'roda-rpg'


LOVE_DIR = os.path.expanduser(os.environ.get('RODA_LOVE_DIR', '~/.local/share/love/' + _identity()))


CONFIG = os.path.join(ROOT, 'config/joc.json')
CONFIG_DEFAULT = os.path.join(ROOT, 'config/joc.default.json')
TEMPS = ('auto', 'sol', 'nuvol', 'pluja', 'tempesta', 'neu', 'boira', 'vent')


def load_config():
    """Configuració del joc: config/joc.json (si no hi és o està malmès, la de per defecte)."""
    base = json.load(open(CONFIG_DEFAULT))
    try:
        cur = json.load(open(CONFIG))
        if isinstance(cur, dict):
            base.update({k: v for k, v in cur.items() if k in base})
    except (OSError, ValueError):
        pass
    return base


def clean_config(req):
    """Valida i normalitza la configuració que arriba de l'editor (només camps coneguts)."""
    if not isinstance(req, dict):
        raise APIError(400, 'Configuració no vàlida')
    c = load_config()
    if 'veu' in req:
        if req['veu'] not in (None, True, False): raise APIError(400, 'veu: sí, no o automàtic')
        c['veu'] = req['veu']
    for k in ('volum', 'volum_musica'):
        if k in req:
            v = float(req[k])
            if not 0 <= v <= 1: raise APIError(400, k + ': entre 0 i 1')
            c[k] = round(v, 2)
    if 'temps' in req:
        if req['temps'] not in TEMPS: raise APIError(400, 'temps desconegut')
        c['temps'] = req['temps']
    if 'mostrar_tots_els_locals' in req:
        c['mostrar_tots_els_locals'] = bool(req['mostrar_tots_els_locals'])
    if 'locals_verificats' in req:
        ids = req['locals_verificats']
        if not isinstance(ids, list) or len(ids) > 2000 or not all(isinstance(i, str) and re.fullmatch(r'[a-z0-9_]{1,40}', i) for i in ids):
            raise APIError(400, 'locals_verificats: llista d\'identificadors')
        c['locals_verificats'] = sorted(set(ids))
    return c


def save_config(c):
    os.makedirs(os.path.dirname(CONFIG), exist_ok=True)
    if os.path.exists(CONFIG):
        shutil.copy2(CONFIG, CONFIG + '.bak')
    tmp = CONFIG + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(c, f, ensure_ascii=False, indent=1)
    os.replace(tmp, CONFIG)


def locals_list():
    try:
        return [{'id': l['id'], 'name': l['name'], 'kind': l['kind'], 'verified': l.get('verified', False)}
                for l in json.load(open(os.path.join(ROOT, 'data/locals.json')))['locals']]
    except (OSError, ValueError, KeyError):
        return []


# ---------------------------------------------------------------- perfils sincronitzats entre aparells
# Els perfils i partides viuen al navegador de cada aparell; el joc (src/sync.lua) en desa una còpia aquí perquè
# el que es crea al PC es vegi al mòbil. Un fitxer per jugador del hub (owner), fora del repositori: dades familiars.
SYNC_DIR = os.path.expanduser(os.environ.get('RODA_SYNC_DIR', '~/.local/share/' + _identity() + '-sync'))
SYNC_PATHS = ('/api/sync/pull', '/api/sync/push', '/api/sync/delete')
SYNC_MAX = 900_000          # bytes d'una petició de sincronització (el pont web admet 1 MB)
sync_lock = threading.Lock()
UID_RE = re.compile(r'[A-Za-z0-9_-]{4,40}')


def sync_file(owner):
    if owner is None: owner = ''
    if not isinstance(owner, str) or len(owner) > 64: raise APIError(400, 'Jugador no vàlid')
    key = owner.encode('utf-8').hex() or 'local'
    return os.path.join(SYNC_DIR, key + '.json')


def sync_load(owner):
    path = sync_file(owner)
    for cand in (path, path + '.bak'):
        try:
            with open(cand, encoding='utf-8') as f:
                d = json.load(f)
            if isinstance(d, dict) and isinstance(d.get('profiles'), dict):
                d.setdefault('deleted', {})
                return d
        except (OSError, ValueError):
            continue
    return {'profiles': {}, 'deleted': {}}


def sync_save(owner, d):
    path = sync_file(owner)
    os.makedirs(SYNC_DIR, mode=0o700, exist_ok=True)
    if os.path.exists(path): shutil.copy2(path, path + '.bak')
    tmp = path + '.tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        json.dump(d, f, ensure_ascii=False)
    os.chmod(tmp, 0o600)
    os.replace(tmp, path)


def sync_request(path, req):
    if not isinstance(req, dict): raise APIError(400, 'Dades no vàlides')
    owner = req.get('owner') or ''
    with sync_lock:
        d = sync_load(owner)
        if path == '/api/sync/pull':
            return {'profiles': d['profiles'], 'deleted': d['deleted']}
        uid = req.get('uid')
        if not isinstance(uid, str) or not UID_RE.fullmatch(uid): raise APIError(400, 'Perfil no vàlid')
        t = req.get('t')
        if not isinstance(t, (int, float)) or t < 0: raise APIError(400, 'Data no vàlida')
        if path == '/api/sync/delete':
            cur = d['profiles'].get(uid)
            if cur is None or cur.get('t', 0) <= t:
                d['profiles'].pop(uid, None)
                d['deleted'][uid] = t
                sync_save(owner, d)
            return {'ok': True}
        prof = req.get('profile')
        if not isinstance(prof, dict) or not isinstance(prof.get('name'), str): raise APIError(400, 'Perfil no vàlid')
        if uid in d['deleted'] and d['deleted'][uid] >= t: return {'ok': True, 'deleted': True}
        d['deleted'].pop(uid, None)
        cur = d['profiles'].get(uid) or {'t': -1, 'save_t': -1}
        changed = False
        if t > cur.get('t', -1):
            cur['t'], cur['profile'], changed = t, prof, True
        save, save_t = req.get('save'), req.get('save_t')
        if isinstance(save, dict) and isinstance(save_t, (int, float)) and save_t > cur.get('save_t', -1):
            cur['save_t'], cur['save'], changed = save_t, save, True
        if changed:
            d['profiles'][uid] = cur
            sync_save(owner, d)
        return {'ok': True, 't': cur.get('t'), 'save_t': cur.get('save_t')}


def private_home():
    out = {}
    for key, name in (('home', 'home.json'), ('house', 'casa_privada.json')):
        try:
            with open(os.path.join(LOVE_DIR, name), encoding='utf-8') as f:
                out[key] = json.load(f)
        except (OSError, ValueError):
            pass
    if 'house' in out:
        out['house'].pop('warnings', None)
    return out
def local_client(addr):
    try:
        ip = ipaddress.ip_address(addr)
    except ValueError:
        return False
    if ip.version == 6 and ip.ipv4_mapped:
        ip = ip.ipv4_mapped
    return ip.is_private or ip.is_loopback or ip.is_link_local


HUB_GROQ = os.environ.get('HUB_GROQ_URL', 'http://127.0.0.1:8090/api/groq')
# modelo propio para los personajes: cuota de Groq separada de la del resto de juegos del hub
NPC_MODEL = os.environ.get('NPC_MODEL', 'openai/gpt-oss-120b')
# rotación de modelos del hub (cada modelo de Groq tiene su propio límite por minuto; gemini-* usa las
# claves Gemini del hub si las hay): se prueban por orden hasta que uno responde
CAMPAIGN_MODELS = [m for m in os.environ.get('CAMPAIGN_MODELS', 'openai/gpt-oss-120b,qwen/qwen3.8-27b,openai/gpt-oss-20b,gemini-2.5-flash').split(',') if m]
CAMPAIGN_MAX_TOKENS = int(os.environ.get('CAMPAIGN_MAX_TOKENS', '4000'))
NPC_SPRITES = {'npc_archaeologist', 'npc_gardener', 'npc_smith', 'npc_sailor', 'npc_musician', 'npc_librarian', 'npc_miner', 'npc_cook', 'npc_teacher', 'npc_elder', 'npc_girl', 'npc_baker', 'npc_fisher', 'npc_ranger', 'npc_postie', 'npc_tourist', 'npc_kid',
               'npc_lady', 'npc_police', 'npc_doctor', 'npc_clerk', 'npc_coach', 'npc_builder', 'npc_builder2', 'npc_cat_orange', 'npc_cat_grey'}
chat_lock = threading.Lock()
chat_cache = collections.OrderedDict()
chat_slots = threading.Semaphore(2)   # como mucho 2 llamadas a la IA a la vez
DEFAULT_OPTIONS = ['Què fas aquí?', "Explica'm alguna cosa de Roda", 'Adéu!']
publish_state = {'running': False, 'ok': None, 'log': [], 'started': None, 'finished': None}
lock = threading.Lock()


def validate_zone(z):
    if not isinstance(z,dict) or not isinstance(z.get('id'),str) or not ID_RE.fullmatch(z['id']): return 'Zona sense id vàlid'
    if any(type(z.get(k)) is not int for k in ('x','y','w','h')): return 'Coordenades no vàlides'
    width,height=map_size()
    if not (2<=z['w']<=120 and 2<=z['h']<=120 and 0<=z['x']<=width-z['w'] and 0<=z['y']<=height-z['h']): return 'Zona fora del mapa'
    tiles=read_json(os.path.join(ROOT,'data/tiles.json'))['tiles']
    def layers(obj,w,h):
        objects=obj.get('objects',[])
        if not isinstance(objects,list) or len(objects)>1000:return 'Objectes no vàlids'
        for item in objects:
            if not isinstance(item,dict) or item.get('type') not in ('npc','sign','door','exit','spawn'):return 'Tipus d’objecte no vàlid'
            if any(type(item.get(k)) is not int for k in ('x','y')) or not(0<=item['x']<w and 0<=item['y']<h):return 'Objecte fora de la zona'
            if item['type']=='npc' and validate_chat({'npc':{k:item[k] for k in ('name','persona','say') if k in item}}):return 'Personatge no vàlid'
            if item['type']=='sign' and (not isinstance(item.get('say',[]),list) or any(not isinstance(v,str) or len(v)>600 for v in item.get('say',[]))):return 'Cartell no vàlid'
            if item['type']=='door' and item.get('interior') and (not isinstance(item['interior'],str) or not ID_RE.fullmatch(item['interior'])):return 'Porta no vàlida'
        for k in ('ground','detail','structures','overhead','height'):
            if k not in obj: continue
            v=obj[k]
            if not isinstance(v,list) or len(v)!=w*h: return 'Capa de mida incorrecta'
            if k=='height':
                if any(type(x) is not int or not 0<=x<=3 for x in v): return 'Altura no vàlida'
            elif any(x is not None and (not isinstance(x,str) or (x and x not in tiles)) for x in v): return 'Tile no vàlid'
    err=layers(z,z['w'],z['h'])
    if err:return err
    interiors=z.get('interiors',{})
    if not isinstance(interiors,dict) or len(interiors)>30:return 'Interiors no vàlids'
    for iid,it in interiors.items():
        if not isinstance(iid,str) or not ID_RE.fullmatch(iid) or not iid.endswith('_int') or not isinstance(it,dict):return 'Interior no vàlid'
        if any(type(it.get(k)) is not int or not 4<=it[k]<=60 for k in ('w','h')):return 'Mida interior no vàlida'
        err=layers(it,it['w'],it['h'])
        if err:return err
    if 'poly' in z and z['poly'] is not None:
        poly=z['poly']
        if not isinstance(poly,list) or not 3<=len(poly)<=128:return 'Polígon no vàlid'
        for pt in poly:
            if not isinstance(pt,list) or len(pt)!=2 or any(type(v) is not int for v in pt) or not (0<=pt[0]<=z['w'] and 0<=pt[1]<=z['h']):return 'Polígon fora del mapa'


def validate_npcs(lst):
    if not isinstance(lst,list) or len(lst)>500:return 'Llista de personatges no vàlida'
    ids=set();width,height=map_size()
    for n in lst:
        if not isinstance(n,dict) or not isinstance(n.get('id'),str) or not ID_RE.fullmatch(n['id']):return 'Id no vàlid'
        if n['id'] in ids:return 'Id repetit'
        ids.add(n['id'])
        if not(type(n.get('x')) is int and type(n.get('y')) is int and 0<=n['x']<width and 0<=n['y']<height):return 'Posició fora del mapa'
        if not isinstance(n.get('sprite','npc_elder'),str) or n.get('sprite','npc_elder') not in NPC_SPRITES:return 'Aspecte desconegut'
        if validate_chat({'npc':{k:n[k] for k in ('name','persona','say','place') if k in n}}):return 'Text no vàlid'


def clean_chat(v, fallback):
    """Valida la respuesta de la IA: texto corto y hasta 3 opciones cortas."""
    if not isinstance(v, dict):
        return None
    reply = str(v.get('reply', '')).strip()
    if not isinstance(v.get('options',[]),list):return None
    opts = [o.strip()[:40] for o in v.get('options',[]) if isinstance(o,str) and o.strip()][:3]
    if not reply or len(reply) > 160:
        return None
    if not opts:
        opts = DEFAULT_OPTIONS[:2]
    if not any('adéu' in o.lower() or 'adeu' in o.lower() for o in opts):
        opts = opts[:2] + ['Adéu!']
    return {'reply': reply, 'options': opts, 'ai': True}


def public_npc(identifier):
    if not isinstance(identifier,str) or not re.fullmatch(r'[a-z0-9_]{1,100}',identifier):return None
    try:
        for npc in read_json(NPCS) if os.path.exists(NPCS) else []:
            if npc.get('id')==identifier and npc.get('ai'):return npc
        for name in os.listdir(ZONES) if os.path.isdir(ZONES) else []:
            if not name.endswith('.json'):continue
            zone=read_json(os.path.join(ZONES,name))
            for zid,area in [(zone.get('id'),zone),*list(zone.get('interiors',{}).items())]:
                for i,npc in enumerate(area.get('objects',[])):
                    if npc.get('type')=='npc' and npc.get('ai') and identifier==f'{zid}_npc_{i}':return npc
    except (OSError,ValueError,TypeError,AttributeError):return None
    return None

CHAT_PER_MIN = int(os.environ.get('NPC_CHAT_PER_MIN', '20'))
chat_hits = {}

def chat_allowed(ip):
    """Com a molt CHAT_PER_MIN converses amb IA per minut i aparell (una criatura que prem sense parar no buida la quota)."""
    now=time.monotonic()
    with chat_lock:
        hits=[t for t in chat_hits.get(ip,[]) if now-t<60]
        if len(chat_hits)>512: chat_hits.clear()
        if len(hits)>=CHAT_PER_MIN:
            chat_hits[ip]=hits; return False
        hits.append(now); chat_hits[ip]=hits
        return True


# el que fa ara un veí (src/systems/errands.lua): el client només n'envia la clau
NPC_DOING = {'bakery': 'vas a buscar el pa al forn', 'hair': 'vas a la perruqueria a tallar-te els cabells',
             'shop': 'vas al súper a fer la compra', 'beach': 'ets a la platja prenent el sol i banyant-te',
             'pool': 'ets a la piscina fent un bany', 'garden': 'estàs regant el jardí de casa',
             'bread': 'tornes del forn amb una barra de pa', 'bag': 'tornes del súper amb la bossa plena',
             'haircut': "t'acabes de tallar els cabells i estàs content del tall nou"}


def npc_chat(req):
    # Only server-owned public NPCs can supply provider context. Family characters stay local.
    npc = public_npc((req.get('npc') or {}).get('id'))
    if npc is None:return {'reply':'Hola! Quin dia més bonic a Roda de Berà.','options':DEFAULT_OPTIONS,'ai':False}
    name = str(npc.get('name') or 'Veí')[:40]
    persona = str(npc.get('persona') or 'un veí amable del poble')[:600]
    place = 'Roda de Berà'
    say = [str(x)[:200] for x in (npc.get('say') or [])][:10]
    hist = [h for h in (req.get('history') or []) if isinstance(h, dict)][-8:]
    ask = str(req.get('ask') or 'Hola!')[:120]
    doing = NPC_DOING.get(str((req.get('npc') or {}).get('doing') or ''))   # encàrrec actual (llista tancada)
    fallback = {'reply': random.choice(say) if say else 'Hola! Quin dia més bonic a Roda de Berà.',
                'options': DEFAULT_OPTIONS, 'ai': False}
    key = json.dumps([name, persona, place, hist, ask, doing], ensure_ascii=False)
    with chat_lock:
        if key in chat_cache:
            chat_cache.move_to_end(key)
            return chat_cache[key]
    system = (f"Interpretes el personatge «{name}» (aquest és el teu nom) d'un joc d'aventures infantil ambientat a "
              "Roda de Berà (Tarragona). "
              f"Personalitat i història: {persona}. Ara ets a: {place}. "
              + (f"Ara mateix {doing}: si ve al cas, comenta-ho. " if doing else '') +
              "Parles amb un infant de 6 a 10 anys que juga. Respon SEMPRE en català, amb to amable i divertit, "
              "en 1 o 2 frases curtes (màxim 160 caràcters). Res de violència, por, temes d'adults ni dades personals; "
              "no demanis mai dades a l'infant. Pots parlar de llocs reals del poble (l'Arc de Berà, el Roc de Sant "
              "Gaietà, la platja, Sant Bartomeu, l'estació, Roda de Mar...). "
              + (f"Per inspirar-te (no les repeteixis literalment): {' | '.join(say)}. " if say else '') +
              ("Si et saluden, saluda i presenta't breument amb el teu nom. " if not hist else '') +
              'Respon NOMÉS amb JSON: {"reply":"...","options":["...","...","Adéu!"]} on options són 3 preguntes '
              "o respostes curtes (màxim 40 caràcters) que l'infant et podria dir després.")
    msgs = [{'role': 'system', 'content': system}]
    for h in hist:
        role = 'assistant' if h.get('role') == 'npc' else 'user'
        msgs.append({'role': role, 'content': str(h.get('text', ''))[:320]})
    msgs.append({'role': 'user', 'content': ask})
    body = json.dumps({'model': NPC_MODEL, 'messages': msgs, 'temperature': 0.8, 'max_tokens': 260,
                       'response_format': {'type': 'json_object'}}).encode()
    if not chat_slots.acquire(blocking=False):
        return fallback
    try:
        with urllib.request.urlopen(urllib.request.Request(HUB_GROQ,data=body,headers={'Content-Type':'application/json'}),timeout=8) as r:
            raw=r.read(65537)
        if len(raw)>65536:raise ValueError('response too large')
        data=json.loads(raw or b'{}')
        out = clean_chat(json.loads(data.get('text') or '{}'), fallback)
    except Exception as e:  # noqa: BLE001
        print('npc_chat: IA no disponible:', type(e).__name__, flush=True)
        out = None
    finally:
        chat_slots.release()
    if not out:
        return fallback
    with chat_lock:
        chat_cache[key] = out
        while len(chat_cache) > 500:
            chat_cache.popitem(last=False)
    return out


# ---------------------------------------------------------------- campañas de misiones (tools/campaigns.py)
llm_slot = threading.Semaphore(1)   # una mejora con IA a la vez (Groq gratis: pocos tokens por minuto)
CAMPAIGN_RE = re.compile(r'/api/campaigns/([a-z][a-z0-9_]{1,39})')

def campaign_list(data, ref):
    out=[]
    for c in data.get('chapters',[]):
        errors,warnings=Campaigns.validate(c,ref,data['chapters'])
        out.append({'id':c.get('id'),'title':c.get('title'),'after':c.get('after'),'unlock':c.get('unlock',0),
                    'parallel':bool(c.get('parallel')),'missions':len(c.get('missions') or []),
                    'templates':len(c.get('templates') or {})+len(c.get('pair_templates') or {})+(1 if c.get('chain') else 0),
                    'errors':len(errors),'warnings':len(warnings)})
    return out

def campaign_groq(msgs):
    """Una llamada al /api/groq del hub sin caer a la IA local (no_local), rotando claves y modelos.
    Devuelve (texto, tokens, modelo)."""
    body=json.dumps({'models':CAMPAIGN_MODELS,'model':CAMPAIGN_MODELS[0],'messages':msgs,'temperature':0.7,'max_tokens':CAMPAIGN_MAX_TOKENS,
                     'response_format':{'type':'json_object'},'no_local':True}).encode()
    try:
        with urllib.request.urlopen(urllib.request.Request(HUB_GROQ,data=body,headers={'Content-Type':'application/json'}),timeout=150) as r:
            raw=r.read(2_000_001)
    except urllib.error.HTTPError as e:
        if e.code==429:
            try: wait=int(json.loads(e.read(4096) or b'{}').get('retry_after') or 60)
            except (ValueError,TypeError,AttributeError): wait=60
            raise APIError(429,f'Tots els models del hub estan al límit de tokens per minut. Torna-ho a provar d’aquí a uns {max(5,min(wait,300))} s o fes servir ⬇️ JSON amb un altre LLM.')
        raise APIError(502,'La IA no respon (HTTP %d). Prova més tard o fes servir ⬇️ JSON amb un altre LLM.'%e.code)
    except OSError:
        raise APIError(504,'La IA no respon a temps. Prova més tard o fes servir ⬇️ JSON amb un altre LLM.')
    res=json.loads(raw or b'{}')
    if res.get('backend') not in ('groq','gemini'):
        raise APIError(503,'La IA del hub no està disponible ara mateix. Prova en uns minuts o fes servir ⬇️ JSON.')
    return res.get('text') or '',((res.get('raw') or {}).get('usage') or {}).get('total_tokens') or 0,res.get('model') or ''

def campaign_llm(req):
    """Pide a la IA un parche para la campaña (borrador del editor) y lo devuelve aplicado y validado.
    Si el parche tiene errores, se le devuelven una vez para que lo corrija; si esa segunda llamada no se
    puede hacer (límite por minuto de Groq), se entrega la primera propuesta con sus errores."""
    ch=req.get('campaign'); instruction=req.get('instruction')
    if not isinstance(ch,dict) or not isinstance(instruction,str) or not 3<=len(instruction.strip())<=1500:
        raise APIError(400,'Cal la campanya i un encàrrec (3-1500 caràcters)')
    data=Campaigns.load();ref=Campaigns.reference(full=False);full_ref=Campaigns.reference()
    others=[c for c in data.get('chapters',[]) if c.get('id')!=ch.get('id')]
    if not llm_slot.acquire(blocking=False):raise APIError(429,'Ja hi ha una petició a la IA en curs')
    try:
        best=None;errors=None;previous=None;tokens=0;attempts=0;used_models=[]
        for attempt in range(2):
            try: text,used,model=campaign_groq(Campaigns.llm_messages(data,ch,instruction,ref,errors,previous))
            except APIError:
                if best: break                     # 2ª llamada sin cuota: se queda la primera propuesta
                raise
            attempts+=1;tokens+=used;previous=text
            if model: used_models.append(model)
            try:
                patch=Campaigns.parse_llm(text)
                proposed=Campaigns.apply_patch(ch,patch)
            except (ValueError,TypeError,AttributeError) as e:
                errors=['La resposta no és un pegat vàlid: '+str(e)[:200]];continue
            errors,warnings=Campaigns.validate(proposed,full_ref,others)
            best={'campaign':proposed,'notes':str(patch.get('notes') or '')[:600],'errors':errors,'warnings':warnings}
            if not errors:break
        if not best: raise APIError(502,'La IA no ha tornat un pegat vàlid: '+'; '.join((errors or ['sense resposta'])[:3]))
        return dict(best,diff=Campaigns.diff(ch,best['campaign']),attempts=attempts,tokens=tokens,models=used_models)
    finally:
        llm_slot.release()

def run_publish():
    ok=False
    try:
        os.makedirs(os.path.join(ROOT,'build'),exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='.publish-',dir=os.path.join(ROOT,'build')) as staging:
            # Snapshot sources before compiling; edits after this point belong to the next publish.
            with document_lock:
                for name in ('src','data','maps','assets','tools','web','docs','main.lua','conf.lua','Makefile','README.md'):
                    source=os.path.join(ROOT,name);dest=os.path.join(staging,name)
                    if os.path.isdir(source):
                        shutil.copytree(source,dest,ignore=shutil.ignore_patterns('node_modules','.history','__pycache__','private'),symlinks=True)
                    elif os.path.isfile(source):shutil.copy2(source,dest)
            modules=os.path.join(ROOT,'tools/web/node_modules')
            if os.path.isdir(modules):
                os.makedirs(os.path.join(staging,'tools/web'),exist_ok=True)
                os.symlink(modules,os.path.join(staging,'tools/web/node_modules'))
            release_id='web-'+time.strftime('%Y%m%d-%H%M%S')+'-'+secrets.token_hex(4)
            steps=[['python3','tools/compile_maps.py'],['python3','tools/make_overview.py'],
                   ['python3','tools/validate_content.py'],['sh','tools/build_web.sh']]
            for cmd in steps:
                with lock:publish_state['log'].append('$ '+' '.join(cmd))
                result=subprocess.run(cmd,cwd=staging,capture_output=True,text=True,timeout=600,
                    env=dict(os.environ,PYTHONUNBUFFERED='1',RODA_RELEASE_ID=release_id))
                with lock:publish_state['log'].extend((result.stdout+result.stderr).strip().splitlines()[-25:])
                if result.returncode:return
            release=os.path.join(ROOT,'releases',release_id)
            os.makedirs(os.path.dirname(release),exist_ok=True)
            os.rename(os.path.join(staging,'releases',release_id),release)
            activate_release(ROOT,release)
            ok=True
    except (OSError,ValueError,subprocess.TimeoutExpired):
        with lock:publish_state['log'].append('Publicació interrompuda; es conserva la versió activa')
    finally:
        with lock:publish_state.update(running=False,ok=ok,finished=time.time())


class Handler(SimpleHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send_json(self, obj, code=200):
        data = json.dumps(obj, ensure_ascii=False).encode()
        self.send_response(code)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        if getattr(self,'document_etag',None): self.send_header('ETag',self.document_etag)
        if getattr(self,'session_cookie',None): self.send_header('Set-Cookie',self.session_cookie)
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Cache-Control', 'no-store')
        self.end_headers()
        self.wfile.write(data)

    def require_adult(self):
        cookie=SimpleCookie()
        try: cookie.load(self.headers.get('Cookie',''))
        except Exception: raise APIError(401,'Cal el PIN d’adult')
        token=cookie.get('roda_adult')
        token=token.value if token else ''
        now=time.monotonic()
        with auth_lock:
            for k in list(sessions):
                if sessions[k] <= now: del sessions[k]
            if token not in sessions: raise APIError(401,'Cal el PIN d’adult')

    def adult_login(self):
        req=self.body_json()
        if not isinstance(req,dict) or not isinstance(req.get('pin'),str) or not re.fullmatch(r'[0-9]{1,12}',req['pin']):
            raise APIError(400,'PIN no vàlid')
        now=time.monotonic(); ip=self.client_address[0]
        with auth_lock:
            for k in list(auth_attempts):
                if now-auth_attempts[k][0]>60: del auth_attempts[k]
            start,count=auth_attempts.get(ip,(now,0))
            if count>=8 or len(auth_attempts)>256: raise APIError(429,'Massa intents; espera un minut')
            auth_attempts[ip]=(start,count+1)
        if not verify_adult(req['pin']): raise APIError(401,'PIN incorrecte')
        token=secrets.token_urlsafe(32)
        with auth_lock:
            for k in list(sessions):
                if sessions[k]<=now: del sessions[k]
            if len(sessions)>=100: raise APIError(503,'Massa sessions; torna-ho a provar més tard')
            sessions[token]=now+900
        self.session_cookie='roda_adult='+token+'; HttpOnly; SameSite=Strict; Path=/; Max-Age=900'
        return self.send_json({'ok':True})

    def body_json(self):
        if hasattr(self,'_json_body'): return self._json_body
        limit=16384 if urlparse(self.path).path in ('/api/npc_chat','/api/adult-check','/api/private_home','/api/publish','/api/procgen') or (urlparse(self.path).path=='/api/config' and self.command=='POST') else 20_000_000
        if self.headers.get('Transfer-Encoding'): raise APIError(400,'Codificació no permesa')
        try: n=int(self.headers.get('Content-Length','0'))
        except ValueError: raise APIError(400,'Longitud no vàlida')
        if n<0: raise APIError(400,'Longitud no vàlida')
        if urlparse(self.path).path in SYNC_PATHS: limit=SYNC_MAX
        if n>limit: raise APIError(413,'Petició massa gran')
        if n and self.headers.get('Content-Type','').split(';')[0]!='application/json': raise APIError(415,'Cal JSON')
        if hasattr(self,'connection'): self.connection.settimeout(5)
        try: raw=self.rfile.read(n)
        except TimeoutError: raise APIError(408,'Temps de lectura esgotat')
        if len(raw)!=n: raise APIError(400,'Petició incompleta')
        try:
            self._json_body=json.loads(raw or b'null')
            return self._json_body
        except (ValueError,UnicodeError): raise APIError(400,'JSON no vàlid')

    def translate_path(self, path):
        p = unquote(urlparse(path).path)
        if p.startswith('/releases/'):
            match=re.fullmatch(r'/releases/([a-z0-9][a-z0-9_-]{0,79})/([a-zA-Z0-9_.-]+)',p)
            if not match:return os.path.join(ROOT,'build','__nope__')
            base,rest=os.path.join(ROOT,'releases',match.group(1)),match.group(2)
        elif p.startswith('/editor'):
            bundled=os.path.join(ROOT,'build/web/editor')
            base,rest=(bundled if os.path.isdir(bundled) else os.path.join(ROOT,'web/editor')),p[len('/editor'):]
        elif p.startswith('/data/'):
            bundled=os.path.join(ROOT,'build/web/map-data')
            base,rest=(bundled if os.path.isdir(bundled) else os.path.join(ROOT,'maps/runtime')),p[len('/data'):]
        elif p in ('/assets/tiles.json', '/assets/palette.json'):
            return os.path.join(ROOT, 'data', p.rsplit('/', 1)[1])
        elif p.startswith('/assets/'):
            base, rest = os.path.join(ROOT, 'assets/runtime'), p[len('/assets'):]
        else:
            base, rest = os.path.join(ROOT, 'build/web'), p
        full = os.path.normpath(os.path.join(base, rest.lstrip('/')))
        if full != base and not full.startswith(base + os.sep):   # (sin os.sep, /editor/../editor2 colaba)
            return os.path.join(base, '__nope__')
        if os.path.isdir(full):
            full = os.path.join(full, 'index.html')
        return full

    def end_headers(self):
        path=urlparse(self.path).path
        if not path.startswith('/api/'):
            self.send_header('Cache-Control','public, max-age=31536000, immutable' if path.startswith('/releases/') and not path.endswith('index.html') else 'no-cache')
        self.send_header('X-Content-Type-Options','nosniff')
        super().end_headers()

    def get_document(self,path,default):
        with document_lock:
            self.document_etag=revision(path)
            try: data=read_json(path) if os.path.exists(path) else default
            except ValueError: raise APIError(503,'Fitxer danyat: cal recuperar una còpia')
            return self.send_json(data)

    @api_route
    def do_GET(self):
        p = urlparse(self.path).path
        if p == '/api/zones':
            out = []
            for f in sorted(os.listdir(ZONES)) if os.path.isdir(ZONES) else []:
                if f.endswith('.json'):
                    try:
                        z = json.load(open(os.path.join(ZONES, f)))
                        out.append({k: z.get(k) for k in ('id', 'name', 'scene', 'x', 'y', 'w', 'h', 'poly')})
                    except (OSError,ValueError):
                        out.append({'id': f[:-5], 'error': 'Fitxer no vàlid'})
            return self.send_json(out)
        m = re.match(r'^/api/zones/([a-z0-9_]+)$', p)
        if m:
            f = os.path.join(ZONES, m.group(1) + '.json')
            if not os.path.exists(f):
                return self.send_json({'error': 'no existe'}, 404)
            return self.get_document(f,None)
        if p == '/api/publish':
            with lock:
                return self.send_json(publish_state)
        if p == '/api/config':
            return self.send_json({'config': load_config(), 'locals': locals_list(), 'temps': list(TEMPS)})
        if p == '/api/npcs':
            return self.get_document(NPCS,[])
        if p == '/api/map_edits':
            return self.get_document(MAP_EDITS,{'cells':{}})
        if p.startswith('/api/campaigns'):
            return self.campaigns_get(p)
        return super().do_GET()

    def campaigns_get(self,p):
        with document_lock:
            self.document_etag=revision(Campaigns.MISSIONS)
            try: data=Campaigns.load()
            except ValueError: raise APIError(503,'data/missions.json danyat: cal recuperar una còpia (data/.history/)')
        if p=='/api/campaigns':
            ref=Campaigns.reference()
            return self.send_json({'campaigns':campaign_list(data,ref),'doc':data.get('_doc','')})
        if p=='/api/campaigns/reference':
            return self.send_json(Campaigns.reference())
        match=re.fullmatch(r'/api/campaigns/([a-z][a-z0-9_]{1,39})(/export)?',p)
        if not match: raise APIError(404,'Ruta desconeguda')
        _,ch=Campaigns.find(data,match.group(1))
        if ch is None: raise APIError(404,'Campanya desconeguda')
        if match.group(2):
            return self.send_json(Campaigns.export_doc(data,match.group(1)))
        errors,warnings=Campaigns.validate(ch,Campaigns.reference(),data['chapters'])
        return self.send_json({'campaign':ch,'errors':errors,'warnings':warnings})

    def campaigns_write(self,change):
        """change(data) → data nuevo; comprueba If-Match contra missions.json y deja copia en data/.history/."""
        with document_lock:
            expected=self.headers.get('If-Match')
            if not expected: raise APIError(428,'Cal carregar la versió abans de desar')
            if revision(Campaigns.MISSIONS)!=expected:
                raise APIError(409,'data/missions.json ha canviat (una altra pestanya o algú altre). Conserva el teu esborrany i torna a carregar.')
            try: data=Campaigns.load()
            except ValueError: raise APIError(503,'data/missions.json danyat: cal recuperar una còpia (data/.history/)')
            new=change(data)
            Campaigns.write(new)
            self.document_etag=revision(Campaigns.MISSIONS)
            return new

    @api_route
    def do_PUT(self):
        p=urlparse(self.path).path
        data=self.body_json()
        match=CAMPAIGN_RE.fullmatch(p)
        if match:
            if not isinstance(data,dict): raise APIError(400,'Cal una campanya')
            out={}
            def change(doc):
                new,errors,warnings=Campaigns.save_chapter(doc,match.group(1),data)
                if errors: raise APIError(400,'La campanya té errors: '+'; '.join(errors[:4])+(' …' if len(errors)>4 else ''))
                out['warnings']=warnings
                return new
            self.campaigns_write(change)
            return self.send_json({'ok':True,'warnings':out['warnings']})
        if p=='/api/config':
            c=clean_config(data); save_config(c)
            return self.send_json({'ok':True,'config':c})
        if p=='/api/npcs':
            path,err=NPCS,validate_npcs(data)
        elif p=='/api/map_edits':
            path,err=MAP_EDITS,validate_map_edits(data)
        else:
            match=re.fullmatch(r'/api/zones/([a-z0-9_]{2,40})',p)
            if not match: raise APIError(404,'Ruta desconeguda')
            path=os.path.join(ZONES,match.group(1)+'.json')
            err=validate_zone(data)
            if not err and data['id']!=match.group(1):err='Id no coincideix'
        if err: raise APIError(400,err)
        self.document_etag=write_document(path,data,self.headers.get('If-Match'))
        return self.send_json({'ok':True,'cells':len(data['cells'])} if p=='/api/map_edits' else {'ok':True})

    @api_route
    def do_DELETE(self):
        cmatch=CAMPAIGN_RE.fullmatch(urlparse(self.path).path)
        if cmatch:
            def change(doc):
                try: return Campaigns.delete_chapter(doc,cmatch.group(1))
                except KeyError: raise APIError(404,'Campanya desconeguda')
                except ValueError as e: raise APIError(400,str(e))
            self.campaigns_write(change)
            return self.send_json({'ok':True})
        match=re.fullmatch(r'/api/zones/([a-z0-9_]{2,40})',urlparse(self.path).path)
        if not match:raise APIError(404,'Ruta desconeguda')
        path=os.path.join(ZONES,match.group(1)+'.json')
        self.document_etag=write_document(path,None,self.headers.get('If-Match'),delete=True)
        return self.send_json({'ok':True})

    @api_route
    def do_POST(self):
        if urlparse(self.path).path == '/api/adult-check': return self.adult_login()
        if urlparse(self.path).path == '/api/npc_chat':
            try:
                req = self.body_json()
            except APIError:
                raise
            except Exception as e:  # noqa: BLE001
                return self.send_json({'error': 'JSON no vàlid'}, 400)
            error=validate_chat(req)
            if error: raise APIError(400,error)
            if not chat_allowed(self.client_address[0]):
                # massa preguntes seguides des d'un mateix aparell: frases fixes (protegeix la quota de Groq del hub)
                npc=public_npc((req.get('npc') or {}).get('id')) or {}
                say=[str(x)[:200] for x in (npc.get('say') or [])][:10]
                return self.send_json({'reply':random.choice(say) if say else 'Hola! Quin dia més bonic a Roda de Berà.',
                                       'options':DEFAULT_OPTIONS,'ai':False})
            return self.send_json(npc_chat(req))
        if urlparse(self.path).path == '/api/procgen':
            try:
                req = self.body_json() or {}
                kind = req.get('kind', 'house')
                if kind not in ('house', 'shop', 'block'):
                    raise ValueError('tipo desconocido')
                seed = int(req.get('seed') or random.randint(1, 10**9))
                out = subprocess.run(['luajit', os.path.join(ROOT, 'tools/procgen_cli.lua'), kind, str(seed)],
                                     capture_output=True, text=True, timeout=20, check=True).stdout
                return self.send_json(json.loads(out))
            except APIError:
                raise
            except Exception as e:  # noqa: BLE001
                return self.send_json({'error': 'No es pot generar'}, 400)
        if urlparse(self.path).path == '/api/sat2pixel':
            try:
                req = self.body_json() or {}
                sys.path.insert(0, os.path.join(ROOT, 'tools'))
                import sat2pixel
                w, h = int(req['w']), int(req['h'])
                if not (2 <= w <= 160 and 2 <= h <= 160):
                    raise ValueError('tamaño fuera de rango (2..160)')
                if req.get('image'):
                    img = sat2pixel.from_data_url(req['image'])
                else:
                    x, y = int(req['x']), int(req['y'])
                    if x < 0 or y < 0 or x + w > 1600 or y + h > 1600:
                        raise ValueError('fuera del mapa')
                    img = sat2pixel.pnoa_crop(x, y, w, h)
                tiles = json.load(open(os.path.join(ROOT, 'data/tiles.json')))['tiles']
                return self.send_json(sat2pixel.convert(img, w, h, tiles, seed=int(req.get('seed') or 7)))
            except APIError:
                raise
            except Exception as e:  # noqa: BLE001
                return self.send_json({'error': 'No es pot convertir'}, 400)
        if urlparse(self.path).path.startswith('/api/campaigns/'):
            return self.campaigns_post(urlparse(self.path).path)
        if urlparse(self.path).path in SYNC_PATHS:   # perfils entre aparells (només xarxa local)
            sp = urlparse(self.path).path
            if not local_client(self.client_address[0]):
                print(f'sync: {sp} rebutjat (fora de la xarxa de casa: {self.client_address[0]})', flush=True)
                return self.send_json({'error': 'Només a la xarxa de casa'}, 403)
            req = self.body_json()
            res = sync_request(sp, req)
            # registre curt per diagnosticar (sense dades del perfil): qui, quin jugador del hub i quants perfils
            owner = req.get('owner') if isinstance(req, dict) else None
            print(f'sync: {sp} des de {self.client_address[0]} jugador={str(owner or "local")[:8]} '
                  f'perfils={len(res.get("profiles", {})) if sp.endswith("pull") else "-"} '
                  f'host={self.headers.get("Host", "")[:60]} via={self.headers.get("X-Forwarded-For", "")[:40]}', flush=True)
            return self.send_json(res)
        if urlparse(self.path).path == '/api/config':   # el joc la llegeix en arrencar (sense PIN)
            self.body_json()
            return self.send_json(load_config())
        if urlparse(self.path).path == '/api/private_home':
            self.body_json()
            # la ubicación de casa solo se da dentro de la red local (si el puerto se abre a internet, no)
            if not local_client(self.client_address[0]):
                return self.send_json({}, 403)
            return self.send_json(private_home())
        if urlparse(self.path).path != '/api/publish':
            return self.send_json({'error': 'ruta'}, 404)
        with lock:
            if publish_state['running']:
                return self.send_json({'error': 'ya se está publicando'}, 409)
            publish_state.update(running=True, ok=None, log=[], started=time.time(), finished=None)
        threading.Thread(target=run_publish, daemon=True).start()
        return self.send_json({'ok': True})

    def campaigns_post(self,p):
        req=self.body_json()
        if not isinstance(req,dict): raise APIError(400,'Dades no vàlides')
        if p=='/api/campaigns/llm':
            return self.send_json(campaign_llm(req))
        with document_lock:
            data=Campaigns.load()
        if p in ('/api/campaigns/validate','/api/campaigns/import'):
            if p=='/api/campaigns/validate':
                ch,notes=req.get('campaign'),None
            else:
                base=req.get('base') if isinstance(req.get('base'),dict) else None
                try: ch,notes=Campaigns.parse_import(req.get('doc'),base)
                except (ValueError,TypeError,AttributeError) as e: raise APIError(400,'No es pot importar: '+str(e)[:200])
            if not isinstance(ch,dict): raise APIError(400,'Cal una campanya')
            own=req.get('id') or ch.get('id')
            others=[c for c in data.get('chapters',[]) if c.get('id')!=own]
            errors,warnings=Campaigns.validate(ch,Campaigns.reference(),others)
            _,old=Campaigns.find(data,ch.get('id'))
            if isinstance(req.get('base'),dict): old=req['base']
            return self.send_json({'campaign':ch,'notes':notes,'errors':errors,'warnings':warnings,
                                   'diff':Campaigns.diff(old,ch),'exists':old is not None})
        if p=='/api/campaigns/order':
            ids=req.get('ids')
            if not isinstance(ids,list): raise APIError(400,'Cal la llista ids')
            def change(doc):
                try: return Campaigns.reorder(doc,ids)
                except ValueError as e: raise APIError(400,str(e))
            self.campaigns_write(change)
            return self.send_json({'ok':True})
        raise APIError(404,'Ruta desconeguda')


def main():
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8102
    os.makedirs(ZONES, exist_ok=True)
    ThreadingHTTPServer.allow_reuse_address = True
    srv = ThreadingHTTPServer(('0.0.0.0', port), Handler)
    print(f'Roda RPG: juego en / y editor en /editor/ (puerto {port})', flush=True)
    srv.serve_forever()


if __name__ == '__main__':
    main()
