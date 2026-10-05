-- Casa del protagonista a partir del plànol (love . --test=tests/casa_plano_flow.lua --mute): només si hi ha
-- casa_privada.json al directori de dades (dades privades: mai al repositori). Comprova que hi ha els cotxes del
-- pàrquing, el carregador, la pèrgola i la piscina, i desa casa_parking.png i casa_jardi.png.
return function(api)
  local g = api.scene().game
  api.talk_through()
  g:load_house()
  if not g.house then print('[test] sense casa_privada.json: res a provar'); return end
  -- s'entra per la porta de la façana sud (la que es veu), no empenyent la paret de l'est
  api.check(g.house.entrance ~= 'este', 'la casa s\'entra per la porta sud (' .. tostring(g.house.entrance) .. ')')
  local ow = api.scene()
  if ow.home then
    ow:find_house_door()
    local hd = ow.house_door
    api.check(hd ~= nil and not ow.house_east, 'la porta de casa és la de la façana, sense entrada per l\'est')
    if hd then
      api.player().body.x, api.player().body.y = hd[1] * 16 + 8, (hd[2] + 1) * 16 + 6
      api.player().facing = 'up'
      api.wait(2); api.press('confirm'); api.wait(40)
      api.check(api.scene().id == g.house.entry, 'per la porta sud s\'entra a casa (' .. api.scene().id .. ')')
    end
  end
  g.scene_manager:change(g.house.entry, g.house.spawn or 'spawn_in')
  for _ = 1, 120 do if not g.transition and api.scene().id == g.house.entry then break end; api.wait(1) end
  api.wait(20)
  local w = api.scene()
  api.check(w.id == g.house.entry, 'som a la planta baixa de casa')
  api.check(#w.parked >= 1, 'hi ha cotxes aparcats al pàrquing (' .. #w.parked .. ')')
  local function find(name)
    for ty = 0, w.map.height - 1 do for tx = 0, w.map.width - 1 do
      if w:tile_name('structures', tx, ty) == name or w:tile_name('overhead', tx, ty) == name then return tx, ty end
    end end
  end
  api.check(find('i_ev_charger') ~= nil, 'el carregador del cotxe')
  local px, py = find('o_canopy_15')
  api.check(px ~= nil, 'la pèrgola del jardí')
  local function shot(file, tx, ty)
    api.player().body.x, api.player().body.y = tx * 16 + 8, ty * 16 + 8
    api.wait(20)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 60 do if done then break end; api.wait(1) end
  end
  local car = w.parked[1]
  if car then shot('casa_parking.png', math.floor(car.x / 16), math.floor(car.y / 16) + 2) end
  if px then shot('casa_jardi.png', px, py + 2) end
end
