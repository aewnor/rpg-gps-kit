-- Native rendered smoke: fixtures in memory, no household writes/provider calls.
return function(api)
 local g=api.scene().game
 local Rpg=require('src.systems.rpg')
 local Motion=require('src.motion')
 local Input=require('src.input')
 local p={body={x=0,y=0},moving=false,move_intent=true}
local World=require('src.scenes.world_scene')
local entered=false
local facade=setmetatable({player=p,facade_ahead=function()return 2,3,'door' end,
 enter_facade=function()entered=true end},{__index=World})
for _=1,15 do facade:check_facade_door() end
api.check(entered,'pushing a facade enters even with stationary feet')
 for _,id in ipairs({'bruna_jardinera','nil_ferrer','ona_musica','roc_miner','aina_marina','pau_cuiner'}) do
  local found=false
  for _,n in ipairs(api.scene().npcs) do if n.name=='npc_'..id then found=true end end
  api.check(found,'new character present: '..id)
 end
 g.state.char_level=10
 for id,it in pairs(g.items) do
  if type(it)=='table' and it.sprite and it.sprite:match('^item_') then
   g.state.inventory[id]=1
   api.check(g:special_sprite(it.sprite)~=nil,'icon '..id)
   if it.kind=='weapon' then
    api.check(Rpg.equip(g.state,g.items,id),'equip '..id)
    api.player().stamina=100
    Input.press('attack');api.wait(8)
    love.graphics.captureScreenshot(function(d)d:encode('png','weapon-'..id..'.png')end)
    api.wait(45)
   end
  end
 end
 for name in pairs(require('src.data').read_json('data/variety.json').characters) do
  api.check(g.sprites.chars[name]~=nil,'character '..name)
 end
 g:change('cova_pedrera','spawn_entrance');api.wait(40)
 local w=api.scene();local c=w.chests[1]
 api.check(c~=nil,'chest in cave')
 c.open_t=0;w.sstate.chests[c.obj.props.flag]=true
 api.player().body.x=c.rect.x+8;api.player().body.y=c.rect.y+30
 for i=1,8 do api.wait(2);love.graphics.captureScreenshot(function(d)d:encode('png','chest-'..i..'.png')end) end
 Motion.set('user',true);api.wait(3);api.check(w.shaker:offset()==0,'reduced camera')
 Motion.set('user',false)
 for _,id in ipairs({'cinema','rhythm','penalties','circuit','recycle'}) do
  require('src.minigames.init').start(g,id,{})
  api.wait(16)
  love.graphics.captureScreenshot(function(d)d:encode('png','minigame-'..id..'.png')end)
  api.wait(2);g.minigame=nil
 end
 print('[variety] rendered weapons, characters, chest, minigames and reduced motion')
end
