-- Llanterna (love . --test=tests/flashlight_flow.lua --mute): de nit i a la cova, amb la llanterna hi ha un con de
-- llum cap a on mires. Desa llanterna_nit.png i llanterna_cova.png.
return function(api)
  local g = api.scene().game
  local st = api.state()
  local function shot(file)
    local done = false
    love.graphics.captureScreenshot(function(d) d:encode('png', file); done = true end)
    for _ = 1, 100 do if done then break end; api.wait(1) end
  end
  st.clock = 23 * 60
  g.config.temps = 'sol'
  st.inventory.llanterna = nil
  api.wait(10)
  api.check(api.scene():flashlight_angle() == nil, 'sense llanterna, no hi ha con')
  st.inventory.llanterna = 1
  api.player().facing = 'right'
  api.wait(10)
  api.check(api.scene():flashlight_angle() == 0, 'amb la llanterna, el con mira cap a la dreta')
  shot('llanterna_nit.png')
  g:change('cova_roda_1', 'spawn_entrance')
  api.wait(90)
  api.player().facing = 'up'
  api.wait(10)
  api.check(math.abs(api.scene():flashlight_angle() + math.pi / 2) < 1e-6, 'a la cova, mirant amunt')
  shot('llanterna_cova.png')
end
