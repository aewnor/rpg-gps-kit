-- Dibujo común de los minijuegos: panel a pantalla completa, títulos, ayudas de teclas e iconos en
-- píxel (sol, petxina, Arc de Berà, Olaf, estrella, moneda) hechos con primitivas: sin imágenes extra.
local UI = {}

UI.C = {
  bg = { 0.12, 0.10, 0.14 }, panel = { 0.20, 0.16, 0.22 }, edge = { 0.89, 0.72, 0.40 }, text = { 0.96, 0.94, 0.89 },
  dim = { 0.70, 0.66, 0.60 }, good = { 0.55, 0.92, 0.50 }, bad = { 1.0, 0.45, 0.40 }, gold = { 1.0, 0.82, 0.30 },
  red = { 0.79, 0.25, 0.23 }, sea = { 0.29, 0.64, 0.69 }, ink = { 0.12, 0.10, 0.14 },
}

local function col(c, a) love.graphics.setColor(c[1], c[2], c[3], a or 1) end
UI.col = col

function UI.frame(title, font)
  col(UI.C.bg); love.graphics.rectangle('fill', 0, 0, 320, 240)
  col(UI.C.panel); love.graphics.rectangle('fill', 4, 4, 312, 232)
  col(UI.C.edge); love.graphics.rectangle('line', 4.5, 4.5, 311, 231)
  col(UI.C.gold); UI.center(title, 8, font)
end

function UI.center(text, y, font, c)
  if c then col(c) end
  love.graphics.print(text, math.floor(160 - font:getWidth(text) / 2), y)
end

-- línea de ayuda abajo («Z: aturar · Esc: sortir»)
function UI.help(text, font)
  col(UI.C.dim); UI.center(text, 218, font)
  love.graphics.setColor(1, 1, 1)
end

-- texto grande con sombra (resultados)
function UI.big(text, y, font, c, elapsed)
  local motion=require('src.motion')
  local k=motion.ease((elapsed or 1)/.18)
  y=y+(motion.reduced and 0 or math.floor(3*(1-k)+.5))
  local s = 2
  local w = font:getWidth(text) * s
  local x = math.floor(160 - w / 2)
  col(UI.C.ink, 0.9*k); love.graphics.print(text, x + 2, y + 2, 0, s, s)
  col(c or UI.C.gold,k); love.graphics.print(text, x, y, 0, s, s)
  love.graphics.setColor(1,1,1,1)
end

-- ---------------------------------------------------------------- iconos 16×16 (escala s)
local function px(x0, y0, s, x, y, w, h) love.graphics.rectangle('fill', x0 + x * s, y0 + y * s, (w or 1) * s, (h or 1) * s) end

UI.ICONS = {
  sol = function(x, y, s)
    col({ 1.0, 0.75, 0.25 })
    for _, r in ipairs({ { 7, 0, 2, 3 }, { 7, 13, 2, 3 }, { 0, 7, 3, 2 }, { 13, 7, 3, 2 }, { 2, 2, 2, 2 }, { 12, 2, 2, 2 },
                         { 2, 12, 2, 2 }, { 12, 12, 2, 2 } }) do px(x, y, s, r[1], r[2], r[3], r[4]) end
    col({ 1.0, 0.86, 0.35 }); px(x, y, s, 4, 4, 8, 8)
    col({ 1.0, 0.95, 0.6 }); px(x, y, s, 5, 5, 3, 2)
  end,
  petxina = function(x, y, s)
    col({ 0.96, 0.78, 0.74 })
    for k = 0, 5 do px(x, y, s, 7 - k, 3 + k, 2 + 2 * k, 1) end
    px(x, y, s, 2, 9, 12, 3)
    col({ 0.80, 0.55, 0.52 })
    for _, cx in ipairs({ 4, 7, 10 }) do px(x, y, s, cx, 6, 1, 6) end
    px(x, y, s, 6, 12, 4, 2)
  end,
  arc = function(x, y, s)       -- Arc de Berà: pilars i arc de pedra
    col({ 0.79, 0.73, 0.63 }); px(x, y, s, 1, 2, 14, 3); px(x, y, s, 1, 5, 4, 10); px(x, y, s, 11, 5, 4, 10)
    px(x, y, s, 5, 5, 6, 2)
    col({ 0.65, 0.58, 0.48 }); px(x, y, s, 0, 1, 16, 1); px(x, y, s, 2, 6, 1, 9); px(x, y, s, 13, 6, 1, 9)
    col({ 0.29, 0.64, 0.69 }); px(x, y, s, 6, 7, 4, 8)
  end,
  olaf = function(x, y, s)      -- cara de gat gris
    col({ 0.55, 0.55, 0.58 }); px(x, y, s, 2, 1, 3, 4); px(x, y, s, 11, 1, 3, 4); px(x, y, s, 2, 4, 12, 10)
    col({ 0.75, 0.75, 0.78 }); px(x, y, s, 5, 9, 6, 4)
    col({ 0.55, 0.85, 0.40 }); px(x, y, s, 4, 6, 2, 2); px(x, y, s, 10, 6, 2, 2)
    col({ 0.95, 0.6, 0.65 }); px(x, y, s, 7, 9, 2, 1)
    col({ 0.12, 0.10, 0.14 }); px(x, y, s, 5, 6, 1, 2); px(x, y, s, 11, 6, 1, 2)
  end,
  estrella = function(x, y, s)
    col({ 0.98, 0.85, 0.35 })
    px(x, y, s, 7, 1, 2, 4); px(x, y, s, 1, 5, 14, 2); px(x, y, s, 3, 7, 10, 2); px(x, y, s, 4, 9, 8, 2)
    px(x, y, s, 3, 11, 3, 3); px(x, y, s, 10, 11, 3, 3); px(x, y, s, 5, 5, 6, 6)
    col({ 1, 0.97, 0.75 }); px(x, y, s, 6, 6, 2, 2)
  end,
  moneda = function(x, y, s)
    col({ 0.75, 0.55, 0.29 }); px(x, y, s, 4, 1, 8, 14); px(x, y, s, 2, 3, 12, 10); px(x, y, s, 1, 5, 14, 6)
    col({ 0.98, 0.80, 0.30 }); px(x, y, s, 4, 2, 8, 12); px(x, y, s, 3, 4, 10, 8)
    col({ 0.75, 0.55, 0.29 }); px(x, y, s, 7, 4, 2, 8)
    col({ 1, 0.95, 0.6 }); px(x, y, s, 5, 4, 1, 3)
  end,
  poma = function(x, y, s)
    col({ 0.79, 0.25, 0.23 }); px(x, y, s, 3, 5, 10, 9); px(x, y, s, 4, 4, 8, 11)
    col({ 0.45, 0.58, 0.28 }); px(x, y, s, 8, 1, 3, 3)
    col({ 0.95, 0.6, 0.5 }); px(x, y, s, 5, 6, 2, 2)
  end,
  gema = function(x, y, s)
    col({ 0.33, 0.78, 0.76 }); px(x, y, s, 4, 3, 8, 3); px(x, y, s, 2, 6, 12, 2); px(x, y, s, 4, 8, 8, 3); px(x, y, s, 6, 11, 4, 3)
    col({ 0.75, 0.97, 0.95 }); px(x, y, s, 5, 4, 2, 2)
  end,
  xp = function(x, y, s)
    col({ 1.0, 0.86, 0.40 }); px(x, y, s, 1, 4, 14, 8)
    col({ 0.33, 0.24, 0.13 }); px(x, y, s, 3, 6, 1, 4); px(x, y, s, 5, 6, 1, 4); px(x, y, s, 4, 8, 1, 1)
    px(x, y, s, 8, 6, 1, 4); px(x, y, s, 9, 6, 2, 1); px(x, y, s, 9, 8, 2, 1); px(x, y, s, 11, 7, 1, 1)
  end,
}

function UI.icon(name, x, y, s)
  local f = UI.ICONS[name]
  if f then f(math.floor(x), math.floor(y), s or 1) end
  love.graphics.setColor(1, 1, 1)
end

-- fletxa d'una direcció (ritme): triangle + tija
function UI.arrow(dir, cx, cy, size, c)
  col(c)
  local a = ({ left = math.pi, right = 0, up = -math.pi / 2, down = math.pi / 2 })[dir]
  local s = size
  local function p(dx, dy) return cx + dx * math.cos(a) - dy * math.sin(a), cy + dx * math.sin(a) + dy * math.cos(a) end
  local x1, y1 = p(s, 0)
  local x2, y2 = p(0, -s)
  local x3, y3 = p(0, s)
  love.graphics.polygon('fill', x1, y1, x2, y2, x3, y3)
  local a1x, a1y = p(0, -s * 0.4)
  local a2x, a2y = p(-s, -s * 0.4)
  local a3x, a3y = p(-s, s * 0.4)
  local a4x, a4y = p(0, s * 0.4)
  love.graphics.polygon('fill', a1x, a1y, a2x, a2y, a3x, a3y, a4x, a4y)
end

return UI
