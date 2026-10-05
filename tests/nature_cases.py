import sys, copy
from pathlib import Path
import numpy as np
from scipy.ndimage import label
sys.path.insert(0,str(Path(__file__).resolve().parents[1]/'tools'))
from nature import enrich
from semantic import G
from types import SimpleNamespace

def world():
    w=h=120
    names=['tree_pine0_bot','tree_pine0_top','tree_pine1_bot','tree_pine1_top','tree_olive_bot','tree_olive_top','tree_palm_bot','tree_palm_top','bush_0','bush_1']+[f'nature_{n}' for n in ['lavender','flowers','grass','fern','reeds','mushrooms','pebbles','rock_0','rock_1','rock_2']]
    tiles={n:{'id':i} for i,n in enumerate(names)}
    m=SimpleNamespace(W=w,H=h,L={n:np.zeros((h,w),np.int64) for n in ['ground_detail','structures','overhead']},
      coll=np.zeros((h,w),np.int64),placed=np.zeros((h,w),bool),d0=np.zeros((h,w),np.int64),bld=np.zeros((h,w),np.int64),
      ground=np.full((h,w),G['FOREST']),objects=[{'x':50*16,'y':50*16,'type':'door','width':0,'height':0}],tmj={},tiles=tiles)
    m.gid=lambda n:tiles[n]['id']+1
    m.ground[:,65:]=G['SCRUB'];m.d0[:,60]=7;m.bld[80:86,30:36]=1
    return m
m=world();original=m.coll.copy();r=enrich(m)
assert r['trees']>10 and r['plants']>10 and r['rocks']>0,r
assert not m.L['structures'][:,58:63].any(),'road clearance'
assert not m.L['structures'][47:54,47:54].any(),'door clearance'
assert not m.L['ground_detail'][47:54,47:54].any(),'door plants'
assert label(m.coll==0)[1]==1,'nature must not cut paths'
other=world();enrich(other)
for k in m.L:assert np.array_equal(m.L[k],other.L[k]),'deterministic '+k
before=copy.deepcopy(m.L);enrich(m)
for k in m.L:assert np.array_equal(before[k],m.L[k]),'idempotence '+k
print('Nature: deterministic, repeatable, clear roads/doors, connected walking area',r)
