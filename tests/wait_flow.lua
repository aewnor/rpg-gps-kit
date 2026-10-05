-- Esperar (menú de pausa) i servei tancat de nit (love . --test=tests/wait_flow.lua --mute): a les 23:28 l'escola
-- consta com a tancada amb l'hora d'obrir, i «Esperar → Fins al matí» porta el rellotge a les 8:00.
return function(api)
  local g = api.scene().game
  local Town = require('src.systems.town')
  local function step(n)   -- (api.wait no tanca els diàlegs: avisos de missió)
    for _ = 1, n do
      local d = api.scene().dialogue
      if d.open then d.open = false; if d.on_close then d.on_close() end end
      api.wait(1)
    end
  end
  local w = api.scene()
  local st = api.state()
  st.day, st.clock = 1, 23 * 60 + 28          -- dilluns a la nit
  step(5)
  local info = Town.closed_info(g, 'escola')
  api.check(info ~= nil and info.when:find('demà', 1, true) ~= nil, 'de nit, l\'escola és tancada (' .. tostring(info and info.when) .. ')')
  st.clock = 12 * 60
  api.check(Town.closed_info(g, 'escola') == nil, 'a migdia, oberta')
  st.clock = 23 * 60 + 28
  g:open_menu()
  g.menu:open_wait()
  local pick
  for _, it in ipairs(g.menu:items()) do if it[1]:find('Fins al matí', 1, true) then pick = it end end
  api.check(pick ~= nil, 'opció «Fins al matí»')
  if pick then pick[2]() end
  for _ = 1, 400 do if not w.rest_fx then break end; step(1) end
  api.check(st.day == 2 and math.floor(st.clock + 0.5) == 480, 'ha passat el temps fins a les 8:00 (' .. st.day .. ', ' .. math.floor(st.clock) .. ')')
end
