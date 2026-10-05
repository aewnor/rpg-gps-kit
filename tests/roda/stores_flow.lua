-- Botigues grans, casa solar, vista allunyada i casa del jugador (love . --test=tests/stores_flow.lua --mute).
-- Desa store_bonpreu.png, store_leroy.png, casa_solar.png, vista_lluny.png i casa_pares.png.
return function(api)
  local g = api.scene().game
  local Services = require('src.systems.services')
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  local function wait_scene(prev) for _ = 1, 300 do if g.scene ~= prev and not g.transition then break end; api.wait(1) end end
  local function go_out()
    local back = g.state.proc and g.state.proc.back
    if back then g:change(back.scene, nil, { x = back.x, y = back.y, level = 0 }) end
    for _ = 1, 300 do if not g.transition then break end; api.wait(1) end
    api.wait(5)
  end
  api.talk_through()
  g.config.temps = 'sol'
  -- botigues: el Bonpreu i el Leroy Merlin, amb passadissos, caixes i clients
  for _, id in ipairs({ 'bonpreu', 'leroy' }) do
    local w = api.scene()
    local n
    for _, x in ipairs(w.npcs) do if x.props.service_id == id then n = x end end
    api.check(n ~= nil, id .. ': hi ha el personatge de la botiga')
    if n then
      w.player.body.x, w.player.body.y = n.body.x, n.body.y + 18
      api.wait(3)
      Services.enter(w, n)
      wait_scene(w)
      local inside = api.scene()
      local size = Services.STORE_SIZE[id]
      api.check(inside ~= w and inside.map.width == size[1] and inside.map.height == size[2],
        string.format('%s: interior de %d×%d', id, inside.map.width, inside.map.height))
      local cashiers, clients = 0, 0
      for _, x in ipairs(inside.npcs) do
        local nm = x.props.say_name or ''
        if nm == 'Caixera' or x.props.service_id == id then cashiers = cashiers + 1 end
        if nm == 'Client' then clients = clients + 1 end
      end
      api.check(cashiers >= 4 and clients >= 3, string.format('%s: %d caixeres i %d clients', id, cashiers, clients))
      api.wait(20)
      shot('store_' .. id .. '.png')
      go_out()
    end
  end
  -- casa amb placas: interior amb aparells i un cofre
  local w = api.scene()
  local id = g:proc_interior(700, 820, 'house', { scene = 'overworld', x = 700 * 16 + 8, y = 821 * 16 + 10, level = 0 },
    1, nil, nil, true)
  local spec = g.generated[id].spec
  local tiles = {}
  for _, t in ipairs(spec.structures) do tiles[t] = true end
  local chest = false
  for _, o in ipairs(spec.objects) do if o.type == 'chest' then chest = true end end
  api.check(tiles.i_inverter and tiles.i_battery and tiles.i_smart_panel and chest, 'la casa solar té inversor, bateries, pantalla i cofre')
  g.scene_manager:change(id, 'spawn_in')
  wait_scene(w)
  api.wait(20)
  shot('casa_solar.png')
  go_out()
  -- vista allunyada: el doble de món a la pantalla
  w = api.scene()
  api.press('view'); api.wait(5)
  api.check(w.zoom_out and w.cam.w == 640, 'N allunya la vista (640×480 de món)')
  api.wait(20)
  shot('vista_lluny.png')
  api.press('view'); api.wait(5)
  api.check(not w.zoom_out and w.cam.w == 320, 'N torna a la vista normal')
  -- casa del jugador (la del plano) amb el pare i la mare
  if g.house then
    w = api.scene()
    g.scene_manager:change(g.house.entry, g.house.spawn or 'spawn_in')
    wait_scene(w)
    api.wait(30)
    local inside = api.scene()
    local parents = 0
    for _, x in ipairs(inside.npcs) do if x.props.parent and not x.hidden then parents = parents + 1 end end
    print('[test] pares visibles a la planta d\'entrada: ' .. parents)
    shot('casa_pares.png')
  else
    print('[test] sense casa del plano en aquest aparell')
  end
end
