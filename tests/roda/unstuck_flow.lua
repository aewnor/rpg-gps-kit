-- Salt per desencallar-se (love . --test=tests/unstuck_flow.lua --mute). Atrapat a nivell 1 en una casella només de
-- carrer (no et pots moure enlloc), en menys d'un segon i mig saltes a una casella lliure. També a mà (Menú).
return function(api)
  local Input = require('src.input')
  local U = require('src.systems.unstuck')
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local w = api.scene()
  local pl = api.player()
  local b = pl.body
  -- 1) la pasarela del torrent (605, 863) on es va quedar la protagonista 2: es pot sortir caminant
  local moves = {}
  for _, dir in ipairs({ 'left', 'right', 'up', 'down' }) do
    api.teleport(605, 863); b.level = 1; api.wait(2)
    local x0, y0 = b.x, b.y
    Input.hold(dir, true); api.wait(30); Input.release_all()
    moves[#moves + 1] = dir .. '=' .. math.floor(math.abs(b.x - x0) + math.abs(b.y - y0))
  end
  print('pasarela', table.concat(moves, ' '))
  -- 2) trampa: nivell 1 en una casella de carrer → cap direcció lliure
  api.teleport(600, 859); api.wait(2)
  b.level = 1
  api.check(U.free_dirs(w) == 0, 'trampa: nivell 1 sobre el carrer, no et pots moure')
  local x0, y0 = b.x, b.y
  Input.hold('right', true)
  for _ = 1, 90 do api.wait(1); if pl.jump then break end end
  api.check(pl.jump ~= nil, 'en menys d\'un segon i mig salta sol')
  for _ = 1, 60 do api.wait(1); if not pl.jump then break end end
  Input.release_all()
  api.check(b.level == 0 and (b.x ~= x0 or b.y ~= y0) and U.free_dirs(w) > 0, 'aterra en una casella lliure i ja es pot moure')
  -- 3) a mà, des del menú
  local g = w.game
  g:open_menu(); g.menu:open_actions()
  local found
  local list = g.menu.list or (g.menu.top and g.menu:top() and g.menu:top().items) or {}
  for _, it in ipairs(list) do if tostring(it[1]):find('Saltar') then found = it end end
  api.check(found ~= nil, 'al menú d\'accions hi ha «Saltar (desencallar-me)»')
  if found then found[2]() end
  api.wait(2)
  api.check(pl.jump ~= nil or g.menu == nil, 'des del menú, salta')
  for _ = 1, 60 do api.wait(1); if not pl.jump then break end end
  api.on_frame = nil
end
