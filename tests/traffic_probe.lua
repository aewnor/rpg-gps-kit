-- Capturas del tráfico de la fase 4: peatones en un paso de cebra, motos/patinetes y barreras del paso a nivel
-- (comprobación visual: love . --test=tests/traffic_probe.lua --mute)
return function(api)
  local sc = api.scene()
  local g = sc.game
  local function shot(name)
    love.graphics.captureScreenshot(function(d) d:encode('png', name .. '.png') end)
    api.wait(3)
  end
  local kinds = {}
  for _, c in ipairs(sc.traffic.cars) do kinds[c.kind] = (kinds[c.kind] or 0) + 1 end
  for k, n in pairs(kinds) do print('vehículos', k, n) end
  -- paso de cebra con más tráfico cerca
  local best, bn
  for _, cw in ipairs(sc.traffic.crosswalks) do
    if cw.ang then
      local n = 0
      for _, c in ipairs(sc.traffic.cars) do
        local x, y = require('src.systems.traffic').pos(c)
        if (x - cw.x) ^ 2 + (y - cw.y) ^ 2 < 300 ^ 2 then n = n + 1 end
      end
      if not bn or n > bn then best, bn = cw, n end
    end
  end
  api.teleport(math.floor(best.x / 16) + 3, math.floor(best.y / 16) + 2)
  g.dev.turbo = 1
  local waits, crossed = 0, 0
  for i = 1, 40 do
    api.wait(30)
    for _, p in ipairs(sc.peds.list) do
      if p.state == 'wait' then waits = waits + 1 end
      if p.state == 'cross' then crossed = crossed + 1 end
    end
    if i == 12 then shot('p4_peds') end
  end
  print('peatones', #sc.peds.list, 'esperando', waits, 'cruzando', crossed)
  -- paso a nivel: esperar a que cierre
  local cr
  for _, c in ipairs(sc.trains.crossings) do if c.road_ang then cr = c; break end end
  print('pasos a nivel', #sc.trains.crossings, 'con calle', cr ~= nil)
  if cr then
    api.teleport(math.floor(cr.x / 16) + 3, math.floor(cr.y / 16) + 3)
    g.dev.turbo = 8
    local t = 0
    while cr.state ~= 'warning' and t < 3000 do api.wait(10); t = t + 1 end
    g.dev.turbo = 1
    api.wait(40); shot('p4_barrier_half')
    while cr.bar < 1 and t < 4000 do api.wait(5); t = t + 1 end
    local seen = 0
    for _ = 1, 40 do
      api.wait(5)
      local s = sc.shaker.level or 0
      if s > 0.05 and seen == 0 then seen = 1; shot('p4_train_pass') end
    end
    print('barrera', cr.bar, cr.state)
  end
end
