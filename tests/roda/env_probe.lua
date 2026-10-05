-- Capturas del entorno (comprobación visual: love . --test=tests/env_probe.lua --mute): escuela, Parc de la
-- Silena, nucleo antiguo y urbanización.
return function(api)
  local Streets = require('src.systems.streets')
  local g = api.scene().game
  g.dev.turbo = 1
  local spots = {
    { 'env_escola', 'Escola Salvador Espriu' }, { 'env_silena', 'Parc de la Silena' },
    { 'env_esglesia', 'Plaça de l\'Església' }, { 'env_cucurull', 'Escola El Cucurull' },
  }
  for _, sp in ipairs(spots) do
    local a = Streets.area(sp[2])
    if a then
      api.player().body.x, api.player().body.y = a.cx, a.cy + 40
      api.wait(60)
      love.graphics.captureScreenshot(function(d) d:encode('png', sp[1] .. '.png') end)
      api.wait(3)
    else print('[test] sin área', sp[2]) end
  end
  api.player().body.x, api.player().body.y = 330 * 16, 1250 * 16    -- urbanització (Roda Barà)
  api.wait(60)
  love.graphics.captureScreenshot(function(d) d:encode('png', 'env_urba.png') end)
  api.wait(3)
end
