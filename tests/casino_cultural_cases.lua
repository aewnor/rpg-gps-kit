package.path='./?.lua;./?/init.lua;'..package.path
local M=require('src.minigames.init')
local old={day=4,minigames={day=4,tokens=9,bonus_tokens=8,roulette=true,trained={strength=true},circuit_best=12}}
local m=M.daily(old)
assert(m.tokens==nil and m.bonus_tokens==nil and m.roulette==nil,'retire legacy gambling balances')
assert(m.trained.strength and m.circuit_best==12,'preserve other progress')
assert(M.start({},'slots')==nil and M.start({},'roulette')==nil,'reject retired launch IDs')
assert(M.apply({},'slots',{}, {coins=999})==false,'reject legacy rewards')
local P=require('src.world.procgen')
local s=P.poi{kind='casino'}
local shows=0
for _,o in ipairs(s.objects) do if o.type=='arcade' then assert(o.game=='cinema');shows=shows+1 end end
assert(shows==2,'cinema and theatre')
for _,v in ipairs(s.structures) do assert(v~='i_slot' and not v:find('roulette')) end
local C=require('src.minigames.cinema')
for _,mode in ipairs({'cinema','theatre'}) do
 local c=C.new{mode=mode}
 for i=1,4 do c:update(.1,{pressed={confirm=true}}) end
 assert(c.done and c.result.finished and c.result.coins==nil)
 c=C.new{mode=mode};c:update(.1,{pressed={cancel=true}});assert(c.done and not c.result.finished)
end
local f=assert(io.open('data/tiles.json'));local tiles=require('src.lib.json').decode(f:read('*a')).tiles;f:close()
local blocked={}
for i,v in ipairs(s.structures) do if v~='' then assert(tiles[v],v);blocked[i]=tiles[v].solid end end
for _,o in ipairs(s.objects) do if o.type=='sign' or o.type=='npc' then blocked[o.y*s.w+o.x+1]=true end end
local queue={s.spawn};local seen={};local head=1
while queue[head] do
 local p=queue[head];head=head+1;local x,y=p[1],p[2];local i=y*s.w+x+1
 if x>=0 and y>=0 and x<s.w and y<s.h and not blocked[i] and not seen[i] then
  seen[i]=true
  for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do queue[#queue+1]={x+d[1],y+d[2]} end
 end
end
for _,o in ipairs(s.objects) do
 if o.type=='arcade' or o.type=='npc' or o.type=='sign' then
  local accessible=false
  for _,d in ipairs({{1,0},{-1,0},{0,1},{0,-1}}) do if seen[(o.y+d[2])*s.w+o.x+d[1]+1] then accessible=true end end
  assert(accessible,'reachable: '..(o.name or o.label or o.type))
 end
end
print('CASINO CULTURAL OK')
