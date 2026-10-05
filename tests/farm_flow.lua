-- Granges (love . --test=tests/farm_flow.lua --mute): el pagès dona pinso, els animals passegen pel corral,
-- mengen contents i les gallines ponen un ou; la missió «Un dia a la granja». Desa granja.png.
return function(api)
  local Farm = require('src.systems.farm')
  local Missions = require('src.systems.missions')
  local Town = require('src.systems.town')
  local g = api.scene().game
  local w = api.scene()
  local st = api.state()
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local defs = Town.defs(g)
  local q = Missions.state(st)
  q.active = nil
  Missions.activate(defs, st, 'granja_dia', Town.hooks(w))
  api.wait(3); api.talk_through()
  api.check(w.farm and #w.farm.animals >= 20, 'animals a les granges (' .. (w.farm and #w.farm.animals or 0) .. ')')
  local spot = w.map:object('spot', 'granja_1')
  api.check(spot ~= nil, 'la Granja del Ruc és a la brúixola')
  local farmer
  for _, n in ipairs(w.npcs) do if n.props.farmer == 'Granja del Ruc' then farmer = n end end
  api.check(farmer ~= nil, 'hi ha el pagès')
  if not (spot and farmer) then return end
  api.teleport(math.floor(farmer.body.x / 16), math.floor(farmer.body.y / 16) + 1)
  api.player().facing = 'up'
  api.wait(5)
  api.press('confirm'); api.wait(5); api.talk_through()
  api.check((st.inventory.pinso or 0) == Farm.PINSO_DAY, 'el pagès dona ' .. Farm.PINSO_DAY .. ' grapats de pinso')
  api.press('confirm'); api.wait(5); api.talk_through()
  api.check((st.inventory.pinso or 0) == Farm.PINSO_DAY, 'el mateix dia no en torna a donar')
  -- els animals es mouen dins el corral
  local a1
  local pos = {}
  for _, a in ipairs(w.farm.animals) do
    if a.farm == 'Granja del Ruc' and not a.loose then a1 = a1 or a; pos[a] = { a.x, a.y } end
  end
  api.wait(400)
  local inside = a1.x >= a1.pen.x and a1.x <= a1.pen.x + a1.pen.w and a1.y >= a1.pen.y and a1.y <= a1.pen.y + a1.pen.h
  api.check(inside, 'els animals no surten del corral')
  -- (l'atzar és per hora: un animal sol pot haver estat quiet tota l'estona; tots alhora, no)
  local moved = 0
  for a, p in pairs(pos) do if a.x ~= p[1] or a.y ~= p[2] or a.state ~= 'idle' then moved = moved + 1 end end
  api.check(moved > 0, 'els animals passegen i mengen (' .. moved .. ')')
  -- donar menjar a tres espècies i a una gallina
  local fed = {}
  for _, a in ipairs(w.farm.animals) do
    if a.farm == 'Granja del Ruc' and not fed[a.kind] and (st.inventory.pinso or 0) > 0 then
      fed[a.kind] = true
      Farm.interact(w, a.x, a.y - 6)
      api.wait(3); api.talk_through()
    end
  end
  api.check(fed.gallina and (st.inventory.ou or 0) >= 1, 'la gallina ha post un ou')
  api.check(q.done.granja_dia, 'missió «Un dia a la granja» feta')
  -- ja tips
  local a = w.farm.animals[1]
  local before = st.inventory.pinso or 0
  Farm.interact(w, a.x, a.y - 6); api.wait(3); api.talk_through()
  api.check(a.fed <= 0 or (st.inventory.pinso or 0) == before, 'un animal tip no torna a menjar')
  api.teleport(math.floor(a1.pen.x / 16) + 3, math.floor((a1.pen.y + a1.pen.h) / 16) + 2)
  api.wait(200)
  local done = false
  love.graphics.captureScreenshot(function(d) d:encode('png', 'granja.png'); done = true end)
  for _ = 1, 100 do if done then break end; api.wait(1) end
  api.on_frame = nil
end
