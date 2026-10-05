-- Hojas del protagonista generadas en tiempo de ejecución a partir de su paperdoll (port de
-- tools/make_sprites.py: action_sheet, bike_sheet, vehicle_sheet). Así un avatar hecho en el editor de
-- perfil ataca, se protege y va en bici, patinete, scooter o moto con su propio aspecto.
local Canvas = require('src.paperdoll.canvas')
local Chars = require('src.paperdoll.chars')
local pyround = Canvas.pyround

local S = {}
local ROWD = { [0] = 'down', [1] = 'up', [2] = 'left' }

local function base_frame(spec, row, col) return Chars.frame(spec, ROWD[row], col) end

-- parte de arriba del cuerpo (filas 0–17), como top.a[:18] = body.a[:18]
local function top_of(spec, row)
  local body = base_frame(spec, row, 4)
  local top = Canvas.new(16, 24)
  for y = 0, 17 do for x = 0, 15 do top.p[y * 16 + x + 1] = body.p[y * 16 + x + 1] end end
  return top
end

local function draw_sword(s, x0, y0, x1, y1)
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0))
  for i = 0, n do
    local x, y = pyround(x0 + (x1 - x0) * i / n), pyround(y0 + (y1 - y0) * i / n)
    for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
      local qx, qy = x + d[1], y + d[2]
      if qy >= 0 and qy < s.h and qx >= 0 and qx < s.w then
        local c = s:get(qx, qy)
        if not c or c[4] == 0 then s:px(qx, qy, 'ink') end
      end
    end
  end
  for i = 0, n do
    local x, y = pyround(x0 + (x1 - x0) * i / n), pyround(y0 + (y1 - y0) * i / n)
    s:px(x, y, i < 2 and 'ochre2' or (i % 2 == 1 and 'white' or 'white2'))
  end
end

-- ataque (3 fases × 4 direcciones) y defensa (4): 32 × 32, 4 columnas
function S.action(spec)
  local frames = {}
  local plans = {
    down = { 0, { { { 24, 14 }, { 29, 6 } }, { { 16, 22 }, { 16, 31 } }, { { 8, 20 }, { 2, 26 } } } },
    up = { 1, { { { 24, 14 }, { 29, 6 } }, { { 16, 6 }, { 16, 0 } }, { { 8, 14 }, { 2, 8 } } } },
    left = { 2, { { { 20, 12 }, { 26, 3 } }, { { 9, 16 }, { 0, 16 } }, { { 10, 20 }, { 3, 27 } } } },
  }
  local OFF = { down = { 0, 1 }, up = { 0, -1 }, left = { -1, 0 } }
  for _, d in ipairs({ 'down', 'up', 'left', 'right' }) do
    local src = d == 'right' and 'left' or d
    local row, phases = plans[src][1], plans[src][2]
    for ph = 0, 2 do
      local s = Canvas.new(32, 32)
      local body = base_frame(spec, row, 4)
      local off = ph == 1 and OFF[src] or { 0, 0 }
      local hp, tp = phases[ph + 1][1], phases[ph + 1][2]
      local behind = src == 'up' or ph == 0
      if behind then draw_sword(s, hp[1], hp[2], tp[1], tp[2]) end
      s:blit(body, 8 + off[1], 6 + off[2])
      if not behind then draw_sword(s, hp[1], hp[2], tp[1], tp[2]) end
      frames[#frames + 1] = d == 'right' and s:flip_h() or s
    end
  end
  local shield_rows = { '.kkkkkk.', 'kWWrrWWk', 'krrrrrrk', 'kWWrrWWk', 'kWWrrWWk', '.kWrrWk.', '..kkkk..' }
  local cm = { k = 'ink', W = 'ochre', r = 'red' }
  for _, d in ipairs({ 'down', 'up', 'left', 'right' }) do
    local src = d == 'right' and 'left' or d
    local row = ({ down = 0, up = 1, left = 2 })[src]
    local s = Canvas.new(32, 32)
    local body = base_frame(spec, row, 4)
    if src == 'up' then
      s:pattern(12, 12, shield_rows, cm); s:blit(body, 8, 7)
    else
      s:blit(body, 8, 7)
      if src == 'down' then s:pattern(12, 17, shield_rows, cm) else s:pattern(7, 15, shield_rows, cm) end
    end
    frames[#frames + 1] = d == 'right' and s:flip_h() or s
  end
  return Canvas.sheet(frames, 4)
end

local function rider_colors(spec)
  local o = spec._outfit or 'shorts'
  local bare = o == 'shorts' or o == 'dress' or o == 'tshirt'
  return bare and (spec.s or 'skin') or (spec.b or 'blue'), spec.o or 'terra3'
end

function S.bike(spec)
  local frames = {}
  local leg, shoe = rider_colors(spec)
  for _, d in ipairs({ 'down', 'up', 'left', 'right' }) do
    local src = d == 'right' and 'left' or d
    local row = ({ down = 0, up = 1, left = 2 })[src]
    for f = 0, 1 do
      local s = Canvas.new(32, 32)
      local top = top_of(spec, row)
      if src == 'left' then
        for _, cx in ipairs({ 9, 23 }) do
          for a = 0, 345, 15 do
            s:px(pyround(cx + 4 * math.cos(math.rad(a))), pyround(26 + 4 * math.sin(math.rad(a))), 'ink')
          end
          s:px(cx, 26, 'asph2')
        end
        s:hline(10, 22, 23, 'red'); s:vline(16, 20, 25, 'red'); s:px(9, 22, 'red'); s:px(8, 21, 'ink')
        s:hline(6, 9, 20, 'ink')
        s:blit(top, 9, 3)
        local lx = 15 + (f == 1 and 2 or -1)
        s:vline(lx, 21, 24, leg); s:px(lx, 25, shoe)
        s:vline(lx + 2, 21, 23 - f, leg)
      else
        s:rect(14, 22, 4, 10, 'ink'); s:rect(15, 23, 2, 8, 'asph3'); s:vline(15, 24, 29, 'asph2')
        s:rect(15, 19, 2, 4, 'red')
        if src == 'up' then
          s:hline(8, 23, 15, 'ink'); s:rect(7, 14, 2, 3, 'asph3'); s:rect(23, 14, 2, 3, 'asph3')
        end
        s:blit(top, 8, src == 'down' and 1 or 2)
        local lo, hi = 21, 24
        if f == 1 then lo, hi = 24, 21 end
        for _, q in ipairs({ { 12, lo }, { 19, hi } }) do
          local x, yb = q[1], q[2]
          s:vline(x, 18, yb - 1, leg); s:vline(x + 1, 18, yb - 1, leg)
          s:rect(x < 16 and x - 1 or x, yb, 3, 2, shoe)
        end
        if src == 'down' then
          s:hline(8, 23, 15, 'ink'); s:rect(7, 14, 2, 3, 'asph3'); s:rect(23, 14, 2, 3, 'asph3')
          s:px(10, 14, spec.s or 'skin'); s:px(21, 14, spec.s or 'skin')
          s:rect(14, 16, 4, 2, 'white')
        end
      end
      frames[#frames + 1] = d == 'right' and s:flip_h() or s
    end
  end
  return Canvas.sheet(frames, 2)
end

local BODY_C = { patinete = { 'asph3', 'asph2', 'sea' }, scooter = { 'red', 'terra2', 'white' },
                 motocross = { 'ochre', 'ochre2', 'asph3' } }

-- cavall (hípica, src/systems/vehicles.lua 'cavall'): pelatge, ombra i crinera
local COATS = { brown = { 'terra3', 'asph3', 'ink' }, white = { 'white', 'white3', 'stone2' },
                chestnut = { 'ochre3', 'terra3', 'ochre' } }

local function horse(spec, coat)
  local frames = {}
  local leg, shoe = rider_colors(spec)
  local C, C2, M = COATS[coat][1], COATS[coat][2], COATS[coat][3]
  for _, d in ipairs({ 'down', 'up', 'left', 'right' }) do
    local src = d == 'right' and 'left' or d
    local row = ({ down = 0, up = 1, left = 2 })[src]
    for f = 0, 1 do
      local s = Canvas.new(32, 32)
      local top = top_of(spec, row)
      if src == 'left' then
        -- potes (alternen al trot), cos, coll, cap, crinera i cua
        local fl = f == 0 and { 10, 14, 20, 24 } or { 11, 13, 21, 23 }
        for i, x in ipairs(fl) do
          local len = (i % 2 == 0) == (f == 0) and 7 or 6
          s:vline(x, 22, 21 + len, i <= 2 and C or C2); s:px(x, 22 + len, 'ink')
        end
        s:rect(9, 15, 17, 8, C); s:hline(10, 24, 22, C2); s:hline(10, 24, 15, C2)
        s:rect(6, 9, 5, 8, C); s:rect(2, 8, 7, 4, C); s:rect(2, 11, 3, 2, C2)
        s:px(5, 9, 'ink'); s:px(8, 7, C2); s:px(7, 7, C2); s:px(2, 10, 'ink')
        s:vline(10, 7, 15, M); s:vline(11, 8, 13, M)
        s:vline(26, 15, 23, M); s:vline(27, 16, 22, M)
        s:rect(14, 14, 7, 2, 'red')   -- sella
        s:blit(top, 9, 0)
        s:vline(17, 16, 20, leg); s:px(17, 21, shoe)
      else
        local up = src == 'up'
        local a, b = f == 0 and 0 or 1, f == 0 and 1 or 0
        s:vline(11, 22, 29 + a, C2); s:vline(20, 22, 29 + b, C2)
        s:px(11, 30 + a, 'ink'); s:px(20, 30 + b, 'ink')
        s:rect(10, 12, 12, 12, C); s:vline(21, 12, 23, C2)
        if up then
          s:rect(13, 8, 6, 5, C); s:vline(15, 7, 12, M); s:vline(16, 8, 12, M)   -- clatell i crinera
        end
        s:rect(10, 13, 12, 3, 'red')
        s:blit(top, 8, 0)
        s:vline(9, 15, 21, leg); s:vline(22, 15, 21, leg); s:px(9, 22, shoe); s:px(22, 22, shoe)
        if up then
          s:vline(15, 22, 30, M); s:vline(16, 22, 29, M)   -- cua
        else   -- cap de cara, davant del genet
          s:rect(13, 20, 6, 9, C); s:rect(14, 27, 4, 3, C2); s:rect(12, 18, 2, 3, C); s:rect(18, 18, 2, 3, C)
          s:vline(15, 22, 26, coat == 'white' and 'white3' or 'white'); s:vline(16, 22, 26, coat == 'white' and 'white3' or 'white')
          s:px(13, 23, 'ink'); s:px(18, 23, 'ink'); s:px(14, 29, 'ink'); s:px(17, 29, 'ink')
          s:px(15, 20, M); s:px(16, 20, M); s:px(15, 21, M)
        end
      end
      frames[#frames + 1] = d == 'right' and s:flip_h() or s
    end
  end
  return Canvas.sheet(frames, 2)
end

function S.vehicle(spec, kind)
  local coat = kind:match('^cavall_(%w+)$')
  if coat and COATS[coat] then return horse(spec, coat) end
  local frames = {}
  local leg, shoe = rider_colors(spec)
  local c1, c2, c3 = BODY_C[kind][1], BODY_C[kind][2], BODY_C[kind][3]
  for _, d in ipairs({ 'down', 'up', 'left', 'right' }) do
    local src = d == 'right' and 'left' or d
    local row = ({ down = 0, up = 1, left = 2 })[src]
    for f = 0, 1 do
      local s = Canvas.new(32, 32)
      local top = top_of(spec, row)
      local wheel_r = kind == 'patinete' and 3 or 4
      if src == 'left' then
        local xs = kind ~= 'patinete' and { 8, 24 } or { 9, 23 }
        for _, cx in ipairs(xs) do
          for a = 0, 345, 15 do
            local px_ = pyround(cx + wheel_r * math.cos(math.rad(a)))
            local py_ = pyround(27 + wheel_r * math.sin(math.rad(a)))
            local knob = kind == 'motocross' and (math.floor(a / 15) + f) % 3 == 0
            s:px(px_, py_, knob and 'asph2' or 'ink')
          end
          s:px(cx, 27, 'stone2')
        end
        if kind == 'patinete' then
          s:hline(9, 23, 25, c1); s:hline(10, 22, 24, c2)
          s:vline(9, 13, 24, 'asph2'); s:hline(6, 10, 13, 'ink')
          s:blit(top, 10, 2)
          s:vline(15, 20, 23, leg); s:vline(17, 20, 23, leg); s:px(15, 24, shoe); s:px(17, 24, shoe)
        else
          if kind == 'scooter' then
            s:rect(16, 19, 11, 6, c1); s:rect(16, 19, 11, 1, c2); s:rect(19, 18, 7, 2, 'ink')
            s:rect(9, 17, 4, 9, c1); s:px(9, 18, c3); s:hline(10, 18, 25, c2)
          else
            s:rect(14, 18, 12, 4, c1); s:rect(18, 17, 8, 2, 'ink'); s:vline(10, 16, 26, 'stone3')
            s:hline(12, 26, 23, 'asph3'); s:px(26, 22, 'stone2'); s:px(27, 22, 'stone2')
          end
          s:hline(7, 11, 15, 'ink'); s:px(7, 16, c3)
          s:blit(top, 12, 1)
          s:vline(18, 19, 22, leg); s:hline(15, 18, 22 + f, leg); s:px(14, 22 + f, shoe)
        end
      else
        s:rect(14, 22, 4, 10, 'ink'); s:rect(15, 23, 2, 8, 'asph3')
        if kind == 'scooter' then
          s:rect(11, 19, 10, 6, c1); s:rect(12, 19, 8, 2, c2)
        elseif kind == 'motocross' then
          s:rect(12, 18, 8, 5, c1); s:rect(12, 17, 8, 1, c2)
        else
          s:rect(15, 14, 2, 9, 'asph2')
        end
        if src == 'up' and kind ~= 'patinete' then s:rect(14, 23, 4, 2, 'red') end
        s:blit(top, 8, kind == 'patinete' and 0 or 1)
        s:hline(8, 23, 15, 'ink'); s:rect(7, 14, 2, 3, 'asph3'); s:rect(23, 14, 2, 3, 'asph3')
        if kind == 'patinete' then
          s:vline(13, 18, 22, leg); s:vline(18, 18, 22, leg); s:px(13, 23, shoe); s:px(18, 23, shoe)
        else
          s:vline(10, 19, 22, leg); s:vline(21, 19, 22, leg); s:px(10, 23, shoe); s:px(21, 23, shoe)
        end
        if src == 'down' then s:rect(14, kind ~= 'patinete' and 17 or 13, 4, 2, 'white') end
      end
      frames[#frames + 1] = d == 'right' and s:flip_h() or s
    end
  end
  return Canvas.sheet(frames, 2)
end

-- ---------------------------------------------------------------- vistes en diagonal (2026-10-05)
-- Fulla a part (no toca les de 4 direccions, que es comparen amb tools/make_sprites.py): 4 diagonals × 2 fotogrames,
-- 32 × 32, ordre avall-esquerra, avall-dreta, amunt-esquerra, amunt-dreta (com src/paperdoll/diag.lua). Vist a
-- tres quarts: la roda de davant més avall (cap a tu) o més amunt (d'esquena), i el genet amb el cap de perfil i el
-- cos de cara (avall) o el cap d'esquena i el cos de perfil (amunt).
local function top_diag(spec, down)
  local head = base_frame(spec, down and 2 or 1, 4)
  local body = base_frame(spec, down and 0 or 2, 4)
  local top = Canvas.new(16, 24)
  for y = 0, 17 do
    local src = y < 12 and head or body
    for x = 0, 15 do top.p[y * 16 + x + 1] = src.p[y * 16 + x + 1] end
  end
  return top
end

local function seg(s, x0, y0, x1, y1, c, t)
  local n = math.max(math.abs(x1 - x0), math.abs(y1 - y0), 1)
  for i = 0, n do
    local x, y = pyround(x0 + (x1 - x0) * i / n), pyround(y0 + (y1 - y0) * i / n)
    for k = 0, (t or 1) - 1 do s:px(x, y + k, c) end
  end
end

local function wheel(s, cx, cy, rx, ry, knobby, f)
  for a = 0, 345, 15 do
    local knob = knobby and (math.floor(a / 15) + f) % 3 == 0
    s:px(pyround(cx + rx * math.cos(math.rad(a))), pyround(cy + ry * math.sin(math.rad(a))), knob and 'asph2' or 'ink')
  end
  s:px(cx, cy, 'stone2')
end

-- kind: 'bike' | 'patinete' | 'scooter' | 'motocross'
local function ride_diag(spec, kind)
  local frames = {}
  local leg, shoe = rider_colors(spec)
  local C = BODY_C[kind] or { 'red', 'terra2', 'white' }
  for _, d in ipairs({ 'dl', 'dr', 'ul', 'ur' }) do
    local down = d:sub(1, 1) == 'd'
    for f = 0, 1 do
      local s = Canvas.new(32, 32)
      local rx, ry = kind == 'patinete' and 2 or 3, kind == 'patinete' and 3 or 4
      -- avall: roda de darrere amunt a la dreta i la de davant avall a l'esquerra; amunt, al revés
      local fx, fy, bx, by = 5, 27, 26, 21
      if not down then fx, fy, bx, by = 6, 20, 26, 27 end
      local back_first = down
      if back_first then wheel(s, bx, by, rx, ry, kind == 'motocross', f) end
      if not down then wheel(s, fx, fy, rx, ry, kind == 'motocross', f) end
      if kind == 'patinete' then
        seg(s, bx - 1, by + 1, fx + 1, fy - 1, C[1], 2)
        seg(s, fx, fy - 2, fx - 1, down and 14 or 10, 'asph2')
        seg(s, fx - 3, down and 14 or 10, fx + 2, down and 13 or 9, 'ink')
      elseif kind == 'bike' then
        seg(s, bx, by - 3, fx + 2, fy - 4, 'red'); seg(s, bx - 1, by, (bx + fx) / 2, (by + fy) / 2 - 1, 'red')
        seg(s, fx, fy, fx + 1, fy - 6, 'red')
        seg(s, fx - 2, fy - 8, fx + 3, fy - 10, 'ink')
      else
        -- carrosseria: una franja gruixuda de darrere a davant, amb seient fosc a sobre
        local t = kind == 'scooter' and 5 or 3
        seg(s, bx - 1, by - 5, fx + 2, fy - 6, C[1], t)
        seg(s, bx - 2, by - 6, (bx + fx) / 2, (by + fy) / 2 - 7, 'ink', 2)
        seg(s, bx - 1, by - 5, fx + 2, fy - 6, C[2])
        seg(s, fx, fy, fx + 1, fy - 8, kind == 'motocross' and 'stone3' or C[1])
        seg(s, fx - 3, fy - 10, fx + 3, fy - 11, 'ink'); s:px(fx - 1, fy - 8, C[3])
      end
      -- genet: cames als pedals (alternen), després el tors i el cap
      local hx = 16
      local l1, l2 = f == 0 and 23 or 21, f == 0 and 21 or 23
      s:vline(hx - 2, 18, l1, leg); s:px(hx - 2, l1 + 1, shoe)
      s:vline(hx + 2, 18, l2, leg); s:px(hx + 2, l2 + 1, shoe)
      s:blit(top_diag(spec, down), 8, 2)
      -- la roda de davant (avall) i la de darrere (amunt) queden davant de les cames
      if down then wheel(s, fx, fy, rx, ry, kind == 'motocross', f) else wheel(s, bx, by, rx, ry, kind == 'motocross', f) end
      local out = s
      if d:sub(2, 2) == 'r' then out = s:flip_h() end
      frames[#frames + 1] = out
    end
  end
  return Canvas.sheet(frames, 2)
end

local function horse_diag(spec, coat)
  local frames = {}
  local leg, shoe = rider_colors(spec)
  local C, C2, M = COATS[coat][1], COATS[coat][2], COATS[coat][3]
  for _, d in ipairs({ 'dl', 'dr', 'ul', 'ur' }) do
    local down = d:sub(1, 1) == 'd'
    for f = 0, 1 do
      local s = Canvas.new(32, 32)
      -- cos en diagonal: de la gropa (amunt a la dreta) al pit (avall a l'esquerra), o al revés d'esquena
      local function legs(x, y0, len) s:vline(x, y0, y0 + len, C2); s:px(x, y0 + len + 1, 'ink') end
      local a, b = f == 0 and 0 or 1, f == 0 and 1 or 0
      if down then
        legs(23, 18, 6 + a); legs(26, 17, 6 + b)                         -- potes de darrere (més lluny)
        s:vline(29, 11, 19, M); s:vline(30, 12, 18, M)                   -- cua
        for k = 0, 20 do s:vline(28 - k, 11 + math.floor(k * 0.3), 18 + math.floor(k * 0.3), C) end
        seg(s, 28, 18, 8, 24, C2)
        legs(9, 23, 5 + b); legs(13, 24, 5 + a)                          -- potes de davant (més a prop)
        s:rect(4, 11, 5, 9, C); s:rect(1, 16, 6, 6, C); s:rect(1, 20, 4, 2, C2)   -- coll i cap, cap a tu
        s:px(2, 17, 'ink'); s:px(5, 17, 'ink'); s:px(1, 15, C2); s:px(5, 15, C2)
        s:vline(8, 10, 18, M); s:vline(9, 11, 15, M)
        s:rect(14, 13, 7, 3, 'red')                                       -- sella
      else
        legs(6, 14, 6 + a); legs(9, 15, 6 + b)                            -- potes de davant (més lluny)
        s:rect(2, 4, 5, 9, C); s:rect(1, 1, 4, 5, C); s:px(1, 0, C2); s:px(4, 0, C2)   -- cap i coll, d'esquena
        s:vline(6, 3, 12, M); s:vline(7, 4, 11, M)
        for k = 0, 20 do s:vline(5 + k, 10 + math.floor(k * 0.3), 17 + math.floor(k * 0.3), C) end
        seg(s, 5, 17, 25, 23, C2)
        legs(19, 22, 6 + b); legs(24, 22, 6 + a)                          -- potes de darrere (més a prop)
        s:vline(26, 15, 26, M); s:vline(27, 16, 25, M)                    -- cua
        s:rect(12, 12, 7, 3, 'red')
      end
      s:blit(top_diag(spec, down), down and 9 or 8, 0)
      s:vline(down and 15 or 14, 15, 20, leg); s:px(down and 15 or 14, 21, shoe)
      local out = s
      if d:sub(2, 2) == 'r' then out = s:flip_h() end
      frames[#frames + 1] = out
    end
  end
  return Canvas.sheet(frames, 2)
end

-- kind: 'bike', 'patinete', 'scooter', 'motocross' o 'cavall_<pelatge>'
function S.diag(spec, kind)
  local coat = kind:match('^cavall_(%w+)$')
  if coat and COATS[coat] then return horse_diag(spec, coat) end
  return ride_diag(spec, kind)
end

return S
