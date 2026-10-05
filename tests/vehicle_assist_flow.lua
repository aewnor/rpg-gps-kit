-- Conducció assistida al mapa real (love . --test=tests/vehicle_assist_flow.lua --mute): en bici per l'Av. de l'Avenc
-- (que puja i baixa uns graus) amb la fletxa dreta fixa, amb assistència es queda més estona a la calçada que sense.
-- Desa vehicle_diag.png (la bici vista en diagonal).
return function(api)
  local Input = require('src.input')
  local Vehicles = require('src.systems.vehicles')
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local w = api.scene()
  local pl = api.player()
  local function road(tx, ty) local _, s = w.map:height_at(tx, ty); return s == 1 or s == 2 end
  -- un tram de carrer de l'Avenc
  local sx, sy
  -- la fila de calçada (asfalt o camí, sense obstacles) més llarga cap a l'est des de x = 797, a prop de l'avinguda
  local Collision = require('src.world.collision')
  local best = 0
  for ty = 752, 778 do
    local n = 0
    while n < 60 and road(797 + n, ty) and Collision.walk_at(w.map:cell(797 + n, ty), 0) do n = n + 1 end
    if n > best then best, sx, sy = n, 797, ty end
  end
  print('tram', sx, sy, best)
  api.check(sx ~= nil, 'trobat un tram de l\'Av. de l\'Avenc')
  if not sx then return end
  local function run(assist)
    api.teleport(sx, sy); api.wait(3)
    pl.vehicle = Vehicles.new_state('bici', 'right'); pl.bike = true
    pl.vehicle.assist = assist
    local on, n = 0, 0
    Input.hold('right', true)
    for _ = 1, 240 do
      api.wait(1)
      n = n + 1
      if road(math.floor(pl.body.x / 16), math.floor(pl.body.y / 16)) then on = on + 1 end
    end
    Input.release_all()
    return on / n, pl.body.x / 16 - sx
  end
  local a, da = run(true)
  local b, db = run(false)
  api.check(a >= b and a > 0.9, string.format('amb assistència, a la calçada %.0f%% (sense, %.0f%%; %.0f i %.0f caselles)',
    a * 100, b * 100, da, db))
  -- un camí que gira: el Camí de l'Avenc, de (16376, 10698) a (16128, 10375) px, ~37° cap a l'oest; fletxa amunt fixa
  local cx, cy
  for r = 0, 4 do
    for dy = -r, r do for dx = -r, r do
      if not cx and road(1023 + dx, 668 + dy) and Collision.walk_at(w.map:cell(1023 + dx, 668 + dy), 0) then cx, cy = 1023 + dx, 668 + dy end
    end end
  end
  api.check(cx ~= nil, 'trobat el Camí de l\'Avenc')
  if cx then
    local function climb(assist)
      api.teleport(cx, cy); api.wait(3)
      pl.vehicle = Vehicles.new_state('motocross', 'up'); pl.bike = true
      pl.vehicle.assist = assist
      local on = 0
      Input.hold('up', true)
      for _ = 1, 150 do
        api.wait(1)
        if road(math.floor(pl.body.x / 16), math.floor(pl.body.y / 16)) then on = on + 1 end
      end
      Input.release_all()
      return on / 150, cy - pl.body.y / 16
    end
    local ca, ua = climb(true)
    local cb, ub = climb(false)
    api.check(ca >= cb, string.format('pel camí del bosc (2 de terra entre arbres), l\'assistència no empitjora: %.0f%% i sense %.0f%% (%.0f i %.0f caselles)',
      ca * 100, cb * 100, ua, ub))
  end
  -- molts carrers de veritat (data/streets.json): fletxa (de 8) cap on va el carrer, 3 s. Amb guia, més estona
  -- a la via i menys encallat contra el que hi ha als costats
  do
    local json = require('src.lib.json')
    local doc = json.decode(love.filesystem.read('data/streets.json'))
    local trips, k = {}, 0
    for _, l in ipairs(doc.lines) do
      local p = l.p
      if #p >= 4 then
        k = k + 1
        if k % 23 == 0 and #trips < 14 then
          local x0, y0, x1, y1 = p[1], p[2], p[3], p[4]
          local ang = math.atan2(y1 - y0, x1 - x0)
          local oct = math.floor((ang + math.pi / 8) / (math.pi / 4)) % 8
          local dirs = ({ [0] = { 'right' }, { 'right', 'down' }, { 'down' }, { 'down', 'left' }, { 'left' }, { 'left', 'up' },
                          { 'up' }, { 'up', 'right' } })[oct]
          local tx, ty = math.floor(x0 / 16), math.floor(y0 / 16)
          if road(tx, ty) and Collision.walk_at(w.map:cell(tx, ty), 0) then trips[#trips + 1] = { tx, ty, dirs } end
        end
      end
    end
    local function trip(t, assist)
      api.teleport(t[1], t[2]); api.wait(2)
      pl.vehicle = Vehicles.new_state('scooter', 'down'); pl.bike = true
      pl.vehicle.assist = assist
      for _, d in ipairs(t[3]) do Input.hold(d, true) end
      local on, stuck, lx, ly = 0, 0, pl.body.x, pl.body.y
      local Roads = require('src.systems.roads')
      for i = 1, 180 do
        api.wait(1)
        -- «a la via»: a menys de 14 px de l'eix d'una via de data/roads.json (calçada, no vorera ni plaça)
        local near = false
        for _, sg in ipairs(Roads.near(pl.body.x, pl.body.y, 14, {})) do if sg.c ~= 'path' then near = true end end
        if near then on = on + 1 end
        if i > 30 and (pl.body.x - lx) ^ 2 + (pl.body.y - ly) ^ 2 < 0.1 then stuck = stuck + 1 end
        lx, ly = pl.body.x, pl.body.y
      end
      Input.release_all()
      pl.jump = nil
      return on / 180, stuck / 150
    end
    local A, B = { on = 0, stuck = 0 }, { on = 0, stuck = 0 }
    for _, t in ipairs(trips) do
      local o1, s1 = trip(t, true); local o2, s2 = trip(t, false)
      A.on, A.stuck, B.on, B.stuck = A.on + o1, A.stuck + s1, B.on + o2, B.stuck + s2
    end
    local n = math.max(1, #trips)
    api.check(#trips >= 8 and A.on >= B.on and A.stuck <= B.stuck + 0.01,
      string.format('%d carrers: amb guia %.0f%% sobre l\'eix de la via (±14 px) i %.0f%% encallat; sense, %.0f%% i %.0f%%', #trips,
        A.on / n * 100, A.stuck / n * 100, B.on / n * 100, B.stuck / n * 100))
  end
  -- en diagonal
  api.teleport(sx, sy); api.wait(3)
  pl.vehicle = Vehicles.new_state('bici', 'down'); pl.bike = true
  Input.hold('down', true); Input.hold('right', true); api.wait(30)
  Input.release_all()
  api.check(require('src.entities.player').vehicle_diag(pl.vehicle.angle) ~= nil, 'en diagonal, la bici fa servir la vista de tres quarts')
  local done = false
  love.graphics.captureScreenshot(function(d) d:encode('png', 'vehicle_diag.png'); done = true end)
  for _ = 1, 100 do if done then break end; api.wait(1) end
  api.on_frame = nil
end
