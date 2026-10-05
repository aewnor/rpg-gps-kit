"""Vista rápida de la rejilla semántica (depuración)."""
import sys, time
import numpy as np
from PIL import Image
from semantic import build, G, D
from osmlib import to_tile
t=time.time()
r = build('../cartography/municipio.osm.gz', '../cartography/limite.osm.gz')
print('build', round(time.time()-t,1), 's')
GC = {'DRY':(214,200,150),'GRASS':(150,190,100),'FOREST':(70,120,60),'SCRUB':(150,160,90),'FARM':(200,190,110),
'VINEYARD':(170,150,90),'URBAN':(220,215,205),'PARK':(130,190,110),'QUARRY':(180,170,160),'BEACH':(240,225,170),
'ROCK':(140,130,120),'SEA':(60,170,190),'WATER':(80,180,220),'RAILYARD':(170,160,150),'CEMETERY':(150,170,140),
'WETLAND':(110,160,140),'PITCH':(110,170,90),'VOID':(0,0,0)}
DC = {'STREAM':(120,160,200),'PATH':(180,140,90),'TRACK':(170,130,80),'STEPS':(200,120,90),'FOOTWAY':(235,230,220),
'PEDESTRIAN':(240,235,225),'ROAD':(120,120,125),'ROAD_MAIN':(90,90,95),'MOTORWAY':(200,80,60),'RAIL':(60,40,40),
'RAIL_HS':(120,40,120),'PLATFORM':(220,200,200),'PIER':(160,140,120),'LEVEL_CROSSING':(255,255,0),'PENDING':(255,0,255)}
img=np.zeros((640,640,3),np.uint8)
inv={v:k for k,v in G.items()}
for v,k in inv.items(): img[r['ground']==v]=GC[k]
invd={v:k for k,v in D.items()}
for v,k in invd.items():
    if k!='NONE': img[r['detail'][0]==v]=DC[k]
for lv,col in ((1,(255,140,0)),(-1,(0,220,255))):
    img[r['detail'][lv]>0]=col
img[r['bld']>0]=(190,90,60)
if r['limit'] is not None:
    lim=r['limit']; edge=lim ^ np.roll(lim,1,0) | lim ^ np.roll(lim,1,1); img[edge]=(255,0,0)
Image.fromarray(img).resize((1280,1280),Image.NEAREST).save(sys.argv[1] if len(sys.argv)>1 else '/tmp/claude-1000/sem.png')
print('buildings', len(r['binfo'])-1, 'crossings', r['crossings'])
print(to_tile(1.454242,41.186165))
