#!/usr/bin/env python3
"""Original pixel assets for the content expansion. No downloads or paid generators."""
import json, pathlib
from PIL import Image, ImageDraw
from pixel import PALETTE, sheet
import chars
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'assets/runtime/sprites'
def color(k):return PALETTE[k]
def canvas():
 im=Image.new('RGBA',(16,16));return im,ImageDraw.Draw(im)
def rect(d,xy,c):d.rectangle(xy,fill=color(c),outline=color('ink'))
items=json.loads((ROOT/'data/items.json').read_text())
for key,it in items.items():
 if not isinstance(it,dict) or not it.get('sprite','').startswith('item_'):continue
 im,d=canvas();c=it.get('color','ochre');kind=it['kind'];style=it.get('visual','sword')
 if kind=='weapon':
  d.line((7,14,7,4),fill=color('ink'),width=3);d.line((7,14,7,4),fill=color('ochre2'))
  if style in ('sword','sabre','dagger'):
   d.polygon([(6,10),(6,4 if style=='dagger' else 1),(8,0 if style!='dagger' else 3),(9,7),(8,10)],fill=color(c),outline=color('ink'));d.line((7,3,7,9),fill=color('white'));rect(d,(4,10,10,11),'ochre')
  elif style=='spear':d.polygon([(7,0),(10,5),(7,7),(4,5)],fill=color(c),outline=color('ink'));d.point((7,2),fill=color('white'))
  elif style=='hammer':rect(d,(2,1,13,6),'stone3');rect(d,(3,1,12,4),c)
  elif style=='axe':d.polygon([(6,1),(12,2),(14,6),(9,8),(6,5)],fill=color(c),outline=color('ink'));d.line((12,2,14,6,9,8),fill=color('white'))
  else:d.ellipse((3,0,11,7),fill=color(c),outline=color('ink'));d.line((5,2,8,2),fill=color('white'))
 elif kind=='shield':d.polygon([(2,2),(13,2),(12,10),(8,15),(3,11)],fill=color(c),outline=color('ink'));d.line((7,4,7,12),fill=color('white2'));d.line((4,7,10,7),fill=color('ochre'))
 elif kind in ('armor','clothes'):d.polygon([(5,1),(10,1),(14,5),(11,8),(10,6),(11,14),(4,14),(5,6),(3,8),(1,5)],fill=color(c),outline=color('ink'));d.line((7,3,7,13),fill=color('white2'));rect(d,(4,10,11,11),'ochre3')
 elif kind=='helmet':d.pieslice((2,1,13,14),180,360,fill=color(c),outline=color('ink'));rect(d,(1,7,14,9),c);d.point((6,3),fill=color('white'))
 elif style=='egg':   # ou de les gallines de la granja (src/systems/farm.lua)
  d.ellipse((4,2,12,14),fill=color(c),outline=color('ink'));d.point((6,5),fill=color('white'));d.line((9,11,10,9),fill=color('white3'))
 elif style=='sack':   # sac de pinso
  d.polygon([(3,4),(12,4),(14,14),(1,14)],fill=color(c),outline=color('ink'));d.line((5,4,7,1,9,1,10,4),fill=color('ochre3'))
  for x,y in ((5,9),(8,11),(10,8),(6,12)):d.point((x,y),fill=color('ochre'))
 elif style=='radio':
  rect(d,(1,5,14,14),'sea');d.line((3,5,3,1,10,1),fill=color('stone3'),width=1)
  d.ellipse((3,7,8,12),fill=color('ink'));rect(d,(10,7,12,9),'white2');d.point((11,11),fill=color('ochre'))
 elif kind=='food':
  if key in ('mel_bosc','suc_raim'):rect(d,(4,4,11,14),c);rect(d,(5,1,10,4),'ochre3');rect(d,(5,7,10,10),'white2')
  elif key=='sopa_peix':d.ellipse((1,4,14,14),fill=color('white2'),outline=color('ink'));d.ellipse((2,4,13,10),fill=color('terra'));d.line((4,7,10,7),fill=color('ochre'))
  else:d.ellipse((3,4,13,14),fill=color(c),outline=color('ink'));d.line((7,4,9,1,12,2),fill=color('pine2'));d.point((5,6),fill=color('white2'))
 elif style=='fish':   # peixos de la pesca (src/systems/fishing.lua): cos, cua, aleta i ull
  d.polygon([(1,8),(4,4),(10,4),(13,8),(10,12),(4,12)],fill=color(c),outline=color('ink'))
  d.polygon([(12,8),(15,4),(15,12)],fill=color(c),outline=color('ink'))
  d.line((5,6,9,6),fill=color('white'));d.point((4,7),fill=color('ink'));d.line((7,12,9,14),fill=color(it.get('color2',c)))
 elif style=='squid':
  d.ellipse((4,1,11,9),fill=color(c),outline=color('ink'))
  for x in (4,6,8,10):d.line((x+1,9,x,14),fill=color(c))
  d.point((6,5),fill=color('ink'));d.point((9,5),fill=color('ink'))
 elif style=='crab':
  d.ellipse((3,5,12,12),fill=color(c),outline=color('ink'))
  d.line((3,8,0,4),fill=color('ink'));d.line((12,8,15,4),fill=color('ink'));rect(d,(0,2,2,4),c);rect(d,(13,2,15,4),c)
  d.point((6,7),fill=color('white'));d.point((9,7),fill=color('white'))
 elif style=='boot':
  rect(d,(4,1,9,10),c);rect(d,(4,10,14,14),c);d.line((5,4,8,4),fill=color('ochre3'));d.point((12,11),fill=color('sea2'))
 elif style=='key':
  d.ellipse((1,1,7,7),fill=color(c),outline=color('ink'));d.ellipse((3,3,5,5),fill=color('ink'))
  d.line((6,6,14,14),fill=color('ink'),width=3);d.line((6,6,14,14),fill=color(c));d.line((11,11,13,9),fill=color(c),width=2)
 elif style=='amulet':
  d.arc((3,0,12,9),200,340,fill=color('ochre3'));d.line((4,4,7,9),fill=color('ochre3'));d.line((11,4,8,9),fill=color('ochre3'))
  d.ellipse((4,8,11,15),fill=color(c),outline=color('ink'));d.ellipse((6,10,9,13),fill=color('white'));d.point((7,11),fill=color('sea'))
 elif style=='rod':
  d.line((2,15,13,1),fill=color('ochre3'),width=2);d.line((2,15,13,1),fill=color('ochre2'))
  d.ellipse((3,10,7,14),fill=color('stone2'),outline=color('ink'));d.line((13,1,14,9),fill=color('white'))
  rect(d,(13,9,15,11),'red')
 elif style=='log':   # materials del taller (data/crafting.json)
  rect(d,(1,5,14,11),c);d.ellipse((11,5,15,11),fill=color('sand'),outline=color('ink'));d.ellipse((12,7,14,9),outline=color('ochre3'))
  d.line((2,7,10,7),fill=color('ochre3'));d.line((3,9,9,9),fill=color('ochre3'))
 elif style=='fibre':
  for x in (4,7,10):d.line((x,14,x+2,2),fill=color(c),width=2)
  d.line((3,10,13,10),fill=color('ochre2'),width=2)
 elif style=='stone':
  d.polygon([(2,10),(4,5),(9,3),(13,6),(14,11),(9,14),(4,13)],fill=color(c),outline=color('ink'));d.line((5,7,8,5),fill=color('white2'))
 elif style=='ore':
  d.polygon([(2,10),(4,5),(9,3),(13,6),(14,11),(9,14),(4,13)],fill=color('stone2'),outline=color('ink'))
  for x,y in ((6,7),(9,10),(10,6)):rect(d,(x,y,x+1,y+1),'asph2');d.point((x,y),fill=color('white'))
 elif style=='pelt':
  d.polygon([(3,3),(12,3),(14,7),(12,13),(8,11),(3,13),(1,7)],fill=color(c),outline=color('ink'));d.line((5,6,10,6),fill=color('white2'));d.line((4,9,11,9),fill=color('stone'))
 elif style=='leather':
  rect(d,(2,3,13,12),c);d.line((3,5,12,5),fill=color('terra3'));d.line((3,10,12,10),fill=color('terra3'));d.point((4,4),fill=color('sand'))
 else:
  if key=='ploma':d.polygon([(12,1),(13,5),(4,13),(6,6)],fill=color(c),outline=color('ink'));d.line((3,14,11,3),fill=color('stone3'))
  elif key=='rajola_romana':rect(d,(2,2,13,13),c);rect(d,(5,5,10,10),'terra');d.point((7,7),fill=color('white'))
  elif key=='fossil':d.ellipse((2,2,13,13),fill=color(c),outline=color('ink'));d.arc((4,4,11,11),0,300,fill=color('ochre3'));d.arc((6,6,9,9),0,270,fill=color('ochre3'))
  else:d.polygon([(7,1),(12,5),(11,11),(5,14),(2,8)],fill=color(c),outline=color('ink'));d.line((7,3,5,8,6,11),fill=color('white'))
 im.save(OUT/(it['sprite']+'.png'))
variety=json.loads((ROOT/'data/variety.json').read_text())
for name,spec in variety['characters'].items():sheet(chars.sheet_frames(spec),6).image().save(OUT/(name+'.png'))
for tier,c,band in [('wood','ochre2','ochre3'),('iron','asph2','stone'),('silver','white2','sea2'),('legend','ochre','terra3'),('sea','sea2','sand'),('forest','pine2','ochre3'),('roman','terra2','ochre'),('crystal','sea','white')]:
 frames=[]
 for phase in range(5):
  im,d=canvas();rect(d,(1,7,14,14),c);rect(d,(3,8,4,13),band);rect(d,(11,8,12,13),band)
  d.rectangle((2,7,13,8),fill=color('ink'))
  lid_y=[5,4,2,1,1][phase];lid_h=[5,4,3,3,2][phase]
  rect(d,(1,lid_y,14,lid_y+lid_h),c);d.line((2,lid_y+1,13,lid_y+1),fill=color(band))
  rect(d,(7,8 if phase==0 else lid_y+1,8,10 if phase==0 else lid_y+2),'ochre')
  if tier=='sea':d.line((3,12,5,11,7,12,9,11,11,12),fill=color('white2'))
  elif tier=='forest':d.line((2,12,6,9,10,12),fill=color('pine'))
  elif tier=='roman':d.line((5,12,5,10,9,10,9,12),fill=color('sand'))
  elif tier=='crystal':d.polygon([(7,9),(10,11),(7,14),(5,11)],fill=color('white'))
  frames.append(im)
 atlas=Image.new('RGBA',(80,16))
 for i,im in enumerate(frames):atlas.paste(im,(i*16,0))
 atlas.save(OUT/('chest_anim_'+tier+'.png'))
for name in variety['props']:
 im,d=canvas()
 if name=='barrel':rect(d,(3,2,12,14),'ochre2');d.line((3,5,12,5),fill=color('asph3'));d.line((3,11,12,11),fill=color('asph3'))
 elif name=='crate':rect(d,(1,3,14,14),'ochre2');d.line((2,4,13,13,13,4,2,13),fill=color('ochre3'))
 elif name=='flowers':rect(d,(4,10,11,15),'terra2');d.line((7,11,7,3),fill=color('pine2'));d.ellipse((3,2,10,7),fill=color('ochre'));d.point((7,4),fill=color('terra'))
 elif name=='amphora':d.ellipse((3,4,12,14),fill=color('terra'),outline=color('ink'));rect(d,(5,1,10,5),'terra2');d.arc((0,3,6,10),70,270,fill=color('ochre3'));d.arc((9,3,15,10),270,90,fill=color('ochre3'))
 elif name=='lantern':rect(d,(4,4,11,13),'ochre');rect(d,(3,2,12,4),'asph3');d.arc((5,0,10,5),180,360,fill=color('ink'));d.line((7,6,7,11),fill=color('white'))
 else:
  for x,y in [(3,7),(9,4)]:rect(d,(x+1,y+3,x+3,y+7),'white2');d.pieslice((x-1,y-1,x+5,y+5),180,360,fill=color('terra'),outline=color('ink'));d.point((x+1,y),fill=color('white'))
 im.save(OUT/('prop_'+name+'.png'))
print('Variety assets generated')
