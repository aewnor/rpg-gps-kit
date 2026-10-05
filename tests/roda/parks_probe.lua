-- Capturas de parques reconstruidos con la ortofoto (comprobación visual: love . --test=tests/parks_probe.lua --mute)
return function(api)
  local Streets = require('src.systems.streets')
  local g = api.scene().game
  g.dev.turbo = 1
  for i, name in ipairs({ 'Parc de la Masieta', 'Parc Mercé Rodoreda', 'Plaça de l\'Església', 'Parc Roda de Berà' }) do
    local a = Streets.area(name)
    if a then
      local x, y = g:nearest_walkable('overworld', a.cx, a.cy, 0, 10)
      api.player().body.x, api.player().body.y = x or a.cx, y or a.cy
      api.wait(90)
      love.graphics.captureScreenshot(function(d) d:encode('png', 'park_' .. i .. '.png') end)
      api.wait(3)
      print('[test] parc', name, api.scene().hud.banner and api.scene().hud.banner.text)
    end
  end
end
