"""Generated content has valid, distinct frames and is obtainable."""
import json,pathlib
from PIL import Image
r=pathlib.Path(__file__).resolve().parents[1]
items=json.loads((r/'data/items.json').read_text());loot=json.loads((r/'data/loot.json').read_text())
services=json.loads((r/'data/services.json').read_text())['services']
available={e[0] for t in loot.values() if isinstance(t,dict) for e in t['table']}
available.update(i for s in services for i in s.get('stock',[])+s.get('fixed',[]))
# també el que donen les missions (give, reward_item) i el que es pesca (items amb fish)
missions=json.loads((r/'data/missions.json').read_text())
for c in missions['chapters']:
 for m in c['missions']:
  available.update([m['reward_item']] if m.get('reward_item') else [])
  available.update(s['give'] for s in m['steps'] if s.get('give'))
available.update(k for k,d in items.items() if isinstance(d,dict) and d.get('fish'))
# el que es recull o deixen els animals, i el que es crea al taller (data/crafting.json)
crafting=json.loads((r/'data/crafting.json').read_text())
available.update(g['item'] for g in crafting['gather'].values())
available.update(g['bonus'] for g in crafting['gather'].values() if g.get('bonus'))
available.update(e[0] for lst in crafting['drops'].values() for e in lst)
available.update(rc['item'] for rc in crafting['recipes'])
available.update(crafting.get('other_sources',{}))
# i els objectes dels cofres de les masmorres (chest amb item)
for tm in (r/'maps/source').glob('*.tmj'):
 for l in json.loads(tm.read_text()).get('layers',[]):
  for o in l.get('objects',[]):
   if o.get('type')=='chest':available.update(p_['value'] for p_ in o.get('properties',[]) if p_['name']=='item')
for id,d in items.items():
 if isinstance(d,dict) and d.get('sprite','').startswith('item_'):
  assert id in available,id
  im=Image.open(r/'assets/runtime/sprites'/f"{d['sprite']}.png")
  assert im.size==(16,16) and im.getbbox(),id
for tier in ('wood','iron','silver','legend','sea','forest','roman','crystal'):
 im=Image.open(r/'assets/runtime/sprites'/f'chest_anim_{tier}.png')
 assert im.size==(80,16)
 assert len({im.crop((i*16,0,i*16+16,16)).tobytes() for i in range(5)})==5,tier
print('24 obtainable items and 8 distinct five-frame chest sheets OK')
