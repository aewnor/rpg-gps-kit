-- Paperdoll: personajes 16 × 24 dibujados por capas en tiempo de ejecución. Port fiel de tools/chars.py
-- (mismos píxeles: tests/paperdoll_cases.py lo comprueba contra las hojas de Python).
--
-- Capas, de atrás adelante: pelo largo por la espalda → piernas y zapatos → tronco, ropa y brazos → cara →
-- pelo → complementos → sombrero; al final, contorno exterior automático en tinta.
--
-- spec: colores por letra — h/H pelo, s/S piel, w/W ropa, b pantalón o falda, o zapatos, r boca, e iris,
-- p rubor, c/C complemento — (nombre de la paleta o '#rrggbb') y estilo: _hair (short, bob, long, pigtails,
-- bun, bald, spiky), _outfit (tshirt, shorts, pants, dress, sweater, uniform), _hat (cap, ranger, beanie,
-- witch, pirate, santa, pumpkin, chef, nena), _extra (apron, bag, cane, beard, glasses, scarf, belt, ribs).
-- Solo en Lua: _age = 'kid' (1 px más bajo: el cuerpo baja y las piernas se acortan).
local Canvas = require('src.paperdoll.canvas')
local mix = Canvas.mix

local M = {}
local W, H = 16, 24
local INK = 'ink'
M.W, M.H = W, H

M.DEFAULTS = { h = 'ochre3', H = 'terra3', s = 'skin', S = 'skin2', w = 'white', W = 'white2',
               b = 'blue', o = 'terra3', r = 'terra2', e = 'asph3', p = 'blush' }

-- lienzo disperso (x, y) → color
local Px = {}
Px.__index = Px
local function px_new() return setmetatable({ p = {}, n = {} }, Px) end
function Px:put(x, y, c)
  if x >= 0 and x < W and y >= 0 and y < H then self.p[y * W + x] = c end
end
function Px:rect(x0, y0, x1, y1, c) for y = y0, y1 do for x = x0, x1 do self:put(x, y, c) end end end
function Px:has(x, y) return self.p[y * W + x] ~= nil end
function Px:merge(o, dy)
  for k, c in pairs(o.p) do self:put(k % W, math.floor(k / W) + (dy or 0), c) end
end
function Px:sprite()
  local s = Canvas.new(W, H)
  for k in pairs(self.p) do
    local x, y = k % W, math.floor(k / W)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local qx, qy = x + d[1], y + d[2]
      if qx >= 0 and qx < W and qy >= 0 and qy < H and self.p[qy * W + qx] == nil then s:px(qx, qy, INK) end
    end
  end
  for k, c in pairs(self.p) do s:px(k % W, math.floor(k / W), c) end
  return s
end

-- ---------------------------------------------------------------- cabeza
local HEAD_ROWS = { [2] = { 4, 11 }, [11] = { 4, 11 } }
local function head_row(y, dx0, dx1) local r = HEAD_ROWS[y]; if r then return r[1], r[2] end return dx0, dx1 end

local function head_shape(px, c)
  for y = 2, 11 do
    local x0, x1 = head_row(y, 3, 12)
    px:rect(x0, y, x1, y, c)
  end
end

local function face(px, d, cm, blink)
  local s, S = cm.s, cm.S
  if d == 'down' then
    head_shape(px, s)
    for y = 3, 11 do if px:has(12, y) then px:put(12, y, S) end end
    px:put(11, 11, S)
    if blink then
      for _, x in ipairs({ 5, 6, 9, 10 }) do px:put(x, 8, INK) end
    else
      for _, ex in ipairs({ 5, 9 }) do
        px:put(ex, 7, INK); px:put(ex + 1, 7, 'white')
        px:put(ex, 8, cm.e); px:put(ex + 1, 8, INK)
      end
    end
    px:put(4, 9, cm.p); px:put(11, 9, cm.p)
    px:put(7, 10, cm.r); px:put(8, 10, cm.r)
  elseif d == 'up' then
    head_shape(px, s)
  else
    head_shape(px, s)
    px:put(2, 8, s)
    px:put(9, 8, S); px:put(9, 9, S)
    if blink then
      px:put(4, 8, INK); px:put(5, 8, INK)
    else
      px:put(4, 7, 'white'); px:put(5, 7, INK); px:put(4, 8, cm.e); px:put(5, 8, INK)
    end
    px:put(5, 9, cm.p)
    px:put(3, 10, cm.r)
  end
end

local function contains(list, v) for _, x in ipairs(list) do if x == v then return true end end return false end

local function hair(px, d, cm, style)
  local h, Hs = cm.h, cm.H
  local L = cm.L or mix(h, 'white', 0.28)
  local function put(x, y, c) px:put(x, y, c or h) end
  if style == 'bald' then
    if d == 'up' then
      for y = 5, 10 do for x = 3, 12 do put(x, y, y > 8 and Hs or h) end end
    elseif d == 'down' then
      for y = 5, 8 do put(3, y); put(12, y, Hs) end
    else
      for y = 5, 9 do for x = 9, 12 do put(x, y, x == 12 and Hs or h) end end
    end
    return
  end
  for y = 2, 5 do
    local x0, x1 = head_row(y, 3, 12)
    for x = x0, x1 do
      if not (d == 'left' and y == 5 and x < 6) then
        put(x, y, ((x >= 11 and d ~= 'left') or (d == 'left' and x >= 11)) and Hs or h)
      end
    end
  end
  for x = 5, 7 do put(x, 3, L) end
  put(6, 2, L)
  if d == 'down' then
    local fringe = ({ short = { 3, 4, 6, 9, 11, 12 }, spiky = { 3, 5, 7, 10, 12 }, bob = { 3, 4, 5, 10, 11, 12 },
                      long = { 3, 4, 5, 6, 11, 12 }, pigtails = { 3, 4, 6, 7, 8, 11, 12 }, bun = { 3, 12 } })[style]
                    or { 3, 12 }
    for _, x in ipairs(fringe) do put(x, 6, x >= 11 and Hs or h) end
    local sides = ({ short = 7, spiky = 7, bun = 7, pigtails = 8, bob = 11, long = 13 })[style]
    for y = 6, sides do put(3, y, h); put(12, y, Hs) end
    if style == 'bob' or style == 'long' then
      for y = 7, sides do put(2, y, h); put(13, y, Hs) end
      put(4, 10, h); put(11, 10, Hs)
    end
    if style == 'pigtails' then
      for y = 7, 11 do put(1, y, h); put(2, y, y > 9 and Hs or h); put(13, y, Hs); put(14, y, Hs) end
    end
    if style == 'spiky' then put(4, 1, h); put(8, 1, h); put(11, 1, Hs) end
  elseif d == 'up' then
    local bottom = ({ short = 10, spiky = 10, bun = 10, pigtails = 10, bob = 12, long = 14 })[style]
    for y = 5, bottom do
      local x0, x1 = head_row(y, 3, 12)
      if (style == 'bob' or style == 'long') and y >= 7 then x0, x1 = 2, 13 end
      for x = x0, x1 do put(x, y, (y >= bottom - 1 or x >= 12) and Hs or h) end
    end
    if style == 'pigtails' then
      for y = 7, 11 do put(1, y, h); put(2, y, h); put(13, y, Hs); put(14, y, Hs) end
    end
    if style == 'spiky' then put(4, 1, h); put(8, 1, h); put(11, 1, Hs) end
  else
    local back = ({ short = 9, spiky = 9, bun = 9, pigtails = 9, bob = 11, long = 14 })[style]
    put(3, 6, h); put(4, 6, h)
    for y = 5, back do
      for x = (y < 8 and 7 or 8), 12 do
        local ear = (x == 9 and (y == 8 or y == 9)) and contains({ 'short', 'spiky', 'bun', 'pigtails' }, style)
        if not ear then put(x, y, (x == 12 or y == back) and Hs or h) end
      end
    end
    if style == 'bob' or style == 'long' then for y = 7, back do put(13, y, Hs) end end
    if style == 'pigtails' then for y = 7, 11 do put(13, y, h); put(14, y, Hs) end end
    if style == 'spiky' then put(5, 1, h); put(9, 1, h); put(13, 3, Hs) end
  end
  if style == 'bun' then
    for y = 0, 1 do for x = 6, 9 do put(x, y, x == 9 and Hs or h) end end
  end
end

local function hat(px, d, cm, kind)
  if not kind or kind == 'nena' then return end
  if kind == 'cap' then
    local c, c2 = cm.c or cm.w, cm.C or cm.W
    px:rect(4, 1, 11, 1, c)
    px:rect(3, 2, 12, 4, c)
    px:rect(5, 2, 7, 2, mix(c, 'white', .3))
    if d == 'down' then px:rect(3, 5, 12, 5, c2)
    elseif d == 'left' then px:rect(1, 5, 5, 5, c2)
    else px:rect(3, 5, 12, 5, c) end
  elseif kind == 'ranger' then
    px:rect(5, 0, 10, 2, 'ochre2'); px:rect(5, 2, 10, 2, 'pine3')
    px:rect(1, 3, 14, 3, d ~= 'up' and 'ochre3' or 'ochre2')
    px:rect(6, 0, 7, 0, mix('ochre2', 'white', .3))
  elseif kind == 'beanie' then
    px:rect(4, 1, 11, 1, cm.c or 'red')
    px:rect(3, 2, 12, 4, cm.c or 'red')
    px:rect(3, 4, 12, 4, cm.C or 'terra2')
    for x = 4, 11, 2 do px:put(x, 3, cm.C or 'terra2') end
  elseif kind == 'hardhat' then   -- casc d'obra groc amb ala (obrers de les obres)
    local c, c2, c3 = 'sun', mix('sun', 'ochre3', .45), mix('sun', 'white', .5)
    px:rect(5, 0, 10, 0, c); px:rect(4, 1, 11, 4, c); px:rect(7, 0, 8, 4, c2)
    px:rect(2, 5, 13, 5, c2); px:put(5, 1, c3); px:put(5, 2, c3)
  elseif kind == 'chef' then
    px:rect(4, 0, 11, 3, 'white'); px:rect(3, 4, 12, 4, 'white2'); px:put(10, 1, 'white2'); px:put(11, 2, 'white2')
  elseif kind == 'witch' then
    px:rect(1, 4, 14, 4, 'asph3'); px:rect(2, 4, 13, 4, mix('asph3', 'ink', .4))
    px:rect(4, 2, 11, 3, 'asph3'); px:rect(5, 1, 10, 1, 'asph3'); px:rect(7, 0, 10, 0, 'asph3')
    px:rect(4, 3, 11, 3, 'terra'); px:put(5, 2, mix('asph3', 'white', .25))
  elseif kind == 'pirate' then
    px:rect(3, 2, 12, 4, 'red'); px:rect(4, 1, 11, 1, 'red')
    for _, x in ipairs({ 4, 7, 10 }) do px:put(x, 3, 'white') end
    if d == 'left' then px:rect(12, 5, 13, 7, 'red')
    elseif d == 'up' then px:rect(7, 5, 8, 7, 'red') end
  elseif kind == 'helmet' or kind == 'helmet_ride' then   -- casc de bici/moto (vermell amb reixetes) o d'hípica (negre)
    local c = kind == 'helmet' and 'red' or 'asph3'
    local c2, c3 = mix(c, 'ink', .3), mix(c, 'white', .4)
    px:rect(4, 0, 11, 0, c); px:rect(3, 1, 12, 4, c); px:rect(3, 5, 12, 5, c2)
    if kind == 'helmet' then for x = 5, 10, 2 do px:put(x, 1, 'ink'); px:put(x, 2, c2) end end
    px:put(5, 1, c3); px:put(6, 1, c3)
    if d == 'down' then px:rect(3, 6, 3, 7, c2); px:rect(12, 6, 12, 7, c2)   -- sense corretja davant dels ulls
    elseif d == 'left' then px:rect(9, 5, 12, 7, c2); px:rect(2, 5, 4, 5, c)
    else px:rect(3, 5, 12, 6, c2) end
  elseif kind == 'hood' then   -- caputxa del xubasquer (src/systems/weather.lua: quan plou)
    local c, c2, c3 = 'ochre', 'ochre2', mix('ochre', 'white', .35)
    px:rect(4, 0, 11, 0, c); px:rect(3, 1, 12, 3, c); px:rect(3, 4, 12, 4, c2)
    if d == 'down' then
      px:rect(2, 3, 3, 11, c); px:rect(12, 3, 13, 11, c2); px:put(5, 1, c3); px:put(6, 1, c3)
    elseif d == 'up' then
      px:rect(2, 1, 13, 11, c); px:rect(12, 2, 13, 11, c2); px:rect(5, 2, 7, 2, c3)
    else
      px:rect(8, 1, 13, 11, c); px:rect(13, 2, 13, 11, c2); px:rect(2, 2, 3, 4, c); px:put(10, 2, c3)
    end
  elseif kind == 'santa' then
    px:rect(4, 1, 11, 3, 'red'); px:rect(9, 0, 12, 1, 'red')
    px:rect(3, 4, 12, 4, 'white'); px:rect(13, 1, 14, 2, 'white')
  elseif kind == 'pumpkin' then
    for y = 2, 11 do
      local x0, x1 = head_row(y, 2, 13)
      for x = x0, x1 do px:put(x, y, (x == 5 or x == 10 or x >= 12) and 'ochre2' or 'ochre') end
    end
    px:rect(7, 0, 8, 1, 'pine2')
    if d == 'down' then
      for _, q in ipairs({ { 5, 6 }, { 6, 6 }, { 9, 6 }, { 10, 6 }, { 6, 5 }, { 9, 5 } }) do px:put(q[1], q[2], INK) end
      for x = 5, 10 do px:put(x, x % 2 == 1 and 9 or 8, INK) end
    elseif d == 'left' then
      for _, q in ipairs({ { 3, 6 }, { 4, 6 }, { 4, 5 }, { 3, 9 }, { 4, 8 }, { 5, 9 } }) do px:put(q[1], q[2], INK) end
    end
  end
end

-- ---------------------------------------------------------------- cuerpo
local function torso(px, d, cm, outfit, extras, swing)
  local w, Wd, s, b = cm.w, cm.W, cm.s, cm.b
  local sleeve_long = outfit == 'sweater' or outfit == 'uniform' or outfit == 'pants'
  local dress = outfit == 'dress'
  local hip = dress and w or b
  local hip_shade = dress and Wd or mix(b, 'ink', .25)
  local belt = contains(extras, 'belt') or outfit == 'pants' or outfit == 'shorts' or outfit == 'uniform'
  if d == 'down' or d == 'up' then
    px:rect(4, 12, 11, 16, w)
    px:rect(11, 12, 11, 16, Wd)
    px:rect(4, 17, 11, 18, hip); px:rect(11, 17, 11, 18, hip_shade)
    if dress then
      px:rect(3, 17, 12, 18, w); px:rect(3, 18, 12, 18, Wd); px:put(12, 17, Wd)
    end
    if d == 'down' and outfit ~= 'sweater' and outfit ~= 'uniform' then
      px:put(7, 12, s); px:put(8, 12, s)
    end
    if d == 'down' and outfit == 'uniform' then
      px:put(7, 12, 'white'); px:put(8, 12, 'white'); px:put(6, 14, cm.c or 'ochre')
    end
    if belt and not dress then px:rect(4, 16, 11, 16, mix(b, 'ink', .4)) end
    for _, sx in ipairs({ { -1, 3 }, { 1, 12 } }) do
      local side, x = sx[1], sx[2]
      local sw = d == 'down' and (swing * side * -1) or (swing * side)
      local top, hand = 12, 16 + (sw > 0 and 1 or 0) - (sw < 0 and 1 or 0)
      for y = top, hand - 1 do
        local sl = y <= 13 or sleeve_long
        local c
        if sl then c = side < 0 and w or Wd else c = side < 0 and s or cm.S end
        px:put(x, y, c)
      end
      px:put(x, hand, side < 0 and s or cm.S)
    end
  else
    px:rect(5, 12, 10, 16, w)
    px:rect(10, 12, 10, 16, Wd)
    px:rect(5, 17, 10, 18, hip); px:rect(10, 17, 10, 18, hip_shade)
    if dress then px:rect(4, 17, 11, 18, w); px:rect(4, 18, 11, 18, Wd) end
    if belt and not dress then px:rect(5, 16, 10, 16, mix(b, 'ink', .4)) end
    local pts
    if swing > 0 then pts = { { 7, 12 }, { 7, 13 }, { 6, 14 }, { 5, 15 } }
    elseif swing < 0 then pts = { { 8, 12 }, { 8, 13 }, { 9, 14 }, { 10, 15 } }
    else pts = { { 7, 12 }, { 7, 13 }, { 7, 14 }, { 7, 15 } } end
    for i, q in ipairs(pts) do
      local sl = (i - 1) < 2 or sleeve_long
      px:put(q[1], q[2], sl and Wd or cm.S)
      px:put(q[1] + 1, q[2], sl and Wd or cm.S)
    end
    local hx, hy = pts[4][1], pts[4][2]
    px:put(hx, hy + 1, s); px:put(hx + 1, hy + 1, cm.S)
  end
end

local function legs(px, d, cm, outfit, bob, lift)
  local bare = outfit == 'shorts' or outfit == 'dress' or outfit == 'tshirt'
  local lc = bare and cm.s or cm.b
  local lc2 = bare and cm.S or mix(cm.b, 'ink', .25)
  local o, o2 = cm.o, mix(cm.o, 'ink', .35)
  local top = 19 + bob
  if d == 'down' or d == 'up' then
    for _, leg in ipairs({ { 'L', { 5, 6 }, { 4, 6 } }, { 'R', { 9, 10 }, { 9, 11 } } }) do
      local name, xs, sx = leg[1], leg[2], leg[3]
      local foot = lift == name and 20 or 21
      for y = top, foot - 1 do px:put(xs[1], y, lc); px:put(xs[2], y, lc2) end
      px:rect(sx[1], foot, sx[2], foot + 1, o)
      px:rect(sx[1], foot + 1, sx[2], foot + 1, o2)
    end
  else
    if lift == nil then
      for y = top, 20 do px:rect(6, y, 7, y, lc); px:rect(8, y, 9, y, lc2) end
      px:rect(4, 21, 9, 22, o); px:rect(4, 22, 9, 22, o2)
    else
      local i = 0
      for y = top, 20 do
        local m = math.min(i, 1)
        px:rect(5 - m, y, 6 - m, y, lc)
        px:rect(9 + m, y, 10 + m, y, lc2)
        i = i + 1
      end
      px:rect(2, 21, 5, 22, o); px:rect(2, 22, 5, 22, o2)
      px:rect(10, 20, 12, 21, o2)
    end
  end
end

local function extras_draw(px, d, cm, extras)
  if contains(extras, 'apron') then
    if d == 'down' then
      px:rect(5, 13, 10, 18, 'white'); px:rect(10, 13, 10, 18, 'white2'); px:rect(6, 15, 9, 15, 'white2')
    elseif d == 'left' then px:rect(4, 13, 5, 18, 'white')
    else px:put(7, 15, 'white'); px:put(8, 15, 'white') end
  end
  if contains(extras, 'dragon') then   -- Armadura del Drac (src/systems/perles.lua): escates, cinturó d'or i capa
    local g1, g2, red, red2, gold = 'pine2', 'pine3', 'red', 'terra2', 'ochre'
    if d == 'down' then
      px:rect(4, 12, 11, 15, g1)
      for y = 12, 15 do for x = 4 + (y % 2), 11, 2 do px:put(x, y, g2) end end
      px:rect(4, 16, 11, 16, gold); px:put(7, 16, 'ochre2'); px:put(8, 16, 'ochre2')
      px:rect(3, 12, 3, 13, red); px:rect(12, 12, 12, 13, red2)
      px:rect(2, 15, 2, 18, red); px:rect(13, 15, 13, 18, red2)
    elseif d == 'up' then
      px:rect(4, 12, 11, 18, red); px:rect(10, 12, 11, 18, red2); px:rect(4, 12, 11, 12, gold)
      px:rect(3, 17, 12, 18, red); px:rect(11, 17, 12, 18, red2)
    else
      px:rect(5, 12, 9, 15, g1)
      for y = 12, 15 do for x = 5 + (y % 2), 9, 2 do px:put(x, y, g2) end end
      px:rect(5, 16, 9, 16, gold)
      px:rect(10, 12, 11, 18, red); px:rect(11, 13, 12, 18, red2)
    end
  end
  if contains(extras, 'scarf') then
    local c = cm.c or 'red'
    if d == 'left' then px:rect(5, 12, 9, 12, c); px:rect(4, 13, 5, 14, c)
    else
      px:rect(4, 12, 11, 12, c)
      local x = d == 'down' and 9 or 6
      px:put(x, 13, c); px:put(x, 14, c)
    end
  end
  if contains(extras, 'bag') then
    if d == 'down' then
      for i = 0, 4 do px:put(4 + i, 12 + i, 'ochre3') end
      px:rect(9, 15, 12, 17, 'ochre2'); px:rect(9, 15, 12, 15, 'ochre3')
    elseif d == 'up' then
      for i = 0, 4 do px:put(11 - i, 12 + i, 'ochre3') end
      px:rect(3, 15, 6, 17, 'ochre2')
    else
      px:rect(8, 15, 11, 17, 'ochre2'); px:put(8, 15, 'ochre3'); px:put(7, 12, 'ochre3'); px:put(7, 13, 'ochre3')
    end
  end
  if contains(extras, 'beard') then
    local c, c2 = cm.h, cm.H
    if d == 'down' then
      px:rect(4, 9, 11, 11, c); px:rect(5, 12, 10, 12, c2)
      px:put(7, 10, cm.r); px:put(8, 10, cm.r); px:put(11, 9, c2); px:put(11, 10, c2)
    elseif d == 'left' then
      px:rect(3, 9, 7, 11, c); px:rect(4, 12, 6, 12, c2); px:put(3, 10, cm.r)
    end
  end
  if contains(extras, 'glasses') then
    if d == 'down' then for _, x in ipairs({ 4, 7, 8, 11 }) do px:put(x, 7, INK) end
    elseif d == 'left' then px:put(3, 7, INK); px:put(6, 7, INK) end
  end
  if contains(extras, 'ribs') and (d == 'down' or d == 'up') then
    for _, y in ipairs({ 13, 15 }) do px:rect(5, y, 10, y, 'white2') end
    px:rect(7, 12, 8, 16, 'white')
  end
  if contains(extras, 'cane') then
    if d == 'down' then
      for y = 15, 22 do px:put(13, y, 'ochre3') end
      px:put(12, 15, 'ochre3')
    elseif d == 'left' then
      for y = 16, 22 do px:put(3, y, 'ochre3') end
      px:put(4, 16, 'ochre3')
    end
  end
end

-- un fotograma: d = 'down' | 'up' | 'left'; col 0–3 caminar, 4 reposo, 5 parpadeo
function M.frame(spec, d, col)
  local cm = {}
  for k, v in pairs(M.DEFAULTS) do cm[k] = v end
  for k, v in pairs(spec) do if type(k) == 'string' and k:sub(1, 1) ~= '_' then cm[k] = v end end
  local style = spec._hair or 'short'
  local outfit = spec._outfit or 'shorts'
  local hat_kind = spec._hat
  local extras = spec._extra or {}
  local walking = col < 4
  local bob = (walking and (col == 0 or col == 2)) and 1 or 0
  local lift = walking and (col == 0 and 'L' or (col == 2 and 'R' or nil)) or nil
  local swing = walking and (col == 0 and 1 or (col == 2 and -1 or 0)) or 0
  local blink = col == 5
  local up = px_new()
  local back_hair = {}
  if d == 'up' and (style == 'bob' or style == 'long' or style == 'pigtails') then
    hair(up, d, cm, style)
    for k, v in pairs(up.p) do back_hair[k] = v end
  end
  torso(up, d, cm, outfit, extras, swing)
  for k, v in pairs(back_hair) do if math.floor(k / W) >= 12 then up.p[k] = v end end
  face(up, d, cm, blink)
  if hat_kind ~= 'pumpkin' then hair(up, d, cm, style) end
  extras_draw(up, d, cm, extras)
  hat(up, d, cm, hat_kind)
  local low = px_new()
  local llift = lift
  if d == 'left' then llift = lift and 'step' or nil end
  local kid = spec._age == 'kid'
  legs(low, d, cm, outfit, bob + (kid and 1 or 0), llift)
  local out = px_new()
  out:merge(low)
  out:merge(up, bob + (kid and 1 or 0))
  return out:sprite()
end

-- 24 fotogramas: abajo, arriba, izquierda (6 cada uno) y derecha (izquierda volteada)
function M.frames(spec)
  local frames = {}
  for _, d in ipairs({ 'down', 'up', 'left' }) do
    for col = 0, 5 do frames[#frames + 1] = M.frame(spec, d, col) end
  end
  for i = 13, 18 do frames[#frames + 1] = frames[i]:flip_h() end
  return frames
end

-- hoja 96 × 96 (6 columnas × 4 filas), como tools/make_sprites.character()
function M.sheet(spec) return Canvas.sheet(M.frames(spec), 6) end

return M
