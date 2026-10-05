-- Tanda 5 (love . --test=tests/tanda5_flow.lua --mute): neu a terra i teulades, bassals quan plou, arbres amb
-- vent i banderes de la platja (amb la vermella no et pots banyar al mar). Desa neu.png, bassals.png i bandera.png.
return function(api)
  local Weather = require('src.systems.weather')
  local Beach = require('src.systems.beach')
  local Input = require('src.input')
  local g = api.scene().game
  local w = api.scene()
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local real_pick = Weather.pick
  local function weather(kind, extra)
    Weather.pick = function() return kind end
    g.weather = g.weather or Weather.new()
    g.weather.kind, g.weather.level = kind, 1
    for k, v in pairs(extra or {}) do g.weather[k] = v end
    api.wait(3)
  end
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 200 do if done then break end; api.wait(1) end
  end
  api.state().clock = 12 * 60
  -- arbres amb vent: lots propis
  api.wait(5)
  local winds = 0
  for _, c in ipairs(g.renderer:visible(w.map, w.cam)) do if c._wind then winds = winds + 1 end end
  api.check(winds > 0, 'els arbres visibles tenen fotogrames de vent (' .. winds .. ' trossos)')
  -- neu
  weather('neu', { snow = 1, puddles = 0 })
  api.check(g.renderer.snow > 0.9, 'la neu acumulada arriba al renderer')
  shot('neu.png')
  weather('sol', { snow = 1 })
  api.wait(30)
  api.check(g.renderer.snow < 1 and g.renderer.snow > 0.5, 'quan surt el sol, la neu es fon a poc a poc')
  -- bassals
  weather('pluja', { snow = 0, puddles = 1 })
  api.wait(4)
  local n = 0
  for _, v in pairs(w.puddle_cache or {}) do if v then n = n + 1 end end
  api.check(n > 0, 'plou: hi ha bassals a la vista (' .. n .. ')')
  api.wait(200)
  shot('bassals.png')
  -- banderes i bany al mar
  local flags = w.map:objects_of('beach_flag')
  api.check(#flags >= 5, 'banderes al costat dels socorristes (' .. #flags .. ')')
  api.check(Beach.flag('pluja') == 'red' and Beach.flag('sol') == 'green' and Beach.flag('nuvol') == 'yellow',
    'verda amb sol, groga ennuvolat, vermella amb pluja o vent')
  local spot
  for _, o in ipairs(w.map:objects_of('errand')) do if o.props.kind == 'beach' and o.props.swim then spot = o; break end end
  api.check(spot ~= nil, 'hi ha aigua de vora la platja on es pot nedar')
  if spot then
    local sx, sy = math.floor(spot.x / 16), math.floor(spot.y / 16)
    local from, dir
    for r = 1, 4 do
      for _, d in ipairs({ { 0, -1, 'down' }, { 0, 1, 'up' }, { -1, 0, 'right' }, { 1, 0, 'left' } }) do
        local tx, ty = sx + d[1] * r, sy + d[2] * r
        if not from and (w:tile_name('ground', tx, ty) or ''):sub(1, 8) == 'g_beach_' then from, dir = { tx, ty }, d[3] end
      end
    end
    api.check(from ~= nil, 'sorra a tocar de l\'aigua')
    if from then
      local function try()
        api.teleport(from[1], from[2]); api.player().facing = dir; api.wait(3)
        Input.hold(dir, true)
        local swam = false
        for _ = 1, 90 do api.wait(1); if api.player().swimming then swam = true; break end end
        Input.release_all(); api.wait(2)
        return swam
      end
      weather('pluja', { puddles = 0 })
      api.check(not try(), 'amb bandera vermella no entres al mar')
      weather('sol', { puddles = 0 })
      local swam = try()
      api.check(swam, 'amb bandera verda neden al mar')
      api.teleport(math.floor(flags[1].x / 16) - 1, math.floor(flags[1].y / 16) + 3)
      api.wait(200)   -- que marxin els avisos
      shot('bandera.png')
    end
  end
  Weather.pick = real_pick
  api.on_frame = nil
end
