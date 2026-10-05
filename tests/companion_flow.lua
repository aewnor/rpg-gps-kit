-- Amics que t'acompanyen (love . --test=tests/companion_flow.lua --mute): l'amiga s'uneix a la missió, et segueix
-- dins la Cova de la Pedrera, llança pedretes als enemics, et posa una tireta i torna a casa; a «Caçadors de
-- tresors» nota un cofre a prop o en desenterra un. Desa company_cova.png i company_tresor.png.
return function(api)
  local Town = require('src.systems.town')
  local Missions = require('src.systems.missions')
  local Companion = require('src.systems.companion')
  local g = api.scene().game
  local st = g.state
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  local w = api.scene()
  local b = api.player().body
  local hx, hy = math.floor(b.x / 16) + 6, math.floor(b.y / 16)
  g.profile = { name = 'Nena', friends = { { id = 'x1', name = 'Laia', role = 'amiga', look = { age = 'child' },
                                               home = { scene = 'overworld', tile_x = hx, tile_y = hy } } } }
  g:build_friends()
  Town.spawn_friends(w)
  st.char_level = math.max(st.char_level or 1, 3)
  local defs = Town.defs(g)
  api.check(defs.by_id.aventura_cova_x1 and defs.by_id.tresor_amic_x1, 'missions d\'aventura per a l\'amiga')
  local h = Town.hooks(w)
  local q = Missions.state(st)
  q.active = nil
  Missions.activate(defs, st, 'aventura_cova_x1', h)
  Town.event(w, 'talk', { target = 'friend:x1' })
  api.wait(5)
  api.check(st.companion and st.companion.id == 'x1' and w.companion ~= nil, 'la Laia s\'uneix i et segueix')
  local fnpc
  for _, n in ipairs(w.npcs) do if n.props.friend == 'x1' then fnpc = n end end
  api.check(fnpc and fnpc.hidden, 'la Laia del carrer no surt dues vegades')
  -- a la cova
  g.scene_manager:change('cova_pedrera', 'spawn_entrance')
  for _ = 1, 120 do if api.scene().id == 'cova_pedrera' and not g.transition then break end; api.wait(1) end
  api.wait(20)
  local cv = api.scene()
  api.check(cv.id == 'cova_pedrera' and cv.companion ~= nil, 'dins la cova, la Laia hi és')
  local _, s = Missions.current(defs, st)
  api.check(s and s.event == 'ally_help_3', 'entrar a la cova avança la missió (' .. tostring(s and s.type) .. ')')
  st.ward_t = 9999
  local cp = cv.companion
  local shot_taken = false
  for _ = 1, 1200 do
    if (st.companion and st.companion.helps or 0) >= 3 then break end
    local alive
    for _, e in ipairs(cv.enemies) do
      if e.state ~= 'dead' and e.damage and not (e.kind and e.kind.boss) then alive = e; break end
    end
    if not alive then break end
    if (alive.body.x - cp.f.x) ^ 2 + (alive.body.y - cp.f.y) ^ 2 > 50 ^ 2 then
      alive.body.x, alive.body.y = cp.f.x + 28, cp.f.y
    end
    api.wait(1)
    if not shot_taken and #cp.stones > 0 then shot('company_cova.png'); shot_taken = true end
  end
  api.check((st.companion and st.companion.helps or 0) >= 3, 'la Laia llança pedretes als enemics (' .. tostring(st.companion and st.companion.helps) .. ')')
  _, s = Missions.current(defs, st)
  api.check(s and s.type == 'goto', 'tres ajudes: ara cal acompanyar-la a casa')
  st.ward_t = 0
  st.hp = 1
  api.wait(5)
  api.check(st.hp >= 3, 'amb poca vida, la Laia et posa una tireta (' .. st.hp .. ')')
  -- de tornada a casa
  g.scene_manager:change('overworld', 'spawn_pedrera_door')
  for _ = 1, 120 do if api.scene().id == 'overworld' and not g.transition then break end; api.wait(1) end
  api.wait(20)
  w = api.scene()
  api.check(w.companion ~= nil, 'torna a sortir amb tu de la cova')
  api.teleport(hx, hy + 1)
  for _ = 1, 60 do if not st.companion then break end; api.wait(2) end
  api.check(q.done.aventura_cova_x1 and not st.companion and not w.companion, 'a la porta de casa seva, missió feta i la Laia s\'acomiada')
  -- caçadors de tresors
  Missions.activate(defs, st, 'tresor_amic_x1', Town.hooks(w))
  Town.event(w, 'talk', { target = 'friend:x1' })
  api.wait(5); api.talk_through(); api.wait(3); api.talk_through()   -- (un diàleg obert atura el món)
  cp = w.companion
  api.check(cp ~= nil, 'la Laia torna a venir')
  local chest
  for _, c in ipairs(w.chests) do if not w.sstate.chests[c.obj.props.flag] then chest = c; break end end
  if chest and cp then
    api.teleport(math.floor(chest.rect.x / 16), math.floor(chest.rect.y / 16) + 3)
    api.wait(20); api.talk_through(); api.wait(10)
    api.check(cp.pointed[chest.obj.props.flag], 'nota el cofre que hi ha a prop')
    shot('company_tresor.png')
    api.teleport(math.floor(chest.rect.x / 16), math.floor(chest.rect.y / 16) + 1); api.player().facing = 'up'; api.wait(3)
    api.press('confirm'); api.wait(5); api.talk_through()
    _, s = Missions.current(defs, st)
    api.check(s and s.type == 'goto', 'obrir el cofre que ha trobat compta (' .. tostring(s and s.type) .. ')')
  end
  -- si no troben cap cofre, en desenterra un
  q.step.tresor_amic_x1 = 2
  local coins = st.coins or 0
  if w.companion then w.companion.walked = Companion.DIG_AFTER + 1; w.companion.point = nil end
  api.wait(5)
  _, s = Missions.current(defs, st)
  api.check(s and s.type == 'goto' and (st.coins or 0) > coins, 'després d\'una bona passejada en desenterra un tresor')
  st.companion, w.companion = nil, nil
  api.on_frame = nil
end
