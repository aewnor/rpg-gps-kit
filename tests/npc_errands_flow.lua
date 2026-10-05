-- Veïns amb encàrrecs (love . --test=tests/npc_errands_flow.lua --mute): el pa al matí (i tornen amb la barra),
-- la platja si fa sol, regar el jardí al vespre i què expliquen si hi parles.
-- Desa npc_pa.png, npc_platja.png i npc_jardi.png.
return function(api)
  local Town = require('src.systems.town')
  local Weather = require('src.systems.weather')
  local w = api.scene()
  local st = api.state()
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local real_pick = Weather.pick
  Weather.pick = function() return 'sol' end
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  local function at(clock, day)
    st.clock, st.day = clock, day
    for _, n in ipairs(w.npcs) do if n.routine then n.routine.tick = 0 end end
    api.wait(4)
  end
  local function find(place)
    for _, n in ipairs(w.npcs) do
      if n.routine and n.routine.place == place and n.routine.goal then return n end
    end
  end
  local function visit(n, file)
    api.teleport(math.floor(n.body.x / 16), math.floor(n.body.y / 16) + 2)
    api.wait(30)
    shot(file)
  end
  -- 1) el pa
  at(8 * 60 + 32, 2)
  local baker = find('bakery')
  api.check(baker ~= nil, 'a les 8:32 algun veí va a buscar el pa')
  if baker then
    api.check(Town.errand_line(w, baker) ~= nil, 'si hi parles, explica que va a buscar el pa')
    for _ = 1, 3 do api.wait(2) end
    api.check(baker.routine.visited == 'bakery', 'arriba al forn')
    -- a prop (si és lluny, salta directe a casa i deixa el pa)
    api.teleport(math.floor(baker.body.x / 16), math.floor(baker.body.y / 16) + 3)
    api.wait(5)
    at(9 * 60 + 20, 2)
    api.check(baker.routine.carry == 'bread', 'en sortir porta la barra de pa (' .. tostring(baker.routine.place) .. ')')
    visit(baker, 'npc_pa.png')
  end
  -- 2) la platja
  at(12 * 60 + 10, 6)
  api.wait(10)
  local swim = find('beach') or find('pool')
  api.check(swim ~= nil, 'dissabte de sol a migdia, algú va a la platja o a la piscina')
  if swim then
    api.wait(4)
    api.check(swim.activity == 'towel' or swim.activity == 'swim', 'a la platja, tovallola o nedant (' .. tostring(swim.activity) .. ')')
    visit(swim, 'npc_platja.png')
  end
  -- 3) el jardí
  at(19 * 60 + 38, 3)
  local gard = find('garden')
  api.check(gard ~= nil, 'al vespre algú rega el jardí')
  if gard then
    api.wait(4)
    api.check(gard.activity == 'water', 'amb la regadora')
    visit(gard, 'npc_jardi.png')
  end
  -- 4) la pluja: ningú rega
  Weather.pick = function() return 'pluja' end
  w.game.weather.kind = 'pluja'
  at(19 * 60 + 38, 3)
  api.check(find('garden') == nil, 'quan plou, ningú rega')
  Weather.pick = real_pick
  api.on_frame = nil
end
