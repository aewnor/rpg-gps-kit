"""Vegetación mediterránea determinista; sirve en decorate_map y sobre un mapa ya decorado."""
import json
from pathlib import Path
from types import SimpleNamespace
import numpy as np
from scipy.ndimage import maximum_filter
from semantic import G


def enrich(m):
    props=m.tmj.setdefault('properties', [])
    if any(p['name']=='nature_version' and p['value']==1 for p in props):return {'already_enriched': True}
    forbidden=(m.d0!=0)|(m.bld!=0)|(m.coll!=0)
    safe=~maximum_filter(forbidden,size=5,mode='constant',cval=1)
    for o in m.objects:
        x,y=int(o['x']//16),int(o['y']//16)
        w,h=int(o.get('width',0)//16),int(o.get('height',0)//16)
        safe[max(0,y-3):min(m.H,y+h+4),max(0,x-3):min(m.W,x+w+4)]=False
    natural=np.isin(m.ground,[G[k] for k in ['FOREST','SCRUB','GRASS','PARK','DRY','ROCK','BEACH','WETLAND']])
    safe &= natural
    # superfícies fetes (patis d'escola, pistes, aparcaments, obres, places, sorrals): el terreny semàntic hi diu
    # PARK però la casella és pavimentada; cap arbre ni roca hi ha de caure (env6_cases: patis transitables)
    built=[t['id']+1 for n,t in m.tiles.items() if n.startswith(('g_yard','g_court','g_turf','g_pitch','g_parking',
           'g_site','g_skate','g_mini','g_cobble','g_sandpit'))]
    if 'ground' in m.L:
        safe &= ~maximum_filter(np.isin(m.L['ground']&0x1FFFFFFF,built),size=3,mode='constant',cval=0)
    S,O,D=m.L['structures'],m.L['overhead'],m.L['ground_detail']
    report={'trees':0,'shrubs':0,'rocks':0,'plants':0,'by_tile':{}}
    # Hash de coordenadas: independiente del orden de otras etapas del generador.
    yy,xx=np.indices((m.H,m.W),dtype=np.int64)
    hash_=(xx*73856093 ^ yy*19349663 ^ (xx//13)*83492791) % 1000003
    candidates=np.argwhere(safe & ((hash_%100)<12) & (S==0))
    for y,x in candidates:
        y,x=int(y),int(x);h=int(hash_[y,x]);ground=int(m.ground[y,x])
        forest=ground==G['FOREST'];green=ground in (G['GRASS'],G['PARK'])
        rocky=ground in (G['ROCK'],G['DRY'],G['SCRUB'],G['BEACH'])
        # Ningún sólido toca otro: el anillo de 8 celdas permanece libre.
        solid_ok=(not S[y-1:y+2,x-1:x+2].any() and not O[y-1:y+2,x-1:x+2].any()
                  and not m.coll[y-1:y+2,x-1:x+2].any())
        category=None;tile=None
        if solid_ok and h%100<3 and ground!=G['BEACH']:
            if forest or green:
                tree=('pine0','pine1','olive')[(h//101)%3]
                if green and h%11==0:tree='palm'
                tile='tree_'+tree+'_bot';S[y,x]=m.gid(tile);O[y-1,x]=m.gid('tree_'+tree+'_top');category='trees'
            elif rocky:
                tile='nature_rock_'+str((h//101)%3);S[y,x]=m.gid(tile);category='rocks'
            else:
                tile='bush_'+str((h//101)%2);S[y,x]=m.gid(tile);category='shrubs'
            m.coll[y,x]=1;m.placed[y,x]=True
        elif solid_ok and h%100==3 and ground!=G['BEACH']:
            tile='bush_'+str((h//101)%2);S[y,x]=m.gid(tile);m.coll[y,x]=1;m.placed[y,x]=True;category='shrubs'
        elif D[y,x]==0 and O[y,x]==0:
            names=('fern','mushrooms','grass') if forest else ('lavender','flowers','grass') if green else ('pebbles','grass','lavender')
            if ground==G['WETLAND']:names=('reeds',)
            if ground==G['BEACH']:names=('pebbles','grass')
            tile='nature_'+names[(h//101)%len(names)];D[y,x]=m.gid(tile);category='plants'
        if category:
            report[category]+=1;report['by_tile'][tile]=report['by_tile'].get(tile,0)+1
    props.append({'name':'nature_version','type':'int','value':1})
    return report


def main():
    root=Path(__file__).resolve().parents[1]
    path=root/'maps/source/overworld.tmj';tmj=json.loads(path.read_text())
    layers={l['name']:l for l in tmj['layers']};w,h=tmj['width'],tmj['height']
    arrays={k:np.array(layers[k]['data'],dtype=np.int64).reshape(h,w) for k in ['ground','ground_detail','structures','overhead','collision']}
    cf=tmj['tilesets'][1]['firstgid'];tiles=json.loads((root/'data/tiles.json').read_text())['tiles']
    sm=np.load(root/'maps/source/semantic.npz')
    m=SimpleNamespace(tmj=tmj,W=w,H=h,L=arrays,coll=np.where(arrays['collision']>0,arrays['collision']-cf,0),
      ground=sm['ground'],d0=sm['d0'],bld=sm['bld'],placed=np.zeros((h,w),bool),objects=layers['objects']['objects'],tiles=tiles)
    m.gid=lambda n:tiles[n]['id']+1
    import walkgraph
    before=walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    report=enrich(m)
    after=walkgraph.components_fast(m.coll.astype(np.uint8))[0]
    # Cada componente antigua conserva una sola componente nueva, descontando los sólidos nuevos.
    pairs=np.stack([before[m.coll==0],after[m.coll==0]],axis=1)
    unique=np.unique(pairs,axis=0)
    ids,counts=np.unique(unique[:,0],return_counts=True)
    assert not np.any(counts[ids>0]>1),'Nature disconnected walkable components'
    report['disconnected_components']=0
    for k in ['ground_detail','structures','overhead']:layers[k]['data']=arrays[k].ravel().tolist()
    layers['collision']['data']=(m.coll+cf).ravel().tolist()
    tmp=path.with_suffix('.nature.tmp');tmp.write_text(json.dumps(tmj,separators=(',',':')));tmp.replace(path)
    from decorate_map import Map
    Map.sync_tileset(m)
    (root/'maps/source/nature-report.json').write_text(json.dumps(report,indent=2))
    print(json.dumps(report))

if __name__=='__main__':main()
