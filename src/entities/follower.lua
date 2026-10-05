-- Acompañante (Olaf, el gato): sigue al jugador por el mismo camino que ha hecho, a una distancia fija
-- medida sobre ese camino (historial de posiciones), así rodea las esquinas igual que el jugador y no se
-- atasca contra las paredes. No choca con nada ni bloquea el paso. Lua puro salvo draw().
local Follower = {}
Follower.__index = Follower

local ROW = { down = 0, up = 1, left = 2, right = 3 }

function Follower.new(name, sprite, x, y, distance)
  local self = setmetatable({}, Follower)
  self.name = name
  self.sprite = sprite
  self.x, self.y = x, y
  self.history = { { x, y } }   -- posiciones del jugador, de la más antigua a la más reciente
  self.distance = distance or 20
  self.facing = 'down'
  self.anim, self.t = 0, 0
  self.moving = false
  return self
end

-- recolocar (cambio de escena, teletransporte): detrás del jugador
-- (self.walkable(x, y), si existe, descarta sitios dentro de una pared: prueba detrás, a los lados y delante)
function Follower:place(x, y, facing)
  local dx, dy = 0, 1
  if facing == 'down' then dx, dy = 0, -1 elseif facing == 'left' then dx, dy = 1, 0 elseif facing == 'right' then dx, dy = -1, 0 end
  local cands = { { dx * 14, dy * 10 }, { dy * 14, dx * 10 }, { -dy * 14, -dx * 10 }, { -dx * 14, -dy * 10 } }
  local ox, oy = 0, 0
  for _, c in ipairs(cands) do
    if not self.walkable or self.walkable(x + c[1], y + c[2]) then ox, oy = c[1], c[2]; break end
  end
  self.x, self.y = x + ox, y + oy
  self.history = { { self.x, self.y }, { x, y } }
  self.facing = facing or 'down'
end

-- tx, ty: posición del jugador; far: distancia extra (en vehículo va un poco más atrás)
function Follower:update(dt, tx, ty, far)
  self.t = self.t + dt
  local h = self.history
  local last = h[#h]
  -- salto (tren, bus, teletransporte): el jugador no puede recorrer 48 px en un paso andando ni en vehículo
  if (tx - last[1]) ^ 2 + (ty - last[2]) ^ 2 > 48 ^ 2 or (tx - self.x) ^ 2 + (ty - self.y) ^ 2 > 200 ^ 2 then
    self:place(tx, ty, self.facing)
    h = self.history
  end
  last = h[#h]
  if (tx - last[1]) ^ 2 + (ty - last[2]) ^ 2 >= 1 then h[#h + 1] = { tx, ty } end
  -- punto del camino a `distance` px por detrás del jugador
  local want = self.distance + (far or 0)
  local acc, px, py = 0, tx, ty
  local cut = 1
  for i = #h, 2, -1 do
    local a, b = h[i], h[i - 1]
    local seg = math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2)
    if acc + seg >= want then
      local k = (want - acc) / seg
      px, py = a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k
      cut = i - 1
      break
    end
    acc = acc + seg
    px, py = b[1], b[2]
    cut = i - 1
  end
  -- el historial anterior al punto ya no hace falta
  if cut > 1 then
    local nh = {}
    for i = cut, #h do nh[#nh + 1] = h[i] end
    self.history = nh
  end
  local dx, dy = px - self.x, py - self.y
  local d = math.sqrt(dx * dx + dy * dy)
  self.moving = d > 0.3
  if self.moving then
    self.x, self.y = px, py
    self.anim = self.anim + d/64
    if math.abs(dx) > math.abs(dy) then self.facing = dx > 0 and 'right' or 'left'
    else self.facing = dy > 0 and 'down' or 'up' end
    local ax, ay = math.abs(dx), math.abs(dy)   -- en diagonal (si la fulla en té: src/paperdoll/diag.lua)
    self.diag = (ax > 0.4 * ay and ay > 0.4 * ax) and ((dy > 0 and 'd' or 'u') .. (dx < 0 and 'l' or 'r')) or nil
  end
end

function Follower:frame()
  if self.moving and self.diag and self.diag_ok and self.sprite.diag then
    return require('src.paperdoll.diag').ROW[self.diag], math.floor(self.anim * 8) % 4
  end
  if self.moving then return ROW[self.facing], math.floor(self.anim * 8) % 4 end
  return ROW[self.facing], ((self.t % 4.1) < 0.15) and 5 or 4
end

function Follower:draw(ox, oy)
  local row, col = self:frame()
  love.graphics.draw(self.sprite.sheet, self.sprite.quad(row, col),
    math.floor(self.x - 8 + 0.5) - ox, math.floor(self.y + 4 - 24 + 0.5) - oy)
end

return Follower
