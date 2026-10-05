return function(api)
 local g=api.scene().game
 local Services=require('src.systems.services')
 local Collision=require('src.world.collision')
 api.talk_through()
 for _,id in ipairs({'bonpreu','leroy'}) do
  local sv=Services.spec(g,id)
  local n={sprite=sv.sprite,name=sv.name,service=sv.kind,service_id=id,label=sv.label}
  local sid=g:poi_interior(id,Services.POI_KIND[id],{scene='overworld',x=600*16,y=800*16},n,Services.STORE_SIZE[id])
  g:change(sid,'spawn_in');api.wait(90)
  local w=api.scene()
  local client
  for _,v in ipairs(w.npcs) do if v.props.cart then client=v;break end end
  api.check(client~=nil,id..': client amb carro')
  local y=client.body.y
  api.wait(240)
  api.check(math.abs(client.body.y-y)>1,id..': el client recorre el passadís')
  api.check(Collision.walk_at(w.map:cell(math.floor(client.body.x/16),math.floor(client.body.y/16)),0),id..': carro fora de prestatgeries')
  local display
  for _,v in ipairs(w.signs) do if v.props.section==(id=='bonpreu' and 'Fruita i verdura' or 'Il·luminació') then display=v;break end end
  api.check(display~=nil,id..': expositor interactiu')
  local captured
  local old=g.open_list
  g.open_list=function(_,title,entries) captured=entries end
  Services.display(w,display.props)
  g.open_list=old
  local item=id=='bonpreu' and 'poma' or 'llanterna'
  local price=g.items[item].price
  w.state.coins=100
  local before=w.state.inventory[item] or 0
  api.check(#captured>=3,id..': expositor amb productes i inspecció')
  captured[1][2]()
  api.check(w.state.inventory[item]==before+1 and w.state.coins==100-price,id..': compra cobra i entrega una unitat')
  w.state.coins=0
  captured[1][2]()
  api.check(w.state.inventory[item]==before+1 and w.state.coins==0,id..': sense diners no entrega ni cobra')
  -- Acció real davant de l'expositor, incloent el botó compartit amb el mòbil.
  w.player.body.x,w.player.body.y=display.x+16,display.y
  w.player.facing='left';g:close_menu()
  api.check(w:interact(),id..': botó interactuar respon a la prestatgeria')
  g:close_menu();api.wait(240)
  local done=false
  love.graphics.captureScreenshot(function(d)d:encode('png','store_detail_'..id..'.png');done=true end)
  for _=1,100 do if done then break end;api.wait(1) end
 end
end
