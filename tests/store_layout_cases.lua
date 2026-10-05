local P=require('src.world.procgen')
local json=require('src.lib.json')
local f=assert(io.open('data/tiles.json')); local tiles=json.decode(f:read('*a')).tiles;f:close()
local Map=require('src.world.procmap')
for _,kind in ipairs({'super','diy'}) do
 for _,size in ipairs({{30,22},{48,32},{64,40}}) do
  local spec=P.store{kind=kind,size=size,seed=73,npc={service='shop',service_id=kind=='super' and 'bonpreu' or 'leroy'}}
  local m,warnings=Map.build('test',spec,tiles,{scene='overworld',x=0,y=0})
  assert(#warnings==0,table.concat(warnings,','))
  local component=m:component(spec.spawn[1],spec.spawn[2])
  local shelves,clients=0,0
  for _,o in ipairs(spec.objects) do
   if o.type=='display' then
    shelves=shelves+1
    local accessible=false
    for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do
     if m:component(o.x+d[1],o.y+d[2])==component then accessible=true end
    end
    assert(accessible,'unreachable shelf '..o.x..','..o.y)
   elseif o.type=='npc' and o.cart then
    clients=clients+1;assert(#o.route>=2,'shopper needs aisle route')
    for _,point in ipairs(o.route) do assert(m:component(point[1],point[2])==component,'unreachable route') end
   end
  end
  assert(shelves>=8,'missing interactive departments')
  assert(clients>=3,'missing customers with carts')
  for y=0,spec.h-1 do for x=0,spec.w-1 do
   if m:cell(x,y)==0 then assert(m:component(x,y)==component,'isolated floor') end
  end end
 end
end
print('Store layouts: reachable displays, cart routes and exits OK')
