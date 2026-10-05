-- Números flotantes sobre el mundo (+20 XP, +4 HP, -2…): suben, se frenan y se desvanecen.
-- Como mucho MAX a la vez (el más viejo se recicla); si salen varios en el mismo sitio se apilan hacia arriba.
-- update() es Lua puro (tests/juice_cases.lua).
local Popups = {}
Popups.__index = Popups

local MAX = 10
local LIFE = 1.1
Popups.COLORS = {
  xp = { 1.0, 0.86, 0.40 }, hp = { 0.55, 0.92, 0.50 }, coins = { 1.0, 0.80, 0.25 }, dmg = { 1.0, 0.42, 0.36 },
  hurt = { 1.0, 0.30, 0.30 }, stat = { 0.55, 0.85, 1.0 }, info = { 0.96, 0.94, 0.89 },
}

function Popups.new()
  return setmetatable({ list = {}, clock = 0 }, Popups)
end

-- kind: clave de COLORS (o una tabla de color)
function Popups:add(x, y, text, kind)
  local list = self.list
  -- apilar: otro texto reciente cerca → este, una línea más arriba
  local lift = 0
  for _, p in ipairs(list) do
    if p.t < 0.35 and math.abs(p.x0 - x) < 24 and math.abs(p.y0 - y) < 24 then lift = math.max(lift, p.lift + 11) end
  end
  local p
  if #list >= MAX then p = table.remove(list, 1) else p = {} end
  p.x0, p.y0, p.lift = x, y, lift
  p.text, p.t = text, 0
  p.color = type(kind) == 'table' and kind or Popups.COLORS[kind or 'info'] or Popups.COLORS.info
  list[#list + 1] = p
  return p
end

function Popups:update(dt)
  local list = self.list
  for i = #list, 1, -1 do
    local p = list[i]
    p.t = p.t + dt
    if p.t >= LIFE then table.remove(list, i) end
  end
end

-- desplazamiento vertical: sube rápido y se frena (ease-out)
function Popups.rise(t)
  local k = math.min(1, t / LIFE)
  if require('src.motion').reduced then return 0 end
  return 22 * (1 - (1 - k) ^ 3)
end

function Popups:draw(font, ox, oy)
  for _, p in ipairs(self.list) do
    local k = p.t / LIFE
    local a = k < 0.7 and 1 or (1 - (k - 0.7) / 0.3)
    local w = font:getWidth(p.text)
    local x = math.floor(p.x0 - ox - w / 2 + 0.5)
    local y = math.floor(p.y0 - oy - 28 - p.lift - Popups.rise(p.t) + 0.5)
    -- pequeño «pop» de escala al aparecer: un píxel arriba en los primeros instantes
    if p.t < 0.08 then y = y - 1 end
    love.graphics.setColor(0.08, 0.06, 0.10, 0.85 * a)
    love.graphics.print(p.text, x + 1, y + 1)
    love.graphics.print(p.text, x - 1, y + 1)
    love.graphics.print(p.text, x, y + 2)
    love.graphics.setColor(p.color[1], p.color[2], p.color[3], a)
    love.graphics.print(p.text, x, y)
  end
  love.graphics.setColor(1, 1, 1, 1)
end

return Popups
