-- Sacudida de cámara por «trauma» (0..1): los golpes suman trauma, que baja solo; el desplazamiento es
-- proporcional a trauma² (los toques flojos casi no se notan, los fuertes sí). Además, un «retumbo»
-- continuo (tren que pasa al lado) que se fija cada paso y no se acumula. Desplazamiento en píxeles enteros.
local Shake = {}
Shake.__index = Shake

Shake.MAX_X, Shake.MAX_Y = 4, 3
Shake.DECAY = 1.8      -- trauma por segundo

function Shake.new(rng)
  return setmetatable({ trauma = 0, rumble = 0, t = 0, rng = rng or math.random }, Shake)
end

function Shake:add(amount) self.trauma = math.min(1, self.trauma + amount) end

-- retumbo de este paso (0..1): se queda con el mayor de los que lleguen
function Shake:set_rumble(r) if r > self.rumble then self.rumble = math.min(0.6, r) end end

function Shake:update(dt)
  self.t = self.t + dt
  self.trauma = math.max(0, self.trauma - Shake.DECAY * dt)
  self.level = math.max(self.trauma, self.rumble)
  self.rumble = 0
end

function Shake:offset()
  if require('src.motion').reduced then return 0,0 end
  local s = (self.level or 0) ^ 2
  if s < 0.01 then return 0, 0 end
  local x=.7*math.sin(self.t*36)+.3*math.sin(self.t*71)
  local y=.7*math.cos(self.t*43)+.3*math.sin(self.t*67)
  return math.floor(x*Shake.MAX_X*s+.5), math.floor(y*Shake.MAX_Y*s+.5)
end

return Shake
