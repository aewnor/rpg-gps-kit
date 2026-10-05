-- Lienzo de píxeles en Lua puro (equivalente a Sprite de tools/pixel.py): colores {r, g, b, a} de 0 a 255.
-- Lo usa el paperdoll (src/paperdoll/) para generar hojas de personaje en tiempo de ejecución; sin love.*
-- salvo to_image(), para poder probarlo con luajit contra las hojas de Python (tests/paperdoll_cases.py).
local json = require('src.lib.json')

local C = {}
C.__index = C

-- ---------------------------------------------------------------- colores
local PALETTE
local function palette()
  if not PALETTE then
    local txt
    if love and love.filesystem and love.filesystem.read then txt = love.filesystem.read('data/palette.json')
    else local f = assert(io.open('data/palette.json')); txt = f:read('*a'); f:close() end
    PALETTE = {}
    for name, hex in pairs(json.decode(txt)) do PALETTE[name] = C.hex(hex) end
  end
  return PALETTE
end

function C.hex(h)
  h = h:gsub('#', '')
  return { tonumber(h:sub(1, 2), 16), tonumber(h:sub(3, 4), 16), tonumber(h:sub(5, 6), 16), 255 }
end

local cache = {}
-- nombre de la paleta, '#rrggbb' o tabla → {r, g, b, a}
function C.rgba(c)
  if type(c) == 'table' then return c end
  local v = cache[c]
  if v then return v end
  if c:sub(1, 1) == '#' then v = C.hex(c) else v = palette()[c] end
  assert(v, 'color desconocido: ' .. tostring(c))
  cache[c] = v
  return v
end

-- redondeo de Python (mitades al par): mismos píxeles que tools/pixel.py
local function pyround(x)
  local f = math.floor(x)
  local d = x - f
  if d > 0.5 then return f + 1 elseif d < 0.5 then return f end
  return (f % 2 == 0) and f or f + 1
end
C.pyround = pyround

-- mezcla (k = 0 → a, k = 1 → b), como pixel.mix
function C.mix(a, b, k)
  a, b = C.rgba(a), C.rgba(b)
  return { pyround(a[1] * (1 - k) + b[1] * k), pyround(a[2] * (1 - k) + b[2] * k), pyround(a[3] * (1 - k) + b[3] * k), 255 }
end

-- ---------------------------------------------------------------- lienzo
function C.new(w, h)
  return setmetatable({ w = w, h = h, p = {} }, C)   -- p[y * w + x + 1] = color
end

function C:px(x, y, c)
  if x >= 0 and x < self.w and y >= 0 and y < self.h then self.p[y * self.w + x + 1] = C.rgba(c) end
end

function C:get(x, y)
  if x >= 0 and x < self.w and y >= 0 and y < self.h then return self.p[y * self.w + x + 1] end
end

function C:rect(x, y, w, h, c) for yy = y, y + h - 1 do for xx = x, x + w - 1 do self:px(xx, yy, c) end end end
function C:hline(x0, x1, y, c) for x = x0, x1 do self:px(x, y, c) end end
function C:vline(x, y0, y1, c) for y = y0, y1 do self:px(x, y, c) end end

function C:blit(o, x, y)
  for yy = 0, o.h - 1 do
    for xx = 0, o.w - 1 do
      local c = o.p[yy * o.w + xx + 1]
      if c and c[4] > 0 then self:px(x + xx, y + yy, c) end
    end
  end
end

function C:pattern(x, y, rows, cmap)
  for j, row in ipairs(rows) do
    for i = 1, #row do
      local ch = row:sub(i, i)
      if cmap[ch] then self:px(x + i - 1, y + j - 1, cmap[ch]) end
    end
  end
end

function C:flip_h()
  local s = C.new(self.w, self.h)
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do s.p[y * self.w + (self.w - 1 - x) + 1] = self.p[y * self.w + x + 1] end
  end
  return s
end

-- trozo (como sh.a[y0:y0+h, x0:x0+w])
function C:crop(x0, y0, w, h)
  local s = C.new(w, h)
  for y = 0, h - 1 do for x = 0, w - 1 do s.p[y * w + x + 1] = self:get(x0 + x, y0 + y) end end
  return s
end

-- monta lienzos del mismo tamaño en una hoja de `cols` columnas (pixel.sheet)
function C.sheet(list, cols)
  local w, h = list[1].w, list[1].h
  local rows = math.ceil(#list / cols)
  local out = C.new(w * cols, h * rows)
  for i, s in ipairs(list) do
    local ox, oy = ((i - 1) % cols) * w, math.floor((i - 1) / cols) * h
    for y = 0, h - 1 do for x = 0, w - 1 do out.p[(oy + y) * out.w + ox + x + 1] = s.p[y * w + x + 1] end end
  end
  return out
end

-- bytes RGBA (para comparar con Python en las pruebas)
function C:bytes()
  local t = {}
  for i = 1, self.w * self.h do
    local c = self.p[i]
    t[i] = c and string.char(c[1], c[2], c[3], c[4]) or '\0\0\0\0'
  end
  return table.concat(t)
end

function C:to_imagedata()
  local d = love.image.newImageData(self.w, self.h)
  for y = 0, self.h - 1 do
    for x = 0, self.w - 1 do
      local c = self.p[y * self.w + x + 1]
      if c then d:setPixel(x, y, c[1] / 255, c[2] / 255, c[3] / 255, c[4] / 255) end
    end
  end
  return d
end

function C:to_image()
  local i = love.graphics.newImage(self:to_imagedata())
  i:setFilter('nearest', 'nearest')
  return i
end

return C
