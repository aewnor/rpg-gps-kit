-- Textos dels menús (love . --test=tests/menu_text_flow.lua --mute): en majúscules res surt del recuadre. Desa
-- menu_pausa.png, menu_equip.png i menu_personatge.png.
return function(api)
  local g = api.scene().game
  local Upper = require('src.ui.upper')
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 100 do if done then break end; api.wait(1) end
  end
  Upper.on = true
  g:open_menu()
  g.menu.sel = 3
  api.wait(5); shot('menu_pausa.png')
  g.menu:open_slots()
  api.wait(5); shot('menu_equip.png')
  g:close_menu(); g:open_menu(); g.menu.screen = 'character'
  api.wait(5); shot('menu_personatge.png')
  api.check(true, 'captures fetes')
  Upper.on = false
  g:close_menu()
end
