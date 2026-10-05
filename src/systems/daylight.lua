-- Ciclo de día y noche (exteriores). Un día de juego dura DAY_MINUTES minutos reales.
-- De noche se pinta un lienzo de luz (ambiente + focos aditivos) que se multiplica sobre la escena:
-- farolas, ventanas y escaparates (detectados en los chunks visibles), marquesinas, faros de coches
-- y una luz suave alrededor del jugador.
local Daylight = {}
Daylight.__index = Daylight

Daylight.DAY_MINUTES = 24
local W, H = 320, 240

-- color del ambiente por hora (minutos del día) y factor de noche 0..1
local KEYS = {
  { 0, 0.20, 0.24, 0.46 }, { 330, 0.20, 0.24, 0.46 }, { 400, 0.80, 0.62, 0.62 }, { 460, 1, 1, 1 },
  { 1110, 1, 1, 1 }, { 1180, 0.92, 0.66, 0.52 }, { 1250, 0.20, 0.24, 0.46 }, { 1440, 0.20, 0.24, 0.46 },
}

function Daylight.ambient(clock)
  clock = (clock or 600) % 1440
  for i = 1, #KEYS - 1 do
    local a, b = KEYS[i], KEYS[i + 1]
    if clock >= a[1] and clock <= b[1] then
      local k = (clock - a[1]) / math.max(1, b[1] - a[1])
      local r = a[2] + (b[2] - a[2]) * k
      local g = a[3] + (b[3] - a[3]) * k
      local bl = a[4] + (b[4] - a[4]) * k
      local night = 1 - (r + g + bl) / 3
      return r, g, bl, math.max(0, math.min(1, night / 0.7))
    end
  end
  return 1, 1, 1, 0
end

function Daylight.advance(state, dt)
  local c = (state.clock or 600) + dt * 1440 / (Daylight.DAY_MINUTES * 60)
  if c >= 1440 then state.day = (state.day or 1) + 1 end   -- día de juego (ofertas del Lidl, revisión médica)
  state.clock = c % 1440
end

-- salta `minutes` minutos de reloj (dormir): pasa de día si cruza la medianoche
function Daylight.skip(state, minutes)
  local c = (state.clock or 600) + minutes
  while c >= 1440 do c = c - 1440; state.day = (state.day or 1) + 1 end
  state.clock = c
end

function Daylight.label(clock)
  clock = math.floor(clock or 600)
  return string.format('%02d:%02d', math.floor(clock / 60) % 24, clock % 60)
end

-- tipo de luz por nombre de tile (los genera tools/make_tiles.py)
function Daylight.light_kinds(tiles)
  local kinds = {}
  for name, t in pairs(tiles) do
    local kind
    if name == 'o_lamp' then kind = 'lamp'
    elseif name == 'o_busstop_l' then kind = 'bus'
    elseif name:match('^f_.*_win$') or name:match('^f_.*_bal$') or name:match('^f_.*_arch$') or
        name:match('^f_.*_up$') then kind = 'win'
    elseif name:match('^f_.*_shop%d?$') then kind = 'shop'
    elseif name:match('^f_.*_door$') then kind = 'door' end
    if kind then kinds[t.id + 1] = kind end
  end
  return kinds
end

local LIGHT = {  -- radio (px) y color
  lamp = { 46, 1.0, 0.86, 0.55 }, bus = { 30, 0.70, 0.85, 1.0 }, win = { 13, 1.0, 0.78, 0.42 },
  shop = { 22, 1.0, 0.85, 0.6 }, door = { 12, 1.0, 0.75, 0.45 },
  pumpkin = { 18, 1.0, 0.55, 0.15 }, xmas = { 22, 0.9, 1.0, 0.6 }, garland = { 14, 1.0, 0.7, 0.6 },
}

function Daylight.new()
  local self = setmetatable({}, Daylight)
  self.canvas = love.graphics.newCanvas(W, H)
  local size = 64
  local id = love.image.newImageData(size, size)
  for y = 0, size - 1 do
    for x = 0, size - 1 do
      local d = math.sqrt((x + 0.5 - size / 2) ^ 2 + (y + 0.5 - size / 2) ^ 2) / (size / 2)
      local a = math.max(0, 1 - d) ^ 1.5
      id:setPixel(x, y, a, a, a, 1)
    end
  end
  self.glow = love.graphics.newImage(id)
  self.glow:setFilter('linear', 'linear')
  return self
end

local function spot(self, x, y, r, cr, cg, cb, k)
  love.graphics.setColor(cr * k, cg * k, cb * k, 1)
  love.graphics.draw(self.glow, x - r, y - r, 0, 2 * r / 64, 2 * r / 64)
end

-- chunks: visibles (con _lights del renderer); cars: lista {x, y, ang}; player: {x, y}
function Daylight:draw(clock, chunks, cars, player, ox, oy, tint, vw, vh)
  local r, g, b, night = Daylight.ambient(clock)
  if tint and night > 0 then  -- tinte de temporada (más intenso cuanto más de noche)
    r = r * (1 + (tint[1] - 1) * night); g = g * (1 + (tint[2] - 1) * night); b = b * (1 + (tint[3] - 1) * night)
  end
  if night < 0.02 then return end
  local W, H = vw or 320, vh or 240   -- vista allunyada: 640 × 480
  if self.canvas:getWidth() ~= W then self.canvas = love.graphics.newCanvas(W, H) end
  local prev = love.graphics.getCanvas()
  love.graphics.push('all')
  love.graphics.setCanvas(self.canvas)
  love.graphics.origin()
  love.graphics.clear(r, g, b, 1)
  love.graphics.setBlendMode('add')
  local k = math.min(1, night * 1.15)
  for _, c in ipairs(chunks) do
    for _, l in ipairs(c._lights or {}) do
      local x, y = l[1] - ox, l[2] - oy
      local L = LIGHT[l[3]]
      if x > -L[1] and x < W + L[1] and y > -L[1] and y < H + L[1] then
        if l[3] == 'lamp' then y = y - 6 end
        spot(self, x, y, L[1], L[2], L[3], L[4], k)
      end
    end
  end
  for _, c in ipairs(cars or {}) do
    local fx, fy = c.x + math.cos(c.ang) * 22 - ox, c.y + math.sin(c.ang) * 22 - oy
    if fx > -40 and fx < W + 40 and fy > -40 and fy < H + 40 then
      spot(self, fx, fy, 26, 1.0, 0.92, 0.65, k)
      spot(self, c.x - math.cos(c.ang) * 12 - ox, c.y - math.sin(c.ang) * 12 - oy, 8, 1.0, 0.2, 0.15, k)
    end
  end
  if player then spot(self, player.x - ox, player.y - 10 - oy, 34 * (player.light or 1), 0.55, 0.5, 0.42, k) end
  love.graphics.pop()
  love.graphics.setCanvas(prev)
  love.graphics.setBlendMode('multiply', 'premultiplied')
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(self.canvas, 0, 0)
  love.graphics.setBlendMode('alpha')
  -- las bombillas de las farolas brillan por encima de la oscuridad
  love.graphics.setBlendMode('add')
  for _, c in ipairs(chunks) do
    for _, l in ipairs(c._lights or {}) do
      if l[3] == 'lamp' then
        local x, y = l[1] - ox, l[2] - oy - 6
        if x > -8 and x < W + 8 and y > -8 and y < H + 8 then spot(self, x, y, 6, 1, 0.9, 0.6, k * 0.8) end
      end
    end
  end
  love.graphics.setBlendMode('alpha')
  love.graphics.setColor(1, 1, 1, 1)
end

return Daylight
