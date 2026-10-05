-- Cámara que sigue al jugador dentro de los límites del mapa. Posición física en flotante;
-- la de dibujo se redondea (sin redondear las coordenadas del mundo).
local Camera = {}
Camera.__index = Camera

function Camera.new(w, h)
  return setmetatable({ x = 0, y = 0, w = w, h = h }, Camera)
end

function Camera:follow(tx, ty, map_w, map_h)
  local x = tx - self.w / 2
  local y = ty - self.h / 2
  if map_w <= self.w then x = (map_w - self.w) / 2 else x = math.max(0, math.min(map_w - self.w, x)) end
  if map_h <= self.h then y = (map_h - self.h) / 2 else y = math.max(0, math.min(map_h - self.h, y)) end
  self.x, self.y = x, y
end

function Camera:draw_offset()
  return math.floor(self.x + 0.5), math.floor(self.y + 0.5)
end

function Camera:visible(x, y, w, h, margin)
  margin = margin or 32
  return x + w > self.x - margin and x < self.x + self.w + margin and
         y + h > self.y - margin and y < self.y + self.h + margin
end

return Camera
