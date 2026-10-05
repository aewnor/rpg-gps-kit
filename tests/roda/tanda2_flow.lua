-- Pesca, Classe de màgia, encanteris nous, vehicles nous del trànsit i velers
-- (love . --test=tests/tanda2_flow.lua --mute). Desa pesca.png, classe.png, transit.png i velers.png.
return function(api)
  local g = api.scene().game
  local State = require('src.state')
  local Fishing = require('src.systems.fishing')
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  api.talk_through()
  api.on_frame = function()   -- els avisos de missió no han d'aturar la prova
    local d = api.scene().dialogue
    if d.open and not api.keep_dialogue then d.open = false; if d.on_close then d.on_close() end end
  end
  local w = api.scene()
  local st = api.state()
  g.config.temps = 'sol'

  -- 1) pesca al port: una casella transitable mirant l'aigua del port
  State.give(st, Fishing.ROD)
  local spot
  for ty = 1255, 1275 do
    for tx = 1245, 1270 do
      if not spot and w.map:cell(tx, ty) == 0 and w.map:cell(tx + 1, ty) % 4 == 2 and w.map:cell(tx + 2, ty) % 4 == 2 then
        spot = { tx, ty }
      end
    end
  end
  api.check(spot ~= nil, 'hi ha un lloc per pescar al port')
  if spot then
    local pl = api.player()
    pl.body.x, pl.body.y, pl.body.level = spot[1] * 16 + 8, spot[2] * 16 + 10, 0
    pl.facing = 'right'
    api.wait(5)
    api.check(Fishing.try_start(w), 'amb la canya, mirant el mar, es llança l\'ham')
    w.fishing.wait = 0.6
    api.check(w.fishing.spot == 'port', 'el lloc és el port')
    for _ = 1, 120 do if w.fishing and w.fishing.phase == 'bite' then break end; api.wait(1) end
    api.check(w.fishing and w.fishing.phase == 'bite', 'el peix pica')
    shot('pesca.png')
    api.keep_dialogue = true
    api.press('confirm')
    api.wait(3)
    local caught
    for id in pairs(st.fish_log or {}) do caught = id end
    api.check(caught ~= nil and (st.inventory[caught] or 0) >= 1, 'has pescat: ' .. tostring(caught))
    api.wait(20)
    api.keep_dialogue = false
    api.talk_through()
    -- massa aviat: s'espanta
    Fishing.try_start(w)
    w.fishing.phase, w.fishing.t = 'wait', 0
    api.press('confirm')
    api.wait(3)
    api.check(w.fishing == nil, 'si prems abans de la picada, el peix s\'espanta')
  end

  -- 2) Classe de màgia de la mestra: Raig de gel amb la resposta correcta
  st.char_level = math.max(st.char_level or 1, 4)
  State.give(st, 'baston_magic')
  st.equipment.weapon = 'baston_magic'
  st.max_mp, st.mp = 30, 30
  local mestra_npc
  for _, n in ipairs(w.npcs) do if n.props.service_id == 'escola' then mestra_npc = n end end
  api.check(mestra_npc ~= nil, 'la mestra és a l\'escola')
  if mestra_npc then
    api.keep_dialogue = true
    require('src.systems.services').magic_class(w, mestra_npc)
    api.wait(3)
    local m = g.menu
    local pick
    for i, it in ipairs(m and m.list or {}) do if it[1]:find('Raig de gel') then pick = it end end
    api.check(pick ~= nil, 'la classe ofereix el Raig de gel')
    if pick then
      pick[2]()
      api.wait(3)
      api.talk_through()
      api.wait(3)
      local right
      for _, it in ipairs(g.menu and g.menu.list or {}) do if it[1] == 'A 0 graus' then right = it end end
      api.check(right ~= nil, 'la pregunta té la resposta correcta')
      if right then right[2](); api.wait(3) end
      shot('classe.png')
      api.talk_through()
    end
    api.keep_dialogue = false
    api.check((st.learned_spells or {}).gel, 'has après el Raig de gel')
  end
  -- 3) Escut màgic: res no et fa mal; Retorn a la plaça
  require('src.systems.magic').learn(st, 'escut')
  require('src.systems.magic').learn(st, 'retorn')
  st.spell = 'escut'
  w:cast_spell()
  local hp = st.hp
  local hurt = api.player():hit(2, api.player().body.x + 10, api.player().body.y, w:ctx())
  api.check(not hurt and st.hp == hp and (st.ward_t or 0) > 0, 'amb l\'escut màgic no et fan mal')
  st.ward_t = 0
  st.spell = 'retorn'
  st.mp = 30
  w:cast_spell()
  local sp = w.map:object('spawn', 'spawn_public_centre')
  local b = api.player().body
  api.check(math.abs(b.x - sp.x) < 2 and math.abs(b.y - sp.y) < 2, 'el Retorn et porta a la plaça')

  -- 4) trànsit amb vehicles nous i velers
  local kinds = {}
  for _, c in ipairs(w.traffic.cars) do kinds[c.kind] = (kinds[c.kind] or 0) + 1 end
  local big = (kinds.police_car or 0) + (kinds.ambulance or 0) + (kinds.firetruck or 0) + (kinds.truck or 0) + (kinds.excavator or 0)
  api.check(big >= 5, string.format('vehicles nous al trànsit: policia %d, ambulància %d, bombers %d, camió %d, excavadora %d',
    kinds.police_car or 0, kinds.ambulance or 0, kinds.firetruck or 0, kinds.truck or 0, kinds.excavator or 0))
  local tr
  for _, c in ipairs(w.traffic.cars) do if c.kind == 'firetruck' or c.kind == 'ambulance' then tr = c end end
  if tr then
    local x, y = require('src.systems.traffic').pos(tr)
    b.x, b.y = x, y + 30
    api.wait(30)
    local x2, y2 = require('src.systems.traffic').pos(tr)
    b.x, b.y = x2, y2 + 30
    api.wait(2)
    shot('transit.png')
  end
  api.check(w.sailboats and #w.sailboats.boats >= 5, 'velers al mar: ' .. (w.sailboats and #w.sailboats.boats or 0))
  if w.sailboats and w.sailboats.boats[1] then
    local bt = w.sailboats.boats[1]
    local x0, y0 = bt.x, bt.y
    api.wait(60)
    api.check((bt.x - x0) ^ 2 + (bt.y - y0) ^ 2 > 4, 'els velers naveguen')
    b.x, b.y = bt.x - 60, bt.y - 20
    api.press('view')
    api.wait(15)
    print(string.format('[test] veler a %.0f,%.0f; jugador a %.0f,%.0f; càmera %.0f,%.0f', bt.x, bt.y, b.x, b.y, w.cam.x, w.cam.y))
    shot('velers.png')
    api.press('view')
  end
  api.on_frame = nil
end
