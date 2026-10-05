-- Vídeo de la conducció guiada (love . --test=tests/vehicle_assist_video.lua --mute): Av. de l'Avenc cap al nord amb
-- la fletxa amunt fixa (la via fa revolts). Fotogrames guia_NNN.png
return function(api)
  local Input = require('src.input')
  local Vehicles = require('src.systems.vehicles')
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local pl = api.player()
  local Roads = require('src.systems.roads')
  -- punt de l'eix més proper a (10435, 12047)
  api.teleport(652, 752); api.wait(3)
  pl.vehicle = Vehicles.new_state('scooter', 'up'); pl.bike = true
  Input.hold('up', true)
  local n = 0
  for i = 1, 420 do
    api.wait(1)
    if i % 3 == 0 then
      n = n + 1
      love.graphics.captureScreenshot(string.format('guia_%03d.png', n))
    end
  end
  Input.release_all()
  local near = #Roads.near(pl.body.x, pl.body.y, 16, {})
  api.check(near > 0, 'acaba sobre una via (' .. math.floor(pl.body.x / 16) .. ', ' .. math.floor(pl.body.y / 16) .. ')')
  api.on_frame = nil
end
