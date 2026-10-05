-- Captures dels 10 tipus de casa (love . --test=tests/house_layouts_flow.lua --mute): casa_tipus_N.png
return function(api)
  local g = api.scene().game
  local P = require('src.world.procgen')
  api.talk_through()
  local back = { scene = 'overworld', x = api.player().body.x, y = api.player().body.y, level = 0 }
  for k = 1, 10 do
    local spec = P.generate({ kind = 'house', seed = 5000 + k * 37, layout = k, name = 'Tipus ' .. k })
    g:register_generated('hl_' .. k, spec, back)
    g.scene_manager:change('hl_' .. k, 'spawn_in')
    for _ = 1, 120 do if not g.transition and api.scene().id == 'hl_' .. k then break end; api.wait(1) end
    api.wait(20)
    api.check(api.scene().id == 'hl_' .. k, 'tipus ' .. k .. ' carregat')
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', 'casa_tipus_' .. k .. '.png'); done = true end)
    for _ = 1, 100 do if done then break end; api.wait(1) end
  end
end
