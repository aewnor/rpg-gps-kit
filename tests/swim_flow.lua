-- Piscina municipal (love . --test=tests/swim_flow.lua --mute): l'aigua de la Piscina Municipal es pot
-- nedar (més a poc a poc, mig submergit); amb vehicle no s'hi entra; les piscines privades segueixen tancades.
return function(api)
  local g = api.scene().game
  local w = api.scene()
  local pl = w.player
  local Collision = require('src.world.collision')
  local Input = require('src.input')
  local function hold(action, frames) Input.hold(action, true); api.wait(frames); Input.release_all(); api.wait(1) end
  api.talk_through()
  -- primera casella de piscina transitable a la zona de la Piscina Municipal (OSM 774-781 × 612-625)
  local px, py
  for y = 608, 630 do
    for x = 770, 786 do
      local n = w:tile_name('ground', x, y) or ''
      if not px and n:sub(1, 5) == 'pool_' and Collision.walk_at(w.map:cell(x, y), 0) then px, py = x, y end
    end
  end
  api.check(px ~= nil, 'la Piscina Municipal té aigua on es pot nedar')
  if not px then return end
  pl.body.x, pl.body.y = px * 16 + 8, py * 16 + 8
  api.wait(5)
  api.check(pl.swimming == true, 'dins de l\'aigua el jugador neda')
  -- nedant va més lent que caminant
  local x0 = pl.body.x
  hold('right', 30)
  local swim_dx = math.abs(pl.body.x - x0)
  api.check(swim_dx > 0, 'es pot moure nedant')
  -- fora de l'aigua (la vora seca més propera)
  local found
  for r = 1, 12 do
    for y = py - r, py + r do
      for x = px - r, px + r do
        local n = w:tile_name('ground', x, y) or ''
        if not found and n:sub(1, 5) ~= 'pool_' and Collision.walk_at(w.map:cell(x, y), 0) then found = { x, y } end
      end
    end
    if found then break end
  end
  api.check(found ~= nil, 'hi ha vora seca a prop')
  pl.body.x, pl.body.y = found[1] * 16 + 8, found[2] * 16 + 8
  api.wait(5)
  api.check(not pl.swimming, 'fora de l\'aigua ja no neda')
  local x1 = pl.body.x
  hold('right', 30)
  local walk_dx = math.abs(pl.body.x - x1)
  api.check(walk_dx == 0 or walk_dx > swim_dx, string.format('nedar és més lent que caminar (%.0f < %.0f px)', swim_dx, walk_dx))
  -- amb bici: tornem a la vora i l'aigua el fa recular
  pl.body.x, pl.body.y = found[1] * 16 + 8, found[2] * 16 + 8
  api.wait(3)
  api.press('bike')
  api.check(pl.vehicle ~= nil, 'puja a la bici a la vora')
  pl.body.x, pl.body.y = px * 16 + 8, py * 16 + 8
  api.wait(3)
  api.check(not pl.swimming, 'amb bici no s\'entra a la piscina')
  api.press('bike')
  -- una piscina privada qualsevol continua sent aigua no transitable
  local private
  for y = 840, 900 do
    for x = 600, 700 do
      local n = w:tile_name('ground', x, y) or ''
      if not private and n:sub(1, 5) == 'pool_' then private = { x, y } end
    end
  end
  if private then
    api.check(not Collision.walk_at(w.map:cell(private[1], private[2]), 0), 'les piscines privades no es poden nedar')
  end
  print(string.format('[test] nedar %.0f px · caminar %.0f px en 30 fotogrames', swim_dx, walk_dx))
end
