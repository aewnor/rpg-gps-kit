-- Caché de chunks: carga bajo demanda, precarga en la dirección de marcha y descarga lejana.
local Chunks = {}
Chunks.__index = Chunks

function Chunks.new(map, loader)
  return setmetatable({ map = map, loader = loader, live = {}, count = 0, queue = {},
                        loads = 0, unloads = 0, on_unload = nil }, Chunks)
end

local function key(cx, cy) return cy * 1024 + cx end

function Chunks:get(cx, cy)
  local k = key(cx, cy)
  local c = self.live[k]
  if c then return c end
  c = self.loader(string.format('%s/c_%d_%d.bin', self.map.dir, cx, cy))
  c.cx, c.cy = cx, cy
  c.key = k
  self.live[k] = c
  self.count = self.count + 1
  self.loads = self.loads + 1
  if self.on_load then self.on_load(c) end   -- canvis del jugador (arbres tallats: src/systems/crafting.lua)
  return c
end

function Chunks:has(cx, cy) return self.live[key(cx, cy)] ~= nil end

function Chunks:valid(cx, cy)
  return cx >= 0 and cy >= 0 and cx * self.map.chunk < self.map.width and cy * self.map.chunk < self.map.height
end

-- Mantiene el chunk del jugador, sus 8 vecinos y precarga 1 chunk por llamada en la dirección
-- de marcha. Descarga los que quedan a más de `keep` chunks.
function Chunks:update(px, py, vx, vy, keep)
  keep = keep or 2
  local size = self.map.chunk * self.map.tile
  local cx, cy = math.floor(px / size), math.floor(py / size)
  for dy = -1, 1 do
    for dx = -1, 1 do
      if self:valid(cx + dx, cy + dy) then self:get(cx + dx, cy + dy) end
    end
  end
  -- precarga anticipada (fila/columna siguiente en la dirección de marcha)
  local sx = vx > 0 and 2 or vx < 0 and -2 or 0
  local sy = vy > 0 and 2 or vy < 0 and -2 or 0
  if sx ~= 0 or sy ~= 0 then
    for d = -1, 1 do
      local tx = cx + (sx ~= 0 and sx or d)
      local ty = cy + (sy ~= 0 and sy or d)
      if self:valid(tx, ty) and not self:has(tx, ty) then
        self:get(tx, ty)
        break -- un chunk por frame como máximo
      end
    end
  end
  for k, c in pairs(self.live) do
    if math.abs(c.cx - cx) > keep or math.abs(c.cy - cy) > keep then
      if self.on_unload then self.on_unload(c) end
      self.live[k] = nil
      self.count = self.count - 1
      self.unloads = self.unloads + 1
    end
  end
end

function Chunks:clear()
  for k, c in pairs(self.live) do
    if self.on_unload then self.on_unload(c) end
    self.live[k] = nil
  end
  self.count = 0
end

return Chunks
