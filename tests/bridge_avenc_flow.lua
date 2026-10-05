-- Pont de Carrer de la Via a l'Av. de l'Avenc (love . --test=tests/bridge_avenc_flow.lua --mute): venint del sud
-- per sobre de la via i girant a l'est a l'avinguda, abans hi havia un mur invisible (el tauler seguia «a dalt»
-- per terra ferma). Ara s'hi pot girar.
return function(api)
  local Input = require('src.input')
  api.talk_through()
  api.on_frame = function()
    local d = api.scene().dialogue
    if d.open then d.open = false; if d.on_close then d.on_close() end end
  end
  local b = api.player().body
  api.teleport(655, 801); api.wait(5)
  Input.hold('up', true)
  for _ = 1, 400 do if b.y < 790.5 * 16 then break end; api.wait(1) end
  Input.release_all()
  api.check(b.y < 791 * 16, 'creues el pont cap al nord (y=' .. math.floor(b.y / 16) .. ', nivell ' .. tostring(b.level) .. ')')
  Input.hold('right', true)
  for _ = 1, 200 do if b.x > 662 * 16 then break end; api.wait(1) end
  Input.release_all()
  api.check(b.x > 662 * 16, 'gires a l\'est per l\'avinguda sense mur (x=' .. math.floor(b.x / 16) .. ')')
  api.check((b.level or 0) == 0, 'i ja ets a nivell del carrer')
  api.on_frame = nil
end
