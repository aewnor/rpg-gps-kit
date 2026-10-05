-- Panell de dalt (love . --test=tests/hud_flow.lua --mute): vida amb número, màgia, nivell dins el recuadre (també
-- en majúscules) i el que portes a cada mà. Desa hud.png i hud_majuscules.png.
return function(api)
  local g = api.scene().game
  local st = api.state()
  local Rpg = require('src.systems.rpg')
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 100 do if done then break end; api.wait(1) end
  end
  while st.char_level < 4 do Rpg.add_xp(st, st.next_xp) end
  st.inventory.sword_iron, st.inventory.baston_magic, st.inventory.shield_wood = 1, 1, 1
  Rpg.equip(st, g.items, 'sword_iron'); Rpg.equip(st, g.items, 'baston_magic', 'shield')
  st.spell, st.hp, st.coins = 'foc', st.max_hp - 1, 144
  api.wait(20)
  local hud = api.scene().hud
  api.check(hud.clock_y and hud.clock_y > 60, 'el rellotge va sota el panell (y=' .. tostring(hud.clock_y) .. ')')
  shot('hud.png')
  local Upper = require('src.ui.upper')
  Upper.on = true
  api.wait(10)
  shot('hud_majuscules.png')
  Upper.on = false
end
