-- Capturas del «juice» de la fase 4 (comprobación visual: love . --test=tests/juice_probe.lua --mute):
-- números flotantes, hojas en un parque, polvo al derrapar y destellos de un cofre.
return function(api)
  local Input = require('src.input')
  local sc = api.scene()
  local g = sc.game
  g.dev.turbo = 1
  local function shot(name)
    love.graphics.captureScreenshot(function(d) d:encode('png', name .. '.png') end)
    api.wait(2)
  end
  -- parque más cercano
  local b = api.player().body
  local tx0, ty0 = math.floor(b.x / 16), math.floor(b.y / 16)
  local found
  for r = 1, 120 do
    for dy = -r, r, 2 do
      for dx = -r, r, 2 do
        if not found and (math.abs(dx) == r or math.abs(dy) == r) then
          local n = sc:tile_name('ground', tx0 + dx, ty0 + dy) or ''
          if n:find('^g_park') then found = { tx0 + dx, ty0 + dy } end
        end
      end
    end
    if found then break end
  end
  print('parque', found and found[1], found and found[2])
  if found then api.teleport(found[1], found[2]) end
  api.wait(240)
  print('partículas', sc.fx.n)
  sc:reward(20, 5, 'Prova')
  api.state().hp = api.state().hp - 2
  api.wait(12)
  shot('j_park_popups')
  -- derrape con la moto de enduro
  api.state().vehicles.motocross = true
  api.state().char_level, api.state().vehicle = 5, 'motocross'
  Input.press('bike'); api.wait(3)
  Input.hold('right', true); api.wait(50); Input.release_all()
  Input.hold('left', true); api.wait(8); shot('j_skid'); api.wait(10); Input.release_all()
  Input.press('bike'); api.wait(3)
  -- cofre
  for _, c in ipairs(sc.chests) do
    if not sc.sstate.chests[c.obj.props.flag] then
      api.player().body.x, api.player().body.y = c.rect.x + 8, c.rect.y + 16 + 8
      api.player().facing = 'up'; api.wait(2); api.press('confirm'); api.wait(10)
      shot('j_chest')
      api.talk_through(); api.wait(10)
      shot('j_chest_reward')
      break
    end
  end
end
