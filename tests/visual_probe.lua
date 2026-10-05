-- Capturas de comprobación visual (no es una prueba automática)
return function(api)
  local Input = require('src.input')
  local State = require('src.state')
  local g = api.scene().game
  for _, it in ipairs({ 'sword_wood', 'shield_wood' }) do State.give(g.state, it); State.equip(g.state, g.items, it) end
  api.wait(10)
  local function shot(name)
    love.graphics.captureScreenshot(function(d) d:encode('png', name .. '.png') end)
    api.wait(3)
  end
  api.player().facing = 'right'
  Input.press('attack'); api.wait(7); print('estado', api.player().state, api.player().t, api.player().invuln, api.player().body.x, api.player().body.y); shot('v_attack')
  api.wait(30)
  Input.hold('shield', true); api.wait(5); shot('v_block'); Input.release_all()
  api.wait(10)
  Input.press('bike'); api.wait(3)
  Input.hold('right', true); api.wait(20); shot('v_bike'); Input.release_all()
  api.wait(5)
end
