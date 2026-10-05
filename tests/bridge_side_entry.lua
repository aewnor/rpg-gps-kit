-- Puente de Carrer de la Via sobre el tren, llegando por la Av. de l'Avenc (de lado): con las teclas,
-- como una persona que apunta al centro del puente, hay que poder cruzar
-- (love . --test=tests/bridge_side_entry.lua --mute).
return function(api)
  local Input = require('src.input')
  api.wait(5)
  api.scene().traffic.cars = {}   -- sin coches: prueba determinista
  local CX = 656.1 * 16           -- eje del puente (lines.json)
  local function steer_x(frames)
    for _ = 1, frames do
      local b = api.player().body
      Input.release_all()
      if b.x < CX - 3 then Input.hold('right', true) elseif b.x > CX + 3 then Input.hold('left', true) else break end
      api.wait(1)
    end
    Input.release_all(); api.wait(2)
  end
  local function hold(dir, frames) Input.hold(dir, true); api.wait(frames); Input.release_all(); api.wait(2) end
  local function tile() local b = api.player().body; return math.floor(b.x / 16), math.floor(b.y / 16), b.level end
  -- 1) desde la avenida (este): ir al centro del puente y bajar
  api.teleport(661, 790); api.wait(5)
  steer_x(120); hold('down', 220)
  local x, y, l = tile()
  api.check(y >= 800, string.format('desde la avenida se cruza la vía (llega a %d,%d nivel %d)', x, y, l))
  -- 2) de sur a norte
  api.teleport(656, 804); api.wait(5)
  hold('up', 420)
  x, y, l = tile()
  api.check(y <= 786, string.format('de sur a norte (llega a %d,%d nivel %d)', x, y, l))
  -- 3) en diagonal desde la avenida hasta el puente, luego abajo
  api.teleport(662, 788); api.wait(5)
  Input.hold('left', true); Input.hold('down', true); api.wait(45); Input.release_all(); api.wait(2)
  steer_x(120); hold('down', 220)
  x, y, l = tile()
  api.check(y >= 800, string.format('en diagonal desde la avenida (llega a %d,%d nivel %d)', x, y, l))
end
