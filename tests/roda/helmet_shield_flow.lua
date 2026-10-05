-- Casc en bici amb qualsevol aparença i escut animat (love . --test=tests/helmet_shield_flow.lua --mute).
-- Desa casc_bici.png (avall, dreta, a cavall) i escut.png.
return function(api)
  local g = api.scene().game
  local Vehicles = require('src.systems.vehicles')
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local w = api.scene()
  local st = api.state()
  local pl = api.player()
  local sx, sy = g:nearest_walkable('overworld', 611 * 16 + 8, 808 * 16 + 8, 0, 12)
  pl.body.x, pl.body.y = sx, sy
  api.check(st.skin ~= 'avatar' or not (g.profile and g.profile.avatar), 'aparença sense avatar (partida de prova)')
  local canvas = love.graphics.newCanvas(96, 40)
  local function grab(i)
    local done = false
    love.graphics.captureScreenshot(function(d)
      local cx, cy = math.floor(d:getWidth() / 2), math.floor(d:getHeight() / 2)
      local s = d:getWidth() / 320
      local part = love.image.newImageData(32, 40)
      for yy = 0, 39 do for xx = 0, 31 do
        part:setPixel(xx, yy, d:getPixel(math.min(d:getWidth() - 1, cx - 16 * s + xx * s), math.min(d:getHeight() - 1, cy - 30 * s + yy * s)))
      end end
      love.graphics.push('all'); love.graphics.setCanvas(canvas)
      love.graphics.draw(love.graphics.newImage(part), i * 32, 0)
      love.graphics.pop()
      done = true
    end)
    for _ = 1, 100 do if done then break end; api.wait(1) end
  end
  pl.vehicle = Vehicles.new_state('bici', 'down'); pl.bike = true
  for i, f in ipairs({ 'down', 'right' }) do
    pl.facing = f
    pl.vehicle.angle = f == 'down' and math.pi / 2 or 0
    api.wait(4)
    grab(i - 1)
  end
  pl:dismount()
  pl.vehicle = Vehicles.new_state('cavall', 'right'); pl.vehicle.skin = 'cavall_brown'; pl.bike = true
  pl.facing = 'right'
  api.wait(4)
  grab(2)
  love.graphics.captureScreenshot(function(d) d:encode('png', 'casc_cavall.png') end)
  api.wait(5)
  pl:dismount()
  canvas:newImageData():encode('png', 'casc_bici.png')
  -- escut: protegint-se, l'escut puja i espurneja en parar un cop
  st.inventory.shield_wood = 1
  local Rpg = require('src.systems.rpg')
  local shield_id
  for id, d in pairs(g.items) do if type(d) == 'table' and d.kind == 'shield' and not shield_id then shield_id = id end end
  st.equipment.shield = shield_id
  pl.facing = 'right'
  require('src.input').hold('shield', true)
  api.wait(3)
  api.check(pl.state == 'block' and (pl.block_t or 0) > 0, 'protegint-se: l\'escut s\'aixeca (' .. tostring(shield_id) .. ')')
  local hurt, why = pl:hit(1, pl.body.x + 20, pl.body.y, w:ctx())
  api.check(why == 'blocked' and (pl.block_flash or 0) > 0, 'en parar un cop, espurneja')
  api.wait(2)
  love.graphics.captureScreenshot(function(d) d:encode('png', 'escut.png') end)
  api.wait(5)
  require('src.input').release_all()
  api.on_frame = nil
end
