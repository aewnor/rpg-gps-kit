local json=require('src.lib.json')
local function read(p)local f=assert(io.open(p));local s=f:read('*a');f:close();return json.decode(s) end
local items,loot=read('data/items.json'),read('data/loot.json')
local Loot=require('src.systems.loot')
for tier,t in pairs(loot) do if type(t)=='table' then
 local seen={};for _,e in ipairs(t.table) do assert(items[e[1]],e[1]);assert(not seen[e[1]],'duplicate '..tier..' '..e[1]);seen[e[1]]=true end
 local a,b=Loot.roll(loot,tier,'fixture'),Loot.roll(loot,tier,'fixture');assert(json.encode(a)==json.encode(b))
end end
local Motion=require('src.motion')
assert(Motion.chest_frame(0)==1);assert(Motion.chest_frame(.4)==5)
assert(Motion.stride(0)==0 and Motion.stride(8)==1 and Motion.stride(32)==0)
assert(Motion.chest_tier('iron','test')=='iron' or Motion.chest_tier('iron','test')=='roman')
Motion.reduced=true;assert(Motion.bob(1)==0);assert(Motion.chest_frame(0)==5);Motion.reduced=false
print('Variety and motion OK')
local Player=require('src.entities.player')
local Collision=require('src.world.collision')
local move,slide=Collision.move,Collision.slide_assist
local p=Player.new(0,0,0,{collider={10,8},speed=64,stamina=100,stamina_regen=10})
local ctx={state={equipment={}},items={}}
Collision.move=function()return false,false end
Collision.slide_assist=function()return 0,0 end
p:update(.1,{right=true},ctx);assert(not p.moving and p.anim==0,'feet must stop at walls')
assert(p.move_intent,'pushing a door must survive stopped walking animation')
p:update(.1,{},ctx);assert(not p.move_intent,'releasing controls stops pushing')
Collision.move=function(b,dx,dy)b.x=b.x+dx;b.y=b.y+dy;return true,true end
p:update(.1,{right=true},ctx);assert(p.moving and math.abs(p.anim-.1)<.00001)
Collision.move,Collision.slide_assist=move,slide
Motion.set('system',true);Motion.set('user',false);assert(Motion.reduced)
Motion.set('system',false);assert(not Motion.reduced)
print('Travel-based strides and combined motion preferences OK')
local counts={}
for id in pairs(read('data/scenes.json')) do
 local ok,m=pcall(dofile,'maps/runtime/'..id..'/index.lua')
 if ok then for _,o in ipairs(m.objects or {}) do
  if o.type=='chest' and not o.props.item then local t=Motion.chest_tier(o.props.tier or 'wood',o.props.flag or o.name);counts[t]=(counts[t] or 0)+1 end
 end end
end
local roda=(read('data/world.json').name or 'Roda de Berà')=='Roda de Berà'
for _,t in ipairs(roda and {'sea','forest','roman','crystal'} or {}) do assert(counts[t] and counts[t]>0,'unreachable chest family '..t) end
if not roda then local n=0 for _,c in pairs(counts) do n=n+c end assert(n>0,'no chests in the generated map') end
print('All four new chest families occur in the actual game')
