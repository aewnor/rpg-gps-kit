-- 10 distribucions de casa (2026-10-05). src/world/procgen.lua les fa servir per a cases, pisos i plantes de dalt:
-- la llavor de la porta tria el tipus (mateixa casa → mateix tipus i mateixa disposició). Lua pur.
--
-- Cada distribució torna habitacions rectangulars dins l'interior útil (x 1..w-2, y 2..h-2) separades per envans
-- d'una casella. H.build omple d'envà tot el que no és habitació i obre portes entre habitacions veïnes (un arbre
-- des de la de l'entrada, i alguna de més): totes queden enllaçades amb la sortida.
local H = {}

H.NAMES = { 'Clàssica', 'Estudi', 'Passadís', 'Casa de poble', 'Masia amb pati', 'Loft', 'Casa d\'artista',
            'Família gran', 'Casa de platja', 'Dúplex compacte' }
H.COUNT = #H.NAMES

-- terra de cada tipus d'habitació (per distribució es pot canviar el del saló)
H.FLOOR = { living = 'i_floor_wood_0', bedroom = 'i_floor_wood_1', kitchen = 'i_floor_tile_0', bath = 'i_floor_tile_1',
            studio = 'i_floor_wood_0', loft = 'i_floor_wood_1', study = 'i_floor_carpet_0', dining = 'i_floor_wood_0',
            patio = 'g_grass_0', terrace = 'i_floor_stone_0', hall = 'i_floor_tile_1', kids = 'i_floor_carpet_1' }
H.LIVING_FLOOR = { [4] = 'i_floor_stone_1', [5] = 'i_floor_stone_0', [6] = 'i_floor_carpet_1', [7] = 'i_floor_wood_1',
                   [9] = 'i_floor_tile_0' }

local function room(x0, y0, x1, y1, t) return { x0 = x0, y0 = y0, x1 = x1, y1 = y1, type = t } end

-- R(a, b): enter; tall a la fracció f de [a, b] amb ±1 d'atzar, i que deixi com a mínim `m` caselles a cada costat
local function cut(R, a, b, f, m)
  m = m or 3
  local c = a + math.floor((b - a) * f + 0.5) + R(-1, 1)
  return math.max(a + m, math.min(b - m, c))
end

-- cada funció rep (w, h, R, ex) i torna la llista d'habitacions; la primera és on viu la gent (saló o similar)
local L = {}
local X0, Y0
L[1] = function(w, h, R, ex)   -- clàssica: saló a tota alçada | dormitori a dalt, cuina o bany a baix
  local X1, Y1 = w - 2, h - 2
  local vx = cut(R, X0, X1, 0.52)
  if math.abs(vx - ex) < 2 then vx = (ex + 3 <= X1 - 3) and ex + 3 or ex - 3 end
  local hy = cut(R, Y0, Y1, 0.5)
  local left = ex < vx
  local lv = left and room(X0, Y0, vx - 1, Y1, 'living') or room(vx + 1, Y0, X1, Y1, 'living')
  local a, b = left and vx + 1 or X0, left and X1 or vx - 1
  return { lv, room(a, Y0, b, hy - 1, 'bedroom'), room(a, hy + 1, b, Y1, R() < 0.5 and 'kitchen' or 'bath') }
end
L[2] = function(w, h, R)       -- estudi: un sol espai (llit, sofà i cuina junts) i un bany petit al racó
  local X1, Y1 = w - 2, h - 2
  local bw, bh = R(4, 5), R(3, 4)
  local right = R() < 0.5
  local bx0 = right and X1 - bw + 1 or X0
  return { room(X0, Y0 + bh + 1, X1, Y1, 'studio'),
           room(right and X0 or bx0 + bw + 1, Y0, right and bx0 - 2 or X1, Y0 + bh - 1, 'dining'),
           room(bx0, Y0, bx0 + bw - 1, Y0 + bh - 1, 'bath') }
end
L[3] = function(w, h, R)       -- passadís: dormitoris i bany a dalt, passadís al mig, saló i cuina a baix
  local X1, Y1 = w - 2, h - 2
  local cy = cut(R, Y0, Y1, 0.45, 3)          -- passadís: files cy, cy + 1
  local a = cut(R, X0, X1, 0.36); local b = cut(R, a + 1, X1, 0.55, 2)
  local k = cut(R, X0, X1, 0.6)
  return { room(X0, cy + 3, k - 1, Y1, 'living'), room(X0, cy, X1, cy + 1, 'hall'),
           room(X0, Y0, a - 1, cy - 2, 'bedroom'), room(a + 1, Y0, b - 1, cy - 2, 'kids'),
           room(b + 1, Y0, X1, cy - 2, 'bath'), room(k + 1, cy + 3, X1, Y1, 'kitchen') }
end
L[4] = function(w, h, R)       -- casa de poble: estreta i fonda, saló a baix, cuina i bany al mig, dormitori a dalt
  local X1, Y1 = w - 2, h - 2
  local y1 = cut(R, Y0, Y1, 0.33); local y2 = cut(R, y1 + 1, Y1, 0.5, 2)
  local k = cut(R, X0, X1, 0.62)
  return { room(X0, y2 + 1, X1, Y1, 'living'), room(X0, y1 + 1, k - 1, y2 - 1, 'kitchen'),
           room(k + 1, y1 + 1, X1, y2 - 1, 'bath'), room(X0, Y0, X1, y1 - 1, 'bedroom') }
end
L[5] = function(w, h, R)       -- masia: pati enmig envoltat d'habitacions, saló a tota l'amplada a baix
  local X1, Y1 = w - 2, h - 2
  local t = cut(R, Y0, Y1, 0.3, 3); local b = cut(R, t + 1, Y1, 0.62, 3)
  local a = cut(R, X0, X1, 0.27); local c = cut(R, a + 1, X1, 0.7, 3)
  local m = cut(R, X0, X1, 0.5)
  return { room(X0, b + 1, X1, Y1, 'living'), room(a + 1, t + 1, c - 1, b - 1, 'patio'),
           room(X0, Y0, m - 1, t - 1, 'bedroom'), room(m + 1, Y0, X1, t - 1, 'kids'),
           room(X0, t + 1, a - 1, b - 1, 'kitchen'), room(c + 1, t + 1, X1, b - 1, 'bath') }
end
L[6] = function(w, h, R)       -- loft: un gran espai obert (saló i cuina) i, a un costat, dormitori i bany
  local X1, Y1 = w - 2, h - 2
  local right = R() < 0.5
  local vx = right and cut(R, X0, X1, 0.68) or cut(R, X0, X1, 0.32)
  local hy = cut(R, Y0, Y1, 0.58)
  local a, b = right and vx + 1 or X0, right and X1 or vx - 1
  return { right and room(X0, Y0, vx - 1, Y1, 'loft') or room(vx + 1, Y0, X1, Y1, 'loft'),
           room(a, Y0, b, hy - 1, 'bedroom'), room(a, hy + 1, b, Y1, 'bath') }
end
L[7] = function(w, h, R)       -- casa d'artista: taller a tota alçada, dormitori a dalt, saló i cuina a baix
  local X1, Y1 = w - 2, h - 2
  local vx = cut(R, X0, X1, 0.35)
  local hy = cut(R, Y0, Y1, 0.45)
  local k = cut(R, vx + 1, X1, 0.55)
  return { room(vx + 1, hy + 1, k - 1, Y1, 'living'), room(X0, Y0, vx - 1, Y1, 'study'),
           room(vx + 1, Y0, X1, hy - 1, 'bedroom'), room(k + 1, hy + 1, X1, Y1, 'kitchen') }
end
L[8] = function(w, h, R)       -- família gran: tres dormitoris i bany a dalt, saló i cuina a baix
  local X1, Y1 = w - 2, h - 2
  local hy = cut(R, Y0, Y1, 0.45)
  local cols, last = {}, X0
  for i = 1, 3 do cols[i] = cut(R, last, X1, 1 / (5 - i), 2); last = cols[i] + 1 end
  local k = cut(R, X0, X1, 0.62)
  return { room(X0, hy + 1, k - 1, Y1, 'living'),
           room(X0, Y0, cols[1] - 1, hy - 1, 'bedroom'), room(cols[1] + 1, Y0, cols[2] - 1, hy - 1, 'kids'),
           room(cols[2] + 1, Y0, cols[3] - 1, hy - 1, 'kids'), room(cols[3] + 1, Y0, X1, hy - 1, 'bath'),
           room(k + 1, hy + 1, X1, Y1, 'kitchen') }
end
L[9] = function(w, h, R)       -- casa de platja: terrassa a l'entrada, saló-cuina obert, dormitori i bany
  local X1, Y1 = w - 2, h - 2
  local ty = Y1 - R(2, 3)                   -- terrassa: de ty + 1 a baix
  local vx = cut(R, X0, X1, 0.62)
  local hy = cut(R, Y0, ty - 1, 0.5, 2)
  return { room(X0, Y0, vx - 1, ty - 1, 'loft'), room(X0, ty + 1, X1, Y1, 'terrace'),
           room(vx + 1, Y0, X1, hy - 1, 'bedroom'), room(vx + 1, hy + 1, X1, ty - 1, 'bath') }
end
L[10] = function(w, h, R)      -- dúplex compacte: saló a baix, cuina i menjador al mig, despatx i dormitori a dalt
  local X1, Y1 = w - 2, h - 2
  local y1 = cut(R, Y0, Y1, 0.34, 2); local y2 = cut(R, y1 + 1, Y1, 0.5, 2)
  local a = cut(R, X0, X1, 0.45); local b = cut(R, X0, X1, 0.4)
  return { room(X0, y2 + 1, X1, Y1, 'living'), room(X0, y1 + 1, a - 1, y2 - 1, 'kitchen'),
           room(a + 1, y1 + 1, X1, y2 - 1, 'dining'), room(X0, Y0, b - 1, y1 - 1, 'study'),
           room(b + 1, Y0, X1, y1 - 1, 'bedroom') }
end

-- tipus de la casa a partir de la llavor (la de la porta): uniforme entre els 10
function H.pick(seed)
  local s = math.floor(math.abs(seed or 1)) % 2147483646 + 1
  for _ = 1, 3 do s = (s * 16807) % 2147483647 end   -- (exacte amb doubles: 16807 · 2³¹ < 2⁵³)
  return math.floor(s / 4096) % H.COUNT + 1
end

-- veïnes: separades per un envà d'una casella i amb tram comú. Torna llista de { i, j, cel·les possibles de porta }
local function neighbours(rooms)
  local out = {}
  for i = 1, #rooms do
    for j = i + 1, #rooms do
      local a, b = rooms[i], rooms[j]
      local cells = {}
      for _, p in ipairs({ { a, b }, { b, a } }) do
        local p1, p2 = p[1], p[2]
        if p1.x1 + 2 == p2.x0 then      -- envà vertical a x = p1.x1 + 1
          for y = math.max(p1.y0, p2.y0), math.min(p1.y1, p2.y1) do cells[#cells + 1] = { p1.x1 + 1, y, 'v' } end
        end
        if p1.y1 + 2 == p2.y0 then      -- envà horitzontal a y = p1.y1 + 1
          for x = math.max(p1.x0, p2.x0), math.min(p1.x1, p2.x1) do cells[#cells + 1] = { x, p1.y1 + 1, 'h' } end
        end
      end
      if #cells > 0 then out[#out + 1] = { i, j, cells } end
    end
  end
  return out
end

-- construeix la distribució `kind` (1..10) dins una rejilla w × h
-- set(x, y, nom) posa estructura; mark(x, y) deixa la cel·la lliure (pas). ex: columna de la sortida.
-- Torna les habitacions (amb .type) i les cel·les de porta.
function H.build(kind, w, h, R, ex, set, mark)
  X0, Y0 = 1, 2
  local rooms = L[kind] and L[kind](w, h, R, ex) or L[1](w, h, R, ex)
  -- habitacions massa petites (casa estreta): es queda la clàssica
  for _, r in ipairs(rooms) do
    if r.x1 - r.x0 < 1 or r.y1 - r.y0 < 1 then rooms = L[1](w, h, R, ex); break end
  end
  local inside = {}
  for _, r in ipairs(rooms) do
    for y = r.y0, r.y1 do for x = r.x0, r.x1 do inside[y * w + x] = true end end
  end
  for y = Y0, h - 2 do
    for x = X0, w - 2 do if not inside[y * w + x] then set(x, y, 'i_wall_top') end end
  end
  -- portes: arbre des de l'habitació de la sortida (la que toca (ex, h-2)); el pati i el passadís, oberts a tothom
  local start = 1
  for i, r in ipairs(rooms) do if ex >= r.x0 and ex <= r.x1 and r.y1 == h - 2 then start = i end end
  local nb = neighbours(rooms)
  local linked, doors = { [start] = true }, {}
  local function open(e)
    local cells = e[3]
    local n = #cells >= 4 and 2 or 1
    local k = R(1, #cells - n + 1)
    for d = 0, n - 1 do
      local c = cells[k + d]
      set(c[1], c[2], '')
      mark(c[1], c[2])
      if c[3] == 'v' then mark(c[1] - 1, c[2]); mark(c[1] + 1, c[2]) else mark(c[1], c[2] - 1); mark(c[1], c[2] + 1) end
      doors[#doors + 1] = { c[1], c[2] }
    end
    e.done = true
  end
  local open_all = { patio = true, hall = true, terrace = true }
  local grew = true
  while grew do
    grew = false
    for _, e in ipairs(nb) do
      local a, b = linked[e[1]], linked[e[2]]
      if not e.done and (a ~= b) then
        open(e); linked[e[1]], linked[e[2]] = true, true; grew = true
      end
    end
  end
  for _, e in ipairs(nb) do
    if not e.done and (open_all[rooms[e[1]].type] or open_all[rooms[e[2]].type]) then open(e) end
  end
  -- la sortida sempre dona a una habitació
  for y = h - 2, Y0, -1 do
    if inside[y * w + ex] then break end
    set(ex, y, ''); mark(ex, y)
  end
  return rooms, doors
end

return H
