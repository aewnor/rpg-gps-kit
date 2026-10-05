return function(api)
 local g=api.scene().game
 local P=require('src.profile')
 local UI=require('src.ui.profiles')
 local p=P.new('Prova','nena')
 api.talk_through()
 for _,kind in ipairs({'house','block'}) do
  local f=P.new_friend(p,kind=='house' and 'avia' or 'avi')
  f.home={door_x=90,door_y=40};f.interior.kind=kind
  f.interior.cat=true;f.interior.dog=true
  g.sprites.chars['friend_'..f.id]=g.sprites.chars.npc_elder
  g.state.clock=12*60;g.state.day=3
  local id=g:friend_interior(f,{scene='overworld',x=100,y=100,level=0})
  if kind=='block' then id=require('src.world.procgen').flat_id(id,1,1) end
  local spec=g.generated[id].spec
  local pets,parents,occupied={},0,{}
  for _,o in ipairs(spec.objects) do
   if o.type=='npc' then
    local key=o.x..','..o.y
    api.check(not occupied[key],kind..': habitants en caselles diferents');occupied[key]=true
    if o.parent then parents=parents+1 end
    pets[o.sprite]=o
   end
  end
  api.check(parents==0,kind..': avis sense pares')
  api.check(pets.npc_dog and pets.npc_cat_orange,kind..': gos i gat junts')
  g.scene_manager:change(id,'spawn_in');api.wait(70)
  local w=api.scene();local dog
  for _,n in ipairs(w.npcs) do if n.props.sprite=='npc_dog' then dog=n end end
  api.check(dog and dog.sprite.height==16,kind..': gos renderitzat amb sprite propi')
  w.player.body.x,w.player.body.y=dog.body.x,dog.body.y+15;w.player.facing='up'
  api.check(w:interact() and w.dialogue.open,kind..': es pot saludar el gos')
  api.talk_through();api.wait(120)
  local done=false
  love.graphics.captureScreenshot(function(d)d:encode('png','pets_'..kind..'.png');done=true end)
  for _=1,100 do if done then break end;api.wait(1) end
  f.interior.dog=false
  g:friend_interior(f,{scene='overworld',x=100,y=100,level=0})
  local count=0
  for _,o in ipairs(g.generated[id].spec.objects) do if o.sprite=='npc_dog' then count=count+1 end end
  api.check(count==0,kind..': desactivar el gos el treu de casa')
 end
end
