-- Banderes de la platja (2026-10-05): al costat de cada torre de socorrista (objectes 'beach_flag' de
-- tools/decorate_map.py zone_polish) una bandera verda, groga o vermella segons el temps. Amb la vermella no et
-- pots banyar al mar (World:update_swim); a l'aigua de vora la platja (decorate_map.sea_swim) s'hi neda.
local Beach = {}

Beach.COLOR = { sol = 'green', nuvol = 'yellow', boira = 'yellow', vent = 'red', pluja = 'red', tempesta = 'red',
                neu = 'red' }
Beach.NAMES = { green = 'verda', yellow = 'groga', red = 'vermella' }
local RGB = { green = { 0.22, 0.66, 0.30 }, yellow = { 0.98, 0.80, 0.18 }, red = { 0.86, 0.18, 0.16 } }

-- color de la bandera amb el temps `weather` (taula de src/systems/weather.lua o el seu `kind`)
function Beach.flag(weather)
  local kind = type(weather) == 'table' and weather.kind or weather
  return Beach.COLOR[kind or 'sol'] or 'green'
end

-- add(y, fn): ordre de dibuix del món
function Beach.draw(w, add, ox, oy)
  if w.id ~= 'overworld' then return end
  w.beach_flags = w.beach_flags or w.map:objects_of('beach_flag')
  local col = RGB[Beach.flag(w.game.weather)]
  local windy = w.game.weather and (w.game.weather.kind == 'vent' or w.game.weather.kind == 'tempesta')
  local fr = math.floor(love.timer.getTime() * (windy and 8 or 4)) % 2
  for _, o in ipairs(w.beach_flags) do
    if w.cam:visible(o.x - 8, o.y - 24, 16, 26) then
      add(o.y, function()
        local x, y = math.floor(o.x - ox), math.floor(o.y - oy)
        love.graphics.setColor(0.25, 0.22, 0.20); love.graphics.rectangle('fill', x, y - 20, 1, 20)   -- pal
        love.graphics.setColor(0.85, 0.83, 0.78); love.graphics.rectangle('fill', x, y - 21, 1, 1)
        love.graphics.setColor(col)                                                                -- tela onejant
        love.graphics.rectangle('fill', x + 1, y - 20, 7, 5)
        love.graphics.setColor(col[1] * 0.75, col[2] * 0.75, col[3] * 0.75)
        if fr == 0 then love.graphics.rectangle('fill', x + 5, y - 20, 1, 5); love.graphics.rectangle('fill', x + 8, y - 19, 1, 4)
        else love.graphics.rectangle('fill', x + 3, y - 20, 1, 5); love.graphics.rectangle('fill', x + 7, y - 16, 2, 1) end
        love.graphics.setColor(1, 1, 1, 1)
      end)
    end
  end
end

return Beach
