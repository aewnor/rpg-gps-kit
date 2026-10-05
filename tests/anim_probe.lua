-- Secuencia de capturas para revisar animaciones (no es una prueba automática):
--   love . --test=tests/anim_probe.lua --turbo=1 --at=612,806 --mute
-- Deja anim_000.png… en el directorio de datos de LÖVE (caminar, bici, ataque con estela y parpadeo).
return function(api)
  local Input = require('src.input')
  local State = require('src.state')
  local g = api.scene().game
  for _, it in ipairs({ 'sword_wood', 'shield_wood' }) do State.give(g.state, it); State.equip(g.state, g.items, it) end
  api.wait(5)
  local n = 0
  local function shot()
    local name = string.format('anim_%03d.png', n)
    love.graphics.captureScreenshot(function(d) d:encode('png', name) end)
    n = n + 1
  end
  local function hold(dir, frames, every)
    Input.release_all(); Input.hold(dir, true)
    for i = 1, frames do api.wait(1); if i % (every or 3) == 0 then shot() end end
    Input.release_all()
  end
  hold('right', 36); hold('down', 24); hold('left', 24); hold('up', 24)
  for _ = 1, 6 do api.wait(4); shot() end                 -- reposo
  api.player().facing = 'right'
  Input.press('attack')
  for _ = 1, 10 do api.wait(2); shot() end                 -- ataque
  Input.press('bike'); api.wait(2)
  hold('right', 30, 3)
  print('[anim] ' .. n .. ' capturas en ' .. love.filesystem.getSaveDirectory())
end
