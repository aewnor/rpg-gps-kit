-- Missions evolutives al joc (love . --test=tests/epic_flow.lua --mute): objectius nous a la brúixola
-- (spot:, chest:), entrar a la cova completa el pas, pujar de nivell activa la següent missió, i vèncer el drac
-- compta per a la missió del drac.
return function(api)
  local game = api.scene().game
  local Town = require('src.systems.town')
  local Missions = require('src.systems.missions')
  local st = game.state
  game.dev.turbo = 1
  api.wait(5)
  local w = api.scene()
  local defs = Town.defs(game)
  local q = Missions.state(st)
  local c = Town.resolve(w, 'spot:cova_roda')
  api.check(c and math.abs(c.x / 16 - 320) < 4, 'la brúixola sap on és la Cova de Roda')
  api.check(Town.resolve(w, 'chest:cofre_escut_roda') ~= nil, 'i el cofre de l\'escut (Ermita de Berà)')
  api.check(Town.resolve(w, 'spot:cau_drac') ~= nil, 'i el cim del drac')
  -- capítols previs fets
  for _, ch in ipairs(defs.chapters) do
    if ch.id ~= 'drac' then for _, m in ipairs(ch.missions) do q.done[m.id] = true end end
  end
  q.active = nil
  q.done.llums = true   -- (ja ha parlat amb la Policia de les llums)
  st.char_level = 3
  Missions.activate(defs, st, 'cova', Town.hooks(w))
  api.wait(20)
  local T = w.town
  api.check(T.target and T.text and T.text:find('Cova'), 'missió activa: fletxa cap a la cova (' .. tostring(T.text) .. ')')
  st.inventory.llanterna = 1
  game:change('cova_roda_1', 'spawn_entrance')
  api.wait(90)
  api.check(q.done.cova, 'entrar a la cova completa «La Cova de Roda»')
  api.check(q.active == 'fons', 'i comença «El fons de la cova»')
  api.wait(10); api.talk_through()     -- la introducció de la missió nova
  st.inventory.baston_magic, st.inventory.cristall_drac = 1, 1
  api.wait(40); api.talk_through()
  api.check(q.done.fons and q.active == 'fort', 'amb el bastó i el cristall: «Fes-te fort»')
  local Rpg = require('src.systems.rpg')
  while st.char_level < 5 do api.scene():reward(st.next_xp, 0) end
  api.wait(40); api.talk_through()
  api.check(q.done.fort and q.active == 'cim', 'nivell 5: «Puja al cim» (' .. tostring(q.active) .. ')')
  q.done.cim = true
  Missions.activate(defs, st, 'drac', Town.hooks(api.scene()))
  st.inventory.cristall_drac = 1
  game:change('cau_drac', 'spawn_entrance')
  api.wait(90)
  local boss = api.scene().boss
  api.check(boss ~= nil, 'el drac és al cau')
  if boss then
    boss:damage(999, boss.body.x, boss.body.y + 10)
    api.scene():enemy_event(boss, 'dead')
    api.wait(5)
  end
  api.check(q.done.drac and q.active == 'heroi', 'vèncer el drac: «Explica-ho al poble»')
  api.talk_through()
  game:change('cau_drac', 'spawn_entrance')
  api.wait(90)
  api.check(api.scene().boss == nil, 'un cop vençut, el drac ja no torna')
end
